import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants.dart';
import '../../core/spine_base.dart';
import 'spine_state.dart';
import 'face_detection_provider.dart';
import 'navi_status_provider.dart';
import 'visitor_arrived_provider.dart';

class SpineService extends StateNotifier<SpineState> {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;
  late Ref _ref;
  String? _spineUrl;
  String? _jwt;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 30000; // 30 seconds max

  // Pending get_position request. The spine answers a {intent:'get_position'}
  // with a single {type:'position', position:{x,y,z,rotation}} message. We hold
  // the completer here and resolve it from _handleMessage. Only one round-trip
  // is in flight at a time (the UI captures one point at a time).
  Completer<Map<String, double>?>? _positionCompleter;
  Timer? _positionTimeoutTimer;

  SpineService(Ref ref) : super(SpineState.initial()) {
    _ref = ref;
    // Fix 2: Use Future.microtask() instead of fire-and-forget async
    // This ensures the event loop processes before we initialize
    Future.microtask(() => _init());
    // Fix 2: Keep this provider alive even when no widget is watching it
    ref.keepAlive();
  }

  Future<void> _init() async {
    try {
      // Get JWT from Supabase auth
      final session = Supabase.instance.client.auth.currentSession;
      _jwt = session?.accessToken ?? 'dev';

      // Spine runs on the machine serving this app — derive the host from the
      // browser URL so LAN-served builds work from any device.
      _spineUrl = spineWsUrl;

      print('[SpineService] ========================================');
      print('[SpineService] CONNECTING TO SPINE BROKER');
      print('[SpineService] Spine WebSocket: $_spineUrl');
      print('[SpineService] (Camera stream from robot: http://192.168.1.12:8080)');
      print('[SpineService] ========================================');

      await connect(_spineUrl!, _jwt!);
    } catch (e) {
      print('[SpineService] Init error: $e');
      _scheduleReconnect();
    }
  }

  Future<void> connect(String spineUrl, String jwt) async {
    try {
      _spineUrl = spineUrl;
      _jwt = jwt;

      print('[SpineService] Connecting to $spineUrl (attempt ${_reconnectAttempts + 1})');
      _channel = WebSocketChannel.connect(Uri.parse(spineUrl));

      // Add connection timeout - fail if not authenticated within 10 seconds
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (!state.connected) {
          print('[SpineService] Connection timeout - no auth response');
          _channel?.sink.close();
          _onDisconnect();
        }
      });

      // Send auth first
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': jwt}));

      // Listen for messages
      _channel!.stream.listen(
        (message) => _handleMessage(jsonDecode(message)),
        onDone: _onDisconnect,
        onError: (error) {
          print('[SpineService] WebSocket error: $error');
          _onDisconnect();
        },
      );

      state = state.copyWith(connected: true);
      _reconnectAttempts = 0; // Reset attempts on successful connection
      _connectionTimeoutTimer?.cancel();
      print('[SpineService] Connected successfully');
    } catch (e) {
      print('[SpineService] Connection error: $e');
      state = state.copyWith(connected: false);
      _scheduleReconnect();
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final msgType = msg['type'];
    print('[SpineService] ======== MESSAGE RECEIVED ========');
    print('[SpineService] Type: $msgType');
    print('[SpineService] Full payload: $msg');

    if (msgType == 'error') {
      // Log detailed error message
      final errorMsg = msg['message'];
      print('[SpineService] [ERROR] Message: $errorMsg');
      print('[SpineService] [ERROR] This error blocks the intent from executing');
    } else if (msgType == 'authenticated') {
      // Cancel connection timeout - we got authenticated
      print('[SpineService] [AUTH SUCCESS] Connected and authenticated');
      _connectionTimeoutTimer?.cancel();
      // Request initial status
      print('[SpineService] Requesting initial robot status...');
      sendIntent({'intent': 'get_status'});
    } else if (msgType == 'robot_status' && msg['status'] != null) {
      print('[SpineService] [STATUS UPDATE] Received robot status');
      final status = RobotStatus.fromJson(msg['status']);
      print('[SpineService] Status details: online=${status.online}, isMoving=${status.isMoving}, obstacleState=${status.obstacleState}');
      state = state.copyWith(status: status);
    } else if (msgType == 'stopped') {
      print('[SpineService] [STOP ACK] System stopped - updating UI state to stopped=true');
      state = state.copyWith(stopped: true);
    } else if (msgType == 'resumed') {
      print('[SpineService] [RESUME ACK] System resumed - updating UI state to stopped=false');
      state = state.copyWith(stopped: false);
    } else if (msgType == 'event') {
      final eventType = msg['event'] as String?;
      final eventPayload = msg['eventPayload'] as Map<String, dynamic>?;
      print('[SpineService] Robot event: $eventType payload: $eventPayload');

      if (eventType == 'face_detected' && eventPayload != null) {
        // The broker spreads RobotEvent.payload into eventPayload, so the fields
        // live under eventPayload['payload']. Fall back to flat for safety.
        final inner = (eventPayload['payload'] as Map<String, dynamic>?) ?? eventPayload;
        final name = (inner['name'] as String?) ?? 'unknown';
        final matched = name != 'unknown';
        final distance = (inner['distance'] as num?)?.toDouble() ?? 0.0;
        print('[SpineService] Face detection → $name (L2 $distance)');
        _ref.read(faceDetectionProvider.notifier).report(
              FaceDetection(
                name: name,
                staffId: inner['staff_id'] as String?,
                matched: matched,
                distance: distance,
                at: DateTime.now(),
              ),
            );
      }

      if (eventType == 'navi_event' && eventPayload != null) {
        // Same nesting as face_detected: fields live under eventPayload['payload'].
        final inner = (eventPayload['payload'] as Map<String, dynamic>?) ?? eventPayload;
        final naviEvent = inner['event'] as String?;
        print('[SpineService] Navi event: $naviEvent data: ${inner['data']}');
        if (naviEvent == 'cancel_result') {
          _ref.read(naviStatusProvider.notifier).clear();
        }
      }

      if (eventType == 'visitor_arrived' && eventPayload != null) {
        // Same nesting as face_detected: fields live under eventPayload['payload'].
        final inner = (eventPayload['payload'] as Map<String, dynamic>?) ?? eventPayload;
        final host = inner['host'] as Map<String, dynamic>?;
        _ref.read(visitorArrivedProvider.notifier).report(
              VisitorArrival(
                visitorName: (inner['visitor_name'] as String?) ?? 'A visitor',
                hostName: (host?['full_name'] as String?) ?? 'staff',
                channel: (inner['channel'] as String?) ?? 'none',
                at: DateTime.now(),
              ),
            );
      }
    } else if (msgType == 'position') {
      // Request-response reply to {intent:'get_position'}. Resolve the pending
      // completer with the captured pose, then clear it. Ignore stray/late
      // position messages when no request is in flight.
      print('[SpineService] [POSITION] Received pose reply');
      final pos = msg['position'] as Map<String, dynamic>?;
      final completer = _positionCompleter;
      _positionTimeoutTimer?.cancel();
      _positionCompleter = null;
      if (completer != null && !completer.isCompleted) {
        if (pos == null) {
          completer.complete(null);
        } else {
          completer.complete({
            'x': (pos['x'] as num?)?.toDouble() ?? 0.0,
            'y': (pos['y'] as num?)?.toDouble() ?? 0.0,
            'z': (pos['z'] as num?)?.toDouble() ?? 0.0,
            'rotation': (pos['rotation'] as num?)?.toDouble() ?? 0.0,
          });
        }
      }
    } else if (msgType == 'navi_state') {
      // Spine-owned cross-client navigation state: a Go To / Cancel from ANY
      // client (web admin or robot app) lands here on every client.
      final active = msg['active'] == true;
      print('[SpineService] [NAVI STATE] active=$active name=${msg['name']} cancelling=${msg['cancelling']}');
      final notifier = _ref.read(naviStatusProvider.notifier);
      if (active) {
        notifier.syncActive(
          (msg['name'] as String?) ?? 'saved point',
          cancelling: msg['cancelling'] == true,
          stalled: msg['stalled'] == true,
        );
      } else if (msg['arrived'] == true) {
        notifier.arrived((msg['name'] as String?) ?? 'saved point');
      } else {
        notifier.clear();
      }
    } else if (msgType == 'ack') {
      print('[SpineService] [ACK] Command acknowledged: ${msg['intent']}');
    }
    print('[SpineService] ======== END MESSAGE ========');
  }

  /// Request the robot's current SLAM pose. Sends {intent:'get_position'} and
  /// completes when the next {type:'position'} message arrives. Returns null on
  /// a ~7s timeout, if not connected, or if a disconnect aborts the request, so
  /// the caller never hangs.
  Future<Map<String, double>?> getPosition() async {
    if (!state.connected) {
      print('[SpineService] getPosition: not connected');
      return null;
    }
    // Abort any prior in-flight request (resolve it null) before starting a new one.
    _positionTimeoutTimer?.cancel();
    final prior = _positionCompleter;
    if (prior != null && !prior.isCompleted) prior.complete(null);

    final completer = Completer<Map<String, double>?>();
    _positionCompleter = completer;
    _positionTimeoutTimer = Timer(const Duration(seconds: 7), () {
      if (_positionCompleter == completer && !completer.isCompleted) {
        print('[SpineService] getPosition: timed out');
        _positionCompleter = null;
        completer.complete(null);
      }
    });

    sendIntent({'intent': 'get_position'});
    return completer.future;
  }

  /// Navigate the robot to a saved pose. Fire-and-forget — the spine acks
  /// {type:'ack', intent:'navi'}, then broadcasts navi_state to all clients.
  void naviTo(Map<String, dynamic> point, {String? name, String? arrivalText}) {
    sendIntent({
      'intent': 'navi',
      'point': point,
      if (name != null) 'name': name,
      if (arrivalText != null) 'arrivalText': arrivalText,
      'source': 'admin',
    });
  }

  /// Cancel an in-progress navigation. Spine acks {type:'ack', intent:'cancel_navi'}.
  void cancelNavi() {
    sendIntent({'intent': 'cancel_navi'});
  }

  void sendIntent(Map<String, dynamic> intent) {
    if (!state.connected) {
      print('[SpineService] !!!! NOT CONNECTED - DROPPING INTENT !!!!');
      print('[SpineService] Dropped intent: $intent');
      return;
    }
    print('[SpineService] ======== SENDING INTENT ========');
    print('[SpineService] Intent type: ${intent['intent']}');
    print('[SpineService] Full intent: $intent');
    print('[SpineService] Sending via WebSocket to Spine...');
    _channel?.sink.add(jsonEncode({'type': 'intent', 'intent': intent}));
    print('[SpineService] Intent sent, waiting for response...');
  }

  void _onDisconnect() {
    print('[SpineService] Disconnected');
    _connectionTimeoutTimer?.cancel();
    // Abort any pending get_position so the UI doesn't hang waiting for a reply
    // that will never come on a dead socket.
    _positionTimeoutTimer?.cancel();
    final pending = _positionCompleter;
    _positionCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    state = state.copyWith(connected: false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    // Exponential backoff: 3s, 6s, 12s, 24s, 30s max
    final baseDelayMs = spineReconnectDelay.inMilliseconds;
    final exponentialDelayMs = baseDelayMs * (1 << _reconnectAttempts); // 2^attempts
    final delayMs = exponentialDelayMs.clamp(baseDelayMs, _maxReconnectDelay);
    final delay = Duration(milliseconds: delayMs);

    _reconnectAttempts++;

    print('[SpineService] Scheduling reconnect in ${(delayMs / 1000).toStringAsFixed(1)}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, () {
      // Re-fetch JWT in case it expired
      final session = Supabase.instance.client.auth.currentSession;
      final newJwt = session?.accessToken ?? 'dev';
      final url = _spineUrl ?? spineWsUrl;
      connect(url, newJwt);
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _positionTimeoutTimer?.cancel();
    final pending = _positionCompleter;
    _positionCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    _channel?.sink.close();
    super.dispose();
  }
}
