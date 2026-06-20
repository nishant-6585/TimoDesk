import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';

/// Thin wrapper over the already-bridged native CSJBot action MethodChannels
/// (`arm_control`, `head_control`) so the ambient face can gesture during
/// conversation states — e.g. wave when greeting a visitor.
///
/// All calls are best-effort and idempotent: off-device (emulator / no CSJBot
/// SDK present) the channel call throws and we swallow it, so callers never
/// need to guard. The underlying SDK methods (startWaveHands / stopWaveHands /
/// TimoActionReset) are documented in the csjbot-sdk-action-api memory.
class RobotGestures {
  RobotGestures._();

  static const MethodChannel _arm = MethodChannel('com.timoDesk/arm_control');

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
