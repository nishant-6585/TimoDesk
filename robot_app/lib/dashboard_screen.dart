import 'dart:async';
import 'dart:math' show sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'nav_points_provider.dart';
import 'services/nav_points_api.dart'; // kOrange + head/chassis/arm/battery providers + states
import 'face_painter.dart'; // FaceState, FaceStateKind, FacePainter
import 'face_rig.dart'; // FaceRig
import 'services/voice_agent.dart';
import 'services/audio_bridge.dart';
import 'services/elevenlabs_tts.dart';
import 'services/robot_gestures.dart';
import 'services/voice_command_handler.dart';
import 'models/voice_language.dart';
import 'screens/language_selection_screen.dart';
import 'config.dart';
import 'enroll_screen.dart';
import 'nav_points_screen.dart';
import 'status_screen.dart';
import 'control_screen.dart';
import 'settings_screen.dart';

// ── Color & type tokens (DASHBOARD_REDESIGN.md §2) ───────────────────────────
const _bg = Color(0xFF0F0F0F);
const _panel = Color(0xFF151515);
const _panel2 = Color(0xFF1A1A1A);
const _line = Color(0xFF262626);
const _line2 = Color(0xFF2F2F2F);
const _ink = Color(0xFFF4F1EE);
const _muted = Color(0xFF9A9A9A);
const _muted2 = Color(0xFF6B6B6B);
const _green = Color(0xFF4ADE80);
const _greenBg = Color(0xFF06200F);
const _red = Color(0xFFFF5247);
const _accent = kOrange; // #FF6B35
const _accentDimColor = Color(0xFFE14B1E);
// Voice-state glow: LISTENING = blue, SPEAKING = amber (DASHBOARD voice cue).
const _listenGlow = Color(0xFF3B82F6);
const _speakGlow = Color(0xFFF59E0B);

/// Face-dominant reception dashboard (opened from the ambient face). Three
/// columns that fill the viewport and never scroll: nav rail · big face + a
/// single row of reception action tiles · height-distributing Quick Controls.
/// Reuses the shared FacePainter/FaceRig (unchanged); reacts to the same
/// ElevenLabs session as the ambient face. Auto-returns to the face after 30s.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
    required this.voiceAgent,
    required this.audioBridge,
  });

  final VoiceAgent voiceAgent;
  final AudioBridge audioBridge;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

/// The 6 reception action tiles (§5).
enum _Act { greet, listen, checkIn, directions, pageStaff, rest }

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  bool _patrolling = false;
  // Dashboard mini-face (independent rig from the ambient face).
  final FaceRig _rig = FaceRig();
  final _FaceRepaint _repaint = _FaceRepaint();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _paintAccum = 0; // throttles repaint to ~30fps (halves render CPU)
  FaceState _face = const FaceState(state: FaceStateKind.greeting);

  Timer? _idle;
  Timer? _clock;
  Timer? _revert; // action → auto-revert to attentive
  Timer? _seq; // Listen multi-step preview
  Timer? _intro;
  String _timeStr = '';
  static const _idleReturn = Duration(seconds: 30);

  StreamSubscription<VoiceEvent>? _voiceSub;
  StreamSubscription<double>? _playbackSub;
  StreamSubscription<String>? _asrSub; // CSJBot recognition → "user speaking" nod
  bool _voiceActive = false;
  bool _perceptionOn = true;

  // Voice-state glow pulse (face card border + state chip + waveform).
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  // Head/body gestures on voice events — best-effort, non-overlapping.
  late final VoiceCommandHandler _cmd;
  bool _gestureInProgress = false;
  int _lastSwayMs = 0; // throttle speaking sway to ~once / 300ms
  int _lastNodMs = 0; //  throttle acknowledging nod to ~once / 2.5s

  // Speaks action phrases in the agent's real voice (same as the face screen),
  // streamed through the shared speaker; falls back to on-device TTS.
  late final ElevenLabsTts _tts;

  // Action state
  _Act? _activeAct; // tile currently lit
  bool _resting = false;

  // Toast (feedback over the face)
  String _toastText = '';
  IconData _toastIcon = Icons.info_outline;
  bool _toastVisible = false;
  Timer? _toastTimer;

  // Speed 30–80 (% of max), mirrors the provider's 0.3–0.8.
  double _speed = 50;

  // Per-frame metrics (clamp(min, …vh, max)) computed in build().
  double _dockH = 100, _padSq = 120, _armH = 36, _estopH = 50;
  double _tileLabel = 13, _tileSub = 10;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _voiceActive = widget.voiceAgent.isActive;
    _updateClock();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _updateClock());
    _resetIdle();
    _voiceSub = widget.voiceAgent.events.listen(_onVoiceEvent);
    _playbackSub = widget.audioBridge.playbackLevelStream.listen(_onPlaybackLevel);
    _asrSub = widget.audioBridge.asrTextStream.listen(_onUserSpeechGesture);
    _cmd = VoiceCommandHandler(_runVoiceCommand);
    _tts = ElevenLabsTts(
      apiKey: RobotConfig.elevenLabsApiKey,
      voiceId: RobotConfig.elevenLabsVoiceId,
      audio: widget.audioBridge,
    );
    // Intro: open in greeting, settle to attentive after ~2.8s (§6).
    _intro = Timer(const Duration(milliseconds: 2800), () {
      if (mounted && !_resting && _activeAct == null) _setKind(FaceStateKind.attentive);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _idle?.cancel();
    _clock?.cancel();
    _revert?.cancel();
    _seq?.cancel();
    _intro?.cancel();
    _toastTimer?.cancel();
    _voiceSub?.cancel();
    _playbackSub?.cancel();
    _asrSub?.cancel();
    _pulseCtrl.dispose();
    _tts.dispose();
    _repaint.dispose();
    // Do NOT dispose voiceAgent / audioBridge — owned by AmbientFaceScreen.
    super.dispose();
  }

  // ── Face plumbing ───────────────────────────────────────────────────────────
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    // Cap to ~30fps: the Ticker fires every vsync (~60fps), but the FacePainter's
    // glows/blurs are expensive (raster+GPU). Repainting at 30fps roughly halves
    // the render CPU on the RK3576 with no visible loss for a face.
    _paintAccum += dt;
    if (_paintAccum < 0.033) return;
    // Dashboard-only: pin gaze slightly forward/down (gazeY≈0.04) so Mikee stays
    // engaged with whoever's at the desk (the ambient face is a separate rig).
    _rig.tick(_face, _paintAccum.clamp(0.0, 0.05), followGx: 0, followGy: 0.04);
    _paintAccum = 0;
    _repaint.ping();
  }

  void _setKind(FaceStateKind k) {
    if (mounted) setState(() => _face = _face.copyWith(state: k));
    _syncPulse(k);
  }

  // Glow accent for a state (null = neutral, no glow).
  Color? _glowColor(FaceStateKind k) => switch (k) {
        FaceStateKind.listening => _listenGlow,
        FaceStateKind.speaking => _speakGlow,
        _ => null,
      };

  // Run the border/chip/waveform pulse only while listening or speaking.
  void _syncPulse(FaceStateKind k) {
    final glow = k == FaceStateKind.listening || k == FaceStateKind.speaking;
    if (glow && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!glow && _pulseCtrl.isAnimating) {
      _pulseCtrl
        ..stop()
        ..value = 0;
    }
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _timeStr = '$h:$m');
  }

  // ── Voice (shared session drives the face) ──────────────────────────────────
  void _onVoiceEvent(VoiceEvent e) {
    switch (e.kind) {
      case VoiceEventKind.sessionStarted:
        setState(() => _voiceActive = true);
        _setKind(FaceStateKind.listening);
        break;
      case VoiceEventKind.userSpeaking:
        _setKind(FaceStateKind.listening);
        break;
      case VoiceEventKind.agentThinking:
        _setKind(FaceStateKind.thinking);
        _gesture(RobotGestures.headTilt); // curious "thinking" tilt
        final t = e.text; // ElevenLabs user transcript → keyword commands
        if (t != null && t.trim().isNotEmpty) _cmd.handle(t);
        break;
      case VoiceEventKind.agentSpeaking:
        _setKind(FaceStateKind.speaking);
        _gesture(RobotGestures.chestAttention); // perk up to speak (once/turn)
        break;
      case VoiceEventKind.audioChunk:
        break; // playback owned by AmbientFaceScreen
      case VoiceEventKind.sessionEnded:
      case VoiceEventKind.error:
        setState(() => _voiceActive = false);
        if (!_resting) _setKind(FaceStateKind.attentive);
        RobotGestures.headCenter(); // reply done → recenter
        _resetIdle(); // conversation over → restart the return-to-face countdown
        break;
    }
  }

  void _onPlaybackLevel(double level) {
    if (!mounted || !_voiceActive) return;
    if (level < 0) {
      setState(() => _face = _face.copyWith(mouthOpen: 0));
      RobotGestures.headCenter();
    } else {
      final amp = (level * 3.5).clamp(0.04, 1.0);
      setState(() =>
          _face = _face.copyWith(state: FaceStateKind.speaking, mouthOpen: amp));
      // Sway the head with the voice, throttled so we don't flood the SDK.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!_gestureInProgress && now - _lastSwayMs > 300) {
        _lastSwayMs = now;
        RobotGestures.headSway(amp);
      }
    }
  }

  // CSJBot recognized the user speaking → acknowledging nod (throttled). Uses
  // the on-device ASR stream (fires as the user talks), not the cloud transcript.
  void _onUserSpeechGesture(String text) {
    if (!_voiceActive || text.trim().isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNodMs < 2500) return;
    _lastNodMs = now;
    _gesture(RobotGestures.headNod);
  }

  // Run a multi-step gesture, skipping if one is already in flight (so nod /
  // tilt / lean don't fight each other). Best-effort; silent off-device.
  Future<void> _gesture(Future<void> Function() g) async {
    if (!_voiceActive || _gestureInProgress) return;
    _gestureInProgress = true;
    try {
      await g();
    } catch (_) {
      // off-device or SDK busy — ignore
    } finally {
      _gestureInProgress = false;
    }
  }

  // Dispatch a recognized voice command to the real robot bridges + show a pill.
  void _runVoiceCommand(VoiceCommand cmd) {
    _toast('▶ Executing: ${cmd.label}', cmd.icon);
    final chassis = ref.read(chassisProvider.notifier);
    switch (cmd.kind) {
      case VoiceCommandKind.driveForward:
        _voiceDrive('forward');
        break;
      case VoiceCommandKind.driveBack:
        _voiceDrive('back');
        break;
      case VoiceCommandKind.driveLeft:
        _voiceDrive('left');
        break;
      case VoiceCommandKind.driveRight:
        _voiceDrive('right');
        break;
      case VoiceCommandKind.stop:
        chassis.emergencyStop();
        break;
      case VoiceCommandKind.resume:
        break; // no chassis "resume" — the pill is the only feedback
      case VoiceCommandKind.wave:
        ref.read(armProvider.notifier).wave();
        break;
      case VoiceCommandKind.snapshot:
        break; // no snapshot pipeline yet — pill only
      case VoiceCommandKind.reset:
        ref.read(headProvider.notifier).resetHead();
        RobotGestures.resetArms();
        RobotGestures.headCenter();
        break;
      case VoiceCommandKind.sleep:
        setState(() => _resting = true);
        _setKind(FaceStateKind.sleepy);
        break;
      case VoiceCommandKind.wake:
        setState(() => _resting = false);
        _setKind(FaceStateKind.attentive);
        break;
    }
  }

  // One-shot drive nudge: drive, then auto-stop (voice commands aren't held).
  void _voiceDrive(String dir) {
    final chassis = ref.read(chassisProvider.notifier);
    chassis.drive(dir);
    Timer(const Duration(milliseconds: 1400), chassis.stopMove);
  }

  // ── Idle return + navigation ────────────────────────────────────────────────
  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(_idleReturn, () {
      if (!mounted) return;
      // Don't auto-return to the face screen while a conversation is live — the
      // visitor is talking, not touching the screen. Re-check next window; the
      // session's own idle watchdog closes it on genuine silence, after which this
      // navigates back (sessionEnded re-arms a fresh countdown).
      if (_voiceActive) {
        _resetIdle();
        return;
      }
      Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  Future<void> _open(Widget screen) async {
    _idle?.cancel();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _resetIdle();
  }

  // Slim banner shown only while a voice session is live: status + an explicit
  // "End Conversation" control (the shared session is otherwise stopped only from
  // the face screen). Ends the same session both screens share.
  Widget _conversationBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1412),
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(children: [
        const Icon(Icons.graphic_eq_rounded, size: 18, color: _accent),
        const SizedBox(width: 10),
        const Text('Conversation active',
            style: TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        GestureDetector(
          onTap: () => widget.voiceAgent.endSession(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE5484D),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stop_rounded, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text('End Conversation',
                  style: TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Action tiles (§5) ───────────────────────────────────────────────────────
  void _toast(String text, IconData icon) {
    setState(() {
      _toastText = text;
      _toastIcon = icon;
      _toastVisible = true;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toastVisible = false);
    });
  }

  void _revertAfter([int ms = 2600]) {
    _revert?.cancel();
    _revert = Timer(Duration(milliseconds: ms), () {
      if (!mounted || _resting) return;
      setState(() {
        _activeAct = null;
        _face = _face.copyWith(state: FaceStateKind.attentive);
      });
    });
  }

  void _runAction(_Act a) {
    _resetIdle();
    _seq?.cancel();
    if (a != _Act.rest && _resting) _resting = false; // any action wakes from rest
    setState(() => _activeAct = a);

    switch (a) {
      case _Act.greet:
        _setKind(FaceStateKind.greeting);
        ref.read(armProvider.notifier).wave(); // real wave gesture
        _toast('Greeting visitor', Icons.waving_hand_rounded);
        // Same Settings-editable template the ambient face uses for visitors.
        _say(languageForCode(RobotConfig.voiceLanguageCode).renderGreeting(
            RobotConfig.greetVisitorTemplate,
            company: RobotConfig.companyName));
        _revertAfter(2600);
        break;
      case _Act.listen:
        // Preview: listening → thinking → speaking (real voice flow lands later).
        _setKind(FaceStateKind.listening);
        _toast('Listening…', Icons.mic_rounded);
        _say("I'm listening, go ahead.");
        _seq = Timer(const Duration(milliseconds: 2200), () {
          if (!mounted) return;
          _setKind(FaceStateKind.thinking);
          _seq = Timer(const Duration(milliseconds: 1100), () {
            if (!mounted) return;
            _setKind(FaceStateKind.speaking);
            _revertAfter(2600);
          });
        });
        break;
      case _Act.checkIn:
        _setKind(FaceStateKind.attentive);
        _toast('Who are you here to see?', Icons.assignment_ind_outlined);
        _say('Sure — who are you here to see?');
        _revertAfter(2600);
        break;
      case _Act.directions:
        _setKind(FaceStateKind.speaking);
        _toast('Giving directions →', Icons.signpost_outlined);
        _say('Of course, let me show you the way.');
        _revertAfter(2600);
        break;
      case _Act.pageStaff:
        _setKind(FaceStateKind.speaking);
        _toast('Paging the front desk…', Icons.campaign_outlined);
        _say('One moment, I am paging the front desk.');
        _revertAfter(2600);
        break;
      case _Act.rest:
        _resting = !_resting;
        _revert?.cancel();
        if (_resting) {
          _setKind(FaceStateKind.sleepy);
          _toast('Resting', Icons.bedtime_outlined);
          _say('Going to rest now. Tap me when you need me.');
        } else {
          setState(() => _activeAct = null);
          _setKind(FaceStateKind.attentive);
        }
        break;
    }
  }

  /// Speak a phrase aloud in Mikee's real voice — ElevenLabs TTS (same voice as the
  /// face screen), streamed through the shared speaker. Falls back to the on-device
  /// Google TTS only if ElevenLabs is unreachable.
  Future<void> _say(String text) async {
    final ok = await _tts.speak(text);
    if (!ok && mounted) widget.audioBridge.speak(text);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _resetIdle(),
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(children: [
            _topBar(),
            if (_voiceActive) _conversationBar(),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                final h = c.maxHeight;

                // Responsive columns (§1, §7).
                final showNav = w > 980;
                final tight = w <= 1200;
                final navW = tight ? 208.0 : 240.0;
                final ctrlW = tight ? 284.0 : 320.0;
                final dockCols = w <= 980 ? 3 : 6;

                // clamp(min, …vh, max) sizing from the body height.
                _dockH = _vh(h, 0.13, 78, 116);
                _padSq = _vh(h, 0.20, 140, 195); // bigger d-pad → easy to tap (fits chassis + speed row)
                _armH = _vh(h, 0.12, 54, 96); // bigger Wave/Reset buttons
                _estopH = _vh(h, 0.06, 44, 52);
                _tileLabel = _vh(h, 0.0175, 12, 14);
                _tileSub = _vh(h, 0.0135, 9, 10.5);

                return Row(children: [
                  if (showNav) _navRail(navW),
                  Expanded(child: _center(dockCols)),
                  _controls(ctrlW),
                ]);
              }),
            ),
          ]),
        ),
      ),
    );
  }

  static double _vh(double h, double frac, double lo, double hi) =>
      (h * frac).clamp(lo, hi).toDouble();

  // ── Top bar (§1) ────────────────────────────────────────────────────────────
  Widget _topBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: _panel2,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(children: [
        _IconBox(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        // Flexible so the title yields width to the enlarged language button +
        // status pills on the right (truncates instead of overflowing the row).
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: 'Mikee ',
                      style: TextStyle(color: _accent, fontSize: 15, fontWeight: FontWeight.w700)),
                  TextSpan(
                      text: 'Dashboard',
                      style: TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 1),
              Text('RECEPTION HOST',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: _muted2, fontSize: 11, letterSpacing: 1.98, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        LanguageButton(
          voiceAgent: widget.voiceAgent,
          dark: true,
          large: true, // same enlarged style as the face screen
          onReturned: () { if (mounted) setState(() {}); }, // refresh badge
        ),
        const SizedBox(width: 8),
        Consumer(builder: (_, ref, __) {
          final online = ref.watch(headProvider).isRunning ||
              ref.watch(chassisProvider).isRunning ||
              ref.watch(armProvider).isRunning;
          return _pill(online ? _green : Colors.white24, online ? 'SDK Online' : 'SDK Offline');
        }),
        const SizedBox(width: 8),
        _pill(_perceptionOn ? _accent : Colors.white24,
            _perceptionOn ? 'Perception On' : 'Perception Off'),
        const SizedBox(width: 8),
        Consumer(builder: (_, ref, __) {
          final b = ref.watch(batteryProvider).level;
          final icon = b == null
              ? Icons.battery_unknown_rounded
              : b > 66
                  ? Icons.battery_full_rounded
                  : b > 33
                      ? Icons.battery_5_bar_rounded
                      : Icons.battery_2_bar_rounded;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 24, color: _muted),
            const SizedBox(width: 6),
            Text(b == null ? '—' : '$b%',
                style: const TextStyle(color: _muted, fontSize: 17, fontWeight: FontWeight.w700)),
          ]);
        }),
        const SizedBox(width: 12),
        Text(_timeStr,
            style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _pill(Color dot, String label) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        border: Border.all(color: _line2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.7), blurRadius: 6)])),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _ink, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Nav rail (§3) ─────────────────────────────────────────────────────────
  Widget _navRail(double w) {
    return Container(
      width: w,
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(right: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Brand block
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_accent, _accentDimColor]),
                boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.35), blurRadius: 10)],
              ),
              alignment: Alignment.center,
              child: const Text('T',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Mikee', style: TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('FRONT DESK · BAY 1',
                      style: TextStyle(
                          color: _muted2, fontSize: 8, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                ]),
          ]),
        ),
        _navLabel('Menu'),
        _NavItem(icon: Icons.home_rounded, label: 'Home', active: true, onTap: () {}),
        _NavItem(icon: Icons.person_add_alt_1_rounded, label: 'Enroll Staff',
            onTap: () => _open(const EnrollScreen())),
        _NavItem(icon: Icons.insights_rounded, label: 'Robot Status',
            onTap: () => _open(const RobotStatusScreen())),
        _NavItem(icon: Icons.sports_esports_rounded, label: 'Manual Control',
            onTap: () => _open(const ManualControlScreen())),
        _NavItem(icon: Icons.pin_drop_rounded, label: 'Navigation Points',
            onTap: () => _open(const NavPointsScreen())),
        _NavItem(icon: Icons.settings_rounded, label: 'Settings',
            onTap: () => _open(const SettingsScreen())),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Divider(height: 1, color: _line),
        ),
        _navLabel('Services'),
        const _NavItem(icon: Icons.mic_rounded, label: 'Voice Q&A', soon: true),
        const _NavItem(icon: Icons.payments_rounded, label: 'Pay', soon: true),
        const _NavItem(icon: Icons.menu_book_rounded, label: 'Directory', soon: true),
        const Spacer(),
        // Live perception toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _panel2,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.visibility_rounded, size: 16, color: _muted),
            const SizedBox(width: 8),
            const Expanded(child: Text('Live Perception', style: TextStyle(color: _muted, fontSize: 11))),
            Switch(
              value: _perceptionOn,
              activeThumbColor: Colors.white,
              activeTrackColor: _accent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: _line2,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => setState(() => _perceptionOn = v),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _navLabel(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                color: Colors.white24, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
      );

  // ── Center: face card + action dock (§1, §5, §6) ────────────────────────────
  Widget _center(int dockCols) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _faceCard()),
        const SizedBox(height: 12),
        _actionDock(dockCols),
      ]),
    );
  }

  Widget _faceCard() {
    final glow = _glowColor(_face.state);
    final showWave = _face.state == FaceStateKind.listening ||
        _face.state == FaceStateKind.speaking;
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final t = glow == null ? 0.0 : (0.4 + 0.6 * _pulse.value); // 0.4..1.0
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: glow == null ? _line : Color.lerp(_line, glow, t)!,
              width: glow == null ? 1 : 2,
            ),
            boxShadow: glow == null
                ? null
                : [BoxShadow(color: glow.withValues(alpha: 0.45 * t), blurRadius: 24, spreadRadius: 1)],
          ),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: FacePainter(_rig.live, repaint: _repaint))),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.95,
                    colors: [Colors.transparent, Color(0x7A000000)],
                    stops: [0.62, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(top: 12, left: 14, child: _stateChip()),
          if (showWave)
            Positioned(right: 16, bottom: 16, child: IgnorePointer(child: _miniWaveform())),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: IgnorePointer(child: Center(child: _toastPill())),
          ),
        ]),
      ),
    );
  }

  Widget _stateChip() {
    final (name, desc) = _stateLabel(_face.state);
    final glow = _glowColor(_face.state);
    final active = _face.state != FaceStateKind.idle && _face.state != FaceStateKind.sleepy;
    final dot = glow ?? (active ? _accent : Colors.white30);
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final p = glow == null ? 1.0 : (0.4 + 0.6 * _pulse.value);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xD10F0F0F),
            border: Border.all(color: glow == null ? _line2 : glow.withValues(alpha: 0.55 * p)),
            borderRadius: BorderRadius.circular(99),
            boxShadow: glow == null
                ? null
                : [BoxShadow(color: glow.withValues(alpha: 0.30 * p), blurRadius: 12)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dot.withValues(alpha: glow == null ? 1.0 : p),
                shape: BoxShape.circle,
                boxShadow: (glow != null || active)
                    ? [BoxShadow(color: dot.withValues(alpha: 0.7 * (glow == null ? 1.0 : p)), blurRadius: 6)]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(name,
                  key: ValueKey(name),
                  style: TextStyle(
                      color: glow ?? _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
            ),
            const SizedBox(width: 6),
            Text(desc, style: const TextStyle(color: _muted, fontSize: 9)),
          ]),
        );
      },
    );
  }

  // Three staggered bars (phase offsets ≈ 0/80/160 ms over the pulse period).
  // Heights ride the TTS amplitude (_face.mouthOpen) while speaking; an idle
  // shimmer keeps them alive while listening.
  Widget _miniWaveform() {
    final speaking = _face.state == FaceStateKind.speaking;
    final color = _glowColor(_face.state) ?? _accent;
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        Widget bar(double phase) {
          final ph = (_pulseCtrl.value + phase) % 1.0;
          final wave = 0.5 + 0.5 * sin(ph * 2 * pi);
          final amp = speaking ? _face.mouthOpen.clamp(0.0, 1.0) : 0.0;
          final h = 5 + 7 * wave + amp * 20;
          return Container(
            width: 3.5,
            height: h,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(2)),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [bar(0.0), const SizedBox(width: 3), bar(0.2), const SizedBox(width: 3), bar(0.4)],
        );
      },
    );
  }

  (String, String) _stateLabel(FaceStateKind k) => switch (k) {
        FaceStateKind.idle => ('IDLE', '· relaxed, watching the room'),
        FaceStateKind.attentive => ('ATTENTIVE', "· someone's here"),
        FaceStateKind.greeting => ('GREETING', '· welcome!'),
        FaceStateKind.listening => ('LISTENING', '· hearing you…'),
        FaceStateKind.thinking => ('THINKING', '· one moment…'),
        FaceStateKind.speaking => ('SPEAKING', '· responding'),
        FaceStateKind.sleepy => ('SLEEPY', '· resting'),
      };

  Widget _toastPill() {
    return AnimatedSlide(
      offset: _toastVisible ? Offset.zero : const Offset(0, 0.4),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _toastVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xDB141414),
            border: Border.all(color: _accent.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_toastIcon, size: 14, color: _accent),
            const SizedBox(width: 8),
            Text(_toastText, style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ── Action dock — saved navigation points, tap to go (§5 repurposed) ────────
  Widget _actionDock(int cols) {
    return Consumer(builder: (context, ref, _) {
      final st = ref.watch(navPointsProvider);
      final points = st.points.valueOrNull ?? const <NavPoint>[];
      if (points.isEmpty) {
        return SizedBox(
          height: _dockH,
          child: Center(
            child: Text('No saved points yet — capture them in Navigation Points',
                style: TextStyle(color: Colors.white38, fontSize: _tileSub)),
          ),
        );
      }
      final busy = st.navigatingTo != null;
      Widget tile(NavPoint p) => SizedBox(
            width: 176,
            child: Material(
              color: st.navigatingTo?.id == p.id
                  ? kOrange.withOpacity(0.18)
                  : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: busy ? null : () => ref.read(navPointsProvider.notifier).goTo(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place_rounded, color: kOrange, size: 20),
                        const SizedBox(height: 6),
                        Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: _tileLabel,
                                fontWeight: FontWeight.w700)),
                        Text(busy ? 'Navigating…' : 'Tap to go',
                            style: TextStyle(
                                color: Colors.white38, fontSize: _tileSub)),
                      ]),
                ),
              ),
            ),
          );
      return SizedBox(
        height: _dockH,
        child: Row(children: [
          SizedBox(
            width: 96,
            child: Material(
              color: _patrolling ? const Color(0xFF7F1D1D) : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: points.length < 2
                    ? null
                    : () {
                        final spine = ref.read(navSpineClientProvider);
                        if (_patrolling) {
                          spine.sendIntent({'intent': 'patrol_stop'});
                        } else {
                          spine.sendIntent({
                            'intent': 'patrol_start',
                            'loop': true,
                            'points': [
                              for (final p in points)
                                {
                                  'x': p.x, 'y': p.y, 'z': p.z,
                                  'rotation': p.rotation, 'name': p.name,
                                  if (p.description?.trim().isNotEmpty == true)
                                    'arrivalText': p.description!.trim(),
                                }
                            ],
                          });
                        }
                        setState(() => _patrolling = !_patrolling);
                      },
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_patrolling ? Icons.stop_rounded : Icons.route_rounded,
                          color: kOrange, size: 22),
                      const SizedBox(height: 6),
                      Text(_patrolling ? 'Stop' : 'Patrol',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: _tileLabel,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: points.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => tile(points[i]),
            ),
          ),
        ]),
      );
    });
  }

  // ── Quick Controls (§4) — height-distributing, fixed E-Stop ─────────────────
  Widget _controls(double w) {
    return Container(
      width: w,
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(left: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Row(children: const [
            Icon(Icons.swap_horiz_rounded, size: 16, color: _accent),
            SizedBox(width: 8),
            Text('Quick Controls', style: TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
        Expanded(
          child: Column(children: [
            Expanded(child: _headBlock()),
            const SizedBox(height: 10),
            Expanded(child: _chassisBlock()),
            const SizedBox(height: 10),
            Expanded(child: _armBlock()),
          ]),
        ),
        const SizedBox(height: 10),
        _estop(),
      ]),
    );
  }

  // All controls are wired to real SDK calls: Head ▲▼◀▶ → nudge (MikeeActionCustomerCtrl),
  // CTR → resetHead; Chassis ▲▼◀▶ → hold-to-drive (moveForward/moveBySerial + moveSerial
  // heartbeat), STOP/E-Stop → emergencyStop; Speed → setSpeed; Arm Wave/Reset → wave/reset.
  // Badges reflect real motor/arm state (providers update from the plugin event channels).

  Widget _headBlock() {
    return Consumer(builder: (_, ref, __) {
      final h = ref.watch(headProvider);
      final n = ref.read(headProvider.notifier);
      void onNudge(String dir) {
        n.nudge(dir); // real head pan/tilt (MikeeActionCustomerCtrl)
        _setKind(FaceStateKind.attentive);
        _revert?.cancel();
        _revert = Timer(const Duration(milliseconds: 600), () {
          if (mounted && !_resting && _activeAct == null) _setKind(FaceStateKind.idle);
        });
      }

      return _ctrlBlock(
        'Head',
        h.isRunning ? _Badge.active('ACTIVE') : _Badge.idle('IDLE'),
        _dpad([
          null, _DpadBtn(Icons.keyboard_arrow_up_rounded, onTap: () => onNudge('up')), null,
          _DpadBtn(Icons.keyboard_arrow_left_rounded, onTap: () => onNudge('left')),
          _DpadBtn.center('CTR', onTap: n.resetHead),
          _DpadBtn(Icons.keyboard_arrow_right_rounded, onTap: () => onNudge('right')),
          null, _DpadBtn(Icons.keyboard_arrow_down_rounded, onTap: () => onNudge('down')), null,
        ]),
      );
    });
  }

  Widget _chassisBlock() {
    return Consumer(builder: (_, ref, __) {
      final c = ref.watch(chassisProvider);
      final n = ref.read(chassisProvider.notifier);
      // Badge reflects real motor state (provider updates from the plugin's events).
      final movingDir = c.isMoving ? c.direction : null;

      void onDrive(String dir) {
        n.drive(dir); // real hold-to-drive (heartbeat moveSerial until stopMove)
        _setKind(FaceStateKind.attentive);
      }

      return _ctrlBlock(
        'Chassis',
        movingDir != null && movingDir != 'none'
            ? _Badge.active('MOVING · ${movingDir.toUpperCase()}')
            : _Badge.idle('STOPPED'),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _dpad([
            null,
            _DpadBtn(Icons.keyboard_arrow_up_rounded,
                onPressStart: () => onDrive('forward'), onPressEnd: n.stopMove),
            null,
            _DpadBtn(Icons.keyboard_arrow_left_rounded,
                onPressStart: () => onDrive('left'), onPressEnd: n.stopMove),
            _DpadBtn.stop(onTap: n.emergencyStop),
            _DpadBtn(Icons.keyboard_arrow_right_rounded,
                onPressStart: () => onDrive('right'), onPressEnd: n.stopMove),
            null,
            _DpadBtn(Icons.keyboard_arrow_down_rounded,
                onPressStart: () => onDrive('back'), onPressEnd: n.stopMove),
            null,
          ]),
          const SizedBox(height: 8),
          _speedRow(n),
        ]),
      );
    });
  }

  Widget _speedRow(ChassisNotifier n) {
    return Row(children: [
      const Text('Speed',
          style: TextStyle(fontSize: 9, color: _muted2, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 5,
            activeTrackColor: _accent,
            inactiveTrackColor: const Color(0xFF2A2A2A),
            thumbColor: _accent,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: _speed.clamp(30, 80),
            min: 30,
            max: 80,
            divisions: 10,
            onChanged: (v) {
              setState(() => _speed = v);
              n.setSpeed(v / 100); // provider expects 0.3–0.8
            },
          ),
        ),
      ),
      SizedBox(
        width: 34,
        child: Text('${_speed.round()}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, color: _accent, fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  Widget _armBlock() {
    return Consumer(builder: (_, ref, __) {
      final a = ref.watch(armProvider);
      final n = ref.read(armProvider.notifier);
      return _ctrlBlock(
        'Arm',
        a.isWaving ? _Badge.active('WAVING') : _Badge.idle('IDLE'),
        Row(children: [
          Expanded(
            child: _ArmBtn(
              icon: Icons.waving_hand_rounded,
              label: a.isWaving ? 'Waving' : 'Wave',
              height: _armH,
              highlighted: a.isWaving,
              onTap: () {
                if (a.isWaving) {
                  n.stopWave();
                } else {
                  n.wave();
                  _setKind(FaceStateKind.greeting);
                  _revertAfter(2200);
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ArmBtn(
              icon: Icons.refresh_rounded, label: 'Reset', height: _armH, onTap: n.resetArms),
          ),
        ]),
      );
    });
  }

  Widget _estop() {
    return Consumer(builder: (_, ref, __) {
      final c = ref.watch(chassisProvider);
      final n = ref.read(chassisProvider.notifier);
      final stopped = c.isMoving;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            n.emergencyStop();
            n.stopMove();
            ref.read(armProvider.notifier).stopWave();
            _setKind(FaceStateKind.attentive);
          },
          child: Container(
            height: _estopH,
            width: double.infinity,
            decoration: BoxDecoration(
              color: stopped ? const Color(0x33FF5247) : const Color(0x14FF5247),
              border: Border.all(color: stopped ? _red : const Color(0x59FF5247), width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.pan_tool_rounded, color: _red, size: 16),
              SizedBox(width: 8),
              Text('EMERGENCY STOP',
                  style: TextStyle(color: _red, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
            ]),
          ),
        ),
      );
    });
  }

  // Block chrome: header (name + badge) at top, body vertically centered.
  Widget _ctrlBlock(String name, Widget badge, Widget body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(name.toUpperCase(),
              style: const TextStyle(color: _muted, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const Spacer(),
          badge,
        ]),
        Expanded(child: Center(child: body)),
      ]),
    );
  }

  // 3×3 d-pad, square clamp(64,13vh,150). [cells] is 9 long; null = blank.
  Widget _dpad(List<Widget?> cells) {
    return SizedBox(
      width: _padSq,
      height: _padSq,
      child: Column(children: [
        for (var r = 0; r < 3; r++)
          Expanded(
            child: Row(children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: cells[r * 3 + col] ?? const SizedBox.shrink(),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

// ── Per-frame repaint signal (painter only) ──────────────────────────────────
class _FaceRepaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

// ── Top-bar icon box ──────────────────────────────────────────────────────────
class _IconBox extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBox({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            border: Border.all(color: _line2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 15, color: _muted),
        ),
      ),
    );
  }
}

// ── Nav item (§3) ─────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool soon;
  final VoidCallback? onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.soon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? _accent : _muted;
    final item = Container(
      decoration: BoxDecoration(
        color: active ? const Color(0x21FF6B35) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? const Color(0x66FF6B35) : Colors.transparent),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: active ? _accent : _ink,
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ),
        if (soon)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
                border: Border.all(color: _line2), borderRadius: BorderRadius.circular(4)),
            child: const Text('SOON',
                style: TextStyle(color: _muted2, fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
      ]),
    );
    if (soon) return Opacity(opacity: 0.38, child: IgnorePointer(child: item));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: item),
      ),
    );
  }
}

// ── Action tile (§5) ──────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final _Act act;
  final bool active;
  final double labelSize;
  final double subSize;
  final VoidCallback onTap;
  const _ActionTile({
    required this.act,
    required this.active,
    required this.labelSize,
    required this.subSize,
    required this.onTap,
  });

  static const _spec = {
    _Act.greet: (Icons.waving_hand_rounded, 'Greet', 'Welcome a visitor'),
    _Act.listen: (Icons.mic_rounded, 'Listen', 'Hear the visitor'),
    _Act.checkIn: (Icons.assignment_ind_outlined, 'Check In', 'Visitor for a meeting'),
    _Act.directions: (Icons.signpost_outlined, 'Directions', 'Guide & wayfind'),
    _Act.pageStaff: (Icons.campaign_outlined, 'Page Staff', 'Notify reception'),
    _Act.rest: (Icons.bedtime_outlined, 'Rest', 'Low-power / sleep'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, label, sub) = _spec[act]!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF181818), Color(0xFF141414)]),
            border: Border.all(color: active ? _accent : _line),
            borderRadius: BorderRadius.circular(14),
            boxShadow: active ? [BoxShadow(color: _accent.withValues(alpha: 0.18), blurRadius: 12)] : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                border: Border.all(color: active ? _accent : _line2),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: _accent),
            ),
            const Spacer(),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _ink, fontSize: labelSize, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: subSize)),
          ]),
        ),
      ),
    );
  }
}

// ── Status badge (§4) ─────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String text;
  final bool on;
  const _Badge._(this.text, this.on);
  factory _Badge.active(String t) => _Badge._(t, true);
  factory _Badge.idle(String t) => _Badge._(t, false);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: on ? _greenBg : const Color(0xFF242424),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text,
          style: TextStyle(
              color: on ? _green : _muted, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}

// ── D-pad button ──────────────────────────────────────────────────────────────
class _DpadBtn extends StatelessWidget {
  final IconData? icon;
  final String? text;
  final VoidCallback? onTap; // discrete tap (head nudge, CTR, STOP)
  final VoidCallback? onPressStart; // hold-to-drive (chassis): press
  final VoidCallback? onPressEnd; // hold-to-drive: release/cancel
  final bool stop;
  final bool center;
  const _DpadBtn(this.icon, {this.onTap, this.onPressStart, this.onPressEnd})
      : text = null,
        stop = false,
        center = false;
  const _DpadBtn.center(this.text, {required this.onTap})
      : icon = null,
        onPressStart = null,
        onPressEnd = null,
        stop = false,
        center = true;
  const _DpadBtn.stop({required this.onTap})
      : icon = null,
        text = 'STOP',
        onPressStart = null,
        onPressEnd = null,
        stop = true,
        center = false;

  @override
  Widget build(BuildContext context) {
    final Color border = stop ? const Color(0x40FF5247) : _line2;
    final Color fg = stop ? _red : (center ? _muted2 : _muted);
    final Color bg = stop ? const Color(0x14FF5247) : const Color(0xFF161616);
    final Widget visual = Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: 18, color: fg)
          : Text(text!,
              style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
    );
    // Hold-to-drive (chassis): drive on press, stop on release/cancel.
    if (onPressStart != null) {
      return GestureDetector(
        onTapDown: (_) => onPressStart!(),
        onTapUp: (_) => onPressEnd?.call(),
        onTapCancel: () => onPressEnd?.call(),
        child: visual,
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: visual),
    );
  }
}

// ── Arm button ────────────────────────────────────────────────────────────────
class _ArmBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final double height;
  final bool highlighted;
  final VoidCallback onTap;
  const _ArmBtn({
    required this.icon,
    required this.label,
    required this.height,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = highlighted ? _accent : _muted;
    return Material(
      color: highlighted ? const Color(0x21FF6B35) : const Color(0xFF161616),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: highlighted ? _accent : _line2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
          ]),
        ),
      ),
    );
  }
}
