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
import 'services/elevenlabs_tts.dart';
import 'services/person_detect.dart';
import 'services/face_recognition.dart';
import 'models/voice_language.dart';
import 'nav_points_provider.dart';
import 'services/nav_points_api.dart';
import 'services/nav_voice.dart';
import 'services/checkin_voice.dart';
import 'services/checkin_api.dart';
import 'waving_hand_overlay.dart';
import 'face_rig.dart';
import 'gaze_tracker.dart';
import 'services/spine_client.dart';
import 'services/voice_agent.dart';
import 'services/audio_bridge.dart';
import 'screens/language_selection_screen.dart';
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
  StreamSubscription<bool>? _sdkPersonSub; // on-device CSJBot person sensors
  StreamSubscription<FaceEvent>? _faceRecgSub; // CSJBot staff face recognition
  String? _pendingGreetName; // last recognised staff name (injected to ElevenLabs)

  bool _useLivePerception = true; // toggle in debug card; drives gaze when on
  bool _present = false; // a face box is currently visible
  bool _wasLooking = false; // attention-gate edge tracking (greet on rising edge)
  double _liveGazeX = 0, _liveGazeY = 0;
  Timer? _presenceHold;

  // Greeting overlay — text shown in WavingHandOverlay + debounce map.
  String _greetText = '';
  bool _greetVisible = false;
  Timer? _greetTimer;
  final Map<String, DateTime> _greetedAt = {}; // per-name re-greet debounce

  // Greeting coordinator: on motion/presence we hold off greeting for a brief
  // window so face recognition can identify a known staff member FIRST (→ greet
  // by name); if no face is recognised in time we fall back to a plain hello.
  // This makes the greeting deterministic — exactly one per visit, name-if-known
  // — instead of the old race between the person-sensor and face-recognition
  // paths (which caused the intermittent "Hello" vs "Hello <name>").
  bool _awaitingRecognition = false;
  Timer? _recognitionWaitTimer;

  // One-shot TTS for greeting phrases (ElevenLabs voice, falls back to built-in).
  late final ElevenLabsTts _tts;

  // ── Voice visitor check-in ("I'm here to see <host>") ──────────────────────
  // Two-turn dialog: intent+host → ask the visitor's name → POST /visit.
  final CheckinApi _checkinApi = CheckinApi();
  StaffMember? _checkinHost; // resolved host while awaiting the visitor's name
  Timer? _checkinTimeout; // abandon the dialog if no name arrives
  List<StaffMember>? _staffCache; // GET /staff cache for host matching
  DateTime? _staffCacheAt;
  static const Duration _staffCacheTtl = Duration(minutes: 5);
  static const Duration _checkinNameWindow = Duration(seconds: 25);

  // ── Escort arrival check ────────────────────────────────────────────────────
  // After a non-patrol "follow me" arrival, wait briefly for a face; if nobody
  // appears the visitor was lost en route → speak the configurable line.
  Timer? _escortArrivalCheck;

  // Voice (#80) — ElevenLabs Conversational AI session + audio bridge.
  late final VoiceAgent _voiceAgent;
  final AudioBridge _audioBridge = AudioBridge();
  StreamSubscription<VoiceEvent>? _voiceSub;
  StreamSubscription<String>? _wakeSub;
  StreamSubscription<String>? _asrSub;
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
  // Mikee's own greeting. _autoSession marks a session that should auto-close
  // after _engageWindow of silence; manual (button) sessions stay open.
  bool _pendingAutoListen = false;
  Timer? _autoListenFallback;
  bool _autoSession = false;
  Timer? _idleWatch; // periodic idle watchdog → auto-close on inactivity
  int _lastActivityMs = 0; // last USER activity (speech heard / push-to-talk)
  bool _conversed = false; // a real exchange happened → use the longer idle window
  int _lastSpeakingMs = 0; // last time Mikee's speaker was active → mic-gate tail

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
  // Same-name re-greet debounce — Settings-tunable (RobotConfig.regreetMinutes).
  Duration get _regreetWindow => Duration(minutes: RobotConfig.regreetMinutes);
  // How long after the attention gate opens we wait for identity before greeting
  // anonymously. Long enough for the spine recogniser (500ms cadence + 2-of-3
  // voting) to land a match on an enrolled face, short enough that an unknown
  // visitor isn't left waiting for a hello. Spine's explicit "unknown" short-
  // circuits this window — the timeout only covers spine being slow/offline.
  static const Duration _recognitionWindow = Duration(milliseconds: 2000);
  static const Duration _engageWindow = Duration(seconds: 25); // no greeting response → close
  static const Duration _conversationIdle = Duration(seconds: 25); // mid-chat silence → close
  // Mic stays muted this long after Mikee's last speaker output — must exceed the
  // AudioTrack buffer drain (~400ms) so the speaker tail doesn't leak into the mic
  // and re-trigger ElevenLabs (echo loop). No hardware AEC covers our audio path.
  static const int _micTailGuardMs = 800;
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
    // On-device person sensors (laser/RGBD/ultrasonic) → idle→attentive ONLY.
    // Deliberately NOT a greeting trigger: greetings fire exclusively from the
    // camera attention gate (a face looking at the robot), never from LIDAR.
    _sdkPersonSub = PersonDetect.presence.listen(_onPersonDetected);
    // Staff face recognition (CSJBot SDK) — identity FALLBACK when spine is
    // offline (spine's face_detected is authoritative). Silent off-robot.
    _faceRecgSub = FaceRecognition.events.listen(_onFaceRecognized);
    _gaze.start();
    _spine.start();

    _tts = ElevenLabsTts(
      apiKey: RobotConfig.elevenLabsApiKey,
      voiceId: RobotConfig.elevenLabsVoiceId,
      audio: _audioBridge,
    );

    // Voice (#80) — session is opened on demand (debug overlay / Phase B wake word).
    _voiceAgent = VoiceAgent(
      agentId: RobotConfig.elevenLabsAgentId,
      apiKey: RobotConfig.elevenLabsApiKey,
      languageCode: RobotConfig.voiceLanguageCode, // saved language → first session
    );
    _voiceSub = _voiceAgent.events.listen(_onVoiceEvent);
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
    // Mikee's own speaker echo as the user and cut him off mid-sentence. Hands-free,
    // Mikee now finishes his replies; hold-to-talk stays the reliable way to
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
    _greetTimer?.cancel();
    _recognitionWaitTimer?.cancel();
    _checkinTimeout?.cancel();
    _escortArrivalCheck?.cancel();
    _reconnectTimer?.cancel();
    _autoListenFallback?.cancel();
    _idleWatch?.cancel();
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
    // A recognised staff face must ALWAYS be greeted by name (once per debounce
    // window) — even mid-session — unless Mikee is literally mid-utterance;
    // then we skip WITHOUT recording the greet so the next recognition tick
    // (~500ms) retries until his mouth is free.
    final now = DateTime.now();
    final last = _greetedAt[e.name];
    if (last != null && now.difference(last) < _regreetWindow) return; // debounce
    final talking = _face.state == FaceStateKind.speaking ||
        _face.state == FaceStateKind.thinking;
    if (talking) return;
    if (_voiceActive) {
      // In an open session: speak the personal hello but don't touch the
      // session/mic state.
      _greetedAt[e.name] = now;
      final lang = languageForCode(RobotConfig.voiceLanguageCode);
      _showGreeting(lang.greetText(e.name));
      _speakGreeting(_staffSpeech(lang, e.name));
      return;
    }
    _greetedAt[e.name] = now;
    // A NAMED greeting is allowed to fire even after the generic approach
    // greeting already went out — the spine's identity often lands a beat late,
    // and staff should always hear their personalised welcome (once per
    // debounce window). It just must not re-open the mic a second time.
    final upgradeAfterGeneric = _greeted;
    _greeted = true; // counts as this visit's one greeting
    _awaitingRecognition = false; // spine identity won the recognition window
    _recognitionWaitTimer?.cancel();
    final lang = languageForCode(RobotConfig.voiceLanguageCode);
    _showGreeting(lang.greetText(e.name));
    if (upgradeAfterGeneric) {
      _speakGreeting(_staffSpeech(lang, e.name));
    } else {
      _greetThenListen(_staffSpeech(lang, e.name));
    }
  }

  // Spine saw a face that matched NO enrolled staff → this is a visitor. Don't
  // make them wait out the recognition window: greet (without a name) now.
  void _onUnknownFace(void _) {
    if (!_awaitingRecognition || _greeted || _voiceActive) return;
    _awaitingRecognition = false;
    _recognitionWaitTimer?.cancel();
    _greetOnApproach();
  }

  // Rendered spoken phrases — Settings-editable templates (RobotConfig), with
  // {hello}/{welcome} localised by the active voice language.
  String _staffSpeech(VoiceLanguage lang, String name) => lang.renderGreeting(
      RobotConfig.greetStaffTemplate,
      name: name,
      company: RobotConfig.companyName);

  String _visitorSpeech(VoiceLanguage lang) => lang.renderGreeting(
      RobotConfig.greetVisitorTemplate,
      company: RobotConfig.companyName);

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
      _greetOnApproach(); // no face recognised in the window → plain hello
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

  // Shared: set greeting state, show overlay, start hold timer.
  void _showGreeting(String text) {
    if (!mounted) return;
    _greetTimer?.cancel();
    setState(() {
      _greetText = text;
      _greetVisible = true;
      _face = _face.copyWith(state: FaceStateKind.greeting);
    });
    _greetTimer = Timer(_greetHold, () {
      if (!mounted) return;
      setState(() {
        _greetVisible = false;
        _face = _face.copyWith(
          state: _present ? FaceStateKind.attentive : FaceStateKind.idle,
        );
      });
    });
  }

  // Speak a greeting phrase — ElevenLabs voice first, built-in TTS as fallback.
  void _speakGreeting(String text) {
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
    _asrUtterance = partial.trim();
    _bumpActivity(); // real user speech — keep the session alive
    _asrFinalTimer?.cancel();
    _asrFinalTimer = Timer(const Duration(milliseconds: 900), () {
      final utterance = _asrUtterance;
      _asrUtterance = '';
      if (utterance.isEmpty) return;
      debugPrint('VendorASR utterance: "$utterance"');
      if (_handleNavVoice(utterance)) return;
      if (_handleCheckinVoice(utterance)) return;
      if (_voiceActive) {
        _voiceAgent.sendUserText(utterance);
        setState(() => _face = _face.copyWith(state: FaceStateKind.thinking));
      }
    });
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
    if (result.point != null) {
      final p = result.point!;
      debugPrint('NavVoice: "$transcript" → go to "${p.name}"');
      // The departure phrase is spoken by the navi_state broadcast handler
      // (nav_points_provider) — speaking it here too would double up.
      ref.read(navPointsProvider.notifier).goTo(p);
    } else {
      final known = points.map((p) => p.name).take(3).join(', ');
      debugPrint('NavVoice: "$transcript" → no point matches "${result.heard}"');
      _speakGreeting(points.isEmpty
          ? "I don't have any saved locations yet."
          : "I couldn't find a place called ${result.heard}. "
              'I can take you to: $known.');
    }
    return true;
  }

  // ── Voice visitor check-in ("I'm here to see <host>") ──────────────────────
  // Returns true when [transcript] belongs to the check-in dialog (intent turn
  // OR the follow-up name turn) — handled here with our own spoken replies, so
  // the conversational agent never answers a flow it knows nothing about.
  bool _handleCheckinVoice(String transcript) {
    // Turn 2: we asked for the visitor's name — this utterance IS the answer.
    if (_checkinHost != null) {
      _dropFirstAgentTurn = true;
      _audioBridge.stopPlayback();
      _completeCheckin(transcript);
      return true;
    }
    final result = CheckinVoice.match(transcript);
    if (!result.isCommand) return false;
    _dropFirstAgentTurn = true;
    _audioBridge.stopPlayback();
    _beginCheckin(result.hostHeard);
    return true;
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
      debugPrint('Checkin: no staff match for "$hostHeard"');
      _speakGreeting("I couldn't find $hostHeard in our staff directory. "
          'You can also check in at the front desk.');
      return;
    }
    debugPrint('Checkin: host "$hostHeard" → ${host.fullName} (${host.id})');
    _checkinHost = host;
    _checkinTimeout?.cancel();
    _checkinTimeout = Timer(_checkinNameWindow, () {
      debugPrint('Checkin: name window expired — dialog abandoned');
      _checkinHost = null;
    });
    _speakGreeting('Sure — I will let ${host.fullName} know. '
        'May I have your name, please?');
  }

  Future<void> _completeCheckin(String transcript) async {
    final host = _checkinHost;
    _checkinHost = null;
    _checkinTimeout?.cancel();
    if (host == null) return;
    if (CheckinVoice.isCancel(transcript)) {
      _speakGreeting('No problem.');
      return;
    }
    final name = CheckinVoice.extractVisitorName(transcript);
    if (name.isEmpty) {
      _speakGreeting("Sorry, I didn't catch your name — "
          'please check in at the front desk.');
      return;
    }
    var ok = false;
    try {
      ok = await _checkinApi.postVisit(visitorName: name, hostStaffId: host.id);
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
    if (ref.read(navPointsProvider).navSource == 'patrol') return;
    final template = RobotConfig.escortLostText;
    if (template.isEmpty) return;
    _escortArrivalCheck?.cancel();
    _escortArrivalCheck = Timer(const Duration(seconds: 8), () {
      if (!mounted || _present || _voiceActive) return;
      if (ref.read(navPointsProvider).navigatingTo != null) return; // re-tasked
      debugPrint('Escort: nobody in view after arriving at "$pointName"');
      _speakGreeting(template.replaceAll('{name}', pointName));
    });
  }

  // Speak the greeting, then auto-open the mic so a visitor can talk without
  // tapping. The hand-off waits for the greeting audio to drain (handled in
  // _onPlaybackLevel) so the mic never captures Mikee's own voice; the fallback
  // timer covers the built-in-TTS path (no playback-level signal) or a missed drain.
  void _greetThenListen(String phrase) {
    if (_voiceActive) return; // already in a conversation
    _pendingAutoListen = true;
    _autoListenFallback?.cancel();
    _autoListenFallback = Timer(const Duration(seconds: 4), _startAutoListen);
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

  // Single idle watchdog for AUTO sessions. Closes the session after
  // _engageWindow of silence before the first exchange (passer-by who never
  // talks), or after _conversationIdle once a real conversation has started.
  // "Activity" = Mikee speaking (playback) OR the user speaking (agentThinking /
  // userSpeaking) — see _bumpActivity — so an active back-and-forth keeps it open
  // on EITHER screen, while genuine silence closes it. Manual sessions (mic button)
  // are exempt and stay open until ended. Replaces the old engage + hard-cap timers.
  void _startIdleWatch() {
    _conversed = false;
    _bumpActivity();
    _idleWatch?.cancel();
    _idleWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_voiceActive || !_autoSession) return;
      // Idle is measured from the last USER activity (speech heard / push-to-talk),
      // NOT from Mikee's own speech — otherwise an agent that keeps talking with no
      // visitor perpetually resets the timer and never returns to idle (obs 1).
      final idleMs = DateTime.now().millisecondsSinceEpoch - _lastActivityMs;
      final window = _conversed ? _conversationIdle : _engageWindow;
      // Don't cut Mikee off mid-utterance, but hard-cap at 2× the window so a
      // runaway/looping agent can't hold the session open indefinitely.
      final mikeeTalking = _face.state == FaceStateKind.speaking ||
          _face.state == FaceStateKind.thinking;
      final hardCap = idleMs >= 2 * window.inMilliseconds;
      if (idleMs >= window.inMilliseconds && (!mikeeTalking || hardCap)) {
        debugPrint('AmbientFace: user idle ${(idleMs / 1000).toStringAsFixed(0)}s ≥ '
            '${window.inSeconds}s → closing');
        _endVoice();
      }
    });
  }

  void _bumpActivity() => _lastActivityMs = DateTime.now().millisecondsSinceEpoch;

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
    final now = DateTime.now();
    final last = _greetedAt[name];
    if (last != null && now.difference(last) < _regreetWindow) return; // debounce
    _greetedAt[name] = now;
    _greeted = true; // counts as this visit's one greeting (blocks the plain hello)
    _pendingGreetName = name;
    final lang = languageForCode(RobotConfig.voiceLanguageCode);
    _showGreeting(lang.greetText(name)); // overlay + greeting face state
    _voiceAgent.injectGreeting('STAFF_RECOGNIZED: $_pendingGreetName');
    _startVoice(auto: true); // opens the session → agent greets by name, then listens
  }

  void _setStateKind(FaceStateKind k) {
    if (!mounted) return;
    setState(() => _face = _face.copyWith(state: k));
  }

  // ── #80 voice: ElevenLabs session drives the face state machine ─────────────
  void _onVoiceEvent(VoiceEvent e) {
    debugPrint('Voice: ${e.kind.name}'
        '${e.text != null && e.text!.isNotEmpty ? " [${e.text}]" : ""}');
    switch (e.kind) {
      case VoiceEventKind.sessionStarted:
        // Open in listening — Mikee is waiting for the user (the ring shows).
        // Also clear any stale playback (e.g. a reply cut off by a language
        // switch reconnect) so we don't talk over the new session.
        _suppressTeardown = false; // a new session is live — clear any pending recovery
        _audioBridge.stopPlayback();
        _audioBridge.startSpeechEngine(); // session-gated mic engine (startIsr)
        setState(() {
          _voiceActive = true;
          _face = _face.copyWith(state: FaceStateKind.listening);
        });
        _startIdleWatch(); // auto sessions: begin the inactivity countdown
        break;
      case VoiceEventKind.userSpeaking:
        // User cut in (interruption) → stop playback + listen.
        _dropFirstAgentTurn = false; // visitor is engaging → allow agent audio again
        _bumpActivity(); // visitor engaged — keep the session open
        _audioBridge.stopPlayback();
        setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
        break;
      case VoiceEventKind.agentThinking:
        // A new turn is starting → stop dropping audio; the upcoming reply plays.
        // NOTE: in this ElevenLabs integration the USER's speech surfaces here
        // (with the transcript), not as userSpeaking — so this is our reliable
        // "a real person engaged" signal. Mark the conversation started + keep alive.
        _dropFirstAgentTurn = false; // real reply coming → play it
        _conversed = true;
        _bumpActivity();
        _reconnectAttempts = 0; // a real turn landed → refresh the retry budget
        // Voice navigation: "go to <saved point>" spoken to Mikee. When the
        // transcript is a nav command WE handle the reply + action and drop the
        // agent's own answer to this turn (it doesn't know the saved points).
        if (e.text != null && _handleNavVoice(e.text!)) {
          _dropFirstAgentTurn = true;
          break;
        }
        // Visitor check-in ("I'm here to see <host>") — ours end-to-end too:
        // the agent doesn't know the staff directory or the /visit flow.
        if (e.text != null && _handleCheckinVoice(e.text!)) {
          _dropFirstAgentTurn = true;
          break;
        }
        // Genuine processing gap (STT done, reply not yet streaming).
        setState(() => _face = _face.copyWith(state: FaceStateKind.thinking, mouthOpen: 0));
        break;
      case VoiceEventKind.agentSpeaking:
        // Mute the robot's built-in (Chinese) TTS so only the ElevenLabs voice is
        // heard — the CSJBot AIUI runs in parallel (it gives us the mic) but must
        // not talk over Mikee.
        _audioBridge.stopSpeak();
        // Auto session's unprompted FIRST message: drop it (we already greeted) and
        // stay in listening so the mic isn't muted before the visitor can speak.
        if (_dropFirstAgentTurn) break;
        // NOTE: deliberately NOT bumping activity here — Mikee's OWN speech must not
        // keep the session alive, or an agent that keeps talking with no visitor
        // never returns to idle (obs 1). Only USER input resets the idle timer.
        setState(() => _face = _face.copyWith(state: FaceStateKind.speaking));
        break;
      case VoiceEventKind.audioChunk:
        // Just QUEUE the chunk for playback. Lip-sync (mouthOpen) + the
        // speaking→listening transition are driven by _onPlaybackLevel, which
        // tracks the SPEAKER (not network arrival) — so lips move while Mikee is
        // actually talking and close exactly when playback ends.
        // Dropped after a barge-in, the auto first message, or while holding to talk.
        if (_dropFirstAgentTurn || _pushToTalk) break;
        if (e.audioChunk != null) _audioBridge.playChunk(e.audioChunk!);
        break;
      case VoiceEventKind.sessionEnded:
        // Recovering from an unexpected drop → ignore this teardown; the scheduled
        // reconnect owns recovery and will reopen the session (engine keeps running
        // through the gap — startSpeechEngine on the reopened session is idempotent).
        if (_suppressTeardown) {
          _suppressTeardown = false;
          return;
        }
        _audioBridge.stopSpeechEngine(); // session over → stop the mic engine
        _intentionalClose = false;
        _reconnectAttempts = 0;
        _stopIdleWatch();
        _autoSession = false;
        _audioBridge.stopMic();
        _audioBridge.stopPlayback();
        _spine.logConversation(_voiceAgent.transcript); // fire-and-forget
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

  // [auto] = true when opened automatically after a greeting (→ auto-closes on
  // silence). The mic-button / wake-word callers use the default (false) so a
  // deliberately opened session stays open until the user ends it.
  void _startVoice({bool auto = false, bool reconnect = false}) {
    _pendingAutoListen = false; // a session is starting — cancel any greeting hand-off
    _autoListenFallback?.cancel();
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
      // Half-duplex echo gate (the ONLY gate now): never feed Mikee's own voice back
      // to ElevenLabs. His voice plays through a separate AudioTrack the CSJBot CAE
      // does NOT echo-cancel, so otherwise he hears himself and loops forever. The
      // tail-guard covers the speaker buffer after we flip to listening.
      final speakingMuted = _face.state == FaceStateKind.speaking ||
          (now - _lastSpeakingMs) < _micTailGuardMs;
      // The amplitude noise gate (squelch) was REMOVED (obs 3): it dropped soft and
      // sentence-onset speech (RMS < 0.04 → silence sent), so capture was hit-or-miss.
      // We now feed ElevenLabs the REAL mic continuously whenever Mikee isn't
      // speaking and let its own server-side VAD decide when a turn starts/ends.
      // While Mikee speaks we send SILENCE so the stream stays unbroken for EL's VAD
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
    _audioBridge.stopPlayback(); // barge-in: silence Mikee so the visitor can talk
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

  // Mikee's voice backend (ElevenLabs) is unreachable — most often an expired
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
          "Mikee's voice service (ElevenLabs) closed the connection. The "
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
      // Turn ended (queue drained) → back to listening. The idle watchdog keeps
      // counting from the last activity; the user now has the idle window to reply.
      debugPrint('Playback: drained → listening');
      setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
    } else if (level < _speechFloor) {
      // Near-silent straggler chunk (trailing/padding audio that lands after the
      // real speech, often just after a drain). Don't let it drive "speaking" —
      // that's what twitched the mouth while Mikee was actually just listening.
      setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
    } else {
      // Amplify the speech-range RMS so the mouth opens convincingly.
      _lastSpeakingMs = DateTime.now().millisecondsSinceEpoch; // drives the mic gate
      // NOTE: NOT bumping activity here — Mikee's own playback must not reset the
      // idle timer (obs 1). The watchdog's mid-utterance guard prevents cutting him
      // off mid-reply; only USER speech keeps the session alive.
      final mouth = (level * 3.5).clamp(0.04, 1.0);
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

  void _openDashboard() {
    // Pass the SHARED voice instances so the dashboard reacts to the same session
    // (no second ElevenLabs connection) and doesn't double-own playback. The idle
    // watchdog keeps running here too — an active conversation (speech in/out) keeps
    // it alive on either screen; genuine silence still closes it.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DashboardScreen(
        voiceAgent: _voiceAgent,
        audioBridge: _audioBridge,
      ),
    ));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final battery = ref.watch(batteryProvider);
    final sdk = ref.watch(streamProvider.select((s) => s.sdkStatus));

    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr == true) _startControlServers();
    });

    // Escort: a "follow me" navigation just arrived → check the visitor made it.
    ref.listen(navPointsProvider.select((s) => s.arrivedAt), (prev, curr) {
      if (curr != null && curr != prev) _onEscortArrived(curr);
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
          // Waving-hand greeting overlay (anonymous approach + named greet).
          WavingHandOverlay(
            visible: _greetVisible,
            message: _greetText,
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
            ptt ? 'Listening… release to send' : 'Hold to talk',
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
