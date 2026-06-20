import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';

/// A recognized staff member, from spine's Milestone D recognizer.
class FaceDetectedEvent {
  final String name;
  final String staffId;
  final double? distance;
  const FaceDetectedEvent(this.name, this.staffId, this.distance);
}

/// robot_app's client to the spine WebSocket (ws://<spine>:4000).
///
/// robot_app is otherwise a SERVER to spine (MJPEG :8080, battery :8090, control
/// receivers :8081-3) — this is the FIRST client connection. It authenticates with
/// the kiosk credential (RobotConfig.authToken → spine KIOSK_TOKEN, or the dev
/// bypass token), then surfaces two signals to the face:
///   • faceDetected — staff identity (greeting-by-name). Authoritative.
///   • personDetected — CSJBot Phase 1A boolean presence (coarse fallback).
///
/// Uses dart:io WebSocket (no new dependency). Reconnects with a fixed backoff.
class SpineClient {
  SpineClient({this.reconnectDelay = const Duration(seconds: 3)});

  final Duration reconnectDelay;

  WebSocket? _ws;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _authed = false;

  final _faceCtrl = StreamController<FaceDetectedEvent>.broadcast();
  final _presenceCtrl = StreamController<bool>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();

  /// Recognized staff (matched only — `unknown` is filtered out here).
  Stream<FaceDetectedEvent> get faceDetected => _faceCtrl.stream;

  /// CSJBot presence boolean from robot_status updates.
  Stream<bool> get personDetected => _presenceCtrl.stream;

  /// Connection/auth state (true once authenticated).
  Stream<bool> get connected => _connCtrl.stream;

  bool get isConnected => _authed;

  void start() => _connect();

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final ws = await WebSocket.connect(RobotConfig.spineWsUrl)
          .timeout(const Duration(seconds: 8));
      if (_disposed) {
        await ws.close();
        return;
      }
      _ws = ws;
      _authed = false;
      // Auth MUST be the first message (spine has an auth timeout).
      ws.add(jsonEncode({'type': 'auth', 'token': RobotConfig.authToken}));
      _sub = ws.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'authenticated':
          _authed = true;
          if (!_connCtrl.isClosed) _connCtrl.add(true);
          return;
        case 'error':
          // Auth failed (bad/expired kiosk token). Socket will close → reconnect.
          return;
        case 'event':
          if (msg['event'] == 'face_detected') _handleFaceDetected(msg);
          return;
        case 'robot_status':
          final status = msg['status'];
          if (status is Map && status['personDetected'] is bool) {
            if (!_presenceCtrl.isClosed) {
              _presenceCtrl.add(status['personDetected'] as bool);
            }
          }
          return;
      }
    } catch (_) {
      // ignore malformed frames
    }
  }

  void _handleFaceDetected(Map<String, dynamic> msg) {
    // Shape: { event:'face_detected', eventPayload:{ payload:{staff_id,name,distance} } }
    final ep = msg['eventPayload'];
    if (ep is! Map) return;
    final payload = ep['payload'];
    if (payload is! Map) return;
    final name = payload['name'] as String?;
    final staffId = payload['staff_id'] as String?;
    if (name == null || name == 'unknown' || staffId == null) return; // matched only
    if (!_faceCtrl.isClosed) {
      _faceCtrl.add(
        FaceDetectedEvent(name, staffId, (payload['distance'] as num?)?.toDouble()),
      );
    }
  }

  void _onClosed() {
    _authed = false;
    if (!_connCtrl.isClosed) _connCtrl.add(false);
    _sub?.cancel();
    _sub = null;
    _ws = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, _connect);
  }

  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _ws?.close();
    _ws = null;
    await _faceCtrl.close();
    await _presenceCtrl.close();
    await _connCtrl.close();
  }
}
