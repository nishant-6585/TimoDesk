import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Dart side of the #80 Phase B audio bridge — mic capture + speaker playback +
/// CSJBot wake word. No new dependencies (platform channels only).
///
/// NOTE: RECORD_AUDIO is a runtime permission (Android 6+). The native side only
/// CHECKS it (returns MIC_PERMISSION if missing); granting is a deployment step —
/// on the kiosk robot, pre-grant it (launcher/MDM or `adb shell pm grant
/// com.timoDesk.robotapp android.permission.RECORD_AUDIO`). A permission_handler
/// flow would be a new dependency, so it's intentionally out of scope here.
class AudioBridge {
  static const _method = MethodChannel('com.timoDesk/audio_control');
  static const _micChannel = EventChannel('com.timoDesk/audio_mic');
  static const _wakeChannel = EventChannel('com.timoDesk/wake_events');

  StreamSubscription? _micSub;

  /// Start mic capture. Each 16 kHz/mono/16-bit PCM chunk is delivered to
  /// [onChunk] — wire it to voiceAgent.sendAudioChunk. Returns false if the mic
  /// can't start (permission denied / no device — e.g. on an emulator).
  Future<bool> startMic(void Function(Uint8List chunk) onChunk) async {
    try {
      await _method.invokeMethod('startMic');
      _micSub = _micChannel
          .receiveBroadcastStream()
          .listen((data) => onChunk(data as Uint8List));
      return true;
    } on PlatformException catch (e) {
      debugPrint('AudioBridge.startMic: ${e.code} ${e.message}');
      return false;
    }
  }

  Future<void> stopMic() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _method.invokeMethod('stopMic');
    } catch (_) {}
  }

  /// Play a raw PCM chunk from ElevenLabs (pcm_16000, 16-bit mono).
  Future<void> playChunk(Uint8List bytes) async {
    try {
      await _method.invokeMethod('playAudio', bytes);
    } catch (_) {}
  }

  Future<void> stopPlayback() async {
    try {
      await _method.invokeMethod('stopAudio');
    } catch (_) {}
  }

  /// Fires "wakeup" each time the CSJBot wake word triggers. Silent on the
  /// emulator (the native plugin swallows the SDK absence).
  Stream<String> get wakeWordStream =>
      _wakeChannel.receiveBroadcastStream().map((e) => e as String);

  void dispose() {
    stopMic();
  }
}
