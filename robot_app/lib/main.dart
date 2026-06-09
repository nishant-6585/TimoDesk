import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ── Channels ──────────────────────────────────────────────────────────────────

const _methodCh = MethodChannel('com.timoDesk/camera_stream');
const _eventCh  = EventChannel('com.timoDesk/camera_events');
const _headMethodCh = MethodChannel('com.timoDesk/head_control');
const _headEventCh  = EventChannel('com.timoDesk/head_events');
const _chassisMethodCh = MethodChannel('com.timoDesk/chassis_control');
const _chassisEventCh  = EventChannel('com.timoDesk/chassis_events');
const _armMethodCh = MethodChannel('com.timoDesk/arm_control');
const _armEventCh  = EventChannel('com.timoDesk/arm_events');
const _batteryMethodCh = MethodChannel('com.timoDesk/battery');

// ── MJPEG state ───────────────────────────────────────────────────────────────

class StreamState {
  final bool   isStreaming;
  final double fps;
  final int    clients;
  final String ip;
  final int    port;
  final String sdkStatus;
  final String flavor;

  const StreamState({
    this.isStreaming = false,
    this.fps         = 0,
    this.clients     = 0,
    this.ip          = '—',
    this.port        = 8080,
    this.sdkStatus   = 'connecting',
    this.flavor      = 'unknown',
  });

  StreamState copyWith({
    bool? isStreaming, double? fps, int? clients,
    String? ip, int? port, String? sdkStatus, String? flavor,
  }) => StreamState(
    isStreaming: isStreaming ?? this.isStreaming,
    fps:         fps         ?? this.fps,
    clients:     clients     ?? this.clients,
    ip:          ip          ?? this.ip,
    port:        port        ?? this.port,
    sdkStatus:   sdkStatus   ?? this.sdkStatus,
    flavor:      flavor      ?? this.flavor,
  );

  String get streamUrl => 'http://$ip:$port/stream';
}

// ── Head control state ─────────────────────────────────────────────────────────

class HeadState {
  final bool   isRunning;
  final int    clientCount;
  final int    headLR;
  final int    headUD;

  const HeadState({
    this.isRunning = false,
    this.clientCount = 0,
    this.headLR = 50,
    this.headUD = 50,
  });

  HeadState copyWith({
    bool? isRunning,
    int? clientCount,
    int? headLR,
    int? headUD,
  }) => HeadState(
    isRunning: isRunning ?? this.isRunning,
    clientCount: clientCount ?? this.clientCount,
    headLR: headLR ?? this.headLR,
    headUD: headUD ?? this.headUD,
  );
}

// ── Chassis control state ──────────────────────────────────────────────────────

class ChassisState {
  final bool   isRunning;
  final int    clientCount;
  final bool   isMoving;
  final double speed;
  final String direction;

  const ChassisState({
    this.isRunning = false,
    this.clientCount = 0,
    this.isMoving = false,
    this.speed = 0.5,
    this.direction = 'none',
  });

  ChassisState copyWith({
    bool? isRunning,
    int? clientCount,
    bool? isMoving,
    double? speed,
    String? direction,
  }) => ChassisState(
    isRunning: isRunning ?? this.isRunning,
    clientCount: clientCount ?? this.clientCount,
    isMoving: isMoving ?? this.isMoving,
    speed: speed ?? this.speed,
    direction: direction ?? this.direction,
  );
}

// ── Arm control state ──────────────────────────────────────────────────────

class ArmState {
  final bool isRunning;
  final int  clientCount;
  final int  leftArm;
  final int  rightArm;
  final bool isWaving;

  const ArmState({
    this.isRunning = false,
    this.clientCount = 0,
    this.leftArm = 50,
    this.rightArm = 50,
    this.isWaving = false,
  });

  ArmState copyWith({
    bool? isRunning,
    int? clientCount,
    int? leftArm,
    int? rightArm,
    bool? isWaving,
  }) => ArmState(
    isRunning: isRunning ?? this.isRunning,
    clientCount: clientCount ?? this.clientCount,
    leftArm: leftArm ?? this.leftArm,
    rightArm: rightArm ?? this.rightArm,
    isWaving: isWaving ?? this.isWaving,
  );
}

// ── Battery state ──────────────────────────────────────────────────────────────

class BatteryState {
  final int percentage;
  final bool isCharging;
  final DateTime? lastUpdate;

  const BatteryState({
    this.percentage = 85,
    this.isCharging = false,
    this.lastUpdate,
  });

  BatteryState copyWith({
    int? percentage,
    bool? isCharging,
    DateTime? lastUpdate,
  }) => BatteryState(
    percentage: percentage ?? this.percentage,
    isCharging: isCharging ?? this.isCharging,
    lastUpdate: lastUpdate ?? this.lastUpdate,
  );
}

// ── Battery notifier ───────────────────────────────────────────────────────────

class BatteryNotifier extends StateNotifier<BatteryState> {
  BatteryNotifier() : super(const BatteryState()) {
    _startBatteryMonitoring();
  }

  Timer? _batteryTimer;

  void _startBatteryMonitoring() {
    _batteryTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      await _updateBattery();
    });
    _updateBattery();
  }

  Future<void> _updateBattery() async {
    try {
      final res = await _batteryMethodCh.invokeMethod<Map>('getBatteryLevel');
      if (res != null) {
        final percentage = (res['level'] as num?)?.toInt() ?? 85;
        final isCharging = res['isCharging'] as bool? ?? false;
        state = state.copyWith(
          percentage: percentage,
          isCharging: isCharging,
          lastUpdate: DateTime.now(),
        );
        _broadcastBatteryUpdate(percentage);
      }
    } on PlatformException catch (e) {
      debugPrint('[BatteryNotifier] Error getting battery: $e');
    }
  }

  void _broadcastBatteryUpdate(int percentage) {
    try {
      _methodCh.invokeMethod('broadcastBatteryUpdate', {
        'type': 'battery_update',
        'payload': {'level': percentage},
      });
    } on PlatformException catch (e) {
      debugPrint('[BatteryNotifier] Broadcast error: $e');
    }
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    super.dispose();
  }
}

final batteryProvider =
    StateNotifierProvider<BatteryNotifier, BatteryState>((ref) => BatteryNotifier())
        .keepAlive();

class StreamNotifier extends StateNotifier<StreamState> {
  StreamNotifier() : super(const StreamState()) {
    _sub = _eventCh.receiveBroadcastStream().listen(_onEvent);
    _loadConfig();
  }

  StreamSubscription? _sub;

  Future<void> _loadConfig() async {
    try {
      final res = await _methodCh.invokeMethod<Map>('getConfig');
      if (res != null) state = state.copyWith(flavor: res['flavor'] as String?);
    } on PlatformException catch (_) {}
  }

  void _onEvent(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    state = state.copyWith(
      isStreaming: m['isStreaming']      as bool?,
      fps:         (m['fps']             as num?)?.toDouble(),
      clients:     m['connectedClients'] as int?,
      ip:          m['ipAddress']        as String?,
      sdkStatus:   m['sdkStatus']        as String?,
    );
  }

  Future<void> startStream() async {
    try {
      final res = await _methodCh.invokeMethod<Map>('startStream');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('startStream: $e'); }
  }

  Future<void> stopStream() async {
    try {
      final res = await _methodCh.invokeMethod<Map>('stopStream');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('stopStream: $e'); }
  }

  void _applyStatus(Map<dynamic, dynamic> m) {
    state = state.copyWith(
      isStreaming: m['isStreaming']      as bool?,
      fps:         (m['fps']             as num?)?.toDouble(),
      clients:     m['connectedClients'] as int?,
      ip:          m['ipAddress']        as String?,
      port:        m['port']             as int?,
      sdkStatus:   m['sdkStatus']        as String?,
    );
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}

final streamProvider =
    StateNotifierProvider<StreamNotifier, StreamState>((ref) => StreamNotifier());

// ── Head control notifier ──────────────────────────────────────────────────────

class HeadNotifier extends StateNotifier<HeadState> {
  HeadNotifier() : super(const HeadState()) {
    _sub = _headEventCh.receiveBroadcastStream().listen(_onEvent);
  }

  StreamSubscription? _sub;

  void _onEvent(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      headLR: m['headLR'] as int?,
      headUD: m['headUD'] as int?,
    );
  }

  Future<void> startHeadControl() async {
    try {
      final res = await _headMethodCh.invokeMethod<Map>('startHeadControl');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('startHeadControl: $e'); }
  }

  Future<void> stopHeadControl() async {
    try {
      final res = await _headMethodCh.invokeMethod<Map>('stopHeadControl');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('stopHeadControl: $e'); }
  }

  Future<void> resetHead() async {
    try {
      final res = await _headMethodCh.invokeMethod<Map>('resetHead');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('resetHead: $e'); }
  }

  void _applyStatus(Map<dynamic, dynamic> m) {
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      headLR: m['headLR'] as int?,
      headUD: m['headUD'] as int?,
    );
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}

final headProvider =
    StateNotifierProvider<HeadNotifier, HeadState>((ref) => HeadNotifier());

// ── Chassis control notifier ───────────────────────────────────────────────────

class ChassisNotifier extends StateNotifier<ChassisState> {
  ChassisNotifier() : super(const ChassisState()) {
    _sub = _chassisEventCh.receiveBroadcastStream().listen(_onEvent);
  }

  StreamSubscription? _sub;

  void _onEvent(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      isMoving: m['isMoving'] as bool?,
      speed: (m['speed'] as num?)?.toDouble(),
      direction: m['direction'] as String?,
    );
  }

  Future<void> startChassisControl() async {
    try {
      final res = await _chassisMethodCh.invokeMethod<Map>('startChassisControl');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('startChassisControl: $e'); }
  }

  Future<void> stopChassisControl() async {
    try {
      final res = await _chassisMethodCh.invokeMethod<Map>('stopChassisControl');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('stopChassisControl: $e'); }
  }

  Future<void> emergencyStop() async {
    try {
      final res = await _chassisMethodCh.invokeMethod<Map>('emergencyStop');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('emergencyStop: $e'); }
  }

  Future<void> setSpeed(double speed) async {
    try {
      final res = await _chassisMethodCh.invokeMethod<Map>('setSpeed', {'speed': speed});
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('setSpeed: $e'); }
  }

  void _applyStatus(Map<dynamic, dynamic> m) {
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      isMoving: m['isMoving'] as bool?,
      speed: (m['speed'] as num?)?.toDouble(),
      direction: m['direction'] as String?,
    );
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}

final chassisProvider =
    StateNotifierProvider<ChassisNotifier, ChassisState>((ref) => ChassisNotifier());

// ── Arm control notifier ───────────────────────────────────────────────────────

class ArmNotifier extends StateNotifier<ArmState> {
  ArmNotifier() : super(const ArmState()) {
    _sub = _armEventCh.receiveBroadcastStream().listen(_onEvent);
  }

  StreamSubscription? _sub;

  void _onEvent(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      leftArm: m['leftArm'] as int?,
      rightArm: m['rightArm'] as int?,
      isWaving: m['isWaving'] as bool?,
    );
  }

  Future<void> startArmControl() async {
    try {
      final res = await _armMethodCh.invokeMethod<Map>('startArmControl');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('startArmControl: $e'); }
  }

  Future<void> stopArmControl() async {
    try {
      final res = await _armMethodCh.invokeMethod<Map>('stopArmControl');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('stopArmControl: $e'); }
  }

  Future<void> resetArms() async {
    try {
      final res = await _armMethodCh.invokeMethod<Map>('resetArms');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('resetArms: $e'); }
  }

  Future<void> wave() async {
    try {
      final res = await _armMethodCh.invokeMethod<Map>('wave');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('wave: $e'); }
  }

  Future<void> stopWave() async {
    try {
      final res = await _armMethodCh.invokeMethod<Map>('stopWave');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('stopWave: $e'); }
  }

  void _applyStatus(Map<dynamic, dynamic> m) {
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      leftArm: m['leftArm'] as int?,
      rightArm: m['rightArm'] as int?,
      isWaving: m['isWaving'] as bool?,
    );
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}

final armProvider =
    StateNotifierProvider<ArmNotifier, ArmState>((ref) => ArmNotifier());

// ── App ───────────────────────────────────────────────────────────────────────

void main() => runApp(const ProviderScope(child: _App()));

const _orange = Color(0xFFFF6B35);

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TimoDesk — Camera Stream',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _orange, brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        cardColor: const Color(0xFF1A1A1A),
      ),
      home: const _StreamScreen(),
    );
  }
}

// ── Main screen ───────────────────────────────────────────────────────────────

class _StreamScreen extends ConsumerWidget {
  const _StreamScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mjpeg   = ref.watch(streamProvider);
    final mNotifier = ref.read(streamProvider.notifier);
    final head = ref.watch(headProvider);
    final hNotifier = ref.read(headProvider.notifier);
    final chassis = ref.watch(chassisProvider);
    final cNotifier = ref.read(chassisProvider.notifier);
    final arm = ref.watch(armProvider);
    final aNotifier = ref.read(armProvider.notifier);

    // Auto-start head, chassis & arm control when camera starts
    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr && !head.isRunning) {
        hNotifier.startHeadControl();
      }
      if (curr && !chassis.isRunning) {
        cNotifier.startChassisControl();
      }
      if (curr && !arm.isRunning) {
        aNotifier.startArmControl();
      }
    });

    final flavorLabel = switch (mjpeg.flavor) {
      'robot'  => 'Robot mode',
      'remote' => 'Remote mode',
      _        => '',
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('TimoDesk — Camera Stream',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (flavorLabel.isNotEmpty)
            Text(flavorLabel,
                style: const TextStyle(fontSize: 11, color: _orange, letterSpacing: 0.8)),
        ]),
        backgroundColor: const Color(0xFF1A1A1A),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── MJPEG section ──────────────────────────────────────────────
            _SectionLabel('MJPEG STREAM'),
            const SizedBox(height: 8),
            _StatusCard(state: mjpeg),
            const SizedBox(height: 12),
            _StreamButton(state: mjpeg, notifier: mNotifier),
            if (mjpeg.isStreaming) ...[
              const SizedBox(height: 12),
              _QrCard(state: mjpeg),
            ],
            // ── Head control section ────────────────────────────────────────
            const SizedBox(height: 28),
            _SectionLabel('HEAD CONTROL'),
            const SizedBox(height: 8),
            _HeadControlCard(state: head, notifier: hNotifier, streamIp: mjpeg.ip),
            const SizedBox(height: 12),
            _HeadControlButton(state: head, notifier: hNotifier),
            const SizedBox(height: 12),
            _HeadResetButton(notifier: hNotifier),
            // ── Chassis control section ─────────────────────────────────────
            const SizedBox(height: 28),
            _SectionLabel('CHASSIS CONTROL'),
            const SizedBox(height: 8),
            _ChassisControlCard(state: chassis, notifier: cNotifier, streamIp: mjpeg.ip),
            const SizedBox(height: 12),
            _ChassisControlButton(state: chassis, notifier: cNotifier),
            const SizedBox(height: 12),
            _ChassisSpeedSlider(notifier: cNotifier, speed: chassis.speed),
            const SizedBox(height: 12),
            _ChassisEmergencyStopButton(notifier: cNotifier),
            const SizedBox(height: 28),
            _SectionLabel('ARM CONTROL'),
            const SizedBox(height: 8),
            _ArmControlCard(state: arm, notifier: aNotifier, streamIp: mjpeg.ip),
            const SizedBox(height: 12),
            _ArmControlButtons(notifier: aNotifier, state: arm),
            const SizedBox(height: 12),
            _ArmSliders(state: arm, notifier: aNotifier),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
        color: Colors.white38, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.bold),
  );
}

// ── MJPEG Status card ─────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final StreamState state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Dot(active: state.isStreaming, activeColor: Colors.greenAccent),
            const SizedBox(width: 8),
            Text(state.isStreaming ? 'LIVE' : 'STOPPED',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.4,
                    color: state.isStreaming ? Colors.greenAccent : Colors.redAccent)),
            const Spacer(),
            _SdkBadge(status: state.sdkStatus),
          ]),
          const Divider(height: 24),
          _Label('Stream URL'),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: state.streamUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied')));
            },
            child: Row(children: [
              Flexible(child: Text(state.streamUrl,
                  style: const TextStyle(color: _orange, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 14, color: _orange),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Label('FPS'),
              const SizedBox(height: 4),
              _FpsBadge(fps: state.fps),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Label('Clients'),
              const SizedBox(height: 4),
              Text('${state.clients}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ])),
          ]),
        ]),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  final bool  active;
  final Color activeColor;
  const _Dot({required this.active, required this.activeColor});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: 12, height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active ? activeColor : Colors.redAccent,
      boxShadow: active
          ? [BoxShadow(color: activeColor.withValues(alpha: 0.5), blurRadius: 8)]
          : null,
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 0.8));
}

class _FpsBadge extends StatelessWidget {
  final double fps;
  const _FpsBadge({required this.fps});
  @override
  Widget build(BuildContext context) {
    final color = fps > 20 ? Colors.greenAccent : fps > 10 ? Colors.yellowAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text('${fps.toStringAsFixed(1)} fps',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

class _SdkBadge extends StatelessWidget {
  final String status;
  const _SdkBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'connected'  => ('SDK CONNECTED',  Colors.greenAccent),
      'error'      => ('SDK ERROR',       Colors.redAccent),
      _            => ('SDK CONNECTING',  Colors.yellowAccent),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: color,
              boxShadow: status == 'connected'
                  ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5)]
                  : null)),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
    ]);
  }
}

class _StreamButton extends StatelessWidget {
  final StreamState    state;
  final StreamNotifier notifier;
  const _StreamButton({required this.state, required this.notifier});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: state.isStreaming ? notifier.stopStream : notifier.startStream,
    icon: Icon(state.isStreaming ? Icons.stop_circle_rounded : Icons.play_circle_rounded),
    label: Text(state.isStreaming ? 'STOP STREAM' : 'START STREAM',
        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
    style: FilledButton.styleFrom(
      backgroundColor: state.isStreaming ? Colors.redAccent : _orange,
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 15),
    ),
  );
}

class _QrCard extends StatelessWidget {
  final StreamState state;
  const _QrCard({required this.state});
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF1A1A1A),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const Text('Scan to view stream',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: QrImageView(data: state.streamUrl, size: 200, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 10),
        Text(state.streamUrl, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    ),
  );
}

// ── Head Control card ──────────────────────────────────────────────────────────

class _HeadControlCard extends StatelessWidget {
  final HeadState state;
  final HeadNotifier notifier;
  final String streamIp;
  const _HeadControlCard({
    required this.state,
    required this.notifier,
    required this.streamIp,
  });

  @override
  Widget build(BuildContext context) {
    final wsUrl = 'ws://$streamIp:8081';

    return Card(
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.wifi_rounded, size: 16, color: _orange),
            const SizedBox(width: 8),
            Text(state.isRunning ? 'ACTIVE' : 'STOPPED',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.4,
                    color: state.isRunning ? const Color(0xFF4ADE80) : const Color(0xFF6B7280))),
            const Spacer(),
            Text('${state.clientCount} client${state.clientCount == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          const Divider(height: 24),
          _Label('WebSocket URL'),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: wsUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('WebSocket URL copied')));
            },
            child: Row(children: [
              Flexible(child: Text(wsUrl,
                  style: const TextStyle(color: _orange, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 14, color: _orange),
            ]),
          ),
          const SizedBox(height: 20),
          _Label('Head Position'),
          const SizedBox(height: 12),
          _HeadPositionIndicator(headLR: state.headLR, headUD: state.headUD),
        ]),
      ),
    );
  }
}

class _HeadPositionIndicator extends StatelessWidget {
  final int headLR;
  final int headUD;
  const _HeadPositionIndicator({required this.headLR, required this.headUD});

  @override
  Widget build(BuildContext context) {
    const width = 140.0;
    const height = 90.0;

    final dotX = (headLR / 100) * width;
    final dotY = ((100 - headUD) / 100) * height;

    return Center(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
        ),
        child: Stack(
          children: [
            // Crosshair
            Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 30, height: 1, color: const Color(0xFF2A2A2A)),
                const SizedBox(height: 0),
                Container(width: 1, height: 30, color: const Color(0xFF2A2A2A)),
              ]),
            ),
            // Dot
            Positioned(
              left: dotX - 6,
              top: dotY - 6,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _orange,
                  boxShadow: [BoxShadow(color: _orange, blurRadius: 4)],
                ),
              ),
            ),
            // Corner labels
            Positioned(
              left: 6, top: 6,
              child: const Text('L', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
            ),
            Positioned(
              right: 6, top: 6,
              child: const Text('R', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
            ),
            Positioned(
              left: width / 2 - 3, top: 4,
              child: const Text('U', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
            ),
            Positioned(
              left: width / 2 - 3, bottom: 4,
              child: const Text('D', style: TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeadControlButton extends StatelessWidget {
  final HeadState state;
  final HeadNotifier notifier;
  const _HeadControlButton({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: state.isRunning ? notifier.stopHeadControl : notifier.startHeadControl,
    icon: Icon(state.isRunning ? Icons.stop_circle_rounded : Icons.play_circle_rounded),
    label: Text(state.isRunning ? 'STOP HEAD CONTROL' : 'START HEAD CONTROL',
        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
    style: FilledButton.styleFrom(
      backgroundColor: state.isRunning ? Colors.redAccent : _orange,
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 15),
    ),
  );
}

class _HeadResetButton extends StatelessWidget {
  final HeadNotifier notifier;
  const _HeadResetButton({required this.notifier});

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: notifier.resetHead,
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: _orange, width: 1.5),
      padding: const EdgeInsets.symmetric(vertical: 12),
    ),
    child: const Text('RESET CENTER',
        style: TextStyle(color: _orange, fontWeight: FontWeight.bold, letterSpacing: 1)),
  );
}

// ── Chassis Control card ───────────────────────────────────────────────────────

class _ChassisControlCard extends StatelessWidget {
  final ChassisState state;
  final ChassisNotifier notifier;
  final String streamIp;
  const _ChassisControlCard({
    required this.state,
    required this.notifier,
    required this.streamIp,
  });

  @override
  Widget build(BuildContext context) {
    final wsUrl = 'ws://$streamIp:8082';

    return Card(
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.directions_car_rounded, size: 16, color: _orange),
            const SizedBox(width: 8),
            Text(state.isRunning ? 'ACTIVE' : 'STOPPED',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.4,
                    color: state.isRunning ? const Color(0xFF4ADE80) : const Color(0xFF6B7280))),
            const Spacer(),
            Text('${state.clientCount} client${state.clientCount == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          const Divider(height: 24),
          _Label('WebSocket URL'),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: wsUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('WebSocket URL copied')));
            },
            child: Row(children: [
              Flexible(child: Text(wsUrl,
                  style: const TextStyle(color: _orange, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 14, color: _orange),
            ]),
          ),
          const SizedBox(height: 20),
          _Label('Direction Indicator'),
          const SizedBox(height: 12),
          _DirectionIndicator(direction: state.direction, isMoving: state.isMoving),
        ]),
      ),
    );
  }
}

class _DirectionIndicator extends StatelessWidget {
  final String direction;
  final bool isMoving;
  const _DirectionIndicator({required this.direction, required this.isMoving});

  @override
  Widget build(BuildContext context) {
    const size = 80.0;
    final color = isMoving ? _orange : const Color(0xFF6B7280);

    String getArrowSymbol() {
      return switch (direction) {
        'forward' => '↑',
        'back' => '↓',
        'left' => '←',
        'right' => '→',
        _ => '●',
      };
    }

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('N', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
            Text('S', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('W', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
            Text('E', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
          ]),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
            child: Text(getArrowSymbol()),
          ),
        ]),
      ),
    );
  }
}

class _ChassisControlButton extends StatelessWidget {
  final ChassisState state;
  final ChassisNotifier notifier;
  const _ChassisControlButton({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: state.isRunning ? notifier.stopChassisControl : notifier.startChassisControl,
    icon: Icon(state.isRunning ? Icons.stop_circle_rounded : Icons.play_circle_rounded),
    label: Text(state.isRunning ? 'STOP CHASSIS' : 'START CHASSIS',
        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
    style: FilledButton.styleFrom(
      backgroundColor: state.isRunning ? Colors.redAccent : _orange,
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 15),
    ),
  );
}

class _ChassisSpeedSlider extends StatelessWidget {
  final ChassisNotifier notifier;
  final double speed;
  const _ChassisSpeedSlider({required this.notifier, required this.speed});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _Label('Speed Control'),
        Text('${(speed * 10).toStringAsFixed(0)}%',
            style: const TextStyle(color: _orange, fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      Slider(
        value: speed,
        min: 0.3,
        max: 0.8,
        divisions: 10,
        activeColor: _orange,
        inactiveColor: const Color(0xFF2A2A2A),
        onChanged: (v) => notifier.setSpeed(v),
      ),
    ],
  );
}

class _ChassisEmergencyStopButton extends StatelessWidget {
  final ChassisNotifier notifier;
  const _ChassisEmergencyStopButton({required this.notifier});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: notifier.emergencyStop,
    icon: const Icon(Icons.emergency_rounded),
    label: const Text('EMERGENCY STOP',
        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
    style: FilledButton.styleFrom(
      backgroundColor: Colors.redAccent,
      padding: const EdgeInsets.symmetric(vertical: 14),
      textStyle: const TextStyle(fontSize: 15),
    ),
  );
}

// ── Arm Control Card ──────────────────────────────────────────────────────────

class _ArmControlCard extends StatelessWidget {
  final ArmState state;
  final ArmNotifier notifier;
  final String streamIp;

  const _ArmControlCard({
    required this.state,
    required this.notifier,
    required this.streamIp,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF1A1A1A),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.pan_tool, color: _orange, size: 20),
            const SizedBox(width: 8),
            const Text('Arm Control', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: state.isRunning ? const Color(0xFF4ADE80) : const Color(0xFF6B7280),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              state.isRunning ? 'ACTIVE' : 'STOPPED',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.link, size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: 'ws://$streamIp:8083')),
              child: Text(
                'ws://$streamIp:8083',
                style: const TextStyle(
                  fontSize: 12,
                  color: _orange,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Clients: ${state.clientCount}', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ]),
    ),
  );
}

class _ArmControlButtons extends StatelessWidget {
  final ArmNotifier notifier;
  final ArmState state;

  const _ArmControlButtons({required this.notifier, required this.state});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(
      child: FilledButton(
        onPressed: state.isRunning ? notifier.stopArmControl : notifier.startArmControl,
        style: FilledButton.styleFrom(
          backgroundColor: state.isRunning ? Colors.grey : _orange,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(state.isRunning ? 'STOP' : 'START',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    ),
  ]);
}

class _ArmSliders extends StatelessWidget {
  final ArmState state;
  final ArmNotifier notifier;

  const _ArmSliders({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _Label('Arm Positions'),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(
        child: Column(children: [
          Text('L Arm: ${state.leftArm}', style: const TextStyle(fontSize: 12, color: _orange, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Slider(
            value: state.leftArm.toDouble(),
            min: 0,
            max: 100,
            divisions: 10,
            activeColor: _orange,
            inactiveColor: const Color(0xFF2A2A2A),
            onChanged: (_) {},
          ),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(children: [
          Text('R Arm: ${state.rightArm}', style: const TextStyle(fontSize: 12, color: _orange, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Slider(
            value: state.rightArm.toDouble(),
            min: 0,
            max: 100,
            divisions: 10,
            activeColor: _orange,
            inactiveColor: const Color(0xFF2A2A2A),
            onChanged: (_) {},
          ),
        ]),
      ),
    ]),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(
        child: FilledButton(
          onPressed: state.isWaving ? notifier.stopWave : notifier.wave,
          style: FilledButton.styleFrom(
            backgroundColor: state.isWaving ? Colors.amber : const Color(0xFF1A1A1A),
            side: const BorderSide(color: _orange, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(state.isWaving ? '👋 WAVING' : '👋 WAVE',
              style: const TextStyle(fontWeight: FontWeight.bold, color: _orange)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton(
          onPressed: notifier.resetArms,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            side: const BorderSide(color: _orange, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: const Text('⟲ RESET',
              style: TextStyle(fontWeight: FontWeight.bold, color: _orange)),
        ),
      ),
    ]),
  ]);
}
