import 'package:flutter/services.dart';

/// Bridge to the native KioskPlugin — Android Lock Task Mode (true kiosk) +
/// immersive system-UI. All calls are best-effort: if the app is NOT set as
/// device-owner (see `adb dpm set-device-owner`), the native side logs and
/// no-ops, so the app still runs (just not locked down).
class Kiosk {
  static const _ch = MethodChannel('com.mikee/kiosk');

  /// Enter kiosk: pin the app (startLockTask) + immersive. [allowSystemUi]
  /// controls whether Home/Recents/status-bar are permitted inside the lock
  /// task (admin/maintenance) — normally false for full lockdown.
  static Future<void> start({required bool allowSystemUi}) async {
    try {
      await _ch.invokeMethod('startKiosk', {'allowSystemUi': allowSystemUi});
    } catch (_) {/* not device-owner / no plugin — ignore */}
  }

  /// Toggle Home/Recents/status-bar pulldown within the running lock task
  /// (wired to the Settings switch). Applies immediately.
  static Future<void> setSystemUi(bool allow) async {
    try {
      await _ch.invokeMethod('setSystemUi', {'allow': allow});
    } catch (_) {}
  }

  /// Show or hide the Android system bars to match kiosk state. Call alongside
  /// [setSystemUi]/[start]: maintenance ([allowSystemUi] true) → edge-to-edge so
  /// the status-bar pulldown the Settings switch promises actually works;
  /// lockdown (false) → immersiveSticky (bars hidden). Pure Flutter-side, so it
  /// applies even when the app isn't device-owner.
  static void applySystemUiChrome(bool allowSystemUi) {
    SystemChrome.setEnabledSystemUIMode(
        allowSystemUi ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  /// True when this app is the device-owner (kiosk actually enforceable).
  static Future<bool> isDeviceOwner() async {
    try {
      return (await _ch.invokeMethod<bool>('isDeviceOwner')) ?? false;
    } catch (_) {
      return false;
    }
  }
}
