// Robot app data layer: native channels + Riverpod providers (camera/head/chassis/
// arm/battery). Extracted verbatim from main.dart — unchanged behavior.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'battery_service.dart';

const kOrange = Color(0xFFFF6B35);

const _methodCh = MethodChannel('com.mikee/camera_stream');
const _eventCh  = EventChannel('com.mikee/camera_events');
const _batteryEventCh = EventChannel('com.mikee/battery_events');
const _headMethodCh = MethodChannel('com.mikee/head_control');
const _headEventCh  = EventChannel('com.mikee/head_events');
const _chassisMethodCh = MethodChannel('com.mikee/chassis_control');
const _chassisEventCh  = EventChannel('com.mikee/chassis_events');
const _armMethodCh = MethodChannel('com.mikee/arm_control');
const _armEventCh  = EventChannel('com.mikee/arm_events');

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
  final bool   isNaviReady; // SLAM map loaded + robot localized → go-to enabled

  const ChassisState({
    this.isRunning = false,
    this.clientCount = 0,
    this.isMoving = false,
    this.speed = 0.5,
    this.direction = 'none',
    this.isNaviReady = false,
  });

  ChassisState copyWith({
    bool? isRunning,
    int? clientCount,
    bool? isMoving,
    double? speed,
    String? direction,
    bool? isNaviReady,
  }) => ChassisState(
    isRunning: isRunning ?? this.isRunning,
    clientCount: clientCount ?? this.clientCount,
    isMoving: isMoving ?? this.isMoving,
    speed: speed ?? this.speed,
    direction: direction ?? this.direction,
    isNaviReady: isNaviReady ?? this.isNaviReady,
  );
}

/// A navigation lifecycle event forwarded from the native chassis plugin
/// (OnNaviListener). [kind] is 'move_result' | 'cancel_result' |
/// 'message_send_result' | 'go_home'; [data] is the raw SDK JSON payload.
class NaviEvent {
  final String kind;
  final String data;
  const NaviEvent(this.kind, this.data);

  /// Heuristic: does this event signal the robot reached its destination?
  /// The CSJBot `moveResult` payload shape is not fully documented — match a few
  /// likely arrival markers. HARDWARE TODO: confirm the exact arrival JSON on the
  /// real robot and tighten this (see device checklist).
  bool get isArrival {
    if (kind != 'move_result') return false;
    final d = data.toLowerCase();
    return d.contains('arriv') ||
        d.contains('"status":1') ||
        d.contains('"result":1') ||
        d.contains('complete') ||
        d.contains('success');
  }
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

  /// Discrete head nudge from the dashboard d-pad: 'up' | 'down' | 'left' | 'right'.
  Future<void> nudge(String dir) async {
    try {
      final res = await _headMethodCh.invokeMethod<Map>('nudgeHead', {'dir': dir});
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('nudgeHead: $e'); }
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

  // Navi lifecycle events (arrival/cancel/etc.) from the native OnNaviListener.
  // Broadcast so the nav-points provider and any screen can listen independently.
  final StreamController<NaviEvent> _naviEvents = StreamController<NaviEvent>.broadcast();
  Stream<NaviEvent> get naviEvents => _naviEvents.stream;

  void _onEvent(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    // Navi lifecycle events are tagged type:"navi" — route them to the stream
    // rather than treating them as a status update.
    if (m['type'] == 'navi') {
      _naviEvents.add(NaviEvent(
        (m['naviEvent'] as String?) ?? 'unknown',
        (m['data'] as String?) ?? '{}',
      ));
      return;
    }
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      isMoving: m['isMoving'] as bool?,
      speed: (m['speed'] as num?)?.toDouble(),
      direction: m['direction'] as String?,
      isNaviReady: m['isNaviReady'] as bool?,
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

  /// Hold-to-drive from the dashboard d-pad: 'forward' | 'back' | 'left' | 'right'.
  /// Pair each [drive] with a [stopMove] on release.
  Future<void> drive(String dir) async {
    try {
      final res = await _chassisMethodCh.invokeMethod<Map>('drive', {'dir': dir});
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('drive: $e'); }
  }

  Future<void> stopMove() async {
    try {
      final res = await _chassisMethodCh.invokeMethod<Map>('stopMove');
      if (res != null) _applyStatus(res);
    } on PlatformException catch (e) { debugPrint('stopMove: $e'); }
  }

  // ── Navigation / SLAM (nav_points screen) ──────────────────────────────────
  // These map to the native chassis plugin methods added for the on-robot
  // Navigation Points feature. Chassis control must be started first
  // (startChassisControl) or the SDK calls no-op.

  /// Read the robot's current SLAM pose. Returns `{x, y, z, rotation}` (doubles)
  /// or `null` if the robot isn't localized / the SDK is absent / it timed out.
  Future<Map<String, double>?> getPosition() async {
    try {
      final res = await _chassisMethodCh.invokeMethod<Map>('getPosition');
      if (res == null) return null;
      double d(Object? v) => (v as num?)?.toDouble() ?? 0.0;
      return {
        'x': d(res['x']),
        'y': d(res['y']),
        'z': d(res['z']),
        'rotation': d(res['rotation']),
      };
    } on PlatformException catch (e) {
      debugPrint('getPosition: $e');
      return null;
    }
  }

  /// Navigate the robot to a saved SLAM pose. Returns true if the SDK accepted
  /// the request. Fire it after [startChassisControl].
  Future<bool> naviTo(Map<String, double> pose) async {
    try {
      final ok = await _chassisMethodCh.invokeMethod<bool>('navi', {
        'x': pose['x'] ?? 0.0,
        'y': pose['y'] ?? 0.0,
        'z': pose['z'] ?? 0.0,
        'rotation': pose['rotation'] ?? 0.0,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('navi: $e');
      return false;
    }
  }

  /// Cancel an in-flight navigation. Returns true if the SDK accepted it.
  Future<bool> cancelNavi() async {
    try {
      final ok = await _chassisMethodCh.invokeMethod<bool>('cancelNavi');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('cancelNavi: $e');
      return false;
    }
  }

  /// Return to the charging dock (SDK goHome; the dock self-aligns via IR).
  /// Same native path the admin's "Go Home" uses through spine.
  Future<bool> goHome() async {
    try {
      final ok = await _chassisMethodCh.invokeMethod<bool>('goHome');
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('goHome: $e');
      return false;
    }
  }

  void _applyStatus(Map<dynamic, dynamic> m) {
    state = state.copyWith(
      isRunning: m['isRunning'] as bool?,
      clientCount: m['clientCount'] as int?,
      isMoving: m['isMoving'] as bool?,
      speed: (m['speed'] as num?)?.toDouble(),
      direction: m['direction'] as String?,
      isNaviReady: m['isNaviReady'] as bool?,
    );
  }

  @override
  void dispose() { _sub?.cancel(); _naviEvents.close(); super.dispose(); }
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

// ── Battery state (real telemetry from the native BatteryPlugin) ────────────────

class BatteryState {
  final int? level; // null = unknown (no real reading yet)
  final int? charge; // SDK charge_status (>0 = on charger/charging)
  final String source; // 'sdk' | 'android' | 'unknown'
  const BatteryState({this.level, this.charge, this.source = 'unknown'});

  /// True when the robot is on the charging dock (charge_status > 0).
  bool get isCharging => charge != null && charge! > 0;
}

class BatteryNotifier extends StateNotifier<BatteryState> {
  BatteryNotifier() : super(const BatteryState()) {
    _sub = _batteryEventCh.receiveBroadcastStream().listen(_onEvent, onError: (e) {
      debugPrint('battery event error: $e');
    });
  }

  StreamSubscription? _sub;

  void _onEvent(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    final level = (m['battery'] as num?)?.toInt();
    final charge = (m['charge'] as num?)?.toInt();
    final charging = charge != null && charge > 0;
    state = BatteryState(
      level: (level != null && level >= 0) ? level : null,
      charge: charge,
      source: (m['source'] as String?) ?? 'unknown',
    );
    // Feed the :8090 HTTP server that spine polls — battery + charging state,
    // so the admin's ⚡ indicator reflects the dock. Push charging even when the
    // level is stale so a dock/undock still updates it.
    BatteryService.setBattery(
        (level != null && level >= 0) ? level : -1,
        charging: charging);
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }
}

final batteryProvider =
    StateNotifierProvider<BatteryNotifier, BatteryState>((ref) => BatteryNotifier());

// ── App ───────────────────────────────────────────────────────────────────────
