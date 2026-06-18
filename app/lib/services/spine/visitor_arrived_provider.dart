import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One visitor_arrived event from the spine /visit pipeline.
class VisitorArrival {
  final String visitorName;
  final String hostName;
  final String channel; // slack | whatsapp | email | none
  final DateTime at;

  VisitorArrival({
    required this.visitorName,
    required this.hostName,
    required this.channel,
    required this.at,
  });
}

/// Holds the latest arrival and auto-clears it after a few seconds so the
/// Live Feed banner behaves like a transient notification.
class VisitorArrivedNotifier extends StateNotifier<VisitorArrival?> {
  VisitorArrivedNotifier() : super(null);

  Timer? _dismiss;
  static const _visibleFor = Duration(seconds: 8);

  void report(VisitorArrival v) {
    state = v;
    _dismiss?.cancel();
    _dismiss = Timer(_visibleFor, () {
      if (mounted) state = null;
    });
  }

  void clear() {
    _dismiss?.cancel();
    state = null;
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }
}

final visitorArrivedProvider =
    StateNotifierProvider<VisitorArrivedNotifier, VisitorArrival?>((ref) {
  ref.keepAlive();
  return VisitorArrivedNotifier();
});
