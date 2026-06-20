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
import 'face_rig.dart';
import 'gaze_tracker.dart';
import 'services/spine_client.dart';
import 'services/voice_agent.dart';
import 'services/audio_bridge.dart';
import 'dashboard_screen.dart';

/// The robot's front-of-house home: an ambient animated face (Beam/OLED
/// CustomPainter, #82). #82 P2 wires it to live perception:
///   • LOCAL ML Kit on /snapshot → gaze x/y + presence → attentive (anonymous).
///   • SPINE WS face_detected → greeting-by-name (authoritative identity).
///   • CSJBot personDetected → coarse presence fallback.
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
  StreamSubscription<bool>? _presenceSub;

  bool _useLivePerception = true; // toggle in debug card; drives gaze when on
  bool _present = false; // a face box is currently visible
  double _liveGazeX = 0, _liveGazeY = 0;
  Timer? _presenceHold;

  // Greeting overlay (Wire 2).
  String? _greetName;
  bool _greetVisible = false;
  Timer? _greetTimer;
  final Map<String, DateTime> _greetedAt = {}; // 10-min re-greet debounce

  // Voice (#80) — ElevenLabs Conversational AI session + audio bridge.
  late final VoiceAgent _voiceAgent;
  final AudioBridge _audioBridge = AudioBridge();
  StreamSubscription<VoiceEvent>? _voiceSub;
  StreamSubscription<String>? _wakeSub;
  bool _voiceActive = false; // a session is open (toggles the debug button)
  double _micLevel = 0; // smoothed mic RMS 0..1 — drives the "listening" meter
  Timer? _speechGapTimer; // return speaking → listening after Timo's audio stops

  static const Duration _greetHold = Duration(milliseconds: 3500);
  static const Duration _regreetWindow = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();

    // Live perception streams.
    _gazeSub = _gaze.results.listen(_onGaze);
    _faceSub = _spine.faceDetected.listen(_onFaceDetected);
    _presenceSub = _spine.personDetected.listen(_onPersonDetected);
    _gaze.start();
    _spine.start();

    // Voice (#80) — session is opened on demand (debug overlay / Phase B wake word).
    _voiceAgent = VoiceAgent(
      agentId: RobotConfig.elevenLabsAgentId,
      apiKey: RobotConfig.elevenLabsApiKey,
    );
    _voiceSub = _voiceAgent.events.listen(_onVoiceEvent);

    // Wake word (Phase B): CSJBot "wakeup" → start a session. Silent stream on
    // the emulator (the native plugin swallows the SDK absence). The face tap is
    // the other trigger (debug overlay today; whole-face tap later).
    _wakeSub = _audioBridge.wakeWordStream.listen((_) {
      if (!_voiceAgent.isActive) _startVoice();
    });

    // Preserve old behavior: bring up the control WS servers (:8081-3) if the
    // camera is already streaming when we mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(streamProvider).isStreaming) _startControlServers();
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
    _voiceSub?.cancel();
    _wakeSub?.cancel();
    _speechGapTimer?.cancel();
    _voiceAgent.dispose();
    _audioBridge.dispose();
    _gazeSub?.cancel();
    _faceSub?.cancel();
    _presenceSub?.cancel();
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

  // ── Wire 1: local gaze + presence ───────────────────────────────────────────
  void _onGaze(GazeResult r) {
    if (r.facePresent) {
      _liveGazeX = r.gazeX;
      _liveGazeY = r.gazeY;
      _present = true;
      _presenceHold?.cancel();
      _presenceHold = null;
      if (_useLivePerception && _face.state == FaceStateKind.idle) {
        _setStateKind(FaceStateKind.attentive);
      }
    } else {
      // Hold attentive briefly before returning to idle (kills jitter).
      if (_present && _presenceHold == null) {
        final hold = _face.state == FaceStateKind.greeting
            ? const Duration(seconds: 5)
            : const Duration(seconds: 3);
        _presenceHold = Timer(hold, () {
          _present = false;
          _presenceHold = null;
          if (_face.state == FaceStateKind.attentive) {
            _setStateKind(FaceStateKind.idle);
          }
        });
      }
    }
    if (mounted && kDebugMode) setState(() {}); // refresh the perception card
  }

  // ── Wire 2: spine identity + presence ───────────────────────────────────────
  void _onFaceDetected(FaceDetectedEvent e) {
    if (_voiceActive) return; // don't greet over a live conversation
    final now = DateTime.now();
    final last = _greetedAt[e.name];
    if (last != null && now.difference(last) < _regreetWindow) return; // debounce
    _greetedAt[e.name] = now;

    _greetTimer?.cancel();
    setState(() {
      _greetName = e.name;
      _greetVisible = true;
      _face = _face.copyWith(state: FaceStateKind.greeting);
    });
    _greetTimer = Timer(_greetHold, () {
      if (!mounted) return;
      setState(() {
        _greetVisible = false;
        _face = _face.copyWith(
            state: _present ? FaceStateKind.attentive : FaceStateKind.idle);
      });
    });
  }

  void _onPersonDetected(bool pd) {
    // Coarse presence: promote idle → attentive (eyes centered, no box to track).
    if (pd && !_present && _face.state == FaceStateKind.idle) {
      setState(() => _face =
          _face.copyWith(state: FaceStateKind.attentive, gazeX: 0, gazeY: 0));
    }
  }

  void _setStateKind(FaceStateKind k) {
    if (!mounted) return;
    setState(() => _face = _face.copyWith(state: k));
  }

  // ── #80 voice: ElevenLabs session drives the face state machine ─────────────
  void _onVoiceEvent(VoiceEvent e) {
    switch (e.kind) {
      case VoiceEventKind.sessionStarted:
        // Open in listening — Timo is waiting for the user (the ring shows).
        setState(() {
          _voiceActive = true;
          _face = _face.copyWith(state: FaceStateKind.listening);
        });
        break;
      case VoiceEventKind.userSpeaking:
        // User cut in (interruption) → stop playback + listen.
        _speechGapTimer?.cancel();
        _audioBridge.stopPlayback();
        setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
        break;
      case VoiceEventKind.agentThinking:
        // Genuine processing gap (STT done, reply not yet streaming).
        _speechGapTimer?.cancel();
        setState(() => _face = _face.copyWith(state: FaceStateKind.thinking, mouthOpen: 0));
        break;
      case VoiceEventKind.agentSpeaking:
        setState(() => _face = _face.copyWith(state: FaceStateKind.speaking));
        break;
      case VoiceEventKind.audioChunk:
        // Play the PCM chunk through the speaker + drive lip-sync from amplitude.
        // Stay in speaking; a gap timer flips back to listening when audio stops.
        if (e.audioChunk != null) _audioBridge.playChunk(e.audioChunk!);
        if (e.amplitude != null) {
          setState(() => _face = _face.copyWith(
              state: FaceStateKind.speaking, mouthOpen: e.amplitude!));
        }
        _armSpeechGap();
        break;
      case VoiceEventKind.sessionEnded:
        _speechGapTimer?.cancel();
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
        _speechGapTimer?.cancel();
        _audioBridge.stopMic();
        setState(() {
          _voiceActive = false;
          _micLevel = 0;
        });
        break;
    }
    // Mirror the voice phase to spine → admin app.
    _spine.sendVoiceState(e.kind);
  }

  void _startVoice() {
    _voiceAgent.startSession();
    // Capture mic → pipe PCM chunks to the agent AND meter the level so the UI
    // shows we're actually hearing audio (mic fails gracefully on the emulator).
    _audioBridge.startMic((chunk) {
      _voiceAgent.sendAudioChunk(chunk);
      _updateMicLevel(chunk);
    });
  }

  void _endVoice() => _voiceAgent.endSession();

  // Smoothed mic RMS → drives the "Listening / Hearing you" meter. If this never
  // moves while you talk, the mic isn't capturing (vs. a downstream problem).
  void _updateMicLevel(Uint8List chunk) {
    final lvl = VoiceAgent.pcmRms(chunk);
    final smoothed = _micLevel * 0.6 + lvl * 0.4;
    if (mounted) setState(() => _micLevel = smoothed);
  }

  // Timo's TTS streams in chunks; when they stop for a beat, the turn is over →
  // return to listening (no explicit "agent finished" event from ElevenLabs).
  void _armSpeechGap() {
    _speechGapTimer?.cancel();
    _speechGapTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || !_voiceActive) return;
      setState(() => _face = _face.copyWith(state: FaceStateKind.listening, mouthOpen: 0));
    });
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final battery = ref.watch(batteryProvider);
    final sdk = ref.watch(streamProvider.select((s) => s.sdkStatus));

    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr == true) _startControlServers();
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
          // Greeting overlay — "Hi, <name>!" below the mouth.
          if (_greetName != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).size.height * 0.18,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _greetVisible ? 1 : 0,
                  duration: Duration(milliseconds: _greetVisible ? 300 : 500),
                  child: Center(
                    child: Text('Hi, $_greetName!',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          // Status chip, top-right.
          Positioned(
            top: 12,
            right: 16,
            child: Opacity(
              opacity: 0.65,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SdkBadge(status: sdk),
                const SizedBox(width: 10),
                BatteryIndicator(state: battery),
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
