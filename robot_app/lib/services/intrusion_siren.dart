/// intrusion_siren.dart — the audible half of F9's intrusion alarm.
///
/// The CSJBot platform exposes no siren/buzzer API, and there is no alarm
/// hardware on this robot, so the "siren" is built from what the robot actually
/// has: its speaker. A repeated spoken challenge is arguably a better deterrent
/// than a tone anyway — it tells an intruder they have been seen and recorded,
/// which a beep does not.
///
/// Deliberate design points:
///   • Repeats on an interval rather than once, so it keeps sounding while the
///     alert reaches a human, and auto-stops after [maxDuration] so a false
///     positive doesn't shout all night at an empty office.
///   • Uses the device TTS path (AudioBridge.speak), NOT ElevenLabs: the alarm
///     must not depend on the network or an API key being live at 2am.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_bridge.dart';

class IntrusionSiren {
  IntrusionSiren(this._audio);

  final AudioBridge _audio;

  Timer? _repeat;
  Timer? _autoStop;
  bool _active = false;

  bool get isActive => _active;

  /// Gap between challenges — long enough for each line to finish speaking.
  static const Duration repeatEvery = Duration(seconds: 6);

  /// Hard stop, so a false alarm is self-limiting.
  static const Duration maxDuration = Duration(minutes: 2);

  static const String _challenge =
      'Attention. This area is closed and monitored. '
      'You have been recorded and security has been notified.';

  /// Start sounding. Idempotent — a second alarm while already sounding just
  /// extends the auto-stop window rather than stacking timers.
  void start({String? waypoint}) {
    debugPrint('Siren: INTRUSION alarm start (waypoint: ${waypoint ?? "unknown"})');
    _autoStop?.cancel();
    _autoStop = Timer(maxDuration, () {
      debugPrint('Siren: max duration reached — standing down');
      stop();
    });

    if (_active) return;
    _active = true;
    _speak();
    _repeat = Timer.periodic(repeatEvery, (_) => _speak());
  }

  void stop() {
    if (!_active && _repeat == null && _autoStop == null) return;
    debugPrint('Siren: alarm stopped');
    _active = false;
    _repeat?.cancel();
    _repeat = null;
    _autoStop?.cancel();
    _autoStop = null;
    unawaited(_audio.stopSpeak().catchError((_) {}));
  }

  void _speak() {
    // Never let a TTS failure kill the repeat timer — the next tick retries.
    unawaited(_audio.speak(_challenge).catchError((Object e) {
      debugPrint('Siren: speak failed: $e');
    }));
  }

  void dispose() => stop();
}
