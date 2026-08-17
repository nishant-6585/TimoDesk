import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'app_widgets.dart';
import 'config.dart';
import 'face_painter.dart';
import 'services/robot_tts.dart';
import 'services/voice_arbiter.dart';
import 'services/person_detect.dart';
import 'services/face_recognition.dart';
import 'models/voice_language.dart';
import 'greeting_provider.dart';
import 'pin_screen.dart';
import 'nav_points_provider.dart';
import 'services/nav_points_api.dart';
import 'services/nav_voice.dart';
import 'services/voice_fuzzy.dart';
import 'services/persona_voice.dart';
import 'services/checkin_voice.dart';
import 'services/intent_registry.dart';
import 'services/voice_command_catalog.dart';
import 'services/robot_gestures.dart';
import 'services/interaction_log.dart';
import 'services/checkin_api.dart';
import 'waving_hand_overlay.dart';
import 'face_rig.dart';
import 'gaze_tracker.dart';
import 'services/spine_client.dart';
import 'services/voice_agent.dart';
import 'services/voice_provider_factory.dart';
import 'services/audio_bridge.dart';
import 'services/intrusion_siren.dart';
import 'screens/language_selection_screen.dart';
import 'screens/product_picker_screen.dart';
import 'services/xboom_lead_api.dart';
import 'dashboard_screen.dart';

/// The robot's front-of-house home: an ambient animated face (Beam/OLED
/// CustomPainter, #82). #82 P2 wires it to live perception:
///   • LOCAL ML Kit on /snapshot → gaze x/y + presence → attentive (anonymous),
///     PLUS the attention gate: a greeting fires only when a face is LOOKING at
///     the camera (frontal pose + proximity + dwell) — never from the person
///     sensor (LIDAR/RGBD/ultrasonic), which only wakes the eyes.
///   • SPINE WS face_detected → greeting-by-name (authoritative identity);
///     spine "unknown" → immediate visitor greeting (no name).
///   • CSJBot personDetected → coarse presence fallback (attentive only).
///   • CSJBot on-device recognizer → identity FALLBACK when spine is offline.
/// #80 voice: an ElevenLabs Conversational AI session drives listening/thinking/
/// speaking + amplitude lip-sync, and logs the transcript to spine. (Phase A —
/// triggered manually from the debug overlay; wake word + mic are Phase B.)
/// Tap anywhere → Dashboard.
class AmbientFaceScreen extends ConsumerStatefulWidget {
  const AmbientFaceScreen({super.key});

  @override
  ConsumerState<AmbientFaceScreen> createState() => _AmbientFaceScreenState();
}

/// Which check-in question is currently outstanding. `none` = no open dialog,
/// so a stray utterance is passed to the conversational agent as usual.
enum _CheckinStage { none, name, company, purpose }

class _AmbientFaceScreenState extends ConsumerState<AmbientFaceScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  FaceState _face = const FaceState();
  final FaceRig _rig = FaceRig();
  final _repaint = _FaceRepaint(); // per-frame repaint signal for the painter

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // ── Live perception (Wire 1 + Wire 2) ──────────────────────────────────────
  final GazeTracker _gaze = GazeTracker();
  final SpineClient _spine = SpineClient();
  StreamSubscription<GazeResult>? _gazeSub;
  StreamSubscription<FaceDetectedEvent>? _faceSub;
  StreamSubscription<void>? _unknownSub; // spine saw a face, matched no staff
  StreamSubscription<bool>? _presenceSub;
  StreamSubscription<String>? _voiceControlSub; // admin remote voice stop
  StreamSubscription<Map<String, dynamic>>? _configSub; // admin remote config
  StreamSubscription<AlarmCommand>? _alarmSub; // F9 intrusion alarm
  StreamSubscription<Map<String, dynamic>>? _tourSub; // F8 guided-tour events
  StreamSubscription<bool>? _sdkPersonSub; // on-device CSJBot person sensors
  StreamSubscription<FaceEvent>? _faceRecgSub; // CSJBot staff face recognition
  String? _pendingGreetName; // last recognised staff name (injected to ElevenLabs)
  int _pendingGreetAtMs = 0; // when _pendingGreetName was set — freshness guard for session priming

  bool _useLivePerception = true; // toggle in debug card; drives gaze when on
  bool _present = false; // a face box is currently visible
  bool _wasLooking = false; // attention-gate edge tracking (greet on rising edge)
  double _liveGazeX = 0, _liveGazeY = 0;
  Timer? _presenceHold;

  // Greeting overlay text + the re-greet debounce now live in greetingProvider
  // (shared with the dashboard); this screen keeps only the face-state revert.
  Timer? _greetTimer;

  // Greeting coordinator: on motion/presence we hold off greeting for a brief
  // window so face recognition can identify a known staff member FIRST (→ greet
  // by name); if no face is recognised in time we fall back to a plain hello.
  // This makes the greeting deterministic — exactly one per visit, name-if-known
  // — instead of the old race between the person-sensor and face-recognition
  // paths (which caused the intermittent "Hello" vs "Hello <name>").
  bool _awaitingRecognition = false;
  Timer? _recognitionWaitTimer;
  // The spine recognises faces per-frame and can emit an 'unknown' verdict a
  // beat BEFORE it recognises an enrolled staff face (a borderline first frame).
  // Greeting the visitor hello immediately then hearing that faceDetected made
  // a recognised person hear BOTH "Hello, welcome…" and their name. We defer the
  // visitor hello briefly so a staff faceDetected can cancel it (name wins).
  Timer? _pendingVisitorTimer;

  // One-shot TTS for greeting phrases (ElevenLabs voice, falls back to built-in).
  late final RobotTts _tts;

  // ── Voice visitor check-in ("I'm here to see <host>") ──────────────────────
  // Four-turn dialog (blueprint §07 visitor record): intent+host → name →
  // company → purpose → POST /visit. Company and purpose are OPTIONAL: the
  // visitor can skip either, and a timeout after the name still submits with
  // whatever was collected — notifying the host is the critical path and must
  // not be lost to an unanswered follow-up question.
  final CheckinApi _checkinApi = CheckinApi();
  StaffMember? _checkinHost; // resolved host while the dialog is open
  _CheckinStage _checkinStage = _CheckinStage.none;
  String? _checkinName;
  String? _checkinCompany;
  Timer? _checkinTimeout; // abandon/settle the dialog if the visitor goes quiet
  List<StaffMember>? _staffCache; // GET /staff cache for host matching
  DateTime? _staffCacheAt;
  static const Duration _staffCacheTtl = Duration(minutes: 5);
  // Same-name disambiguation: set when we asked "which <name>?"; the next
  // utterance is resolved against these candidates instead of re-matching.
  List<NavPoint>? _pendingNavCandidates;
  Timer? _pendingNavTimeout;
  // The staff member we're currently escorting a visitor to meet (their desk
  // name), so the arrival hook can check whether they're actually there.
  String? _meetStaffName;
  Timer? _meetPresenceCheck;
  static const Duration _checkinNameWindow = Duration(seconds: 25);

  // ── Escort arrival check ────────────────────────────────────────────────────
  // After a non-patrol "follow me" arrival, wait briefly for a face; if nobody
  // appears the visitor was lost en route → speak the configurable line.
  Timer? _escortArrivalCheck;

  // Voice (#80) — ElevenLabs Conversational AI session + audio bridge.
  // The live voice engine (ElevenLabs or OpenAI Realtime) behind the shared
  // VoiceProvider interface — swapped by _rebuildVoiceProvider on a config switch.
  late VoiceProvider _voiceAgent;
  String _voiceProviderName = RobotConfig.voiceProvider; // detect switches
  final AudioBridge _audioBridge = AudioBridge();
  late final IntrusionSiren _siren = IntrusionSiren(_audioBridge);
  StreamSubscription<VoiceEvent>? _voiceSub;
  StreamSubscription<String>? _wakeSub;
  StreamSubscription<String>? _asrSub;

  // Conversational PHYSICAL head gestures during a voice session — mirrors the
  // dashboard so the robot nods / tilts / sways with the conversation on the MAIN
  // FACE SCREEN too (it used to stay dead-still here while the dashboard moved).
  bool _gestureBusy = false; // one multi-step gesture at a time (they'd fight)
  int _lastSwayMs = 0; // throttle speaking sway to ~once / 300ms
  int _lastNodMs = 0; //  throttle the acknowledging nod to ~once / 2.5s
  Timer? _asrFinalTimer;
  String _asrUtterance = '';
  StreamSubscription<double>? _playbackSub; // speaker amplitude → lip-sync
  bool _voiceActive = false; // a session is open (toggles the debug button)
  double _micLevel = 0; // smoothed mic RMS 0..1 — drives the "listening" meter
  bool _serviceAlertVisible = false; // ElevenLabs-unavailable dialog is showing
  bool _dropFirstAgentTurn = false; // auto session: skip the agent's unprompted
  //                                    first message (we already greeted via TTS)
  bool _pushToTalk = false; // hold-to-talk held → send FULL mic (bypass gates),
  //                           reliable in a noisy room; drop agent audio meanwhile

  // Auto-listen UX: after a greeting, open the mic automatically so a visitor can
  // just start talking (no tap). _pendingAutoListen waits for the greeting audio
  // to finish (drain signal) before opening the session — so the mic never hears
  // Mini's own greeting. _autoSession marks a session that should auto-close
  // after _engageWindow of silence; manual (button) sessions stay open.
  bool _pendingAutoListen = false;
  Timer? _autoListenFallback;
  bool _autoSession = false;
  Timer? _idleWatch; // periodic idle watchdog → auto-close on inactivity
  // Idle is measured as ACCUMULATED SILENCE — seconds elapsed while Mini is NOT
  // speaking and no genuine user WORDS have arrived. It is reset ONLY by real
  // transcribed user words / hold-to-talk (see _bumpActivity) — never by raw mic
  // loudness or empty "..." VAD turns, both of which trip on ambient room noise
  // with no AEC and used to keep the session alive forever. It FREEZES while Mini
  // talks (his answer time must not eat the visitor's reply window) but does not
  // reset, so a talk-to-noise loop still closes once the gaps between turns add up.
  int _silenceAccumMs = 0;
  // Accumulated ms with no visitor face while a session is open — closes the
  // session once the visitor has left (see _startIdleWatch), so the agent stops
  // spending ElevenLabs characters on an empty room.
  int _noFaceAccumMs = 0;
  static const int _voiceNoFaceCloseMs = 4000; // + the 3s presence-hold ≈ 7s after they leave
  // Consecutive agent turns triggered with NO real user words (empty "..." VAD
  // trips on noise, or echo). 3 in a row = Mini is answering the room, not a
  // person → close. Reset to 0 by any genuine user words.
  int _phantomTurns = 0;
  static const int _maxPhantomTurns = 3;
  int _lastSpeakingMs = 0; // last time Mini's speaker was active → mic-gate tail

  // Resilience (#obs3): if ElevenLabs drops the connection unexpectedly mid-visit
  // (e.g. a transient `code 1002` agent error), reopen the session ONCE instead of
  // falling back to idle — so a server hiccup self-heals and the visitor can keep
  // talking. Deliberate closes (idle watchdog / stop button) never reconnect.
  Timer? _reconnectTimer;
  bool _intentionalClose = false; // true when WE end the session (not a server drop)
  bool _suppressTeardown = false; // skip the idle teardown for a drop we're recovering
  int _reconnectAttempts = 0; // reset on a fresh start or a real turn; caps retries
  static const int _maxReconnects = 1; // one silent retry per incident

  static const Duration _greetHold = Duration(milliseconds: 3500);
  // The same-name re-greet debounce (Settings-tunable, RobotConfig.
  // regreetMinutes) now lives in greetingProvider — shared with the dashboard.
  // How long after the attention gate opens we wait for identity before greeting
  // anonymously. Long enough for the spine recogniser (500ms cadence + 2-of-3
  // voting) to land a match on an enrolled face, short enough that an unknown
  // visitor isn't left waiting for a hello. Spine's explicit "unknown" short-
  // circuits this window — the timeout only covers spine being slow/offline.
  static const Duration _recognitionWindow = Duration(milliseconds: 2000);
  static const Duration _conversationIdle = Duration(seconds: 15); // mid-chat silence → close
  // Mic stays muted this long after Mini's last speaker output. Must cover BOTH
  // the AudioTrack drain AND the room-reverb tail: with no hardware AEC, feeding
  // that tail to ElevenLabs made its server-side ASR transcribe Mini's own voice
  // into coherent "user" sentences (e.g. "Can you help me?") ~3.5s later — past
  // the transcript echo guard — which reset the idle timer forever. Aligned with
  // _echoGuardMs so the feed and the guard cover the same window. The cost is that
  // a real reply within 2.5s of Mini finishing is clipped; hold-to-talk (mic
  // button) bypasses this entirely for an eager visitor.
  static const int _micTailGuardMs = 2500;
  // A transcript arriving within this window of Mini's own speech is treated as
  // ECHO (his voice fed back), NOT a real user turn — so it doesn't reset the
  // idle watchdog or make him reply to himself.
  static const int _echoGuardMs = 2500;
  // Playback RMS below this is treated as silence (trailing/padding chunks) — it
  // won't drive the "speaking" state, so the mouth doesn't twitch while listening.
  static const double _speechFloor = 0.03;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();

    // Live perception streams.
    _gazeSub = _gaze.results.listen(_onGaze);
    _faceSub = _spine.faceDetected.listen(_onFaceDetected);
    _unknownSub = _spine.unknownFace.listen(_onUnknownFace);
    _presenceSub = _spine.personDetected.listen(_onPersonDetected);
    // Admin can remotely stop the robot's listening/voice session from the
    // dashboard (e.g. to cut off a runaway conversation). End it here.
    _voiceControlSub = _spine.voiceControl.listen((action) {
      if (action == 'stop' && _voiceActive) {
        debugPrint('Voice: admin remote stop → ending session');
        InteractionLog.log('voice_stopped_by_admin', 'remote stop');
        _endVoice();
      }
    });
    // Admin changed robot config (name / behaviours) from the web app — apply
    // + persist it so it takes effect without touching the robot's own Settings.
    _configSub = _spine.configUpdate.listen((cfg) {
      debugPrint('Config: admin update → $cfg');
      RobotConfig.applyRemoteConfig(cfg);
      if (mounted) setState(() {}); // reflect e.g. a rename in the UI
    });
    // Intrusion alarm from the spine's after-hours security patrol (F9). The
    // siren owns its own repeat/auto-stop; here we only start/stop it and put
    // the face into its alarm state.
    _alarmSub = _spine.alarm.listen((cmd) {
      if (cmd.start) {
        InteractionLog.log('intrusion_alarm',
            'siren triggered${cmd.waypoint != null ? ' near ${cmd.waypoint}' : ''}');
        _audioBridge.stopPlayback(); // nothing else should be talking
        _siren.start(waypoint: cmd.waypoint);
      } else {
        _siren.stop();
      }
      if (mounted) setState(() {});
    });
    // Guided tour (F8): the station narration is already spoken by the nav
    // provider on arrival; the spine's `questions_open` is the cue to open the
    // mic so the guest can ask about what they were just shown. The normal idle
    // watchdog closes the session, so no timer is needed here.
    _tourSub = _spine.tourEvents.listen((e) {
      switch (e['event']) {
        case 'questions_open':
          InteractionLog.log('tour_questions_open', '${e['waypoint']}');
          if (!_voiceActive && mounted) {
            debugPrint('Tour: questions open at "${e['waypoint']}" → opening mic');
            _startVoice(auto: true);
          }
          break;
        case 'finished':
          InteractionLog.log('tour_finished', '${e['reason'] ?? 'route complete'}');
          break;
      }
    });
    // On-device person sensors (laser/RGBD/ultrasonic) → idle→attentive ONLY.
    // Deliberately NOT a greeting trigger: greetings fire exclusively from the
    // camera attention gate (a face looking at the robot), never from LIDAR.
    _sdkPersonSub = PersonDetect.presence.listen(_onPersonDetected);
    // Staff face recognition (CSJBot SDK) — identity FALLBACK when spine is
    // offline (spine's face_detected is authoritative). Silent off-robot.
    _faceRecgSub = FaceRecognition.events.listen(_onFaceRecognized);
    _gaze.start();
    _spine.start();

    _tts = RobotTts(audio: _audioBridge);

    // Voice (#80) — session is opened on demand (debug overlay / Phase B wake word).
    // The engine (ElevenLabs / OpenAI Realtime) is chosen by RobotConfig and can
    // be switched live from Settings or the admin app (see _rebuildVoiceProvider).
    _voiceAgent = buildVoiceProvider();
    _voiceSub = _voiceAgent.events.listen(_onVoiceEvent);
    // Rebuild the engine when the voice-provider setting flips (config push from
    // admin or the robot's own Settings both bump elevenConfigRev).
    RobotConfig.elevenConfigRev.addListener(_onVoiceConfigChanged);
    // Speaker amplitude (as it plays) → lip-sync + speaking/listening transition.
    _playbackSub = _audioBridge.playbackLevelStream.listen(_onPlaybackLevel);

    // Wake word (Phase B): CSJBot "wakeup" → start a session. Silent stream on
    // the emulator (the native plugin swallows the SDK absence). The face tap is
    // the other trigger (debug overlay today; whole-face tap later).
    // Vendor ASR text (SPEECH_ISR partials) → utterance aggregation → nav
    // commands / ElevenLabs text turn. This is the working speech path on this
    // robot: recognized TEXT flows, raw PCM does not.
    _asrSub = _audioBridge.asrTextStream.listen(_onVendorAsr);
    _wakeSub = _audioBridge.wakeWordStream.listen((_) {
      if (!_voiceAgent.isActive) _startVoice();
    });
    // NOTE: the on-device CSJBot CAE barge-in was removed — it kept mis-hearing
    // Mini's own speaker echo as the user and cut him off mid-sentence. Hands-free,
    // Mini now finishes his replies; hold-to-talk stays the reliable way to
    // interrupt him (it stops playback and routes the full mic to ElevenLabs).

    // Start the camera stream so /snapshot serves frames to the on-device face
    // detector (GazeTracker → ML Kit) — that's what drives idle→attentive presence
    // (the CSJBot person-near NTF is silent on this unit). If it's already
    // streaming, just bring up the control WS servers; when streaming flips on the
    // build()'s ref.listen wires the control servers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(streamProvider).isStreaming) {
        _startControlServers();
      } else {
        ref.read(streamProvider.notifier).startStream();
      }
    });
  }

  void _startControlServers() {
    if (!ref.read(headProvider).isRunning) ref.read(headProvider.notifier).startHeadControl();
    if (!ref.read(chassisProvider).isRunning) ref.read(chassisProvider.notifier).startChassisControl();
    if (!ref.read(armProvider).isRunning) ref.read(armProvider.notifier).startArmControl();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _presenceHold?.cancel();
    _pendingVisitorTimer?.cancel();
    _greetTimer?.cancel();
    _recognitionWaitTimer?.cancel();
    _checkinTimeout?.cancel();
    _escortArrivalCheck?.cancel();
    _pendingNavTimeout?.cancel();
    _meetPresenceCheck?.cancel();
    _reconnectTimer?.cancel();
    _autoListenFallback?.cancel();
    _idleWatch?.cancel();
    RobotConfig.elevenConfigRev.removeListener(_onVoiceConfigChanged);
    _voiceSub?.cancel();
    _wakeSub?.cancel();
    _asrSub?.cancel();
    _asrFinalTimer?.cancel();
    _playbackSub?.cancel();
    _voiceAgent.dispose();
    _tts.dispose();
    _audioBridge.dispose();
    _gazeSub?.cancel();
    _faceSub?.cancel();
    _unknownSub?.cancel();
    _presenceSub?.cancel();
    _voiceControlSub?.cancel();
    _configSub?.cancel();
    _alarmSub?.cancel();
    _tourSub?.cancel();
    _siren.dispose();
    _sdkPersonSub?.cancel();
    _faceRecgSub?.cancel();
    _gaze.dispose();
    _spine.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause the /snapshot poll when backgrounded (CPU); keep the WS (cheap).
    if (state == AppLifecycleState.resumed) {
      _gaze.start();
    } else {
      _gaze.stop();
    }
  }

  // ── Frame loop ──────────────────────────────────────────────────────────────
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    final follow = _useLivePerception && _present;
    _rig.tick(
      _face,
      dt,
      followGx: follow ? _liveGazeX : null,
      followGy: follow ? _liveGazeY : null,
    );
    _repaint.ping(); // repaint the face only (no full-tree rebuild)
  }

  // ── Wire 1: local gaze + presence + attention gate ──────────────────────────
  void _onGaze(GazeResult r) {
    if (r.facePresent) {
      final fresh = !_present; // rising edge → a new person just approached
      _liveGazeX = r.gazeX;
      _liveGazeY = r.gazeY;
      _present = true;
      _presenceHold?.cancel();
      _presenceHold = null;
      if (_useLivePerception && _face.state == FaceStateKind.idle) {
        _setStateKind(FaceStateKind.attentive);
      }
      // Greeting trigger — attention gate: greet only when the face is LOOKING
      // at the camera (frontal pose + proximity, sustained — see GazeTracker),
      // on the rising edge of that attention. Mere presence turns the eyes; it
      // never speaks. With the gate disabled (Settings), fall back to the old
      // greet-on-fresh-presence behaviour.
      // Recognise-first either way: hold the greeting briefly so an enrolled
      // staff member is greeted by name; unknown faces get the visitor hello.
      if (RobotConfig.attentionGateEnabled) {
        if (r.lookingAtCamera && !_wasLooking && !_voiceActive) {
          _beginGreetSequence();
        }
        _wasLooking = r.lookingAtCamera;
      } else if (fresh && !_voiceActive) {
        _beginGreetSequence();
      }
    } else {
      _wasLooking = false;
      // Hold attentive briefly before returning to idle (kills jitter).
      if (_present && _presenceHold == null) {
        final hold = _face.state == FaceStateKind.greeting
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3);
        _presenceHold = Timer(hold, () {
          _present = false;
          _greeted = false; // person has left — allow greeting on next approach
          _awaitingRecognition = false; // cancel any pending greet-after-recognise
          _recognitionWaitTimer?.cancel();
          _pendingVisitorTimer?.cancel(); // drop any deferred visitor hello
          _reconnectAttempts = 0; // fresh retry budget for the next visitor
          _presenceHold = null;
          if (_face.state == FaceStateKind.attentive ||
              _face.state == FaceStateKind.greeting) {
            _setStateKind(FaceStateKind.idle);
          }
        });
      }
    }
    if (mounted && kDebugMode) setState(() {}); // refresh the perception card
  }

  // ── Wire 2: spine identity + presence ───────────────────────────────────────
  void _onFaceDetected(FaceDetectedEvent e) {
    // PRIORITY RULE (one interaction path at a time, nothing queued):
    //   navigation/escort  >  active voice interaction  >  face greeting.
    // A greeting that loses is CANCELLED outright — we record the greet so the
    // ~500ms recognition tick doesn't re-fire it as a delayed retry (the old
    // behaviour queued it until Mini's mouth was free, which made greetings
    // land on top of the visitor's next command). Speaking a hello mid-session
    // is also banned: it trips the half-duplex gate and MUTES the mic exactly
    // while the visitor is giving a command.
    final talking = _face.state == FaceStateKind.speaking ||
        _face.state == FaceStateKind.thinking;
    final busy = ref.read(navPointsProvider).navigatingTo != null ||
        _voiceActive ||
        talking;
    // Decision (debounce + priority) lives in greetingProvider now. A blocked
    // greeting is no longer recorded as delivered, so it can still land on a
    // later recognition tick once Mini is free — nothing is queued.
    if (!ref.read(greetingProvider.notifier).mayGreetStaff(e.name, busy: busy)) {
      return;
    }
    // A NAMED greeting is allowed to fire even after the generic approach
    // greeting already went out — the spine's identity often lands a beat late,
    // and staff should always hear their personalised welcome (once per
    // debounce window). It just must not re-open the mic a second time.
    final upgradeAfterGeneric = _greeted;
    _greeted = true; // counts as this visit's one greeting
    _awaitingRecognition = false; // spine identity won the recognition window
    _recognitionWaitTimer?.cancel();
    _pendingVisitorTimer?.cancel(); // staff wins — cancel any deferred visitor hello
    // Prime the voice agent with WHO the spine recognised, so the session opens
    // knowing the person — fixes "do you recognize me?" → "I can't identify
    // anyone" (this authoritative path previously never told the agent). Consumed
    // in _startVoice as the one-shot STAFF_RECOGNIZED first turn.
    _pendingGreetName = e.name;
    _pendingGreetAtMs = DateTime.now().millisecondsSinceEpoch;
    final lang = languageForCode(RobotConfig.voiceLanguageCode);
    _showGreeting(lang.greetText(e.name), staffName: e.name);
    if (upgradeAfterGeneric) {
      // A generic visitor hello already went out this visit (the deferral
      // window elapsed before the spine recognised them). The overlay above
      // has switched to their name and the agent is primed — do NOT speak a
      // second time, or they hear two greetings. One voice per visit.
      return;
    }
    _greetThenListen(_staffSpeech(lang, e.name));
  }

  // Spine saw a face that matched NO enrolled staff → this is a VISITOR.
  // Greet them directly — do NOT require the attention-gate window first: in a
  // busy lobby people rarely look dead-on, and the one-shot `_greeted` flag
  // never resets while foot traffic keeps presence continuously true, which
  // left visitors standing in front of a silent robot. The cooldown that stands
  // in for the per-name debounce lives in greetingProvider.
  void _onUnknownFace(void _) {
    // Already greeted this visit (e.g. the spine recognised the person a frame
    // earlier and we greeted BY NAME) → a later 'unknown' frame must NOT add a
    // generic hello on top. One greeting per visit.
    if (_greeted) return;
    // Same priority rules as named greetings: never interrupt an interaction.
    final talking = _face.state == FaceStateKind.speaking ||
        _face.state == FaceStateKind.thinking;
    final busy = _voiceActive ||
        talking ||
        ref.read(navPointsProvider).navigatingTo != null;
    if (!ref.read(greetingProvider.notifier).mayGreetVisitor(busy: busy)) {
      return;
    }
    _awaitingRecognition = false;
    _recognitionWaitTimer?.cancel();
    _pendingGreetName = null; // a visitor is NOT staff — don't prime the agent with a stale name
    // Defer the visitor hello so a staff faceDetected (which the spine may emit
    // a beat AFTER this 'unknown' frame) can cancel it in _onFaceDetected and
    // greet BY NAME instead — otherwise the person hears BOTH. Offline there is
    // no spine identity to wait for, so greet immediately.
    if (_spine.isConnected) {
      _pendingVisitorTimer?.cancel();
      // Give the spine's identity verdict enough time to WIN the race: a
      // recognised staff member's faceDetected(name) frame can land well after
      // the first 'unknown' frame (recognition needs a few 500ms cadence ticks
      // to gain confidence). 1500 ms was too short → staff heard the generic
      // "Hello" and their name never spoke (only on a later mic tap). A longer
      // window means a recognised face gets ONLY "Hello <Name>".
      _pendingVisitorTimer = Timer(const Duration(milliseconds: 3000), () {
        if (!mounted || _greeted || _voiceActive) return;
        _greetOnApproach();
      });
    } else {
      _greetOnApproach();
    }
  }

  // Rendered spoken phrases — Settings-editable templates (RobotConfig), with
  // {hello}/{welcome} localised by the active voice language.
  String _staffSpeech(VoiceLanguage lang, String name) => lang.renderGreeting(
      RobotConfig.greetStaffTemplate,
      name: name,
      company: RobotConfig.companyName,
      robot: RobotConfig.robotName);

  String _visitorSpeech(VoiceLanguage lang) => lang.renderGreeting(
      RobotConfig.greetVisitorTemplate,
      company: RobotConfig.companyName,
      robot: RobotConfig.robotName);

  // Attention gate passed → give face recognition a brief head start so a
  // known staff member is greeted BY NAME, before falling back to the visitor
  // hello. Spine identity (_onFaceDetected) or its "unknown" verdict
  // (_onUnknownFace) resolves the window early; the on-device recogniser
  // (_onFaceRecognized) covers spine-offline. Otherwise the timer fires the
  // visitor greeting. Guarded so exactly one greeting happens per visit.
  void _beginGreetSequence() {
    if (_greeted || _voiceActive || _awaitingRecognition) return;
    // Don't greet passers-by mid-navigation — it talks over the "follow me" /
    // arrival announcements (the "hello instead of my announcement" bug).
    if (ref.read(navPointsProvider).navigatingTo != null) return;
    _awaitingRecognition = true;
    _recognitionWaitTimer?.cancel();
    _recognitionWaitTimer = Timer(_recognitionWindow, () {
      if (!_awaitingRecognition) return;
      _awaitingRecognition = false;
      if (_greeted || _voiceActive) return;
      // When the spine is CONNECTED it is the authoritative identity source and
      // will deliver its own verdict: faceDetected → greet BY NAME, or
      // unknownFace → the visitor hello. Firing a generic hello here on timeout
      // is exactly what made a recognised staff member hear BOTH ("Hello,
      // welcome to xboom" then their name) when the spine landed a beat late.
      // So only fall back to the plain hello when the spine is OFFLINE — the
      // on-device recogniser (_onFaceRecognized) still covers names in that case.
      if (_spine.isConnected) return;
      _greetOnApproach(); // spine offline → plain-hello fallback
    });
  }

  // Visitor greeting (no name) — on-screen wave + voice, template-rendered.
  // Fires once per visit; resets when the person actually leaves (_greeted = false
  // in the presence-hold callback) so every new approach gets a fresh greeting.
  bool _greeted = false;
  void _greetOnApproach() {
    if (_greeted) return;
    _greeted = true;
    final lang = languageForCode(RobotConfig.voiceLanguageCode);
    _showGreeting(lang.greetText());
    _greetThenListen(_visitorSpeech(lang));
  }

  // Shared: publish the greeting (every screen renders it) + drive THIS screen's
  // face into its greeting state, reverting after the hold.
  void _showGreeting(String text, {String? staffName}) {
    if (!mounted) return;
    ref
        .read(greetingProvider.notifier)
        .show(text, staffName: staffName, hold: _greetHold);
    _greetTimer?.cancel();
    setState(() => _face = _face.copyWith(state: FaceStateKind.greeting));
    _greetTimer = Timer(_greetHold, () {
      if (!mounted) return;
      setState(() {
        _face = _face.copyWith(
          state: _present ? FaceStateKind.attentive : FaceStateKind.idle,
        );
      });
    });
  }

  // Speak a greeting phrase — ElevenLabs voice first, built-in TTS as fallback.
  String _lastSpokenText = '';
  int _lastSpokenMs = 0;

  void _speakGreeting(String text) {
    // Dedupe overlapping identical speech: presence fires from TWO sources
    // (spine personDetected + on-device PersonDetect → same _onPersonDetected)
    // and recognition can arrive from two paths, so this can be called twice
    // within milliseconds → two voices talking over each other. Suppress a
    // repeat of the SAME text within a short window.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (text == _lastSpokenText && now - _lastSpokenMs < 3000) return;
    _lastSpokenText = text;
    _lastSpokenMs = now;
    InteractionLog.log('robot_speech', text);
    _tts.speak(text).then((ok) {
      if (!ok) _audioBridge.speak(text);
    });
  }

  // ── Vendor ASR text path ────────────────────────────────────────────────────
  // Partial transcriptions stream in while the user talks; 900ms of silence
  // finalizes the utterance. Nav commands are handled locally; anything else
  // becomes a TEXT turn to the ElevenLabs agent (voice reply as usual).
  void _onVendorAsr(String partial) {
    if (partial.trim().isEmpty) return;
    // ECHO GUARD: the CSJBot vendor ASR also hears Mini's OWN speaker output
    // and transcribes it. Without this, his own words (a) get sent back to the
    // ElevenLabs agent → it replies to itself forever, and (b) bump the idle
    // timer → the session never auto-closes. Ignore any transcript that arrives
    // while he's speaking or within the echo tail.
    final now = DateTime.now().millisecondsSinceEpoch;
    final duringSpeech = _face.state == FaceStateKind.speaking ||
        (now - _lastSpeakingMs) < _echoGuardMs;
    if (duringSpeech) {
      // BARGE-IN: while (and just after) Mini speaks, the CAE stream still leaks
      // fragments of his OWN imperfectly-cancelled voice — the reason the old
      // always-on barge-in was pulled. So only cut him off on a SUBSTANTIAL
      // utterance that isn't an echo of what he's saying (see _isGenuineBargeIn);
      // otherwise keep suppressing it (the original half-duplex behaviour).
      if (!_isGenuineBargeIn(partial)) return;
      debugPrint('BargeIn: visitor cut in — "$partial"');
      InteractionLog.log('barge_in', partial);
      _dropFirstAgentTurn = true; // drop the rest of the interrupted agent turn
      _audioBridge.stopPlayback(); // cut Mini off immediately
      _lastSpeakingMs = 0; // clear the echo tail — we're actively listening now
      setState(() =>
          _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
      // fall through: aggregate + handle this utterance like any other turn.
    }
    _asrUtterance = partial.trim();
    _bumpActivity(); // real user speech — keep the session alive
    _asrFinalTimer?.cancel();
    _asrFinalTimer = Timer(const Duration(milliseconds: 900), () {
      final utterance = _asrUtterance;
      _asrUtterance = '';
      if (utterance.isEmpty) return;
      debugPrint('VendorASR utterance: "$utterance"');
      InteractionLog.log('user_utterance_vendor_asr', utterance);
      if (_dispatchVoiceCommand(utterance)) return;
      if (_voiceActive) {
        // The vendor ASR is Chinese-locked and often emits Chinese (or other
        // non-English) transcripts for English speech. Forwarding those to the
        // ElevenLabs agent as user_message turns pollutes the conversation and
        // flips its own ASR off the configured language — English "Nishant" then
        // comes back transcribed as Hindi. Only forward text that matches the
        // configured language so genuine barge-in still reaches the agent while
        // the garbage is dropped (the agent already hears the live mic audio).
        if (_forwardableToAgent(utterance)) {
          _voiceAgent.sendUserText(utterance);
          setState(() => _face = _face.copyWith(state: FaceStateKind.thinking));
        } else {
          debugPrint('VendorASR: dropping off-language "$utterance" — not forwarding to agent');
        }
      }
    });
  }

  /// Whether a vendor-ASR transcript is in the configured spoken language and so
  /// safe to inject into the ElevenLabs conversation. For English we require the
  /// text to be predominantly Latin script — this rejects the Chinese/Devanagari
  /// mis-transcriptions the vendor engine produces. Non-English configs are
  /// trusted as-is (their scripts are expected to be non-Latin).
  bool _forwardableToAgent(String text) {
    if (RobotConfig.voiceLanguageCode != 'en') return true;
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(text).length;
    if (letters == 0) return false;
    final latin = RegExp(r'[A-Za-z]').allMatches(text).length;
    return latin >= letters * 0.6;
  }

  // ── Barge-in gate ───────────────────────────────────────────────────────────
  // The robot is half-duplex (no hardware AEC): while Mini speaks ENGLISH the
  // vendor CAE mis-transcribes his OWN leaked voice as short Chinese/garbage
  // fragments (要怀疑mfc…, 一路惟) that carry ~no Latin words. So a genuine visitor
  // interruption is either (a) an explicit interrupt word — "stop", "wait" — at
  // ANY length (these are exactly how people cut him off), or (b) a phrase with
  // >= _bargeMinLatinWords real Latin content-words. Whatever passes still must
  // not overlap his own current reply (a word he actually just said). Logged so
  // it can be tuned on hardware. VERIFIED on robot 2026-08-06: a long sentence
  // fired correctly; "stop"/"stop talking" were wrongly rejected as too short —
  // hence the interrupt-word path + Latin-word floor (was a blunt >=3-word gate).
  static const int _bargeMinLatinWords = 2;
  static const double _bargeEchoOverlap = 0.5;
  static const List<String> _interruptWords = [
    'stop', 'quiet', 'enough', 'wait', 'cancel', 'listen', 'hey', 'hello',
    'mini', 'mikee', 'shut up', 'be quiet', 'hold on', 'excuse me', 'one moment',
  ];

  bool _isGenuineBargeIn(String text) {
    final t = text.trim();
    if (t.isEmpty || t == '...') return false;
    final lower = t.toLowerCase();
    final latinWords =
        RegExp(r'[a-z]{2,}').allMatches(lower).map((m) => m.group(0)!).toList();
    final wordSet = latinWords.toSet();
    // Single-word interrupt words must match a whole word; phrases (with a
    // space) match as a substring.
    final hasInterrupt = _interruptWords
        .any((w) => w.contains(' ') ? lower.contains(w) : wordSet.contains(w));
    if (!hasInterrupt && latinWords.length < _bargeMinLatinWords) {
      debugPrint('BargeIn: reject — not genuine speech '
          '(${latinWords.length} latin words) "$t"');
      return false;
    }
    final overlap = _echoOverlap(t, _voiceAgent.lastAgentText);
    if (overlap >= _bargeEchoOverlap) {
      debugPrint('BargeIn: reject — echo of own speech '
          '(${overlap.toStringAsFixed(2)}) "$t"');
      return false;
    }
    debugPrint('BargeIn: accept — "$t"');
    return true;
  }

  // Fraction of the heard content-words that also appear in Mini's own reply.
  // High overlap ⇒ the CAE re-transcribed his voice, not a new speaker. Words
  // ≤2 chars are dropped as noise on both sides.
  double _echoOverlap(String heard, String own) {
    if (own.isEmpty) return 0;
    Set<String> tokens(String s) => s
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 2)
        .toSet();
    final ownWords = tokens(own);
    if (ownWords.isEmpty) return 0;
    final heardWords =
        heard.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 2).toList();
    if (heardWords.isEmpty) return 0;
    final hits = heardWords.where(ownWords.contains).length;
    return hits / heardWords.length;
  }

  // ── Intent dispatch (the single voice-command entry point) ──────────────────
  // The spine catalog decides WHAT is a command and which are enabled for this
  // deployment; this maps the matched kind to the action. Replaces the old
  // _handleStop → _handleNav → _handlePersona → _handleCheckin if-chain (still
  // used underneath for the four rich handlers). Returns true when it WAS a
  // command, so the caller does NOT forward the utterance to the chat agent.
  IntentRegistry get _registry =>
      ref.read(intentRegistryProvider).valueOrNull ?? IntentRegistry.standard;

  // Language name → ElevenLabs code, for the "speak in Hindi" intent.
  static const Map<String, String> _langCodes = {
    'english': 'en', 'hindi': 'hi', 'tamil': 'ta', 'telugu': 'te',
    'kannada': 'kn', 'malayalam': 'ml', 'marathi': 'mr', 'bengali': 'bn',
    'gujarati': 'gu', 'punjabi': 'pa', 'urdu': 'ur', 'spanish': 'es',
    'french': 'fr', 'german': 'de', 'arabic': 'ar', 'chinese': 'zh', 'japanese': 'ja',
  };

  bool _dispatchVoiceCommand(String utterance) {
    // An open "which <name>?" disambiguation captures the next utterance as its
    // answer — before any other matching.
    if (_pendingNavCandidates != null) {
      _resolvePendingNav(utterance);
      return true;
    }
    // A check-in dialog in progress owns EVERY turn: the visitor's answer to
    // "your name?" must feed _advanceCheckin and must NOT be re-matched as another
    // intent (e.g. "…to Nishant" looking like navigate). This is what caused the
    // collision where the name turn drove the robot to the desk instead.
    if (_checkinStage != _CheckinStage.none) {
      return _handleCheckinVoice(utterance);
    }
    final points =
        ref.read(navPointsProvider).points.valueOrNull ?? const <NavPoint>[];
    final m = _registry.match(utterance, IntentContext(navPoints: points));
    if (m == null) return false;
    switch (m.kind) {
      case VoiceIntentKind.stop:
        return _handleStopCommand(utterance);
      case VoiceIntentKind.navigate:
      case VoiceIntentKind.dock:
        return _handleNavVoice(utterance);
      case VoiceIntentKind.persona:
        return _handlePersonaVoice(utterance);
      case VoiceIntentKind.checkin:
        final ok = _handleCheckinVoice(utterance);
        if (ok) InteractionLog.log('checkin_turn', utterance);
        return ok;
      default:
        return _handleExtendedIntent(m, utterance);
    }
  }

  // Actions for the extended intents. Physical commands with no verified on-device
  // bridge in this screen (patrol, drive, snapshot, volume) are RECOGNIZED but get
  // a graceful spoken reply instead of a blind motor command or leaking to chat.
  bool _handleExtendedIntent(IntentMatch m, String utterance) {
    InteractionLog.log('intent', '${m.kind.name} ← "$utterance"');
    _dropFirstAgentTurn = true; // ours — the agent must not also answer this turn
    _audioBridge.stopPlayback();
    switch (m.kind) {
      case VoiceIntentKind.cancelNav:
        ref.read(navPointsProvider.notifier).cancel();
        _speakGreeting("Okay, I'll stay here.");
        return true;
      case VoiceIntentKind.gesture:
        if (m.slot<String>('gesture') == 'wave') {
          ref.read(armProvider.notifier).wave();
          _speakGreeting('Hello there!');
        } else {
          RobotGestures.headCenter();
          _speakGreeting('There — all reset.');
        }
        return true;
      case VoiceIntentKind.sleepWake:
        final wake = m.slot<String>('action') == 'wake';
        setState(() => _face = _face.copyWith(
            state: wake ? FaceStateKind.attentive : FaceStateKind.idle));
        _speakGreeting(wake ? "I'm here!" : 'Okay, resting now.');
        return true;
      case VoiceIntentKind.language:
        final code = _langCodes[m.slot<String>('language') ?? ''];
        if (code != null) {
          _speakGreeting('Switching languages.');
          _voiceAgent.switchLanguage(code);
        }
        return true;
      case VoiceIntentKind.help:
        _speakGreeting('I can greet visitors, take you to people and places, '
            'return to my charging dock, check you in for a meeting, and answer '
            'questions about us. Just ask!');
        return true;
      case VoiceIntentKind.resume:
        _speakGreeting('Sure.');
        return true;
      case VoiceIntentKind.escort:
      case VoiceIntentKind.patrol:
      case VoiceIntentKind.drive:
      case VoiceIntentKind.snapshot:
      case VoiceIntentKind.volume:
        _speakGreeting("I'm not able to do that just yet, but it's on my list.");
        return true;
      default:
        return false;
    }
  }

  // ── Voice navigation ("go to <saved point>") ────────────────────────────────
  // Returns true when [transcript] was a navigation command (handled here —
  // spoken reply + action); false lets the conversational agent answer normally.
  bool _handleNavVoice(String transcript) {
    final points =
        ref.read(navPointsProvider).points.valueOrNull ?? const <NavPoint>[];
    final result = NavVoice.match(transcript, points);
    if (!result.isCommand) return false;

    // A nav command is OURS end-to-end: stop any in-flight agent audio AND
    // drop the agent's next turn so it can't talk over the departure phrase
    // or answer a navigation question it knows nothing about.
    _dropFirstAgentTurn = true;
    _audioBridge.stopPlayback();

    // "Go to the dock" / "go charge" / "go home" → return to the charging dock.
    // The dock isn't a saved point; goHome() drives home via the SDK IR-align
    // path and speaks its own departure + failure lines, so we just close the
    // session (navigation owns the speaker) and dispatch.
    if (result.isDock) {
      debugPrint('NavVoice: "$transcript" → return to charging dock (goHome)');
      InteractionLog.log('nav_command', 'heard "$transcript" → return to charging dock');
      if (_voiceActive) _endVoice();
      ref.read(navPointsProvider.notifier).goHome();
      return true;
    }

    // Same-name ambiguity ("Nishant" matches both Nishant Kumar and Nishant
    // Sharma) → ask which one; the next utterance resolves it (_resolvePendingNav).
    final ties = NavVoice.topTies(transcript, points);
    if (ties.length >= 2) {
      _askWhichPerson(ties);
      return true;
    }

    if (result.point != null) {
      _navigateToPoint(result.point!, transcript);
      return true;
    }

    // No matching point. The place may have been captured AFTER our list loaded
    // (just added in admin) — refresh + retry once; still nothing → a staff-aware
    // reply beats "no such place".
    () async {
      await ref.read(navPointsProvider.notifier).refresh();
      if (!mounted) return;
      final fresh =
          ref.read(navPointsProvider).points.valueOrNull ?? const <NavPoint>[];
      final retry = NavVoice.match(transcript, fresh);
      if (retry.point != null) {
        _navigateToPoint(retry.point!, transcript);
        return;
      }
      await _speakNoDestination(result.heard, fresh);
    }();
    return true;
  }

  /// Drive to [p], and — if it's a staff desk — remember we're taking the visitor
  /// to MEET that person, so the arrival hook checks whether they're there.
  /// Navigation owns the speaker from here (goTo speaks its own departure line),
  /// so we close the agent session first.
  void _navigateToPoint(NavPoint p, String transcript) {
    debugPrint('NavVoice: "$transcript" → go to "${p.name}"');
    InteractionLog.log('nav_command', 'heard "$transcript" → go to "${p.name}"');
    _meetStaffName = p.kind == 'staff_desk' ? p.name : null;
    if (_voiceActive) _endVoice();
    ref.read(navPointsProvider.notifier).goTo(p).then((ok) {
      if (!ok && mounted) {
        InteractionLog.log('nav_dispatch_failed', p.name);
        _meetStaffName = null;
        _speakGreeting("Sorry, I couldn't start navigating to ${p.name}. "
            'Please try again in a moment.');
      }
    });
  }

  /// Same-name disambiguation: ask which person, and hold the candidates so the
  /// next utterance ("Kumar" / "Nishant Sharma") is matched against them.
  void _askWhichPerson(List<NavPoint> candidates) {
    _pendingNavCandidates = candidates;
    _pendingNavTimeout?.cancel();
    _pendingNavTimeout = Timer(const Duration(seconds: 15), () {
      if (_pendingNavCandidates != null) {
        _clearPendingNav();
        if (mounted) _speakGreeting('No problem — just ask again when you like.');
      }
    });
    final names = candidates.map((p) => p.name).join(', or ');
    InteractionLog.log('nav_disambiguate', names);
    _dropFirstAgentTurn = true;
    _speakGreeting('I know a few people by that name — which one: $names?');
  }

  /// Resolve the clarification for an open "which <name>?" question.
  void _resolvePendingNav(String utterance) {
    final candidates = _pendingNavCandidates ?? const <NavPoint>[];
    _clearPendingNav();
    _dropFirstAgentTurn = true;
    _audioBridge.stopPlayback();
    final norm = fuzzyNormalize(utterance);
    NavPoint? pick;
    double best = 0;
    for (final p in candidates) {
      final s = fuzzyScore(norm, fuzzyNormalize(p.name));
      if (s > best) {
        best = s;
        pick = p;
      }
    }
    if (pick != null && best >= 0.5) {
      _navigateToPoint(pick, utterance);
    } else {
      final names = candidates.map((p) => p.name).join(' or ');
      _speakGreeting("Sorry, I didn't catch which one. You can say $names.");
    }
  }

  void _clearPendingNav() {
    _pendingNavCandidates = null;
    _pendingNavTimeout?.cancel();
    _pendingNavTimeout = null;
  }

  // ── ElevenLabs client tools (move 2) ────────────────────────────────────────
  // The agent resolves varied phrasing / pronouns / multi-turn params (e.g.
  // "take me to his desk" → navigate_to{destination:"David"}), then invokes a
  // tool. We run the REAL on-device action and reply so the agent can narrate the
  // outcome. Tool names + param keys must match the dashboard tool definitions.
  Future<void> _handleToolCall(
      String? tool, Map<String, dynamic>? params, String? callId) async {
    if (callId == null) return;
    // While a check-in dialog is collecting the visitor's details, the agent
    // must not also fire tools — it hears the same audio and would call
    // navigate_to on "…to Nishant", hijacking the turn (the on-device dialog
    // then times out without a name). Defer every tool until check-in finishes.
    if (_checkinStage != _CheckinStage.none) {
      _voiceAgent.sendToolResult(
          callId, 'One moment — I am finishing checking the visitor in.',
          isError: true);
      return;
    }
    final p = params ?? const <String, dynamic>{};
    String s(List<String> keys) {
      for (final k in keys) {
        final v = p[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }

    InteractionLog.log('tool_call', '$tool ${p.toString()}');
    try {
      switch (tool) {
        case 'navigate_to':
          final dest = s(['destination', 'place', 'location', 'person', 'name']);
          final points =
              ref.read(navPointsProvider).points.valueOrNull ?? const <NavPoint>[];
          final r = NavVoice.match('take me to $dest', points);
          if (r.isDock) {
            _voiceAgent.sendToolResult(callId, 'Returning to my charging dock.');
            _dropFirstAgentTurn = true;
            if (_voiceActive) _endVoice();
            ref.read(navPointsProvider.notifier).goHome();
          } else if (r.point != null) {
            _voiceAgent.sendToolResult(callId, 'On my way to ${r.point!.name}.');
            _navigateToPoint(r.point!, dest); // ends session; goTo speaks departure
          } else {
            _voiceAgent.sendToolResult(
                callId, 'No saved location matches "$dest".', isError: true);
          }
          return;

        case 'check_in':
          final host = s(['host', 'person', 'name', 'staff']);
          if (host.isEmpty) {
            _voiceAgent.sendToolResult(callId, 'Who would you like to see?', isError: true);
            return;
          }
          _voiceAgent.sendToolResult(callId, 'Checking you in to see $host.');
          _beginCheckin(host);
          return;

        case 'raise_enquiry':
        case 'place_order':
          final kind = tool == 'place_order' ? LeadKind.order : LeadKind.enquiry;
          final product = s(['product', 'item', 'model']);
          if (product.isEmpty) {
            _voiceAgent.sendToolResult(callId, 'Which product is this about?', isError: true);
            return;
          }
          final name = s(['customer_name', 'name', 'visitor_name']);
          final qtyRaw = p['quantity'];
          final res = await XboomLeadApi().submit(
            kind: kind,
            name: name.isEmpty ? 'Voice visitor' : name,
            phone: s(['phone', 'contact', 'mobile']),
            product: product,
            quantity: qtyRaw is num ? qtyRaw.toInt() : int.tryParse('$qtyRaw'),
            notes: s(['notes', 'details']),
          );
          final label = kind == LeadKind.order ? 'order' : 'enquiry';
          _voiceAgent.sendToolResult(
            callId,
            res.ok
                ? 'Your $label for $product is logged'
                    '${res.reference != null ? " (reference ${res.reference})" : ""}. '
                    'Our team will be in touch.'
                : "I couldn't log that just now — please try the front desk.",
            isError: !res.ok,
          );
          return;

        default:
          _voiceAgent.sendToolResult(callId, 'Unrecognized request.', isError: true);
      }
    } catch (e) {
      InteractionLog.log('tool_error', '$tool: $e');
      _voiceAgent.sendToolResult(
          callId, "Sorry, I couldn't do that just now.", isError: true);
    }
  }

  /// The "I can't take you there" reply — staff-aware: if the heard name is a
  /// known colleague whose desk simply isn't captured, say THAT specifically
  /// instead of "no such place".
  Future<void> _speakNoDestination(String heard, List<NavPoint> known) async {
    try {
      final staff = await _staffList();
      final nh = fuzzyNormalize(heard);
      StaffMember? who;
      double best = 0;
      for (final s in staff) {
        final score = fuzzyScore(nh, fuzzyNormalize(s.fullName));
        if (score > best) {
          best = score;
          who = s;
        }
      }
      if (who != null && best >= 0.5 && mounted) {
        InteractionLog.log('nav_staff_no_desk', who.fullName);
        _speakGreeting("I know ${who.fullName}, but I don't have their desk "
            'saved yet — someone can capture it from the robot.');
        return;
      }
    } catch (_) {
      // fall through to the generic reply
    }
    if (!mounted) return;
    final list = known.map((p) => p.name).take(3).join(', ');
    InteractionLog.log('nav_no_match', 'nothing matches "$heard"');
    _speakGreeting(known.isEmpty
        ? "I don't have any saved locations yet."
        : "No place called $heard. I can take you to: $list.");
  }

  // ── Stop command ("stop", "be quiet", "that's enough", "goodbye"…) ─────────
  // The visitor wants Mini to stop: cut off any speech, close the mic/session,
  // and settle to attentive (a person is still likely there) or idle. Returns
  // true when the utterance was a stop request (handled here, agent turn dropped).
  static final RegExp _stopPhrase = RegExp(
    r'\b(stop|quiet|be quiet|shut up|shush|hush|enough|thats enough|'
    r"that's enough|stop talking|stop speaking|stop it|no more|"
    r'never ?mind|forget it|cancel|goodbye|good bye|bye bye|'
    r'bye|thats all|i am done|im done)\b',
    caseSensitive: false,
  );

  bool _handleStopCommand(String transcript) {
    final t = transcript.toLowerCase().trim();
    if (t.isEmpty) return false;
    // Only treat SHORT utterances as stop commands — a long sentence that
    // merely contains "stop" (e.g. "where is the bus stop") shouldn't end the
    // session. ≤4 words keeps it to genuine stop requests.
    final wordCount = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount > 4) return false;
    if (!_stopPhrase.hasMatch(t)) return false;
    debugPrint('Voice: STOP command → ending session');
    InteractionLog.log('voice_stop_command', transcript);
    _audioBridge.stopPlayback(); // cut off any current speech immediately
    _dropFirstAgentTurn = true; // don't let the agent reply to this turn
    if (_voiceActive) {
      _endVoice(); // mic off + session closed (sessionEnded settles the face)
    }
    // Settle to attentive (person likely present) or idle — the sessionEnded
    // handler also does this, but set it now for an instant visual response.
    if (mounted) {
      setState(() => _face = _face.copyWith(
          state: _present ? FaceStateKind.attentive : FaceStateKind.idle,
          mouthOpen: 0));
    }
    return true;
  }

  // ── Persona voice commands ("change your name / voice") ────────────────────
  // Rename persists instantly (UI titles, greetings' {robot}, EL dynamic var).
  // A voice change persists + applies to TTS immediately; the OPEN agent
  // session keeps its old voice, so we close it after confirming — the next
  // session starts with the new voice via the tts override.
  bool _handlePersonaVoice(String transcript) {
    final result = PersonaVoice.match(transcript);
    if (!result.isCommand) return false;
    _dropFirstAgentTurn = true;
    _audioBridge.stopPlayback();
    switch (result.kind!) {
      case PersonaCommandKind.rename:
        final name = result.newName!;
        debugPrint('Persona: rename → "$name"');
        InteractionLog.log('persona_rename', 'heard "$transcript" → renamed to "$name"');
        RobotConfig.setRobotName(name);
        _speakGreeting("Okay! From now on, my name is $name. "
            'Nice to meet you again.');
        break;
      case PersonaCommandKind.voice:
        final preset = result.preset;
        if (preset == null) {
          final options =
              kVoicePresets.map((p) => p.name.split(' ').first).join(', ');
          debugPrint('Persona: voice "${result.heard}" → no preset');
          InteractionLog.log('persona_voice_unknown', result.heard);
          _speakGreeting("I don't have a ${result.heard} voice yet. "
              'I can sound like: $options.');
          break;
        }
        debugPrint('Persona: voice → ${preset.name}');
        InteractionLog.log(
            'persona_voice', 'heard "$transcript" → voice ${preset.name}');
        RobotConfig.setVoice(preset.voiceId, preset.name);
        // Confirm IN THE NEW VOICE (TTS reads the config per utterance)…
        _speakGreeting('How do I sound? This is my ${preset.name} voice.');
        // …then retire the open session so the conversational agent comes
        // back with the same new voice.
        if (_voiceActive) _endVoice();
        break;
    }
    return true;
  }

  // ── Voice visitor check-in ("I'm here to see <host>") ──────────────────────
  // Returns true when [transcript] belongs to the check-in dialog (intent turn
  // OR the follow-up name turn) — handled here with our own spoken replies, so
  // the conversational agent never answers a flow it knows nothing about.
  bool _handleCheckinVoice(String transcript) {
    // A dialog is open — this utterance answers whichever question we asked.
    if (_checkinStage != _CheckinStage.none) {
      _dropFirstAgentTurn = true;
      _audioBridge.stopPlayback();
      _advanceCheckin(transcript);
      return true;
    }
    final result = CheckinVoice.match(transcript);
    if (!result.isCommand) return false;
    _dropFirstAgentTurn = true;
    _audioBridge.stopPlayback();
    _beginCheckin(result.hostHeard);
    return true;
  }

  /// Arm (or re-arm) the per-turn silence window. After the name is known a
  /// timeout SUBMITS rather than abandons — the host still gets notified.
  void _armCheckinTimeout() {
    _checkinTimeout?.cancel();
    _checkinTimeout = Timer(_checkinNameWindow, () {
      if (_checkinStage == _CheckinStage.none) return;
      if (_checkinName != null) {
        debugPrint('Checkin: window expired with a name — submitting what we have');
        _submitCheckin();
      } else {
        debugPrint('Checkin: name window expired — dialog abandoned');
        _resetCheckin();
      }
    });
  }

  void _resetCheckin() {
    _checkinTimeout?.cancel();
    _checkinStage = _CheckinStage.none;
    _checkinHost = null;
    _checkinName = null;
    _checkinCompany = null;
  }

  Future<void> _beginCheckin(String hostHeard) async {
    List<StaffMember> staff;
    try {
      staff = await _staffList();
    } catch (e) {
      debugPrint('Checkin: staff fetch failed: $e');
      _speakGreeting("I'm sorry — I can't reach the reception system right now. "
          'Please check in at the front desk.');
      return;
    }
    final host = CheckinVoice.bestHost(hostHeard, staff);
    if (host == null) {
      // The on-device vendor ASR mangles Indian names badly (e.g. "Nishant" →
      // "sound"), so a no-match here is usually a mishearing, not an unknown
      // person. Rather than answer "I couldn't find <misheard>", stay silent and
      // let the ElevenLabs agent's check_in tool handle it — its cloud ASR
      // resolves names far better (it hears "Nishant" correctly, as proven by
      // navigate_to). The turn is already consumed by _handleCheckinVoice, so the
      // misheard vendor text is NOT forwarded to the agent to override its audio.
      debugPrint('Checkin: no on-device match for "$hostHeard" — deferring to EL check_in tool');
      return;
    }
    debugPrint('Checkin: host "$hostHeard" → ${host.fullName} (${host.id})');
    _checkinHost = host;
    _checkinName = null;
    _checkinCompany = null;
    _checkinStage = _CheckinStage.name;
    _armCheckinTimeout();
    _speakGreeting('I will let ${host.fullName} know. Your name, please?');
  }

  /// One answered turn: record it and either ask the next question or submit.
  void _advanceCheckin(String transcript) {
    // Cancel abandons the whole dialog at any stage.
    if (CheckinVoice.isCancel(transcript)) {
      _resetCheckin();
      _speakGreeting('No problem.');
      return;
    }

    switch (_checkinStage) {
      case _CheckinStage.name:
        final name = CheckinVoice.extractVisitorName(transcript);
        if (name.isEmpty) {
          _resetCheckin();
          _speakGreeting("Sorry, I didn't catch your name — "
              'please check in at the front desk.');
          return;
        }
        _checkinName = name;
        _checkinStage = _CheckinStage.company;
        _armCheckinTimeout();
        _speakGreeting('Thank you, $name. Which company are you visiting from?');
        return;

      case _CheckinStage.company:
        // Skipping is fine — company is optional on the visitor record.
        _checkinCompany =
            CheckinVoice.isSkip(transcript) ? null : _detailOrNull(transcript);
        _checkinStage = _CheckinStage.purpose;
        _armCheckinTimeout();
        _speakGreeting('And may I ask what your visit is regarding?');
        return;

      case _CheckinStage.purpose:
        final purpose =
            CheckinVoice.isSkip(transcript) ? null : _detailOrNull(transcript);
        _submitCheckin(purpose: purpose);
        return;

      case _CheckinStage.none:
        return;
    }
  }

  static String? _detailOrNull(String transcript) {
    final d = CheckinVoice.extractDetail(transcript);
    return d.isEmpty ? null : d;
  }

  /// POST /visit with whatever the dialog collected, then confirm out loud.
  Future<void> _submitCheckin({String? purpose}) async {
    final host = _checkinHost;
    final name = _checkinName;
    final company = _checkinCompany;
    _resetCheckin(); // clear state first — the await must not leave a live dialog
    if (host == null || name == null) return;

    InteractionLog.log('checkin_submit',
        '$name → ${host.fullName}${company != null ? ' ($company)' : ''}');
    var ok = false;
    try {
      ok = await _checkinApi.postVisit(
        visitorName: name,
        hostStaffId: host.id,
        company: company,
        purpose: purpose,
      );
    } catch (e) {
      debugPrint('Checkin: POST /visit failed: $e');
    }
    _speakGreeting(ok
        ? 'Thank you, $name. I have let ${host.fullName} know you are here — '
            'please have a seat.'
        : "I'm sorry, I couldn't record your check-in. "
            'Please contact the front desk.');
  }

  /// GET /staff with a short cache — the directory changes rarely; a visitor
  /// dialog shouldn't wait on a fresh fetch every turn.
  Future<List<StaffMember>> _staffList() async {
    final now = DateTime.now();
    if (_staffCache != null &&
        _staffCacheAt != null &&
        now.difference(_staffCacheAt!) < _staffCacheTtl) {
      return _staffCache!;
    }
    final staff = await _checkinApi.fetchStaff();
    _staffCache = staff;
    _staffCacheAt = now;
    return staff;
  }

  // ── Escort arrival check ────────────────────────────────────────────────────
  // Mid-route we cannot see the follower (the chest camera faces the direction
  // of travel) — but after arriving we should be face-to-face again. If nobody
  // shows up in front of the camera shortly after a non-patrol arrival, the
  // visitor was lost en route: say so (configurable, {name} = the point).
  void _onEscortArrived(String pointName) {
    // Meeting a staff member? Check whether they're actually at their desk. The
    // camera faces forward, so a short settle after arriving gives the presence
    // (facePresent) signal time to catch them.
    if (_meetStaffName != null && _meetStaffName == pointName) {
      final name = _meetStaffName!;
      _meetStaffName = null;
      _meetPresenceCheck?.cancel();
      _meetPresenceCheck = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        if (_present) {
          InteractionLog.log('meet_staff_present', name);
          _speakGreeting("Here's $name's desk.");
        } else {
          InteractionLog.log('meet_staff_absent', name);
          _speakGreeting("This is $name's desk, but they've stepped away.");
        }
      });
      return; // meet-staff arrival owns this event; skip the escort follower check
    }
    if (ref.read(navPointsProvider).navSource == 'patrol') return;
    _escortArrivalCheck?.cancel();
    _escortArrivalCheck = Timer(const Duration(seconds: 8), () {
      if (!mounted || _voiceActive) return;
      if (ref.read(navPointsProvider).navigatingTo != null) return; // re-tasked
      if (_present) {
        // Visitor followed us here (face-to-face again) → don't just stand
        // there mute: re-open the mic so "take me somewhere else" / a question
        // works immediately. The arrival announcement has already played; the
        // idle watchdog closes this session after 15s of silence as usual.
        if (RobotConfig.autoOpenMic) {
          debugPrint('Escort: visitor in view after arriving at "$pointName" '
              '→ auto-opening mic');
          InteractionLog.log('escort_arrival_listen', pointName);
          _startVoice(auto: true);
        }
        return;
      }
      final template = RobotConfig.escortLostText;
      if (template.isEmpty) return;
      debugPrint('Escort: nobody in view after arriving at "$pointName"');
      InteractionLog.log('escort_lost_visitor', pointName);
      _speakGreeting(template.replaceAll('{name}', pointName));
      // No session will flush this interaction (the visitor is gone) — send
      // the ledger now so the abandoned escort is captured for analysis.
      _spine.logConversation(const [], actions: InteractionLog.drain());
    });
  }

  // Greet the person and STOP. We deliberately do NOT auto-open the mic after a
  // greeting: an open mic with no real speaker made Mini re-hear its own greeting
  // echo and monologue forever. The visitor taps the mic button to start talking;
  // until then Mini stays quiet and attentive. (_startAutoListen / _pendingAutoListen
  // are now dormant — kept only for the hold-to-talk / voice-command paths that open
  // a session directly via _startVoice.)
  void _greetThenListen(String phrase) {
    if (_voiceActive) return; // already in a conversation
    // Auto-open the mic after the greeting ONLY if enabled (Settings). Default
    // OFF: Mini greets, but the mic opens only when a person taps Talk.
    if (RobotConfig.autoOpenMic) {
      _pendingAutoListen = true;
      _autoListenFallback?.cancel();
      _autoListenFallback = Timer(const Duration(seconds: 4), _startAutoListen);
    }
    _speakGreeting(phrase);
  }

  // Hand off from the spoken greeting to an open mic. Idempotent (fires once),
  // and only while the visitor is still present and no session is already running.
  void _startAutoListen() {
    _autoListenFallback?.cancel();
    if (!_pendingAutoListen) return;
    _pendingAutoListen = false;
    if (!mounted || _voiceActive || !_present) return;
    debugPrint('AmbientFace: greeting done → auto-opening mic (listening)');
    _startVoice(auto: true);
  }

  // Single idle watchdog for ALL sessions — auto AND manual (mic button). Closes
  // the session after _engageWindow of silence before the first exchange
  // (passer-by / mic pressed but nobody talks), or after _conversationIdle once a
  // real conversation has started. "Activity" = Mini speaking (playback) OR the
  // user speaking (agentThinking / userSpeaking) — see _bumpActivity — so an
  // active back-and-forth keeps it open on EITHER screen, while genuine silence
  // closes it (mic button reverts to the idle orange mic). A held push-to-talk
  // never counts as idle. Replaces the old engage + hard-cap timers.
  void _startIdleWatch() {
    _bumpActivity(); // grace: full silence window before the first close
    _idleWatch?.cancel();
    _idleWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_voiceActive) return;
      if (_pushToTalk) {
        // The visitor is physically holding the button — that IS activity, even
        // in silence; don't let the countdown close the session under their finger.
        _silenceAccumMs = 0;
        _noFaceAccumMs = 0;
        return;
      }
      // VISITOR-PRESENCE GATE (ElevenLabs quota): once the visitor has walked away
      // (no face for a few seconds — _present already carries a 3s debounce hold),
      // close the session instead of letting the agent answer an empty room for
      // the full 15s silence window. Cuts characters spent on phantom turns.
      if (!_present) {
        _noFaceAccumMs += 1000;
        if (_noFaceAccumMs >= _voiceNoFaceCloseMs) {
          debugPrint('IdleWatch: visitor gone (${_voiceNoFaceCloseMs ~/ 1000}s no face) → closing');
          _endVoice();
          return;
        }
      } else {
        _noFaceAccumMs = 0;
      }
      final speaking = _face.state == FaceStateKind.speaking ||
          _face.state == FaceStateKind.thinking;
      // Count ONLY genuine silence: seconds where Mini isn't talking and no real
      // user words have landed. While Mini speaks the counter FREEZES (his own
      // answer must not burn the visitor's reply window) but does NOT reset — so a
      // talk-to-noise loop still closes as the gaps accumulate. Reset happens only
      // in _bumpActivity (real words / hold-to-talk), never from mic loudness.
      if (!speaking) {
        _silenceAccumMs += 1000;
        final window = _conversationIdle.inMilliseconds; // 15s
        debugPrint('IdleWatch: silence=${(_silenceAccumMs / 1000).toStringAsFixed(0)}s '
            'phantom=$_phantomTurns state=${_face.state.name}');
        if (_silenceAccumMs >= window) {
          debugPrint('AmbientFace: ${window ~/ 1000}s of user silence → auto-closing');
          _endVoice();
        }
      }
    });
  }

  // Reset the idle countdown — call ONLY for GENUINE user engagement (real
  // transcribed words, hold-to-talk). Never from raw mic loudness or empty VAD
  // turns: with no AEC, ambient room noise crosses any amplitude threshold and
  // would keep the session alive forever (the reported "never auto-closes" bug).
  void _bumpActivity() {
    _silenceAccumMs = 0;
    _phantomTurns = 0;
    _noFaceAccumMs = 0;
  }

  void _stopIdleWatch() {
    _idleWatch?.cancel();
    _idleWatch = null;
  }

  void _onPersonDetected(bool pd) {
    // Coarse presence: promote idle → attentive (eyes centered, no box to track).
    if (pd && !_present && _face.state == FaceStateKind.idle) {
      setState(() => _face =
          _face.copyWith(state: FaceStateKind.attentive, gazeX: 0, gazeY: 0));
    }
  }

  /// CSJBot on-device staff face recognition — identity FALLBACK only.
  ///   • near present → wake the face (idle/sleepy → attentive). Always.
  ///   • recognized, confidence ≥ 60 → greet BY NAME, but ONLY while spine is
  ///     offline — connected, spine's face_detected is the sole identity source
  ///     (one calibrated pipeline; the two must never race).
  ///   • recognized but uncertain (< 60) → ignored; the recognition window's
  ///     timeout delivers the visitor hello.
  /// Never interrupts a live conversation. Never triggers on mere presence —
  /// greetings stay gated on the camera attention gate.
  void _onFaceRecognized(FaceEvent e) {
    if (_voiceActive) return; // mid-conversation — don't greet over it
    switch (e.type) {
      case 'near':
        if (e.present == true &&
            (_face.state == FaceStateKind.idle ||
                _face.state == FaceStateKind.sleepy)) {
          _setStateKind(FaceStateKind.attentive);
        }
        return;
      case 'recognized':
        if (_spine.isConnected) return; // spine identity is authoritative
        if (_greeted) return; // already greeted this visit — don't repeat
        // Fallback identity must still wait for the attention gate — only greet
        // inside an open recognition window (i.e. someone is looking at us).
        if (!_awaitingRecognition) return;
        final name = e.name?.trim() ?? '';
        if (e.confidence >= 60 && name.isNotEmpty) {
          // Matched → win the recognise-first window and greet BY NAME.
          _awaitingRecognition = false;
          _recognitionWaitTimer?.cancel();
          _greetStaff(name);
        }
        return;
    }
  }

  // Greet a recognised staff member by name (spine-offline fallback path). The
  // on-screen overlay shows the visual greeting; the SPOKEN, by-name, humorous
  // line is delivered by ElevenLabs — we inject "STAFF_RECOGNIZED: <name>" as
  // the first turn so the agent opens the conversation itself (no separate TTS
  // greeting → no overlap). Shares the Settings-tunable _regreetWindow debounce
  // with the spine face_detected path.
  void _greetStaff(String name) {
    // Shares the debounce with the spine face_detected path (greetingProvider).
    // This path already runs only when nothing else owns the speaker, so it
    // isn't "busy" by construction.
    if (!ref.read(greetingProvider.notifier).mayGreetStaff(name, busy: false)) {
      return;
    }
    _recognitionWaitTimer?.cancel();
    _pendingVisitorTimer?.cancel(); // staff wins — cancel any deferred visitor hello
    _greeted = true; // counts as this visit's one greeting (blocks the plain hello)
    _pendingGreetName = name;
    _pendingGreetAtMs = DateTime.now().millisecondsSinceEpoch;
    final lang = languageForCode(RobotConfig.voiceLanguageCode);
    _showGreeting(lang.greetText(name), staffName: name); // overlay + face state
    if (RobotConfig.autoOpenMic) {
      // STAFF_RECOGNIZED priming is centralised in _startVoice (covers this path
      // AND the spine path AND a manual Talk right after recognition).
      _startVoice(auto: true); // opens the session → agent greets by name, then listens
    } else {
      // Default: greet by name via TTS; the mic opens only on a Talk-button tap.
      _speakGreeting(_staffSpeech(lang, name));
    }
  }

  void _setStateKind(FaceStateKind k) {
    if (!mounted) return;
    setState(() => _face = _face.copyWith(state: k));
  }

  // Run a multi-step physical head gesture, skipping if one is already in flight
  // (so nod / tilt / sway don't fight each other) or no session is live.
  // Best-effort; silent off-device / when the SDK is busy.
  Future<void> _gesture(Future<void> Function() g) async {
    if (!_voiceActive || _gestureBusy) return;
    _gestureBusy = true;
    try {
      await g();
    } catch (_) {
      // off-device or SDK busy — ignore
    } finally {
      _gestureBusy = false;
    }
  }

  /// A voice-related config value changed. Only act on an actual engine SWITCH
  /// (elevenConfigRev also bumps on key edits) — swap the live provider so the
  /// next session uses the newly-selected engine.
  void _onVoiceConfigChanged() {
    if (RobotConfig.voiceProvider == _voiceProviderName) return;
    _rebuildVoiceProvider();
  }

  /// Tear down the current voice engine and build the newly-selected one. Any
  /// open session is ended first so we never run two engines at once.
  void _rebuildVoiceProvider() {
    _voiceProviderName = RobotConfig.voiceProvider;
    debugPrint('Voice: switching engine → $_voiceProviderName');
    InteractionLog.log('voice_provider_switch', _voiceProviderName);
    if (_voiceActive) _endVoice();
    _voiceSub?.cancel();
    _voiceAgent.dispose();
    _voiceAgent = buildVoiceProvider();
    _voiceSub = _voiceAgent.events.listen(_onVoiceEvent);
    if (mounted) setState(() {});
  }

  // ── #80 voice: the selected engine's session drives the face state machine ──
  void _onVoiceEvent(VoiceEvent e) {
    debugPrint('Voice: ${e.kind.name}'
        '${e.text != null && e.text!.isNotEmpty ? " [${e.text}]" : ""}');
    switch (e.kind) {
      case VoiceEventKind.sessionStarted:
        // Open in listening — Mini is waiting for the user (the ring shows).
        // Also clear any stale playback (e.g. a reply cut off by a language
        // switch reconnect) so we don't talk over the new session.
        _suppressTeardown = false; // a new session is live — clear any pending recovery
        VoiceArbiter.agentActive = true; // the conversation now owns the speaker
        _audioBridge.stopPlayback(); // silence any in-flight announcement/escort TTS
        _audioBridge.startSpeechEngine(); // session-gated mic engine (startIsr)
        setState(() {
          _voiceActive = true;
          _face = _face.copyWith(state: FaceStateKind.listening);
        });
        _startIdleWatch(); // auto sessions: begin the inactivity countdown
        break;
      case VoiceEventKind.userSpeaking:
        // The engine's VAD fired "user started talking". We barge-in: stop
        // playback and show listening.
        _dropFirstAgentTurn = false; // allow the upcoming agent audio again
        _audioBridge.stopPlayback();
        // Keep the session ALIVE on this — UNLESS the robot itself is speaking (or
        // just did), in which case it's likely its own echo. Previously we never
        // reset idle here, so a visitor who spoke but whose transcript got muted /
        // echo-flagged still hit the 15s idle close mid-conversation. When the
        // robot ISN'T speaking, VAD firing is a genuine "person engaging" signal.
        final nowUs = DateTime.now().millisecondsSinceEpoch;
        final echoUs = _face.state == FaceStateKind.speaking ||
            (nowUs - _lastSpeakingMs) < _echoGuardMs;
        if (!echoUs) _bumpActivity();
        // Acknowledging nod while the visitor talks (throttled ~2.5s).
        if (!echoUs && nowUs - _lastNodMs > 2500) {
          _lastNodMs = nowUs;
          _gesture(RobotGestures.headNod);
        }
        setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
        break;
      case VoiceEventKind.agentThinking:
        // A new turn is starting → stop dropping audio; the upcoming reply plays.
        // NOTE: in this ElevenLabs integration the USER's speech surfaces here
        // (with the transcript), not as userSpeaking — so this is our reliable
        // "a real person engaged" signal. Mark the conversation started + keep alive.
        _gesture(RobotGestures.headTilt); // curious "thinking" tilt (physical head)
        _dropFirstAgentTurn = false; // real reply coming → play it
        _reconnectAttempts = 0; // a real turn landed → refresh the retry budget
        // Reset the idle timer ONLY on GENUINE user words — a non-empty transcript
        // that isn't Mini's own echo. Two failure modes this rules out:
        //   • echo: Mini's voice re-transcribed while/just after he speaks, and
        //   • phantom: an empty "..." turn where EL's VAD tripped on room noise.
        // Both used to reset the watchdog forever. A phantom/echo turn instead
        // increments _phantomTurns; 3 in a row means Mini is answering the room,
        // not a person, so we close.
        final now = DateTime.now().millisecondsSinceEpoch;
        final likelyEcho = _face.state == FaceStateKind.speaking ||
            (now - _lastSpeakingMs) < _echoGuardMs;
        final hasWords =
            e.text != null && e.text!.trim().isNotEmpty && e.text!.trim() != '...';
        if (hasWords && !likelyEcho) {
          _bumpActivity(); // genuine user speech → keep the session alive
          InteractionLog.log('user_utterance_el', e.text!);
        } else if (hasWords && likelyEcho) {
          // The robot's OWN speech echoing back (no hardware AEC). Expected while
          // it talks — NOT evidence of an empty room, so it must NOT count toward
          // the phantom auto-close. That mis-count was hanging up on the visitor
          // mid-conversation (3 echo turns → session closed). The idle watchdog
          // still closes a genuinely silent session, so this stays safe.
          debugPrint('Voice: echo turn ignored (robot hearing itself) — not a phantom');
        } else {
          // Empty "..." turn — the engine's VAD tripped on room noise with no
          // words. THIS is a real phantom; too many in a row = answering the room.
          _phantomTurns++;
          debugPrint('Voice: empty phantom #$_phantomTurns → not resetting idle');
          if (_phantomTurns >= _maxPhantomTurns) {
            debugPrint('Voice: $_maxPhantomTurns phantom turns, no real user → auto-closing');
            _dropFirstAgentTurn = true;
            _endVoice();
            break;
          }
        }
        // Voice command? (stop, navigation/dock, persona, check-in, and the
        // catalog's extended intents). Recognized via the spine-driven registry;
        // WE handle the reply + action and drop the agent's own answer to this
        // turn (it doesn't know our saved points, staff directory, or /visit).
        // Stop still wins first — it's priority 0 inside the registry.
        // CRITICAL: never dispatch a command from an ECHO transcript — without
        // hardware AEC the robot's OWN audible speech (greeting/announcement) is
        // re-transcribed here, and "…bye"/"stop"-like echoes were tripping the
        // STOP command and killing the session mid-conversation. Genuine barge-in
        // still works via the vendor-ASR path (_onVendorAsr → _isGenuineBargeIn).
        if (e.text != null && !likelyEcho && _dispatchVoiceCommand(e.text!)) {
          _dropFirstAgentTurn = true;
          break;
        }
        // Genuine processing gap (STT done, reply not yet streaming).
        setState(() => _face = _face.copyWith(state: FaceStateKind.thinking, mouthOpen: 0));
        break;
      case VoiceEventKind.agentSpeaking:
        // Mute the robot's built-in (Chinese) TTS so only the ElevenLabs voice is
        // heard — the CSJBot AIUI runs in parallel (it gives us the mic) but must
        // not talk over Mini.
        _audioBridge.stopSpeak();
        // Auto session's unprompted FIRST message: drop it (we already greeted) and
        // stay in listening so the mic isn't muted before the visitor can speak.
        if (_dropFirstAgentTurn) break;
        // NOTE: deliberately NOT bumping activity here — Mini's OWN speech must not
        // keep the session alive, or an agent that keeps talking with no visitor
        // never returns to idle (obs 1). Only USER input resets the idle timer.
        _gesture(RobotGestures.chestAttention); // perk up to speak (physical head)
        setState(() => _face = _face.copyWith(state: FaceStateKind.speaking));
        break;
      case VoiceEventKind.audioChunk:
        // Just QUEUE the chunk for playback. Lip-sync (mouthOpen) + the
        // speaking→listening transition are driven by _onPlaybackLevel, which
        // tracks the SPEAKER (not network arrival) — so lips move while Mini is
        // actually talking and close exactly when playback ends.
        // Dropped after a barge-in, the auto first message, or while holding to talk.
        if (_dropFirstAgentTurn || _pushToTalk) break;
        if (e.audioChunk != null) _audioBridge.playChunk(e.audioChunk!);
        break;
      case VoiceEventKind.toolCall:
        // The LLM resolved the visitor's intent (phrasing/pronouns/params) and
        // invoked a client tool — run the REAL action locally and reply.
        _handleToolCall(e.toolName, e.toolParams, e.toolCallId);
        break;
      case VoiceEventKind.sessionEnded:
        // Recovering from an unexpected drop → ignore this teardown; the scheduled
        // reconnect owns recovery and will reopen the session (engine keeps running
        // through the gap — startSpeechEngine on the reopened session is idempotent).
        if (_suppressTeardown) {
          _suppressTeardown = false;
          return;
        }
        VoiceArbiter.agentActive = false; // speaker freed → announcements may resume
        RobotGestures.headCenter(); // conversation over → recenter the physical head
        _audioBridge.stopSpeechEngine(); // session over → stop the mic engine
        _intentionalClose = false;
        _reconnectAttempts = 0;
        _stopIdleWatch();
        _autoSession = false;
        _audioBridge.stopMic();
        _audioBridge.stopPlayback();
        InteractionLog.log('session_ended', 'idle/ended');
        // Flush the WHOLE interaction — spoken turns + the action ledger — as
        // one chronological record (fire-and-forget).
        _spine.logConversation(_voiceAgent.transcript,
            actions: InteractionLog.drain());
        setState(() {
          _voiceActive = false;
          _micLevel = 0;
          _face = _face.copyWith(state: FaceStateKind.idle, mouthOpen: 0);
        });
        break;
      case VoiceEventKind.error:
        // Unexpected server drop (e.g. ElevenLabs `code 1002`)? If the visitor is
        // still here and we haven't used our retry, reopen the session ONCE silently
        // instead of dropping to idle / showing the unavailable dialog.
        if (!_intentionalClose && _present && _reconnectAttempts < _maxReconnects) {
          _reconnectAttempts++;
          _suppressTeardown = true; // ignore the sessionEnded that follows this error
          debugPrint('Voice: unexpected drop → auto-reconnect '
              '$_reconnectAttempts/$_maxReconnects (${e.text})');
          _audioBridge.stopMic();
          _audioBridge.stopPlayback();
          _reconnectTimer?.cancel();
          _reconnectTimer = Timer(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            if (!_present) {
              _finalizeIdle(); // visitor left during the gap → settle to idle
            } else {
              _startVoice(auto: _autoSession, reconnect: true);
            }
          });
          break;
        }
        // Out of retries (or a deliberate close) → give up cleanly.
        _suppressTeardown = false;
        VoiceArbiter.agentActive = false; // failed/closed → free the speaker
        RobotGestures.headCenter(); // recenter the physical head on close
        _stopIdleWatch();
        _autoSession = false;
        _audioBridge.stopMic();
        if (e.serviceUnavailable) _showServiceAlert(e.text);
        setState(() {
          _voiceActive = false;
          _micLevel = 0;
        });
        break;
    }
    // Mirror the voice phase to spine → admin app.
    _spine.sendVoiceState(e.kind);
  }

  // [auto] = true when opened automatically after a greeting. Both auto and
  // manual (mic button / wake word) sessions are closed by the idle watchdog on
  // genuine silence; [auto] still controls greeting/first-turn behaviour.
  void _startVoice({bool auto = false, bool reconnect = false}) {
    _pendingAutoListen = false; // a session is starting — cancel any greeting hand-off
    _autoListenFallback?.cancel();
    // Fire-and-forget: pull the latest saved points so a location captured
    // since the last session (robot or admin side) matches on the FIRST try.
    // The no-match handler also refreshes+retries as a safety net.
    ref.read(navPointsProvider.notifier).refresh();
    _autoSession = auto;
    // A fresh (non-reconnect) start clears the retry budget; a reconnect keeps it so
    // a server that immediately drops again can't loop forever.
    if (!reconnect) {
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
    }
    _intentionalClose = false;
    // Auto sessions already greeted via TTS, so DROP the ElevenLabs agent's own
    // unprompted first message — playing it would hold the face in "speaking" for
    // several seconds and the half-duplex gate would mute the visitor's reply the
    // whole time (root cause of "auto greeting can't hear me"). Cleared on the
    // first real user input. Manual (button) sessions keep the first message.
    _dropFirstAgentTurn = false; // TEMP: reverted — dropping it may break EL turn-taking
    // Prime the agent with the freshly-recognised staff member (spine OR on-device)
    // so this session opens KNOWING who's in front of it — Mini can greet by name
    // and answer "do you recognize me?". One-shot first turn; the agent's dashboard
    // prompt interprets the STAFF_RECOGNIZED: prefix. Freshness-guarded so a stale
    // name from an earlier visit doesn't leak into a much later manual session.
    final recognized = _pendingGreetName?.trim();
    final hasRecognized = recognized != null &&
        recognized.isNotEmpty &&
        DateTime.now().millisecondsSinceEpoch - _pendingGreetAtMs < 120000;
    if (hasRecognized) {
      _voiceAgent.injectGreeting('STAFF_RECOGNIZED: $recognized');
    }
    // Manual mic-tap (or wake word): greet immediately so the visitor gets an
    // instant "Hello" / "Hello <Name>" instead of silence until they speak first.
    // Speak it via TTS and DROP the agent's own first turn so it doesn't greet on
    // top. (Auto sessions are already greeted by the face-detection flow.)
    if (!auto && !reconnect) {
      _dropFirstAgentTurn = true;
      // But do NOT greet again if this visit was already greeted (e.g. the face
      // was recognised and "Hello <Name>" already played) — a second hello on the
      // mic tap is the double-greeting the visitor complained about.
      if (!_greeted) {
        _greeted = true;
        _speakGreeting(hasRecognized ? 'Hello $recognized!' : 'Hello! How can I help you?');
      }
    }
    _voiceAgent.startSession();
    // Capture mic → pipe PCM chunks to the agent AND meter the level so the UI
    // shows we're actually hearing audio (mic fails gracefully on the emulator).
    _audioBridge.startMic((chunk) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rms = VoiceAgent.pcmRms(chunk);
      // Hold-to-talk: the visitor is deliberately pressing the button, so send the
      // FULL mic audio — no noise gate, no half-duplex — for reliable capture in a
      // loud room. (Agent audio is dropped meanwhile so it doesn't talk over them.)
      if (_pushToTalk) {
        _voiceAgent.sendAudioChunk(chunk);
        _updateMicLevel(rms);
        return;
      }
      // Half-duplex echo gate (the ONLY gate now): never feed Mini's own voice back
      // to ElevenLabs. His voice plays through a separate AudioTrack the CSJBot CAE
      // does NOT echo-cancel, so otherwise he hears himself and loops forever. The
      // tail-guard covers the speaker buffer after we flip to listening.
      final speakingMuted = _face.state == FaceStateKind.speaking ||
          (now - _lastSpeakingMs) < _micTailGuardMs;
      // NOTE: mic loudness is NOT used to keep the session alive. Without hardware
      // AEC, ambient room noise crosses any amplitude threshold ~5s after Mini
      // stops and both (a) reset the idle timer and (b) tripped ElevenLabs' VAD
      // into phantom "..." turns, so the session never auto-closed. The idle timer
      // now advances on wall-clock silence and resets only on real transcribed
      // words (see _startIdleWatch / _bumpActivity).
      // The amplitude noise gate (squelch) was REMOVED (obs 3): it dropped soft and
      // sentence-onset speech (RMS < 0.04 → silence sent), so capture was hit-or-miss.
      // We now feed ElevenLabs the REAL mic continuously whenever Mini isn't
      // speaking and let its own server-side VAD decide when a turn starts/ends.
      // While Mini speaks we send SILENCE so the stream stays unbroken for EL's VAD
      // without leaking his echo back in.
      _voiceAgent.sendAudioChunk(speakingMuted ? Uint8List(chunk.length) : chunk);
      _updateMicLevel(rms);
    });
  }

  void _endVoice() {
    _intentionalClose = true; // a deliberate close → never auto-reconnect
    _reconnectTimer?.cancel();
    _voiceAgent.endSession();
  }

  // Settle the voice UI back to idle without ending a (already-closed) session —
  // used when a reconnect is abandoned because the visitor walked away.
  void _finalizeIdle() {
    _suppressTeardown = false;
    _stopIdleWatch();
    _autoSession = false;
    _audioBridge.stopMic();
    _audioBridge.stopPlayback();
    if (!mounted) return;
    setState(() {
      _voiceActive = false;
      _micLevel = 0;
      _face = _face.copyWith(state: FaceStateKind.idle, mouthOpen: 0);
    });
  }

  // Hold-to-talk (press & hold the mic button). Opens a session if none, barges in
  // over any current speech, and routes the FULL mic to ElevenLabs while held —
  // bypassing the noise gate for reliable capture in a loud room. On release the
  // mic resumes its gated/silence stream so ElevenLabs finalises the turn + replies.
  void _startHoldToTalk() {
    _audioBridge.stopPlayback(); // barge-in: silence Mini so the visitor can talk
    setState(() {
      _pushToTalk = true;
      _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0);
    });
    if (!_voiceActive) _startVoice(auto: true); // open a session if needed
    _bumpActivity();
  }

  void _endHoldToTalk() {
    if (!_pushToTalk) return;
    setState(() => _pushToTalk = false);
    _bumpActivity(); // a turn was just spoken → keep the session alive for the reply
  }

  // Mini's voice backend (ElevenLabs) is unreachable — most often an expired
  // subscription / out of credits / disabled key. Tell the operator plainly so
  // it isn't mistaken for an app bug. Shown above any pushed screen; guarded so
  // it never stacks.
  void _showServiceAlert(String? detail) {
    if (!mounted || _serviceAlertVisible) return;
    _serviceAlertVisible = true;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Row(children: [
          Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B35)),
          SizedBox(width: 10),
          Text('Voice unavailable', style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          "Mini's voice service (ElevenLabs) closed the connection. The "
          "subscription has likely expired or run out of credits.\n\n"
          "Please renew / recharge the ElevenLabs account, then tap the mic again."
          "${detail != null && detail.isNotEmpty ? '\n\n$detail' : ''}",
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFFFF6B35))),
          ),
        ],
      ),
    ).whenComplete(() => _serviceAlertVisible = false);
  }

  // Smoothed mic RMS → drives the "Listening / Hearing you" meter. If this never
  // moves while you talk, the mic isn't capturing (vs. a downstream problem).
  void _updateMicLevel(double lvl) {
    final smoothed = _micLevel * 0.6 + lvl * 0.4;
    if (mounted) setState(() => _micLevel = smoothed);
  }

  // Speaker amplitude as each chunk PLAYS (native playback thread). Drives
  // lip-sync in sync with what's heard; level < 0 is the drain sentinel → the
  // turn is over, return to listening. This replaces the old arrival-based gap
  // timer that closed the mouth while audio was still queued.
  void _onPlaybackLevel(double level) {
    if (!mounted) return;
    // Before a session: the spoken greeting just finished (drain) → open the mic.
    if (!_voiceActive) {
      if (_pendingAutoListen && level < 0) _startAutoListen();
      return;
    }
    if (level < 0) {
      // Turn ended (queue drained) → back to listening. We do NOT reset the idle
      // clock here anymore: the watchdog FREEZES the silence counter while Mini
      // speaks (so his answer never eats the visitor's reply window) and resumes
      // it on drain. Bumping on every drain also reset the counter on PHANTOM
      // turns (Mini answering room noise), so the session never auto-closed.
      debugPrint('Playback: drained → listening');
      RobotGestures.headCenter(); // Mini finished talking → recenter the head
      setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
    } else if (level < _speechFloor) {
      // Near-silent straggler chunk (trailing/padding audio that lands after the
      // real speech, often just after a drain). Don't let it drive "speaking" —
      // that's what twitched the mouth while Mini was actually just listening.
      setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
    } else {
      // Amplify the speech-range RMS so the mouth opens convincingly.
      _lastSpeakingMs = DateTime.now().millisecondsSinceEpoch; // drives the mic gate
      // NOTE: NOT bumping activity here — Mini's own playback must not reset the
      // idle timer (obs 1). The watchdog's mid-utterance guard prevents cutting him
      // off mid-reply; only USER speech keeps the session alive.
      final mouth = (level * 3.5).clamp(0.04, 1.0);
      // Sway the PHYSICAL head with the voice, throttled so we don't flood the SDK
      // (mirrors the dashboard) — this is what was missing on the face screen.
      if (!_gestureBusy && _lastSpeakingMs - _lastSwayMs > 300) {
        _lastSwayMs = _lastSpeakingMs;
        _gesture(() => RobotGestures.headSway(mouth));
      }
      setState(() =>
          _face = _face.copyWith(state: FaceStateKind.speaking, mouthOpen: mouth));
    }
  }

  // Debug-only: cycle through every state + nudge gaze manually.
  void _debugCycle() {
    if (_voiceActive) _endVoice();
    final next = FaceStateKind
        .values[(_face.state.index + 1) % FaceStateKind.values.length];
    final expr = switch (next) {
      FaceStateKind.greeting => 1,
      FaceStateKind.thinking => 2,
      FaceStateKind.attentive => 3,
      _ => 0,
    };
    setState(() => _face = _face.copyWith(state: next, expression: expr));
  }

  void _openDashboard() async {
    // Admin area is PIN-gated: a visitor tapping the face screen must enter the
    // PIN before reaching the dashboard/settings/enroll. Cancel returns to the face.
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const PinScreen(),
    ));
    if (ok != true || !mounted) return;
    // Pass the SHARED voice instances so the dashboard reacts to the same session
    // (no second ElevenLabs connection) and doesn't double-own playback. The idle
    // watchdog keeps running here too — an active conversation (speech in/out) keeps
    // it alive on either screen; genuine silence still closes it.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DashboardScreen(
        voiceAgent: _voiceAgent,
        audioBridge: _audioBridge,
        // The dashboard "Talk" button reuses THIS screen's mic pipeline — it's
        // still mounted behind the dashboard, so _startVoice fully works.
        onStartTalk: () => _startVoice(),
      ),
    ));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final battery = ref.watch(batteryProvider);
    final sdk = ref.watch(streamProvider.select((s) => s.sdkStatus));
    final greeting = ref.watch(greetingProvider);

    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr == true) _startControlServers();
    });

    // Escort: a "follow me" navigation just arrived → check the visitor made it.
    ref.listen(navPointsProvider.select((s) => s.arrivedAt), (prev, curr) {
      if (curr != null && curr != prev) _onEscortArrived(curr);
    });

    // Navigation started from ANY source (admin Go-To, patrol, robot voice) →
    // navigation owns the speaker: close an open agent session so motor noise
    // can't trigger stray replies over the departure/reassurance announcements.
    // (The robot-voice path already closes it at command time; this covers the
    // rest.) The mic re-opens on arrival when the visitor is in view.
    ref.listen(navPointsProvider.select((s) => s.navigatingTo), (prev, curr) {
      if (curr != null && prev == null && _voiceActive) {
        debugPrint('AmbientFace: navigation started → closing voice session');
        _endVoice();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openDashboard,
        child: Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: FacePainter(_rig.live, repaint: _repaint)),
            ),
          ),
          // Waving-hand greeting overlay (anonymous approach + named greet),
          // driven by the shared coordinator so it matches the dashboard.
          WavingHandOverlay(
            visible: greeting != null,
            message: greeting?.text ?? '',
          ),
          // Language selector, top-left (top-right holds the SDK/battery chip).
          Positioned(
            top: 12,
            left: 16,
            child: LanguageButton(
              voiceAgent: _voiceAgent,
              large: true, // big, obvious target on the face screen
              onReturned: () { if (mounted) setState(() {}); }, // refresh badge
            ),
          ),
          // Status chip, top-right.
          Positioned(
            top: 12,
            right: 16,
            child: Opacity(
              opacity: 0.9,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SdkBadge(status: sdk),
                const SizedBox(width: 12),
                BatteryIndicator(state: battery, large: true),
              ]),
            ),
          ),
          // Voice-session active indicator (top accent bar).
          if (_voiceActive)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(Color(0xFFFF6B35)),
                ),
              ),
            ),
          // Showroom sales capture: Order + Enquiry FABs, stacked above the mic
          // (visitor-facing — pushes LeadFormScreen → spine → XBoom Workflow OS).
          _leadButtons(),
          // Big tap-to-talk button (easy target; toggles the voice session).
          _voiceButton(),
          // Voice session indicator — current phase + live mic-level meter.
          if (_voiceActive) _voiceIndicator(),
          const Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Text('tap to open dashboard',
                  style: TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          ),
          if (kDebugMode) _debugPanel(),
        ]),
      ),
    );
  }

  // Order + Enquiry FABs for showroom visitors, stacked directly above the mic
  // button (mic sits at bottom: 28 with a 92px circle + label ≈ 130px tall).
  // Slightly smaller than the mic so Talk stays the primary action.
  Widget _leadButtons() {
    return Positioned(
      right: 28,
      bottom: 178,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _leadFab(
          icon: Icons.contact_support_rounded,
          label: 'Enquiry',
          color: const Color(0xFF3B82F6),
          onTap: () => _openLeadForm(LeadKind.enquiry),
        ),
        const SizedBox(height: 18),
        _leadFab(
          icon: Icons.shopping_cart_rounded,
          label: 'Order',
          color: const Color(0xFF4ADE80),
          onTap: () => _openLeadForm(LeadKind.order),
        ),
      ]),
    );
  }

  Widget _leadFab({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  // Open the visitor order/enquiry flow (catalog picker → details form). Any
  // live voice session is closed first so Mini doesn't keep talking (or
  // listening) over the on-screen keyboard.
  Future<void> _openLeadForm(LeadKind kind) async {
    if (_voiceActive) _endVoice();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductPickerScreen(kind: kind),
    ));
  }

  // Large voice button. TAP = toggle hands-free (auto-listen) session; HOLD =
  // push-to-talk (full mic while held — reliable in a noisy room). Green while
  // holding, red when a hands-free session is open, accent otherwise.
  Widget _voiceButton() {
    final ptt = _pushToTalk;
    final active = _voiceActive;
    final color = ptt
        ? const Color(0xFF4ADE80)
        : active
            ? const Color(0xFFE5484D)
            : const Color(0xFFFF6B35);
    return Positioned(
      right: 28,
      bottom: 28,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: active ? _endVoice : _startVoice, // quick tap → toggle hands-free
          onLongPressStart: (_) => _startHoldToTalk(), // press & hold → talk
          onLongPressEnd: (_) => _endHoldToTalk(),
          onLongPressCancel: _endHoldToTalk,
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 22, spreadRadius: 1),
              ],
            ),
            child: Icon(
                ptt
                    ? Icons.graphic_eq_rounded
                    : active
                        ? Icons.stop_rounded
                        : Icons.mic_rounded,
                color: Colors.white,
                size: 42),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            ptt
                ? 'Listening… release to send'
                : active
                    ? 'Tap to stop'
                    : 'Tap to Talk',
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  // A production voice indicator: shows the current phase (Listening / Hearing
  // you / Thinking / Speaking) and a LIVE mic-level meter so the user knows the
  // app is actually capturing their voice.
  Widget _voiceIndicator() {
    const accent = Color(0xFFFF6B35);
    const green = Color(0xFF4ADE80);
    final speaking = _face.state == FaceStateKind.speaking;
    final thinking = _face.state == FaceStateKind.thinking;
    final hearing = _micLevel > 0.02; // user voice registering

    final String label;
    final Color color;
    final IconData icon;
    if (speaking) {
      label = 'Speaking…';
      color = accent;
      icon = Icons.volume_up_rounded;
    } else if (thinking) {
      label = 'Thinking…';
      color = Colors.amber;
      icon = Icons.more_horiz_rounded;
    } else if (hearing) {
      label = 'Hearing you';
      color = green;
      icon = Icons.mic_rounded;
    } else {
      label = 'Listening…';
      color = accent;
      icon = Icons.mic_none_rounded;
    }
    final meter = (_micLevel * 5).clamp(0.0, 1.0); // amplify speech-range RMS

    return Positioned(
      bottom: 56,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              // Live mic level — moves when the mic actually captures your voice.
              Container(
                width: 96,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: meter,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hearing ? green : accent.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _debugPanel() {
    return Positioned(
      bottom: 12,
      left: 12,
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white54, fontSize: 11),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('state: ${_face.state.name}',
                style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('present: $_present  gaze ${_gaze.last.gazeX.toStringAsFixed(2)},'
                ' ${_gaze.last.gazeY.toStringAsFixed(2)}'),
            Text('looking: ${_gaze.last.lookingAtCamera}'
                '  yaw ${_gaze.last.yawDeg.toStringAsFixed(0)}°'
                '  face ${(_gaze.last.faceRatio * 100).toStringAsFixed(0)}%'),
            Text('spine: ${_spine.isConnected ? "connected" : "…"}'),
            Text('voice: ${_voiceActive ? "on" : "off"}  mic: ${_micLevel.toStringAsFixed(3)}'),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _chip('next state', _debugCycle),
              const SizedBox(width: 6),
              _chip(_voiceActive ? 'end voice' : 'start voice',
                  _voiceActive ? _endVoice : _startVoice),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('live perception '),
              Switch(
                value: _useLivePerception,
                activeThumbColor: const Color(0xFFFF6B35),
                onChanged: (v) => setState(() => _useLivePerception = v),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      );
}

/// Lightweight per-frame repaint signal — wired to FacePainter's `repaint:` so
/// only the painter repaints each tick (no full widget rebuild).
class _FaceRepaint extends ChangeNotifier {
  void ping() => notifyListeners();
}
