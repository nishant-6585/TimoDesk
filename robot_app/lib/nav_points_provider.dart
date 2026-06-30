import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart'; // chassisProvider (native getPosition/naviTo/cancelNavi)
import 'services/nav_points_api.dart';

/// Whole-screen state for the on-robot Navigation Points feature.
///
/// Holds the loaded list (as an [AsyncValue] so the UI can render
/// loading/empty/error uniformly) plus a transient "navigating to X" flag while
/// a go-to is in flight.
@immutable
class NavPointsState {
  final AsyncValue<List<NavPoint>> points;
  final bool capturing;
  final NavPoint? navigatingTo; // non-null while a go-to is active

  const NavPointsState({
    this.points = const AsyncValue.loading(),
    this.capturing = false,
    this.navigatingTo,
  });

  NavPointsState copyWith({
    AsyncValue<List<NavPoint>>? points,
    bool? capturing,
    NavPoint? navigatingTo,
    bool clearNavigating = false,
  }) =>
      NavPointsState(
        points: points ?? this.points,
        capturing: capturing ?? this.capturing,
        navigatingTo: clearNavigating ? null : (navigatingTo ?? this.navigatingTo),
      );
}

class NavPointsNotifier extends StateNotifier<NavPointsState> {
  NavPointsNotifier(this._ref) : super(const NavPointsState()) {
    load();
  }

  final Ref _ref;
  final NavPointsApi _api = NavPointsApi();

  /// Ensure chassis control is started before any getPosition/navi call — the
  /// native SDK no-ops otherwise (mirrors how the dashboard d-pad starts it).
  Future<void> _ensureChassis() async {
    final chassis = _ref.read(chassisProvider);
    if (!chassis.isRunning) {
      await _ref.read(chassisProvider.notifier).startChassisControl();
    }
  }

  /// (Re)load all saved points.
  Future<void> load() async {
    state = state.copyWith(points: const AsyncValue.loading());
    try {
      final list = await _api.list();
      if (!mounted) return;
      state = state.copyWith(points: AsyncValue.data(list));
    } catch (e, st) {
      if (!mounted) return;
      state = state.copyWith(points: AsyncValue.error(e, st));
    }
  }

  /// Capture the robot's CURRENT pose (drive it there first) and save under
  /// [name]. Throws on failure (not localized / insert error) so the screen can
  /// surface the reason; reloads on success.
  Future<void> capture(String name, {String? description}) async {
    state = state.copyWith(capturing: true);
    try {
      await _ensureChassis();
      final pose = await _ref.read(chassisProvider.notifier).getPosition();
      if (pose == null) {
        throw Exception(
            'Could not read robot position. Make sure the robot is localized on its map, then try again.');
      }
      await _api.insert(
        name: name,
        description: description,
        x: pose['x'] ?? 0.0,
        y: pose['y'] ?? 0.0,
        z: pose['z'] ?? 0.0,
        rotation: pose['rotation'] ?? 0.0,
      );
      await load();
    } finally {
      if (mounted) state = state.copyWith(capturing: false);
    }
  }

  /// Delete a saved point and reload.
  Future<void> delete(String id) async {
    await _api.delete(id);
    await load();
  }

  /// Send the robot to a saved point. Sets [NavPointsState.navigatingTo] while
  /// the SDK is driving there. Returns false if the SDK rejected the request.
  Future<bool> goTo(NavPoint point) async {
    state = state.copyWith(navigatingTo: point);
    try {
      await _ensureChassis();
      final ok = await _ref.read(chassisProvider.notifier).naviTo(point.pose);
      if (!ok && mounted) state = state.copyWith(clearNavigating: true);
      return ok;
    } catch (e) {
      debugPrint('goTo: $e');
      if (mounted) state = state.copyWith(clearNavigating: true);
      return false;
    }
  }

  /// Cancel an in-flight navigation and clear the navigating flag.
  Future<void> cancel() async {
    await _ref.read(chassisProvider.notifier).cancelNavi();
    if (mounted) state = state.copyWith(clearNavigating: true);
  }

  /// Mark navigation finished (e.g. the operator dismisses the banner).
  void clearNavigating() {
    if (mounted) state = state.copyWith(clearNavigating: true);
  }
}

/// Singleton provider (kept alive so the saved list survives navigating away
/// from the screen), matching the robot_app convention.
final navPointsProvider =
    StateNotifierProvider<NavPointsNotifier, NavPointsState>((ref) {
  ref.keepAlive();
  return NavPointsNotifier(ref);
});
