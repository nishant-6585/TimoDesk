// Manual Control dashboard tile → head / chassis / arm / e-stop.
// Control widgets moved verbatim from the old _StreamScreen; providers unchanged.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'app_widgets.dart';

class ManualControlScreen extends ConsumerWidget {
  const ManualControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mjpeg = ref.watch(streamProvider);
    final head = ref.watch(headProvider);
    final hNotifier = ref.read(headProvider.notifier);
    final chassis = ref.watch(chassisProvider);
    final cNotifier = ref.read(chassisProvider.notifier);
    final arm = ref.watch(armProvider);
    final aNotifier = ref.read(armProvider.notifier);

    // Auto-start head/chassis/arm control when the camera stream is live
    // (same behavior the old _StreamScreen had).
    ref.listen(streamProvider.select((s) => s.isStreaming), (prev, curr) {
      if (curr && !head.isRunning) hNotifier.startHeadControl();
      if (curr && !chassis.isRunning) cNotifier.startChassisControl();
      if (curr && !arm.isRunning) aNotifier.startArmControl();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Control', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel('HEAD CONTROL'),
          const SizedBox(height: 8),
          _HeadControlCard(state: head, notifier: hNotifier, streamIp: mjpeg.ip),
          const SizedBox(height: 12),
          _HeadControlButton(state: head, notifier: hNotifier),
          const SizedBox(height: 12),
          _HeadResetButton(notifier: hNotifier),
          const SizedBox(height: 28),
          SectionLabel('CHASSIS CONTROL'),
          const SizedBox(height: 8),
          _ChassisControlCard(state: chassis, notifier: cNotifier, streamIp: mjpeg.ip),
          const SizedBox(height: 12),
          _ChassisControlButton(state: chassis, notifier: cNotifier),
          const SizedBox(height: 12),
          _ChassisSpeedSlider(notifier: cNotifier, speed: chassis.speed),
          const SizedBox(height: 12),
          _ChassisEmergencyStopButton(notifier: cNotifier),
          const SizedBox(height: 28),
          SectionLabel('ARM CONTROL'),
          const SizedBox(height: 8),
          _ArmControlCard(state: arm, notifier: aNotifier, streamIp: mjpeg.ip),
          const SizedBox(height: 12),
          _ArmControlButtons(notifier: aNotifier, state: arm),
          const SizedBox(height: 12),
          _ArmSliders(state: arm, notifier: aNotifier),
        ]),
      ),
    );
  }
}

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
            const Icon(Icons.wifi_rounded, size: 16, color: kOrange),
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
          FieldLabel('WebSocket URL'),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: wsUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('WebSocket URL copied')));
            },
            child: Row(children: [
              Flexible(child: Text(wsUrl,
                  style: const TextStyle(color: kOrange, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 14, color: kOrange),
            ]),
          ),
          const SizedBox(height: 20),
          FieldLabel('Head Position'),
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
                  color: kOrange,
                  boxShadow: [BoxShadow(color: kOrange, blurRadius: 4)],
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
      backgroundColor: state.isRunning ? Colors.redAccent : kOrange,
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
      side: const BorderSide(color: kOrange, width: 1.5),
      padding: const EdgeInsets.symmetric(vertical: 12),
    ),
    child: const Text('RESET CENTER',
        style: TextStyle(color: kOrange, fontWeight: FontWeight.bold, letterSpacing: 1)),
  );
}

// ── Chassis Control card ───────────────────────────────────────────────────────

class _ChassisControlCard extends StatelessWidget {
  final ChassisState state;
  final ChassisNotifier notifier;
  final String streamIp;
  const _ChassisControlCard({
    required this.state,
    required this.notifier,
    required this.streamIp,
  });

  @override
  Widget build(BuildContext context) {
    final wsUrl = 'ws://$streamIp:8082';

    return Card(
      color: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.directions_car_rounded, size: 16, color: kOrange),
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
          FieldLabel('WebSocket URL'),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: wsUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('WebSocket URL copied')));
            },
            child: Row(children: [
              Flexible(child: Text(wsUrl,
                  style: const TextStyle(color: kOrange, fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 14, color: kOrange),
            ]),
          ),
          const SizedBox(height: 20),
          FieldLabel('Direction Indicator'),
          const SizedBox(height: 12),
          _DirectionIndicator(direction: state.direction, isMoving: state.isMoving),
        ]),
      ),
    );
  }
}

class _DirectionIndicator extends StatelessWidget {
  final String direction;
  final bool isMoving;
  const _DirectionIndicator({required this.direction, required this.isMoving});

  @override
  Widget build(BuildContext context) {
    const size = 80.0;
    final color = isMoving ? kOrange : const Color(0xFF6B7280);

    String getArrowSymbol() {
      return switch (direction) {
        'forward' => '↑',
        'back' => '↓',
        'left' => '←',
        'right' => '→',
        _ => '●',
      };
    }

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F0F),
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('N', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
            Text('S', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('W', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
            Text('E', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5))),
          ]),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
            child: Text(getArrowSymbol()),
          ),
        ]),
      ),
    );
  }
}

class _ChassisControlButton extends StatelessWidget {
  final ChassisState state;
  final ChassisNotifier notifier;
  const _ChassisControlButton({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: state.isRunning ? notifier.stopChassisControl : notifier.startChassisControl,
    icon: Icon(state.isRunning ? Icons.stop_circle_rounded : Icons.play_circle_rounded),
    label: Text(state.isRunning ? 'STOP CHASSIS' : 'START CHASSIS',
        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
    style: FilledButton.styleFrom(
      backgroundColor: state.isRunning ? Colors.redAccent : kOrange,
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 15),
    ),
  );
}

class _ChassisSpeedSlider extends StatelessWidget {
  final ChassisNotifier notifier;
  final double speed;
  const _ChassisSpeedSlider({required this.notifier, required this.speed});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        FieldLabel('Speed Control'),
        Text('${(speed * 10).toStringAsFixed(0)}%',
            style: const TextStyle(color: kOrange, fontSize: 13, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      Slider(
        value: speed,
        min: 0.3,
        max: 0.8,
        divisions: 10,
        activeColor: kOrange,
        inactiveColor: const Color(0xFF2A2A2A),
        onChanged: (v) => notifier.setSpeed(v),
      ),
    ],
  );
}

class _ChassisEmergencyStopButton extends StatelessWidget {
  final ChassisNotifier notifier;
  const _ChassisEmergencyStopButton({required this.notifier});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: notifier.emergencyStop,
    icon: const Icon(Icons.emergency_rounded),
    label: const Text('EMERGENCY STOP',
        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
    style: FilledButton.styleFrom(
      backgroundColor: Colors.redAccent,
      padding: const EdgeInsets.symmetric(vertical: 14),
      textStyle: const TextStyle(fontSize: 15),
    ),
  );
}

// ── Arm Control Card ──────────────────────────────────────────────────────────

class _ArmControlCard extends StatelessWidget {
  final ArmState state;
  final ArmNotifier notifier;
  final String streamIp;

  const _ArmControlCard({
    required this.state,
    required this.notifier,
    required this.streamIp,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF1A1A1A),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.pan_tool, color: kOrange, size: 20),
            const SizedBox(width: 8),
            const Text('Arm Control', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: state.isRunning ? const Color(0xFF4ADE80) : const Color(0xFF6B7280),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              state.isRunning ? 'ACTIVE' : 'STOPPED',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.link, size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: 'ws://$streamIp:8083')),
              child: Text(
                'ws://$streamIp:8083',
                style: const TextStyle(
                  fontSize: 12,
                  color: kOrange,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.underline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Clients: ${state.clientCount}', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ]),
    ),
  );
}

class _ArmControlButtons extends StatelessWidget {
  final ArmNotifier notifier;
  final ArmState state;

  const _ArmControlButtons({required this.notifier, required this.state});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(
      child: FilledButton(
        onPressed: state.isRunning ? notifier.stopArmControl : notifier.startArmControl,
        style: FilledButton.styleFrom(
          backgroundColor: state.isRunning ? Colors.grey : kOrange,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(state.isRunning ? 'STOP' : 'START',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    ),
  ]);
}

class _ArmSliders extends StatelessWidget {
  final ArmState state;
  final ArmNotifier notifier;

  const _ArmSliders({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    FieldLabel('Arm Positions'),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(
        child: Column(children: [
          Text('L Arm: ${state.leftArm}', style: const TextStyle(fontSize: 12, color: kOrange, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Slider(
            value: state.leftArm.toDouble(),
            min: 0,
            max: 100,
            divisions: 10,
            activeColor: kOrange,
            inactiveColor: const Color(0xFF2A2A2A),
            onChanged: (_) {},
          ),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(children: [
          Text('R Arm: ${state.rightArm}', style: const TextStyle(fontSize: 12, color: kOrange, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Slider(
            value: state.rightArm.toDouble(),
            min: 0,
            max: 100,
            divisions: 10,
            activeColor: kOrange,
            inactiveColor: const Color(0xFF2A2A2A),
            onChanged: (_) {},
          ),
        ]),
      ),
    ]),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(
        child: FilledButton(
          onPressed: state.isWaving ? notifier.stopWave : notifier.wave,
          style: FilledButton.styleFrom(
            backgroundColor: state.isWaving ? Colors.amber : const Color(0xFF1A1A1A),
            side: const BorderSide(color: kOrange, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(state.isWaving ? '👋 WAVING' : '👋 WAVE',
              style: const TextStyle(fontWeight: FontWeight.bold, color: kOrange)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton(
          onPressed: notifier.resetArms,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A1A),
            side: const BorderSide(color: kOrange, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: const Text('⟲ RESET',
              style: TextStyle(fontWeight: FontWeight.bold, color: kOrange)),
        ),
      ),
    ]),
  ]);
}
