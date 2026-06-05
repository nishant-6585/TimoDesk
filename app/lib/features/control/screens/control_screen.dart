import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../widgets/joystick_widget.dart';
import '../widgets/arm_slider_widget.dart';
import '../widgets/stop_overlay.dart';
import '../widgets/robot_status_bar.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  double _leftArm = 50;
  double _rightArm = 50;
  double _speed = 0.5;

  void _sendHeadIntent(double lr, double ud) {
    ref.read(spineProvider.notifier).sendIntent({
      'intent': 'head',
      'lr': lr.toInt(),
      'ud': ud.toInt(),
    });
  }

  void _sendDriveIntent(double x, double y) {
    // Calculate direction from x, y coordinates
    final dx = (x - 50) / 50;
    final dy = (y - 50) / 50;

    String direction = 'none';
    if (dx.abs() > 0.3 || dy.abs() > 0.3) {
      final angle = (dy.atan2(dx) * 180 / 3.14159).toInt();
      if (angle > -45 && angle <= 45) direction = 'right';
      else if (angle > 45 && angle <= 135) direction = 'forward';
      else if (angle > 135 || angle <= -135) direction = 'left';
      else direction = 'back';
    }

    if (direction != 'none') {
      ref.read(spineProvider.notifier).sendIntent({
        'intent': 'drive',
        'dir': direction,
      });
    }
  }

  void _sendArmIntent() {
    ref.read(spineProvider.notifier).sendIntent({
      'intent': 'arm',
      'left': _leftArm.toInt(),
      'right': _rightArm.toInt(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final spineState = ref.watch(spineProvider);
    final isDisabled = !spineState.connected || spineState.stopped;

    return Scaffold(
      backgroundColor: TimoColors.background,
      appBar: AppBar(
        title: const Text('Control'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                RobotStatusBar(
                  spineConnected: spineState.connected,
                  isMoving: spineState.status?.isMoving ?? false,
                  battery: spineState.status?.battery ?? 0,
                ),
                const SizedBox(height: 24),

                // Joysticks side by side
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    JoystickWidget(
                      label: 'HEAD',
                      disabled: isDisabled,
                      onMove: (x, y) => _sendHeadIntent(x, y),
                    ),
                    JoystickWidget(
                      label: 'DRIVE',
                      disabled: isDisabled,
                      onMove: (x, y) => _sendDriveIntent(x, y),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Arm sliders
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: TimoColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: TimoColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ARMS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TimoColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ArmSliderWidget(
                        label: 'Left Arm',
                        value: _leftArm,
                        disabled: isDisabled,
                        onChanged: (value) {
                          setState(() => _leftArm = value);
                          _sendArmIntent();
                        },
                      ),
                      const SizedBox(height: 16),
                      ArmSliderWidget(
                        label: 'Right Arm',
                        value: _rightArm,
                        disabled: isDisabled,
                        onChanged: (value) {
                          setState(() => _rightArm = value);
                          _sendArmIntent();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isDisabled
                            ? null
                            : () => ref.read(spineProvider.notifier).sendIntent({'intent': 'wave'}),
                        icon: const Icon(Icons.waving_hand),
                        label: const Text('Wave'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isDisabled
                            ? null
                            : () => ref.read(spineProvider.notifier).sendIntent({'intent': 'reset_body'}),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // STOP overlay
          StopOverlay(
            visible: spineState.stopped,
            onResume: () => ref.read(spineProvider.notifier).sendIntent({'intent': 'resume'}),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.read(spineProvider.notifier).sendIntent({'intent': 'stop'}),
        backgroundColor: TimoColors.error,
        child: const Icon(Icons.stop, color: Colors.white),
        tooltip: 'Emergency STOP',
      ),
    );
  }
}
