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
    print('[SpineService] Message: ${msg['type']}');

    if (msg['type'] == 'authenticated') {
      // Cancel connection timeout - we got authenticated
      _connectionTimeoutTimer?.cancel();
      // Request initial status
      sendIntent({'intent': 'get_status'});
    } else if (msg['type'] == 'robot_status' && msg['status'] != null) {
      final status = RobotStatus.fromJson(msg['status']);
      state = state.copyWith(status: status);
    } else if (msg['type'] == 'stopped') {
      state = state.copyWith(stopped: true);
    } else if (msg['type'] == 'resumed') {
      state = state.copyWith(stopped: false);
    } else if (msg['type'] == 'event') {
      final eventType = msg['event'] as String?;
      final eventPayload = msg['eventPayload'] as Map<String, dynamic>?;
      // Log for now — Phase 1B will wire these to UI
      print('[SpineService] Robot event: $eventType payload: $eventPayload');
    }
  }

  void sendIntent(Map<String, dynamic> intent) {
    if (!state.connected) {
      print('[SpineService] Not connected, dropping intent: $intent');
      return;
    }
    print('[SpineService] Sending intent: $intent');
    _channel?.sink.add(jsonEncode({'type': 'intent', 'intent': intent}));
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
