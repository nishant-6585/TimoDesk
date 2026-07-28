import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live Follow-Me escort progress, synced from the spine's navi_state
/// broadcasts (`escort: {active, index, total, checking}`). Null when no
/// escort is running. Cross-client like navi state: an escort started from
/// ANY client (robot app, admin, MCP) shows here.
class EscortStatus {
  final int index; // current leg, 0-based
  final int total; // waypoints in the route
  final bool checking; // paused, scanning for the visitor
  const EscortStatus({
    required this.index,
    required this.total,
    required this.checking,
  });
}

class EscortStatusNotifier extends StateNotifier<EscortStatus?> {
  EscortStatusNotifier() : super(null);

  /// Apply the `escort` field of a navi_state broadcast. The spine only
  /// includes the field while an escort is active, so absent/null → clear.
  void sync(Map<String, dynamic>? escort) {
    if (escort == null || escort['active'] != true) {
      state = null;
      return;
    }
    state = EscortStatus(
      index: (escort['index'] as num?)?.toInt() ?? 0,
      total: (escort['total'] as num?)?.toInt() ?? 0,
      checking: escort['checking'] == true,
    );
  }

  void clear() => state = null;
}

final escortStatusProvider =
    StateNotifierProvider<EscortStatusNotifier, EscortStatus?>((ref) {
  ref.keepAlive();
  return EscortStatusNotifier();
});
