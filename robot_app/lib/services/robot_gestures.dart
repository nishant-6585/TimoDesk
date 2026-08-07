import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';

/// Thin wrapper over the already-bridged native CSJBot action MethodChannels
/// (`arm_control`, `head_control`) so the ambient face can gesture during
/// conversation states — e.g. wave when greeting a visitor.
///
/// All calls are best-effort and idempotent: off-device (emulator / no CSJBot
/// SDK present) the channel call throws and we swallow it, so callers never
/// need to guard. The underlying SDK methods (startWaveHands / stopWaveHands /
/// MikeeActionReset) are documented in the csjbot-sdk-action-api memory.
class RobotGestures {
  RobotGestures._();

  static const MethodChannel _arm = MethodChannel('com.mikee/arm_control');
  static const MethodChannel _head = MethodChannel('com.mikee/head_control');

  /// Absolute head pose (0–100; 50 = center, higher ud = up, higher lr = right).
  /// Best-effort: off-device the channel throws and we swallow it.
  static Future<void> _setHead(int lr, int ud) async {
    try {
      await _head.invokeMethod('setHead', {'lr': lr, 'ud': ud});
    } catch (e) {
      if (kDebugMode) debugPrint('RobotGestures._setHead no-op: $e');
    }
  }

  /// Acknowledging nod — dip down, then back to neutral.
  static Future<void> headNod() async {
    await _setHead(50, 35);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _setHead(50, 55);
  }

  /// Curious "thinking" tilt to one side, then recenter.
  static Future<void> headTilt() async {
    await _setHead(65, 55);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _setHead(50, 55);
  }

  /// Subtle speaking sway driven by TTS amplitude (0..1). Called repeatedly
  /// while Mini talks; the caller throttles to ~once per 300 ms.
  static Future<void> headSway(double amplitude) async {
    final lr = (50 + amplitude * 12).clamp(35.0, 65.0).round();
    await _setHead(lr, 55);
  }

  /// Return the head to the neutral conversational pose.
  static Future<void> headCenter() async {
    await _setHead(50, 55);
  }

  /// Perk up to speak — a brief forward lean (approximated on the head ud axis,
  /// as Mini exposes no separate chest joint), then settle.
  static Future<void> chestAttention() async {
    await _setHead(50, 40);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _setHead(50, 55);
  }

  /// Wave hello, then auto-stop after [hold] so the arms settle. Fire-and-forget;
  /// intended to run alongside the greeting overlay (~3.5s hold).
  static Future<void> waveHello(
      {Duration hold = const Duration(seconds: 3)}) async {
    try {
      await _arm.invokeMethod('wave');
      Future<void>.delayed(hold, () async {
        try {
          await _arm.invokeMethod('stopWave');
        } catch (_) {/* off-device or already stopped */}
      });
    } catch (e) {
      if (kDebugMode) debugPrint('RobotGestures.waveHello no-op: $e');
    }
  }

  /// Return arms to the neutral pose.
  static Future<void> resetArms() async {
    try {
      await _arm.invokeMethod('resetArms');
    } catch (e) {
      if (kDebugMode) debugPrint('RobotGestures.resetArms no-op: $e');
    }
  }
}
