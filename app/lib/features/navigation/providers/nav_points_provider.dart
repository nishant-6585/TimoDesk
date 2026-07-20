import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/supabase.dart';
import '../../../services/spine/navi_status_provider.dart';
import '../../../services/spine/spine_provider.dart';

/// A named SLAM pose the robot can navigate to. Mirrors the `nav_points`
/// Supabase table (migration 010).
class NavPoint {
  final String id;
  final String name;
  final String? description;
  final double x;
  final double y;
  final double z;
  final double rotation;
  final String kind; // 'navigation' | 'welcome'
  final int sortOrder;

  const NavPoint({
    required this.id,
    required this.name,
    this.description,
    required this.x,
    required this.y,
    required this.z,
    required this.rotation,
    required this.kind,
    required this.sortOrder,
  });

  factory NavPoint.fromJson(Map<String, dynamic> j) => NavPoint(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        x: (j['x'] as num?)?.toDouble() ?? 0.0,
        y: (j['y'] as num?)?.toDouble() ?? 0.0,
        z: (j['z'] as num?)?.toDouble() ?? 0.0,
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
        kind: (j['kind'] ?? 'navigation') as String,
        sortOrder: (j['sort_order'] ?? 0) as int,
      );

  /// The pose payload sent to the spine `navi` intent.
  Map<String, dynamic> get pose => {'x': x, 'y': y, 'z': z, 'rotation': rotation};
}

/// CRUD over the `nav_points` table plus the spine round-trips needed to capture
/// a pose (get_position) and replay it (navi). State is the list of saved points
/// as an [AsyncValue] so the UI can render loading / error / data uniformly.
class NavPointsNotifier extends StateNotifier<AsyncValue<List<NavPoint>>> {
  final Ref _ref;

  NavPointsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  /// (Re)load all saved points, ordered the way they should display.
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final rows = await supabaseClient
          .from('nav_points')
          .select()
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      final points = (rows as List)
          .map((e) => NavPoint.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(points);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Capture the robot's current pose via the spine and save it under [name].
  /// Throws on failure (no live robot pose, or insert error) so the UI can
  /// surface the reason; reloads the list on success.
  Future<void> capture(String name, {String? description, String kind = 'navigation'}) async {
    final spine = _ref.read(spineProvider.notifier);
    final pose = await spine.getPosition();
    if (pose == null) {
      throw Exception('Could not read robot position (offline or timed out)');
    }
    await supabaseClient.from('nav_points').insert({
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'x': pose['x'],
      'y': pose['y'],
      'z': pose['z'],
      'rotation': pose['rotation'],
      'kind': kind,
    });
    await load();
  }

  /// Delete a saved point and reload the list.
  Future<void> delete(String id) async {
    await supabaseClient.from('nav_points').delete().eq('id', id);
    await load();
  }

  /// Send the robot to a saved point. Fire-and-forget through the spine.
  void goTo(NavPoint point) {
    _ref.read(spineProvider.notifier).naviTo(point.pose, name: point.name);
    _ref.read(naviStatusProvider.notifier).start(point.name);
  }

  /// Cancel the in-flight navigation. The banner clears when the robot's
  /// cancel_result navi_event comes back through the spine.
  void cancelNavi() {
    _ref.read(spineProvider.notifier).cancelNavi();
    _ref.read(naviStatusProvider.notifier).cancelling();
  }
}

/// Singleton provider (kept alive like the spine/staff providers) so the saved
/// list survives navigation away from the screen.
final navPointsProvider =
    StateNotifierProvider<NavPointsNotifier, AsyncValue<List<NavPoint>>>((ref) {
  ref.keepAlive();
  return NavPointsNotifier(ref);
});
