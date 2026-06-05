import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const _App());

const _orange  = Color(0xFFFF6B35);
const _prefKey = 'recent_ips';

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TimoDesk Viewer',
    themeMode: ThemeMode.dark,
    darkTheme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _orange, brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF0F0F0F),
      cardColor: const Color(0xFF1A1A1A),
    ),
    home: const ConnectScreen(),
  );
}

// ── MJPEG decoder (byte-stream marker scan) ───────────────────────────────────

Stream<Uint8List> _mjpegFrames(String url) async* {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    final res = await req.close();
    final buf = BytesBuilder(copy: false);
    await for (final chunk in res) {
      buf.add(chunk);
      final data = buf.toBytes();
      int consumed = 0;
      while (true) {
        final soi = _findMarker(data, 0xFF, 0xD8, consumed);
        if (soi == -1) break;
        final eoi = _findMarker(data, 0xFF, 0xD9, soi + 2);
        if (eoi == -1) break;
        yield Uint8List.sublistView(data, soi, eoi + 2);
        consumed = eoi + 2;
      }
      if (consumed > 0) {
        final rem = Uint8List.sublistView(data, consumed);
        buf.clear(); buf.add(rem);
      }
    }
  } finally { client.close(); }
}

int _findMarker(Uint8List d, int b0, int b1, int from) {
  for (int i = from; i < d.length - 1; i++) {
    if (d[i] == b0 && d[i + 1] == b1) return i;
  }
  return -1;
}

// ── Stream type ───────────────────────────────────────────────────────────────

enum StreamType { mjpeg, webrtc }

// ── Connect Screen ────────────────────────────────────────────────────────────

class ConnectScreen extends StatefulWidget {
  const ConnectScreen();
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _ipCtrl         = TextEditingController(text: '192.168.1.');
  final _portCtrl       = TextEditingController(text: '8080');
  final _sigPortCtrl    = TextEditingController(text: '3000');
  StreamType _type      = StreamType.mjpeg;
  List<String> _recent  = [];

  @override
  void initState() { super.initState(); _loadRecent(); }

  @override
  void dispose() {
    _ipCtrl.dispose(); _portCtrl.dispose(); _sigPortCtrl.dispose(); super.dispose();
  }

  Future<void> _loadRecent() async {
    final p = await SharedPreferences.getInstance();
    setState(() => _recent = p.getStringList(_prefKey) ?? []);
  }

  Future<void> _saveIp(String ip) async {
    final p = await SharedPreferences.getInstance();
    final upd = [ip, ..._recent.where((e) => e != ip)].take(5).toList();
    await p.setStringList(_prefKey, upd);
    setState(() => _recent = upd);
  }

  void _connect() {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    _saveIp(ip);
    if (_type == StreamType.mjpeg) {
      final port = int.tryParse(_portCtrl.text.trim()) ?? 8080;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MjpegFeedScreen(ip: ip, port: port)));
    } else {
      final sigPort = int.tryParse(_sigPortCtrl.text.trim()) ?? 3000;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => WebRtcFeedScreen(ip: ip, signalingPort: sigPort)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TimoDesk Viewer'),
        backgroundColor: const Color(0xFF1A1A1A), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Stream type toggle
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              _TypeBtn('MJPEG',  StreamType.mjpeg,  _type, (t) => setState(() => _type = t)),
              _TypeBtn('WebRTC', StreamType.webrtc, _type, (t) => setState(() => _type = t)),
            ]),
          ),
          const SizedBox(height: 16),

          // IP field
          TextField(controller: _ipCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _deco('Robot IP Address', '192.168.x.x'),
            onSubmitted: (_) => _connect()),
          const SizedBox(height: 10),

          // Port field (changes based on type)
          if (_type == StreamType.mjpeg) ...[
            TextField(controller: _portCtrl,
              keyboardType: TextInputType.number,
              decoration: _deco('MJPEG Port', '8080'),
              onSubmitted: (_) => _connect()),
          ] else ...[
            TextField(controller: _sigPortCtrl,
              keyboardType: TextInputType.number,
              decoration: _deco('Signaling Port', '3000'),
              onSubmitted: (_) => _connect()),
          ],
          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: _connect,
            icon: Icon(_type == StreamType.webrtc ? Icons.stream : Icons.cast_rounded),
            label: Text('CONNECT  (${_type.name.toUpperCase()})',
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            style: FilledButton.styleFrom(
              backgroundColor: _orange, padding: const EdgeInsets.symmetric(vertical: 16))),

          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('RECENT',
                style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            ..._recent.map((ip) => _RecentTile(
              ip: ip,
              onTap: () { _ipCtrl.text = ip; _connect(); },
              onDelete: () async {
                final p = await SharedPreferences.getInstance();
                final upd = _recent.where((e) => e != ip).toList();
                await p.setStringList(_prefKey, upd);
                setState(() => _recent = upd);
              })),
          ],
        ]),
      ),
    );
  }

  InputDecoration _deco(String label, String hint) => InputDecoration(
    labelText: label, hintText: hint, filled: true,
    fillColor: const Color(0xFF1A1A1A),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _orange)));
}

class _TypeBtn extends StatelessWidget {
  final String label; final StreamType value; final StreamType current;
  final ValueChanged<StreamType> onTap;
  const _TypeBtn(this.label, this.value, this.current, this.onTap);
  @override
  Widget build(BuildContext context) => Expanded(child: GestureDetector(
    onTap: () => onTap(value),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: current == value ? _orange : Colors.transparent,
        borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Text(label,
        style: TextStyle(
          fontWeight: FontWeight.bold, fontSize: 13,
          color: current == value ? Colors.white : Colors.white38)))));
}

class _RecentTile extends StatelessWidget {
  final String ip; final VoidCallback onTap; final VoidCallback onDelete;
  const _RecentTile({required this.ip, required this.onTap, required this.onDelete});
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF1A1A1A),
    margin: const EdgeInsets.only(bottom: 6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    child: ListTile(
      leading: const Icon(Icons.history_rounded, color: _orange, size: 20),
      title: Text(ip, style: const TextStyle(fontSize: 14)),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
        onPressed: onDelete),
      onTap: onTap));
}

// ── MJPEG Feed Screen ─────────────────────────────────────────────────────────

enum _ConnState { connecting, live, error }

class MjpegFeedScreen extends StatefulWidget {
  final String ip; final int port;
  const MjpegFeedScreen({required this.ip, required this.port});
  @override
  State<MjpegFeedScreen> createState() => _MjpegFeedState();
}

class _MjpegFeedState extends State<MjpegFeedScreen> {
  _ConnState _state = _ConnState.connecting;
  Uint8List? _frame;
  StreamSubscription<Uint8List>? _sub;
  Timer? _retry;
  WebSocketChannel? _wsChannel;
  bool _wsConnected = false;
  WebSocketChannel? _wsChassisChannel;
  bool _wsChassisConnected = false;
  int _headLR = 50;
  int _headUD = 50;
  String get _url => 'http://${widget.ip}:${widget.port}/stream';

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _open();
    _connectHeadControl();
    _connectChassisControl();
  }

  @override
  void dispose() {
    _sub?.cancel(); _retry?.cancel();
    _wsChannel?.sink.close();
    _wsChassisChannel?.sink.close();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _connectHeadControl() {
    try {
      _wsChannel = WebSocketChannel.connect(Uri.parse('ws://${widget.ip}:8081'));
      _wsChannel!.stream.listen(
        (msg) {
          try {
            final m = jsonDecode(msg as String) as Map<String, dynamic>;
            if (m['type'] == 'status') {
              if (mounted) {
                setState(() {
                  _headLR = m['headLR'] as int? ?? 50;
                  _headUD = m['headUD'] as int? ?? 50;
                });
              }
            }
          } catch (e) {
            debugPrint('Parse error: $e');
          }
        },
        onError: (_) {
          if (mounted) setState(() => _wsConnected = false);
          Future.delayed(const Duration(seconds: 3), _connectHeadControl);
        },
        onDone: () {
          if (mounted) setState(() => _wsConnected = false);
          Future.delayed(const Duration(seconds: 3), _connectHeadControl);
        },
      );
      if (mounted) setState(() => _wsConnected = true);
    } catch (e) {
      debugPrint('WS error: $e');
      if (mounted) setState(() => _wsConnected = false);
      Future.delayed(const Duration(seconds: 3), _connectHeadControl);
    }
  }

  void _sendHeadCommand(Map<String, dynamic> cmd) {
    if (_wsConnected && _wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode(cmd));
      } catch (e) {
        debugPrint('Send error: $e');
      }
    }
  }

  void _connectChassisControl() {
    try {
      _wsChassisChannel = WebSocketChannel.connect(Uri.parse('ws://${widget.ip}:8082'));
      _wsChassisChannel!.stream.listen(
        (msg) {
          try {
            final m = jsonDecode(msg as String) as Map<String, dynamic>;
            if (m['type'] == 'status') {
              if (mounted) {
                setState(() {
                  // Update chassis state if needed
                });
              }
            }
          } catch (e) {
            debugPrint('Chassis parse error: $e');
          }
        },
        onError: (_) {
          if (mounted) setState(() => _wsChassisConnected = false);
          Future.delayed(const Duration(seconds: 3), _connectChassisControl);
        },
        onDone: () {
          if (mounted) setState(() => _wsChassisConnected = false);
          Future.delayed(const Duration(seconds: 3), _connectChassisControl);
        },
      );
      if (mounted) setState(() => _wsChassisConnected = true);
    } catch (e) {
      debugPrint('Chassis WS error: $e');
      if (mounted) setState(() => _wsChassisConnected = false);
      Future.delayed(const Duration(seconds: 3), _connectChassisControl);
    }
  }

  void _sendChassisCommand(Map<String, dynamic> cmd) {
    if (_wsChassisConnected && _wsChassisChannel != null) {
      try {
        _wsChassisChannel!.sink.add(jsonEncode(cmd));
      } catch (e) {
        debugPrint('Chassis send error: $e');
      }
    }
  }

  void _open() {
    _sub?.cancel();
    setState(() => _state = _ConnState.connecting);
    _sub = _mjpegFrames(_url).listen(
      (f) { if (mounted) setState(() { _frame = f; _state = _ConnState.live; }); },
      onError: (_) {
        if (mounted) setState(() => _state = _ConnState.error);
        _retry = Timer(const Duration(seconds: 3), _open);
      },
      onDone: () {
        if (mounted) setState(() => _state = _ConnState.error);
        _retry = Timer(const Duration(seconds: 3), _open);
      },
      cancelOnError: true,
    );
  }

  @override
  Widget build(BuildContext context) => _FeedScaffold(
    ip: widget.ip, port: widget.port, state: _state,
    child: Stack(children: [
      _frame != null
          ? Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true,
              width: double.infinity, height: double.infinity)
          : _Connecting(state: _state, onRetry: _open),
      if (_wsChassisConnected)
        Positioned(
          bottom: 24, left: 24,
          child: _ChassisFloatingJoystick(
            onCommand: _sendChassisCommand,
          )),
      if (_wsChassisConnected)
        Positioned(
          top: 16, left: 0, right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () => _sendChassisCommand({'cmd': 'stop'}),
              child: Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red[600],
                  boxShadow: [BoxShadow(color: Colors.red, blurRadius: 8)],
                ),
                child: const Icon(Icons.stop_rounded, color: Colors.white, size: 28),
              ),
            ),
          )),
      if (_wsConnected)
        Positioned(
          bottom: 24, right: 24,
          child: _FloatingJoystick(
            onCommand: _sendHeadCommand,
            headLR: _headLR,
            headUD: _headUD,
          )),
    ]));
}

// ── WebRTC Feed Screen ────────────────────────────────────────────────────────

class WebRtcFeedScreen extends StatefulWidget {
  final String ip; final int signalingPort;
  const WebRtcFeedScreen({required this.ip, required this.signalingPort});
  @override
  State<WebRtcFeedScreen> createState() => _WebRtcFeedState();
}

class _WebRtcFeedState extends State<WebRtcFeedScreen> {
  _ConnState       _state  = _ConnState.connecting;
  RTCPeerConnection? _pc;
  RTCVideoRenderer   _renderer = RTCVideoRenderer();
  WebSocket?         _ws;
  bool               _disposed = false;
  String get _sigUrl => 'ws://${widget.ip}:${widget.signalingPort}';

  static const _iceServers = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]};

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _renderer.initialize().then((_) => _connectSignaling());
  }

  @override
  void dispose() {
    _disposed = true;
    _ws?.close();
    _pc?.close();
    _renderer.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  Future<void> _connectSignaling() async {
    if (_disposed) return;
    try {
      _ws = await WebSocket.connect(_sigUrl);
      if (_disposed) { _ws?.close(); return; }

      // Register as viewer
      _wsSend({'type': 'role', 'role': 'viewer'});
      if (mounted) setState(() => _state = _ConnState.connecting);

      _ws!.listen(
        (raw) async {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          await _handleSignaling(msg);
        },
        onError: (_) => _scheduleReconnect(),
        onDone:  ()  => _scheduleReconnect(),
      );
    } catch (_) { _scheduleReconnect(); }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (mounted) setState(() => _state = _ConnState.error);
    Future.delayed(const Duration(seconds: 3), _connectSignaling);
  }

  Future<void> _handleSignaling(Map<String, dynamic> msg) async {
    final type = msg['type'] as String? ?? '';
    switch (type) {
      case 'robot_available':
      case 'waiting_for_robot':
        _wsSend({'type': 'request_offer'});

      case 'offer':
        await _closePc();
        _pc = await createPeerConnection(_iceServers);

        _pc!.onTrack = (RTCTrackEvent e) {
          if (e.track.kind == 'video') {
            _renderer.srcObject = e.streams.first;
            if (mounted) setState(() => _state = _ConnState.live);
          }
        };

        _pc!.onIceCandidate = (RTCIceCandidate c) {
          _wsSend({'type': 'ice', 'candidate': {
            'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex,
            'candidate': c.candidate,
          }});
        };

        _pc!.onIceConnectionState = (RTCIceConnectionState s) {
          if (s == RTCIceConnectionState.RTCIceConnectionStateFailed && mounted) {
            setState(() => _state = _ConnState.error);
          }
        };

        await _pc!.setRemoteDescription(
            RTCSessionDescription(msg['sdp'] as String, 'offer'));
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _wsSend({'type': 'answer', 'sdp': answer.sdp});

      case 'ice':
        final c = msg['candidate'] as Map<String, dynamic>?;
        if (_pc != null && c != null) {
          await _pc!.addCandidate(RTCIceCandidate(
              c['candidate'] as String?,
              c['sdpMid']   as String?,
              c['sdpMLineIndex'] as int?));
        }

      case 'robot_disconnected':
        if (mounted) setState(() => _state = _ConnState.error);
        await _closePc();
    }
  }

  Future<void> _closePc() async {
    await _pc?.close();
    _pc = null;
    _renderer.srcObject = null;
  }

  void _wsSend(Map<String, dynamic> obj) {
    if (_ws?.readyState == WebSocket.open) _ws!.add(jsonEncode(obj));
  }

  @override
  Widget build(BuildContext context) => _FeedScaffold(
    ip: widget.ip, port: widget.signalingPort, label: 'WebRTC',
    state: _state,
    child: _state == _ConnState.live
        ? RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
        : _Connecting(state: _state, onRetry: _connectSignaling));
}

// ── Shared feed scaffold ──────────────────────────────────────────────────────

class _FeedScaffold extends StatelessWidget {
  final String ip; final int port; final _ConnState state;
  final Widget child; final String label;
  const _FeedScaffold({
    required this.ip, required this.port, required this.state,
    required this.child, this.label = 'MJPEG'});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(children: [
      Positioned.fill(child: child),
      Positioned(top: 0, left: 0, right: 0,
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            _OverlayBtn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
            const SizedBox(width: 8),
            _OverlayChip('$ip:$port'),
            const SizedBox(width: 6),
            _OverlayChip(label),
            const Spacer(),
            _StatusChip(state),
          ])))),
    ]));
}

class _Connecting extends StatelessWidget {
  final _ConnState state; final VoidCallback onRetry;
  const _Connecting({required this.state, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    if (state == _ConnState.connecting) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: _orange),
        SizedBox(height: 14),
        Text('Connecting…', style: TextStyle(color: Colors.white54)),
      ]));
    }
    return Container(
      color: Colors.black87,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.white24),
        const SizedBox(height: 16),
        const Text('Cannot connect', style: TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Check robot IP and WiFi — retrying…',
            style: TextStyle(color: Colors.white38, fontSize: 13)),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry Now'),
          style: FilledButton.styleFrom(backgroundColor: _orange)),
      ]));
  }
}

class _OverlayBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _OverlayBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(width: 36, height: 36,
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: Colors.white, size: 20)));
}

class _OverlayChip extends StatelessWidget {
  final String label;
  const _OverlayChip(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)));
}

class _StatusChip extends StatelessWidget {
  final _ConnState state;
  const _StatusChip(this.state);
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      _ConnState.connecting => ('CONNECTING', Colors.yellowAccent),
      _ConnState.live       => ('LIVE',        Colors.greenAccent),
      _ConnState.error      => ('RETRYING',    Colors.redAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color,
            boxShadow: state == _ConnState.live
                ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 4)] : null)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 11,
            fontWeight: FontWeight.bold, letterSpacing: 1)),
      ]));
  }
}

// ── Chassis Floating Joystick ─────────────────────────────────────────────────

class _ChassisFloatingJoystick extends StatefulWidget {
  final Function(Map<String, dynamic>) onCommand;
  const _ChassisFloatingJoystick({required this.onCommand});

  @override
  State<_ChassisFloatingJoystick> createState() => _ChassisFloatingJoystickState();
}

class _ChassisFloatingJoystickState extends State<_ChassisFloatingJoystick> {
  late Offset _knobOffset;
  bool _dragging = false;
  late DateTime _lastCommandTime;

  @override
  void initState() {
    super.initState();
    _knobOffset = Offset.zero;
    _lastCommandTime = DateTime.now();
  }

  void _handlePan(DragUpdateDetails details) {
    const radius = 60.0;
    final newOffset = Offset(
      (details.delta.dx.clamp(-radius, radius)),
      (details.delta.dy.clamp(-radius, radius)),
    );

    final dist = newOffset.distance;
    if (dist > radius) {
      _knobOffset = newOffset / dist * radius;
    } else {
      _knobOffset = newOffset;
    }

    final now = DateTime.now();
    if (now.difference(_lastCommandTime).inMilliseconds >= 150) {
      final angle = atan2(-_knobOffset.dy, _knobOffset.dx) * 180 / pi;
      String direction = 'none';
      if (angle > -45 && angle <= 45) direction = 'right';
      else if (angle > 45 && angle <= 135) direction = 'forward';
      else if (angle > 135 || angle <= -135) direction = 'left';
      else direction = 'back';

      if (direction != 'none') {
        widget.onCommand({'cmd': 'move', 'dir': direction});
      }
      _lastCommandTime = now;
    }

    setState(() => _dragging = true);
  }

  void _handlePanEnd(DragEndDetails details) {
    _knobOffset = Offset.zero;
    widget.onCommand({'cmd': 'stop'});
    setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanUpdate: _handlePan,
    onPanEnd: _handlePanEnd,
    child: Container(
      width: 120, height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A1A).withValues(alpha: 0.85),
        border: Border.all(color: _orange, width: 2),
      ),
      child: Stack(alignment: Alignment.center, children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 80),
          left: 60 + _knobOffset.dx - 20,
          top: 60 + _knobOffset.dy - 20,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange,
              boxShadow: [BoxShadow(color: _orange.withValues(alpha: 0.5), blurRadius: 8)],
            ),
          ),
        ),
      ]),
    ),
  );
}

// ── Floating Joystick ─────────────────────────────────────────────────────────

class _FloatingJoystick extends StatefulWidget {
  final Function(Map<String, dynamic>) onCommand;
  final int headLR;
  final int headUD;
  const _FloatingJoystick({
    required this.onCommand,
    required this.headLR,
    required this.headUD,
  });

  @override
  State<_FloatingJoystick> createState() => _FloatingJoystickState();
}

class _FloatingJoystickState extends State<_FloatingJoystick> {
  late Offset _knobOffset;
  bool _dragging = false;
  late DateTime _lastCommandTime;

  @override
  void initState() {
    super.initState();
    _knobOffset = Offset.zero;
    _lastCommandTime = DateTime.now();
  }

  void _handlePan(DragUpdateDetails details) {
    const radius = 60.0;
    final newOffset = Offset(
      (details.delta.dx.clamp(-radius, radius)),
      (details.delta.dy.clamp(-radius, radius)),
    );

    final dist = newOffset.distance;
    if (dist > radius) {
      _knobOffset = newOffset / dist * radius;
    } else {
      _knobOffset = newOffset;
    }

    final now = DateTime.now();
    if (now.difference(_lastCommandTime).inMilliseconds >= 50) {
      final lr = (50 + (_knobOffset.dx / 60) * 50).toInt().clamp(0, 100);
      final ud = (50 - (_knobOffset.dy / 60) * 50).toInt().clamp(0, 100);
      widget.onCommand({'cmd': 'head_both', 'lr': lr, 'ud': ud});
      _lastCommandTime = now;
    }

    setState(() => _dragging = true);
  }

  void _handlePanEnd(DragEndDetails details) {
    _knobOffset = Offset.zero;
    widget.onCommand({'cmd': 'head_both', 'lr': 50, 'ud': 50});
    setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onPanUpdate: _handlePan,
    onPanEnd: _handlePanEnd,
    child: Container(
      width: 120, height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A1A1A).withValues(alpha: 0.85),
        border: Border.all(color: _orange, width: 2),
      ),
      child: Stack(alignment: Alignment.center, children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 80),
          left: 60 + _knobOffset.dx - 20,
          top: 60 + _knobOffset.dy - 20,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _orange,
              boxShadow: [BoxShadow(color: _orange.withValues(alpha: 0.5), blurRadius: 8)],
            ),
          ),
        ),
      ]),
    ),
  );
}
