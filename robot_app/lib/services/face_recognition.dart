import 'package:flutter/services.dart';

/// Staff face-recognition events from the CSJBot SDK, bridged by
/// [FaceRecognitionPlugin] over the "com.mikee/face_events" EventChannel.
///
/// Two event kinds arrive on the same stream:
///   • type "recognized" — a face matched the on-device DB → [name] + [confidence]
///     (plus best-effort [age]/[gender]). confidence ≥ 60 is reliable.
///   • type "near" — presence toggled → [present].
///
/// Off the real robot the SDK is absent, so the native side never emits and this
/// stream is simply silent (the greeting logic then falls back to the visitor flow).
class FaceRecognition {
  FaceRecognition._();

  static const EventChannel _ch = EventChannel('com.mikee/face_events');

  static Stream<FaceEvent> get events => _ch
      .receiveBroadcastStream()
      .map((e) => FaceEvent.fromMap(Map<String, dynamic>.from(e as Map)));
}

class FaceEvent {
  final String type; // 'recognized' or 'near'
  final String? name; // only when type='recognized'
  final int confidence; // only when type='recognized', 0-100
  final bool? present; // only when type='near'
  final int age; // best-effort, only when type='recognized'
  final String? gender; // best-effort, only when type='recognized'

  const FaceEvent({
    required this.type,
    this.name,
    this.confidence = 0,
    this.present,
    this.age = 0,
    this.gender,
  });

  factory FaceEvent.fromMap(Map<String, dynamic> m) => FaceEvent(
        type: (m['type'] as String?) ?? '',
        name: m['name'] as String?,
        confidence: (m['confidence'] as int?) ?? 0,
        present: m['present'] as bool?,
        age: (m['age'] as int?) ?? 0,
        gender: m['gender'] as String?,
      );
}
