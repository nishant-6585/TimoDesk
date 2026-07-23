import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// Dart side of the #80 Phase B audio bridge — mic capture + speaker playback +
/// CSJBot wake word. No new dependencies (platform channels only).
///
/// NOTE: RECORD_AUDIO is a runtime permission (Android 6+). The native side only
/// CHECKS it (returns MIC_PERMISSION if missing); granting is a deployment step —
/// on the kiosk robot, pre-grant it (launcher/MDM or `adb shell pm grant
/// com.mikee.robotapp android.permission.RECORD_AUDIO`). A permission_handler
/// flow would be a new dependency, so it's intentionally out of scope here.
class AudioBridge {
  static const _method = MethodChannel('com.mikee/audio_control');
  static const _micChannel = EventChannel('com.mikee/audio_mic');
  static const _playbackChannel = EventChannel('com.mikee/audio_playback');
  static const _wakeChannel = EventChannel('com.mikee/wake_events');
  static const _asrChannel = EventChannel('com.mikee/asr_events');

  StreamSubscription? _micSub;

  // Each EventChannel has a SINGLE native sink. If two screens (ambient face +
  // dashboard) each call receiveBroadcastStream(), the second listener overwrites
  // the native sink and the first screen silently stops getting events (this broke
  // the face's playback→state updates while the dashboard was open, freezing the
  // mic gate). Cache one broadcast stream per channel so both screens share it.
  Stream<String>? _asrText;
  Stream<double>? _playbackLevels;
  Stream<String>? _wakeWord;

  /// Recognized user speech (CSJBot CAE, echo-cancelled). Emits the live
  /// transcription string each time the user is detected speaking — used for
  /// on-device barge-in (cut Mikee off when the user starts talking).
  Stream<String> get asrTextStream => _asrText ??=
      _asrChannel.receiveBroadcastStream().map((e) => e?.toString() ?? '');

  /// Start mic capture. Each 16 kHz/mono/16-bit PCM chunk is delivered to
  /// [onChunk] — wire it to voiceAgent.sendAudioChunk. Returns false if the mic
  /// can't start (permission denied / no device — e.g. on an emulator).
  /// Start/stop the vendor speech engine (startIsr) — session-gated: the engine
  /// makes the system stream mic PCM to our listener but is too CPU-hungry to
  /// run 24/7. Call start on voice-session start, stop on session end.
  Future<void> startSpeechEngine() async {
    try {
      await _method.invokeMethod('startSpeechEngine');
    } catch (e) {
      debugPrint('AudioBridge.startSpeechEngine: $e');
    }
  }

  Future<void> stopSpeechEngine() async {
    try {
      await _method.invokeMethod('stopSpeechEngine');
    } catch (e) {
      debugPrint('AudioBridge.stopSpeechEngine: $e');
    }
  }

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

  /// Speak a phrase aloud via the CSJBot built-in TTS (synthesis works even though
  /// mic INPUT is vendor-blocked). No-op off the robot.
  Future<void> speak(String text) async {
    try {
      await _method.invokeMethod('speak', {'text': text});
    } catch (_) {}
  }

  Future<void> stopSpeak() async {
    try {
      await _method.invokeMethod('stopSpeak');
    } catch (_) {}
  }

  /// Playback amplitude (0..1) of each chunk AS IT PLAYS through the speaker —
  /// drives lip-sync in sync with what's actually heard. Emits -1 when playback
  /// drains (speech finished), so the face can return to listening on time.
  Stream<double> get playbackLevelStream => _playbackLevels ??=
      _playbackChannel.receiveBroadcastStream().map((e) => (e as num).toDouble());

  /// Fires "wakeup" each time the CSJBot wake word triggers. Silent on the
  /// emulator (the native plugin swallows the SDK absence).
  Stream<String> get wakeWordStream => _wakeWord ??=
      _wakeChannel.receiveBroadcastStream().map((e) => e as String);

  void dispose() {
    stopMic();
  }
}
