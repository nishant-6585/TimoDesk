import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/constants.dart';
import '../../features/settings/providers/settings_provider.dart';
import 'spine_state.dart';

class SpineService extends StateNotifier<SpineState> {
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;
  late Ref _ref;
  String? _spineUrl;
  String? _jwt;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 30000; // 30 seconds max

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

      // HARDCODED: Use localhost for development (Spine runs on dev machine)
      // In production, Spine will run on the robot itself at ws://192.168.10.18:4000
      _spineUrl = 'ws://localhost:4000';

      print('[SpineService] ========================================');
      print('[SpineService] CONNECTING TO SPINE BROKER');
      print('[SpineService] Spine WebSocket: $_spineUrl');
      print('[SpineService] (Camera stream from robot: http://192.168.10.18:8080)');
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
    } else if (msgType == 'ack') {
      print('[SpineService] [ACK] Command acknowledged: ${msg['intent']}');
    }
    print('[SpineService] ======== END MESSAGE ========');
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
      // HARDCODED: Use localhost (where Spine broker runs on dev machine)
      final url = _spineUrl ?? 'ws://localhost:4000';
      connect(url, newJwt);
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
