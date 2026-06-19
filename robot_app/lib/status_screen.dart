// Robot Status dashboard tile → live MJPEG/FPS/clients/SDK + battery.
// Reuses the existing streamProvider + batteryProvider unchanged.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide StreamNotifier;
import 'package:qr_flutter/qr_flutter.dart';
import 'providers.dart';
import 'app_widgets.dart';

class RobotStatusScreen extends ConsumerWidget {
  const RobotStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mjpeg = ref.watch(streamProvider);
    final mNotifier = ref.read(streamProvider.notifier);
    final battery = ref.watch(batteryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Robot Status', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [BatteryIndicator(state: battery), const SizedBox(width: 12)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel('MJPEG STREAM'),
          const SizedBox(height: 8),
          StatusCard(state: mjpeg),
          const SizedBox(height: 12),
          StreamButton(state: mjpeg, notifier: mNotifier),
          if (mjpeg.isStreaming) ...[
            const SizedBox(height: 12),
            QrCard(state: mjpeg),
          ],
        ]),
      ),
    );
  }
}

class StatusCard extends StatelessWidget {
  final StreamState state;
  const StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            StatusDot(active: state.isStreaming, activeColor: Colors.greenAccent),
            const SizedBox(width: 8),
            Text(state.isStreaming ? 'LIVE' : 'STOPPED',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.4,
                    color: state.isStreaming ? Colors.greenAccent : Colors.redAccent)),
            const Spacer(),
            SdkBadge(status: state.sdkStatus),
          ]),
          const Divider(height: 24),
          FieldLabel('Stream URL'),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: state.streamUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied')));
            },
            child: Row(children: [
              Flexible(child: Text(state.streamUrl,
                  style: const TextStyle(color: kOrange, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 14, color: kOrange),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel('FPS'),
              const SizedBox(height: 4),
              FpsBadge(fps: state.fps),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel('Clients'),
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

class StreamButton extends StatelessWidget {
  final StreamState    state;
  final StreamNotifier notifier;
  const StreamButton({required this.state, required this.notifier});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: state.isStreaming ? notifier.stopStream : notifier.startStream,
    icon: Icon(state.isStreaming ? Icons.stop_circle_rounded : Icons.play_circle_rounded),
    label: Text(state.isStreaming ? 'STOP STREAM' : 'START STREAM',
        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
    style: FilledButton.styleFrom(
      backgroundColor: state.isStreaming ? Colors.redAccent : kOrange,
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 15),
    ),
  );
}

class QrCard extends StatelessWidget {
  final StreamState state;
  const QrCard({required this.state});
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

