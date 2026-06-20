import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart'; // kOrange + head/chassis/arm/battery providers + states
import 'face_painter.dart'; // FaceState, FaceStateKind, FacePainter
import 'face_rig.dart'; // FaceRig
import 'services/voice_agent.dart';
import 'services/audio_bridge.dart';
import 'enroll_screen.dart';
import 'status_screen.dart';
import 'control_screen.dart';
import 'settings_screen.dart';

// ── Color tokens (match the prototype) ────────────────────────────────────────
const _bg = Color(0xFF0F0F0F);
const _surf = Color(0xFF1A1A1A);
const _surf2 = Color(0xFF222222);
const _border = Color(0xFF2A2A2A);
const _green = Color(0xFF4ADE80);
const _amber = Color(0xFFFBBF24);
const _red = Color(0xFFEF4444);

/// Feature dashboard (opened from the ambient face) — 3-zone landscape layout:
/// nav rail · live mini-face + conversation · quick controls.
/// Reacts to the SAME ElevenLabs session as the ambient face (shared VoiceAgent +
/// AudioBridge passed in). Auto-returns to the face after 30s idle.
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

class _ChatMsg {
  final String role; // 'timo' | 'visitor'
  final String text;
  const _ChatMsg(this.role, this.text);
}

// Single canonical product copy: "Timo, xboom's reception host" (lowercase xboom,
// per company name). NOTE: the ElevenLabs agent's own first message is configured
// in the dashboard — set it to match ("...xboom's reception host...") for full
// consistency once a live session replaces this placeholder.
const _greeting =
    "Hi! I'm Timo, xboom's reception host. How can I help you today?";

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // Mini face (independent animator from the ambient face).
  final FaceRig _rig = FaceRig();
  final _FaceRepaint _repaint = _FaceRepaint();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  FaceState _face = const FaceState();

  Timer? _idle;
  Timer? _clock;
  String _timeStr = '';
  static const _idleReturn = Duration(seconds: 30);

  StreamSubscription<VoiceEvent>? _voiceSub;
  StreamSubscription<double>? _playbackSub;
  List<_ChatMsg> _messages = const [_ChatMsg('timo', _greeting)];
  final ScrollController _scrollCtrl = ScrollController();
  bool _voiceActive = false;
  bool _perceptionOn = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _voiceActive = widget.voiceAgent.isActive;
    _updateClock();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _updateClock());
    _resetIdle();
    _voiceSub = widget.voiceAgent.events.listen(_onVoiceEvent);
    _playbackSub = widget.audioBridge.playbackLevelStream.listen(_onPlaybackLevel);
    _syncMessages();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _idle?.cancel();
    _clock?.cancel();
    _voiceSub?.cancel();
    _playbackSub?.cancel();
    _repaint.dispose();
    _scrollCtrl.dispose();
    // Do NOT dispose voiceAgent / audioBridge — owned by AmbientFaceScreen.
    super.dispose();
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    if (mounted) setState(() => _timeStr = '$h:$m');
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    // Dashboard-only: pin gaze forward/centered (no idle wander) so the iris stays
    // centered in the mini-face. The shared ambient face is unaffected (separate rig).
    _rig.tick(_face, dt.clamp(0.0, 0.05), followGx: 0, followGy: 0);
    _repaint.ping();
  }

  void _setKind(FaceStateKind k) {
    if (mounted) setState(() => _face = _face.copyWith(state: k));
  }

  // ── Voice (shared session) ──────────────────────────────────────────────────
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
        _syncMessages();
        break;
      case VoiceEventKind.agentSpeaking:
        _setKind(FaceStateKind.speaking);
        _syncMessages();
        break;
      case VoiceEventKind.audioChunk:
        // Playback is owned by AmbientFaceScreen (still alive underneath). Driving
        // playChunk here too would double-play. Lip-sync comes from the playback
        // level stream below.
        break;
      case VoiceEventKind.sessionEnded:
        setState(() => _voiceActive = false);
        _setKind(FaceStateKind.idle);
        _syncMessages();
        break;
      case VoiceEventKind.error:
        setState(() => _voiceActive = false);
        _setKind(FaceStateKind.idle);
        break;
    }
  }

  // Speaker amplitude (as it plays) → mini-face lip-sync; -1 = drained.
  void _onPlaybackLevel(double level) {
    if (!mounted || !_voiceActive) return;
    if (level < 0) {
      setState(() => _face = _face.copyWith(mouthOpen: 0));
    } else {
      setState(() => _face = _face.copyWith(
          state: FaceStateKind.speaking, mouthOpen: (level * 3.5).clamp(0.04, 1.0)));
    }
  }

  // Rebuild the transcript panel from the shared agent's accumulated turns.
  // The static greeting is ONLY shown when there's no real conversation yet —
  // once a session runs, the agent's own first message replaces it (no duplicate).
  void _syncMessages() {
    final t = widget.voiceAgent.transcript;
    final msgs = <_ChatMsg>[];
    for (final turn in t) {
      final role = (turn['role'] == 'user') ? 'visitor' : 'timo';
      final text = (turn['text'] ?? '').toString();
      if (text.isNotEmpty) msgs.add(_ChatMsg(role, text));
    }
    if (msgs.isEmpty) msgs.add(const _ChatMsg('timo', _greeting));
    if (mounted) setState(() => _messages = msgs);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _toggleVoice() {
    if (widget.voiceAgent.isActive) {
      widget.voiceAgent.endSession();
      widget.audioBridge.stopMic();
      widget.audioBridge.stopPlayback();
    } else {
      widget.voiceAgent.startSession();
      widget.audioBridge.startMic((chunk) => widget.voiceAgent.sendAudioChunk(chunk));
    }
    setState(() => _voiceActive = widget.voiceAgent.isActive);
  }

  void _onChip(String label) {
    setState(() => _messages = [..._messages, _ChatMsg('visitor', label)]);
    _scrollToBottom();
    if (!widget.voiceAgent.isActive) _toggleVoice(); // start voice to handle it
  }

  // ── Idle + navigation ─────────────────────────────────────────────────────
  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(_idleReturn, () {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  Future<void> _open(Widget screen) async {
    _idle?.cancel();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _resetIdle();
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
            Expanded(
              child: Row(children: [
                _navRail(),
                Expanded(child: _centerPanel()),
                _controlsPanel(),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────────
  Widget _topBar() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: _surf,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white60),
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Timo',
                style: TextStyle(color: kOrange, fontSize: 15, fontWeight: FontWeight.w700)),
            Text('RECEPTION HOST',
                style: TextStyle(
                    color: Colors.white38, fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w600)),
          ],
        ),
        const Spacer(),
        Consumer(builder: (_, ref, __) {
          final online = ref.watch(headProvider).isRunning ||
              ref.watch(chassisProvider).isRunning;
          return _pill(online ? _green : Colors.white24, online ? 'SDK Online' : 'SDK Offline');
        }),
        const SizedBox(width: 8),
        _pill(_perceptionOn ? _amber : Colors.white24,
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
            Icon(icon, size: 16, color: Colors.white60),
            const SizedBox(width: 4),
            Text(b == null ? '—' : '$b%',
                style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w600)),
          ]);
        }),
        const SizedBox(width: 12),
        Text(_timeStr,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
      ]),
    );
  }

  Widget _pill(Color dot, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _surf2,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Nav rail ──────────────────────────────────────────────────────────────
  Widget _navRail() {
    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: _surf,
        border: Border(right: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _navLabel('Main'),
        _NavItem(icon: Icons.home_rounded, label: 'Home', active: true, onTap: () {}),
        _NavItem(icon: Icons.person_add_alt_1_rounded, label: 'Enroll Staff',
            onTap: () => _open(const EnrollScreen())),
        _NavItem(icon: Icons.insights_rounded, label: 'Robot Status',
            onTap: () => _open(const RobotStatusScreen())),
        _NavItem(icon: Icons.sports_esports_rounded, label: 'Manual Control',
            onTap: () => _open(const ManualControlScreen())),
        _NavItem(icon: Icons.settings_rounded, label: 'Settings',
            onTap: () => _open(const SettingsScreen())),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Divider(height: 1, color: _border),
        ),
        _navLabel('Services'),
        const _NavItem(icon: Icons.mic_rounded, label: 'Voice Q&A', soon: true),
        const _NavItem(icon: Icons.payments_rounded, label: 'Pay', soon: true),
        const _NavItem(icon: Icons.navigation_rounded, label: 'Navigate', soon: true),
        const _NavItem(icon: Icons.menu_book_rounded, label: 'Directory', soon: true),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _surf2,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            const Icon(Icons.visibility_rounded, size: 16, color: Colors.white60),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Live Perception',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
            ),
            Switch(
              value: _perceptionOn,
              activeThumbColor: kOrange,
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

  // ── Center panel ────────────────────────────────────────────────────────────
  // Two equal-width cards, full Expanded width, 16 padding all round, 14 gap.
  Widget _centerPanel() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 46, child: _faceCard()),
        const SizedBox(height: 14),
        Expanded(flex: 54, child: _convoCard()),
      ]),
    );
  }

  // Face fills a tall rounded "chest screen" card → big, prominent eyes (the
  // painter scales to shortestSide, so a taller card = larger face).
  Widget _faceCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(painter: FacePainter(_rig.live, repaint: _repaint)),
          ),
          // Radial vignette over the face for chest-screen depth.
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
          Positioned(top: 10, left: 12, child: _stateChip()),
        ]),
      ),
    );
  }

  Widget _convoCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surf,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        _convoHeader(),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _bubble(_messages[i]),
          ),
        ),
        if (_messages.length <= 2) _chips(),
        _inputBar(),
      ]),
    );
  }

  Widget _convoHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
      child: Row(children: [
        const Icon(Icons.forum_rounded, size: 15, color: kOrange),
        const SizedBox(width: 8),
        const Text('Conversation',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        Container(width: 6, height: 6, decoration: BoxDecoration(
            color: _voiceActive ? _green : Colors.white24, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(_voiceActive ? 'Live' : 'Idle',
            style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _stateChip() {
    final (name, desc) = _stateLabel(_face.state);
    final active = _face.state != FaceStateKind.idle && _face.state != FaceStateKind.sleepy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xD10F0F0F),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: active ? kOrange : Colors.white30, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(name,
            style: const TextStyle(
                color: kOrange, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(width: 6),
        Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 9)),
      ]),
    );
  }

  (String, String) _stateLabel(FaceStateKind k) => switch (k) {
        FaceStateKind.idle => ('IDLE', '· relaxed, watching the room'),
        FaceStateKind.attentive => ('READY', '· someone is nearby'),
        FaceStateKind.greeting => ('GREETING', '· welcoming a visitor'),
        FaceStateKind.listening => ('LISTENING', '· hearing you…'),
        FaceStateKind.thinking => ('THINKING', '· processing…'),
        FaceStateKind.speaking => ('SPEAKING', '· responding'),
        FaceStateKind.sleepy => ('SLEEPY', '· power saving'),
      };

  Widget _bubble(_ChatMsg m) {
    final isTimo = m.role == 'timo';
    return Align(
      alignment: isTimo ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: isTimo ? _surf2 : const Color(0x26FF6B35),
          border: Border.all(color: isTimo ? _border : const Color(0x4DFF6B35)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isTimo ? 4 : 14),
            bottomRight: Radius.circular(isTimo ? 14 : 4),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isTimo)
            const Padding(
              padding: EdgeInsets.only(bottom: 3),
              child: Text('TIMO',
                  style: TextStyle(
                      color: kOrange, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          Text(m.text, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.45)),
        ]),
      ),
    );
  }

  Widget _chips() {
    const labels = ['Meet someone', 'WiFi password', 'About xboom', 'Restroom'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final l in labels)
          OutlinedButton(
            onPressed: () => _onChip(l),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l, style: const TextStyle(fontSize: 11)),
          ),
      ]),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
      child: Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _surf2,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('Tap 🎤 to speak',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _toggleVoice,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _voiceActive ? const Color(0x26EF4444) : const Color(0x26FF6B35),
              border: Border.all(color: _voiceActive ? _red : kOrange),
              borderRadius: BorderRadius.circular(10),
            ),
            // Idle = ready mic (orange). Active = clear STOP affordance (red) —
            // not a slashed "mic-off" that reads as broken/muted.
            child: Icon(_voiceActive ? Icons.stop_rounded : Icons.mic_rounded,
                color: _voiceActive ? _red : kOrange, size: 20),
          ),
        ),
      ]),
    );
  }

  // ── Controls panel ──────────────────────────────────────────────────────────
  Widget _controlsPanel() {
    return Container(
      width: 312,
      decoration: const BoxDecoration(
        color: _surf,
        border: Border(left: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          _ctrlSection('HEAD', Consumer(builder: (_, ref, __) {
            final h = ref.watch(headProvider);
            final n = ref.read(headProvider.notifier);
            return Column(children: [
              _HeadPositionIndicator(headLR: h.headLR, headUD: h.headUD),
              const SizedBox(height: 10),
              _SmallBtn('Reset', Icons.center_focus_strong_rounded, onTap: n.resetHead),
            ]);
          })),
          const SizedBox(height: 10),
          _ctrlSection('CHASSIS', Consumer(builder: (_, ref, __) {
            final c = ref.watch(chassisProvider);
            final n = ref.read(chassisProvider.notifier);
            return Column(children: [
              _DirectionIndicator(direction: c.direction, isMoving: c.isMoving),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Speed',
                    style: TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.w700)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: c.speed.clamp(0.3, 0.8),
                      min: 0.3,
                      max: 0.8,
                      activeColor: kOrange,
                      inactiveColor: _border,
                      onChanged: (v) => n.setSpeed(v),
                    ),
                  ),
                ),
                Text('${(c.speed * 10).toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.w700)),
              ]),
            ]);
          })),
          const SizedBox(height: 10),
          _ctrlSection('ARMS', Consumer(builder: (_, ref, __) {
            final a = ref.watch(armProvider);
            final n = ref.read(armProvider.notifier);
            return Row(children: [
              Expanded(child: _SmallBtn(a.isWaving ? '👋 Waving' : '👋 Wave', null,
                  onTap: a.isWaving ? n.stopWave : n.wave, highlighted: a.isWaving)),
              const SizedBox(width: 6),
              Expanded(child: _SmallBtn('⟲ Reset', null, onTap: n.resetArms)),
            ]);
          })),
          const SizedBox(height: 14),
          Consumer(builder: (_, ref, __) {
            final c = ref.watch(chassisProvider);
            final n = ref.read(chassisProvider.notifier);
            return GestureDetector(
              onTap: n.emergencyStop,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: c.isMoving ? const Color(0x33EF4444) : const Color(0x14EF4444),
                  border: Border.all(
                      color: c.isMoving ? _red : const Color(0x59EF4444), width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.emergency_rounded, color: _red, size: 18),
                  const SizedBox(width: 8),
                  const Text('Emergency Stop',
                      style: TextStyle(
                          color: _red, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0x33EF4444), borderRadius: BorderRadius.circular(4)),
                    child: Text(c.isMoving ? 'MOVING' : 'IDLE',
                        style: const TextStyle(
                            color: _red, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _ctrlSection(String label, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surf2,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
        ),
        child,
      ]),
    );
  }
}

// ── Per-frame repaint signal (painter only) ──────────────────────────────────
class _FaceRepaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

// ── Nav item ──────────────────────────────────────────────────────────────────
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
    final color = active ? kOrange : Colors.white60;
    final item = Container(
      decoration: BoxDecoration(
        color: active ? const Color(0x26FF6B35) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(color: active ? kOrange : Colors.transparent, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 11),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
        ),
        if (soon)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
                border: Border.all(color: _border), borderRadius: BorderRadius.circular(4)),
            child: const Text('SOON',
                style: TextStyle(
                    color: Colors.white38, fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
      ]),
    );
    if (soon) return Opacity(opacity: 0.38, child: IgnorePointer(child: item));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: item),
      ),
    );
  }
}

// ── Small control button ──────────────────────────────────────────────────────
class _SmallBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool highlighted;
  const _SmallBtn(this.label, this.icon, {required this.onTap, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    final c = highlighted ? kOrange : Colors.white70;
    return Material(
      color: highlighted ? const Color(0x26FF6B35) : _surf,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: highlighted ? kOrange : _border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 5)],
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
          ]),
        ),
      ),
    );
  }
}

// ── Head position indicator (reimpl — control_screen's is private) ────────────
class _HeadPositionIndicator extends StatelessWidget {
  final int headLR;
  final int headUD;
  const _HeadPositionIndicator({required this.headLR, required this.headUD});

  @override
  Widget build(BuildContext context) {
    const width = 140.0;
    const height = 80.0;
    final dotX = (headLR / 100) * width;
    final dotY = ((100 - headUD) / 100) * height;
    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Stack(children: [
          Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 28, height: 1, color: _border),
              Container(width: 1, height: 28, color: _border),
            ]),
          ),
          Positioned(
            left: dotX - 6,
            top: dotY - 6,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: kOrange,
                boxShadow: [BoxShadow(color: kOrange, blurRadius: 4)],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Direction indicator (reimpl — control_screen's is private) ────────────────
class _DirectionIndicator extends StatelessWidget {
  final String direction;
  final bool isMoving;
  const _DirectionIndicator({required this.direction, required this.isMoving});

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    final color = isMoving ? kOrange : const Color(0xFF6B7280);
    final symbol = switch (direction) {
      'forward' => '↑',
      'back' => '↓',
      'left' => '←',
      'right' => '→',
      _ => '●',
    };
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _bg,
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: color),
            child: Text(symbol),
          ),
        ),
      ),
    );
  }
}
