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

    // Auto-start head control when camera starts
    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr && !head.isRunning) {
        hNotifier.startHeadControl();
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
