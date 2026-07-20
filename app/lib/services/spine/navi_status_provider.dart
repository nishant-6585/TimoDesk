import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The admin's view of an autonomous navigation. Set when a Go To starts (from
/// ANY client — spine navi_state broadcasts keep every UI in sync), flipped to
/// [arrived] when the spine's arrival watcher confirms the robot reached the
/// point, and cleared on cancel confirmation / manual dismiss. While active it
/// deliberately persists so the Cancel button stays reachable.
class NaviStatus {
  final String pointName;
  final DateTime startedAt;
  final bool cancelling; // Cancel sent, awaiting the robot's cancel_result
  final bool arrived; // navigation completed — banner shows success briefly
  final bool stalled; // goal active but robot not moving (nav service wedged)
  const NaviStatus({
    required this.pointName,
    required this.startedAt,
    this.cancelling = false,
    this.arrived = false,
    this.stalled = false,
  });

  NaviStatus copyWith({bool? cancelling, bool? arrived, bool? stalled}) => NaviStatus(
        pointName: pointName,
        startedAt: startedAt,
        cancelling: cancelling ?? this.cancelling,
        arrived: arrived ?? this.arrived,
        stalled: stalled ?? this.stalled,
      );
}

class NaviStatusNotifier extends StateNotifier<NaviStatus?> {
  NaviStatusNotifier() : super(null);

  Timer? _arrivedTimer;

  void start(String pointName) {
    _arrivedTimer?.cancel();
    state = NaviStatus(pointName: pointName, startedAt: DateTime.now());
  }

  /// Apply a spine `navi_state` broadcast — the shared cross-client truth.
  /// Keeps the local startedAt when the same navigation is already showing.
  void syncActive(String pointName,
      {bool cancelling = false, bool stalled = false}) {
    _arrivedTimer?.cancel();
    final cur = state;
    if (cur != null && cur.pointName == pointName && !cur.arrived) {
      state = cur.copyWith(cancelling: cancelling, stalled: stalled);
    } else {
      state = NaviStatus(
          pointName: pointName,
          startedAt: DateTime.now(),
          cancelling: cancelling,
          stalled: stalled);
    }
  }

  /// Navigation completed — show the success banner briefly, then clear.
  void arrived(String pointName) {
    _arrivedTimer?.cancel();
    state = NaviStatus(
        pointName: pointName, startedAt: DateTime.now(), arrived: true);
    _arrivedTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && state?.arrived == true) state = null;
    });
  }

  void cancelling() => state = state?.copyWith(cancelling: true);

  void clear() {
    _arrivedTimer?.cancel();
    state = null;
  }

  @override
  void dispose() {
    _arrivedTimer?.cancel();
    super.dispose();
  }
}

final naviStatusProvider =
    StateNotifierProvider<NaviStatusNotifier, NaviStatus?>((ref) {
  ref.keepAlive();
  return NaviStatusNotifier();
});
