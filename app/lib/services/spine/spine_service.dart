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
  late Ref _ref;
  String? _spineUrl;
  String? _jwt;

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

      // Get spine URL from settings provider (defaults to real robot IP)
      final settings = _ref.read(settingsProvider);
      _spineUrl = settings.spineUrl;

      print('[SpineService] Using spine URL from settings: $_spineUrl');
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

      print('[SpineService] Connecting to $spineUrl');
      _channel = WebSocketChannel.connect(Uri.parse(spineUrl));

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
      print('[SpineService] Connected');
    } catch (e) {
      print('[SpineService] Connection error: $e');
      state = state.copyWith(connected: false);
      _scheduleReconnect();
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    print('[SpineService] Message: ${msg['type']}');

    if (msg['type'] == 'authenticated') {
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
    state = state.copyWith(connected: false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    print('[SpineService] Scheduling reconnect in ${spineReconnectDelay.inSeconds}s');
    _reconnectTimer = Timer(spineReconnectDelay, () {
      // Re-fetch JWT in case it expired
      final session = Supabase.instance.client.auth.currentSession;
      final newJwt = session?.accessToken ?? 'dev';
      final url = _spineUrl ?? 'ws://192.168.1.100:4000';
      connect(url, newJwt);
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
