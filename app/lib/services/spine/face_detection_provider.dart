import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One face_detected event from the autonomous spine recognizer.
class FaceDetection {
  final String name; // staff full name, or 'unknown'
  final String? staffId;
  final bool matched;
  final double distance; // L2 to nearest enrolled embedding
  final DateTime at;

  FaceDetection({
    required this.name,
    required this.staffId,
    required this.matched,
    required this.distance,
    required this.at,
  });
}

/// Holds the most recent detection and auto-clears it after a few seconds so the
/// dashboard card behaves like a transient notification.
class FaceDetectionNotifier extends StateNotifier<FaceDetection?> {
  FaceDetectionNotifier() : super(null);

  Timer? _dismiss;
  static const _visibleFor = Duration(seconds: 6);

  void report(FaceDetection d) {
    state = d;
    _dismiss?.cancel();
    _dismiss = Timer(_visibleFor, () {
      if (mounted) state = null;
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }
}

final faceDetectionProvider =
    StateNotifierProvider<FaceDetectionNotifier, FaceDetection?>((ref) {
  ref.keepAlive();
  return FaceDetectionNotifier();
});
