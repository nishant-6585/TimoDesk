import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'voice_agent.dart' show VoiceEventKind;

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
  final _unknownCtrl = StreamController<void>.broadcast();
  final _presenceCtrl = StreamController<bool>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final _naviCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _escortCtrl = StreamController<Map<String, dynamic>>.broadcast();
  final _voiceControlCtrl = StreamController<String>.broadcast();
  final _configCtrl = StreamController<Map<String, dynamic>>.broadcast();

  /// Recognized staff (matched only — `unknown` is filtered out here).
  Stream<FaceDetectedEvent> get faceDetected => _faceCtrl.stream;

  /// A face was detected but matched NO enrolled staff (spine emits
  /// name:'unknown'). Lets the greeting flow welcome a visitor immediately
  /// instead of waiting out the recognition window.
  Stream<void> get unknownFace => _unknownCtrl.stream;

  /// CSJBot presence boolean from robot_status updates.
  Stream<bool> get personDetected => _presenceCtrl.stream;

  /// Connection/auth state (true once authenticated).
  Stream<bool> get connected => _connCtrl.stream;

  /// Spine-owned cross-client navigation state ({active, name, cancelling, …}).
  /// Fired whenever ANY client (web admin or this robot) starts/cancels a Go To.
  Stream<Map<String, dynamic>> get naviState => _naviCtrl.stream;

  /// Follow-Me escort lifecycle from the spine sequencer:
  /// {event:'started'|'checkpoint'|'arrival_check'|'person_confirmed'|'finished', …}.
  /// The nav provider speaks these so checkpoint pauses aren't silent.
  Stream<Map<String, dynamic>> get escortEvents => _escortCtrl.stream;

  /// Admin-issued voice control from spine — currently the action string
  /// 'stop' (end the active listening/voice session remotely).
  Stream<String> get voiceControl => _voiceControlCtrl.stream;

  /// Admin-issued robot config (name / behaviour toggles / speed) from spine.
  Stream<Map<String, dynamic>> get configUpdate => _configCtrl.stream;

  bool get isConnected => _authed;

  /// Wall-clock of the last frame the spine sent us. Null until authenticated.
  DateTime? _lastMessageAt;

  /// Stricter than [isConnected]: the socket is authenticated AND has produced
  /// traffic recently.
  ///
  /// [isConnected] can be a lie. A silent Wi-Fi drop or a spine host that loses
  /// power leaves a half-open TCP socket: no FIN arrives, `onDone` never fires,
  /// and `_authed` stays true until a write finally fails. Callers that would
  /// otherwise sit waiting for a reply that can never come (goTo / cancel) must
  /// gate on this instead and take their native path immediately.
  ///
  /// 12s threshold: the spine broadcasts `robot_status` to every client every
  /// 5s (`spine/src/server.ts` status heartbeat), so a live socket is never
  /// quiet for two consecutive beats.
  bool get isLive =>
      _authed &&
      _lastMessageAt != null &&
      DateTime.now().difference(_lastMessageAt!) < const Duration(seconds: 12);

  /// Send an arbitrary intent to the spine (e.g. navi / cancel_navi).
  /// No-op when not connected — callers should check [isConnected] first.
  void sendIntent(Map<String, dynamic> intent) =>
      _send({'type': 'intent', 'intent': intent});

  void start() => _connect();

  // ── Voice (#80) ─────────────────────────────────────────────────────────────

  /// Broadcast the current voice phase to spine → admin app. Maps the VoiceAgent
  /// event kind to a `voice_state` intent; spine re-broadcasts it as a voice_*
  /// event. No-op if not connected (best-effort telemetry).
  String? _lastVoiceState; // dedupe — only broadcast on change
  void sendVoiceState(VoiceEventKind kind) {
    final state = switch (kind) {
      VoiceEventKind.userSpeaking => 'listening',
      VoiceEventKind.agentThinking => 'thinking',
      VoiceEventKind.agentSpeaking => 'speaking',
      VoiceEventKind.sessionEnded => 'idle',
      _ => null,
    };
    if (state == null || state == _lastVoiceState) return;
    _lastVoiceState = state;
    _send({
      'type': 'intent',
      'intent': {'intent': 'voice_state', 'voiceState': state},
    });
  }

  /// Persist a completed conversation to spine `/voice/log` (HTTP one-shot write).
  /// Best-effort — a logging failure must never affect the conversation UX.
  Future<void> logConversation(List<Map<String, dynamic>> transcript,
      {List<Map<String, dynamic>> actions = const []}) async {
    if (transcript.isEmpty && actions.isEmpty) return;
    try {
      await http
          .post(
            Uri.parse('${RobotConfig.spineBaseUrl}/voice/log'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${RobotConfig.authToken}',
            },
            body: jsonEncode({
              'transcript': transcript,
              // The interaction LEDGER: what the robot decided/did, appended
              // chronologically after the spoken turns (each entry timestamped).
              if (actions.isNotEmpty) 'actions': actions,
              'resolved_by': 'elevenlabs',
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // swallow — telemetry only
    }
  }

  void _send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null || !_authed) return;
    ws.add(jsonEncode(msg));
  }

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
    // Any frame — including the 5s robot_status heartbeat — proves the socket
    // is still carrying traffic. Stamped before parsing so even a malformed
    // frame counts as liveness.
    _lastMessageAt = DateTime.now();
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
          if (msg['event'] == 'escort_event') _handleEscortEvent(msg);
          return;
        case 'robot_status':
          final status = msg['status'];
          if (status is Map && status['personDetected'] is bool) {
            if (!_presenceCtrl.isClosed) {
              _presenceCtrl.add(status['personDetected'] as bool);
            }
          }
          return;
        case 'navi_state':
          if (!_naviCtrl.isClosed) _naviCtrl.add(msg);
          return;
        case 'voice_control':
          // Admin remote control of the robot's voice session (e.g. 'stop').
          final action = msg['action'] as String?;
          if (action != null && !_voiceControlCtrl.isClosed) {
            _voiceControlCtrl.add(action);
          }
          return;
        case 'config_update':
          // Admin changed robot-side config (name / toggles / speed).
          final cfg = msg['config'];
          if (cfg is Map && !_configCtrl.isClosed) {
            _configCtrl.add(Map<String, dynamic>.from(cfg));
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
    if (name == null || name == 'unknown' || staffId == null) {
      // Face present but not an enrolled match → visitor signal.
      if (name == 'unknown' && !_unknownCtrl.isClosed) _unknownCtrl.add(null);
      return;
    }
    if (!_faceCtrl.isClosed) {
      _faceCtrl.add(
        FaceDetectedEvent(name, staffId, (payload['distance'] as num?)?.toDouble()),
      );
    }
  }

  void _handleEscortEvent(Map<String, dynamic> msg) {
    // Shape: { event:'escort_event', eventPayload:{ payload:{event, …} } }
    final ep = msg['eventPayload'];
    if (ep is! Map) return;
    final payload = ep['payload'];
    if (payload is! Map) return;
    if (!_escortCtrl.isClosed) {
      _escortCtrl.add(Map<String, dynamic>.from(payload));
    }
  }

  void _onClosed() {
    _authed = false;
    _lastMessageAt = null;
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
    await _unknownCtrl.close();
    await _presenceCtrl.close();
    await _connCtrl.close();
    await _naviCtrl.close();
    await _escortCtrl.close();
    await _voiceControlCtrl.close();
    await _configCtrl.close();
  }
}
