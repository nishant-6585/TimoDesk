import 'package:flutter/services.dart';

/// On-device CSJBot person detection (laser / RGBD / ultrasonic sensors),
/// bridged from [PersonDetectPlugin]. Emits `true` when a person is detected
/// near the robot and `false` when the area is clear — an idle→active trigger
/// that works without the network/cloud and without the microphone.
///
/// Off the real robot the native side never emits, so the stream is simply
/// silent (no events).
class PersonDetect {
  PersonDetect._();

  static const EventChannel _channel = EventChannel('com.mikee/person_events');

  /// Presence stream. The native side forwards the raw sensor state (int);
  /// non-zero is treated as "person present". (Exact state codes to be confirmed
  /// on-device.)
  static Stream<bool> get presence => _channel
      .receiveBroadcastStream()
      .map((e) => (e is int ? e : 0) != 0);
}
