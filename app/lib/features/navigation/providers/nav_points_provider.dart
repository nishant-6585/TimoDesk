import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/spine_base.dart';
import '../../../services/spine/navi_status_provider.dart';
import '../../../services/spine/spine_provider.dart';

String _authToken() =>
    Supabase.instance.client.auth.currentSession?.accessToken ?? 'test-token';

Map<String, String> get _headers => {
      'Authorization': 'Bearer ${_authToken()}',
      'Content-Type': 'application/json',
    };

/// Unwrap the spine's `{ ok, ... }` envelope, or throw with its reason.
Map<String, dynamic> _envelope(http.Response res, String verb) {
  Map<String, dynamic>? data;
  try {
    data = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {
    // Non-JSON body (proxy error page, empty 401) — fall through to the throw.
  }
  if (data == null || data['ok'] != true) {
    throw Exception('$verb failed (${res.statusCode}): ${data?['reason'] ?? res.body}');
  }
  return data;
}

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

/// CRUD over nav points plus the spine round-trips needed to capture a pose
/// (get_position) and replay it (navi). State is the list of saved points as an
/// [AsyncValue] so the UI can render loading / error / data uniformly.
///
/// CRUD goes through the spine's /nav-points routes rather than PostgREST: after
/// migration 017 the table is admin-allowlisted and closed to `anon`, and the
/// robot's chest screen (which has no Supabase session) shares these routes.
class NavPointsNotifier extends StateNotifier<AsyncValue<List<NavPoint>>> {
  final Ref _ref;

  NavPointsNotifier(this._ref) : super(const AsyncValue.loading()) {
    load();
  }

  /// (Re)load all saved points, ordered the way they should display.
  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final res = await http
          .get(Uri.parse('$spineHttpBase/nav-points'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      final rows = _envelope(res, 'Load')['points'] as List;
      final points = rows
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
    final res = await http
        .post(
          Uri.parse('$spineHttpBase/nav-points'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            if (description != null && description.isNotEmpty) 'description': description,
            'x': pose['x'],
            'y': pose['y'],
            'z': pose['z'],
            'rotation': pose['rotation'],
            'kind': kind,
          }),
        )
        .timeout(const Duration(seconds: 12));
    _envelope(res, 'Save');
    await load();
  }

  /// Update a point's name / arrival announcement and reload the list.
  /// Coordinates are left untouched — re-capture to move a point.
  Future<void> update(String id, {String? name, String? description}) async {
    final res = await http
        .patch(
          Uri.parse('$spineHttpBase/nav-points/${Uri.encodeComponent(id)}'),
          headers: _headers,
          body: jsonEncode({
            if (name != null && name.isNotEmpty) 'name': name,
            'description': (description == null || description.isEmpty) ? null : description,
          }),
        )
        .timeout(const Duration(seconds: 12));
    _envelope(res, 'Update');
    await load();
  }

  /// Delete a saved point and reload the list.
  Future<void> delete(String id) async {
    final res = await http
        .delete(
          Uri.parse('$spineHttpBase/nav-points/${Uri.encodeComponent(id)}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    _envelope(res, 'Delete');
    await load();
  }

  /// Send the robot to a saved point. Fire-and-forget through the spine.
  void goTo(NavPoint point) {
    final say = point.description?.trim();
    _ref.read(spineProvider.notifier).naviTo(
          point.pose,
          name: point.name,
          arrivalText: (say != null && say.isNotEmpty) ? say : null,
        );
    _ref.read(naviStatusProvider.notifier).start(point.name);
  }

  /// Start a patrol over the given points (spine-side sequencer loops them).
  void patrolStart(List<NavPoint> points) {
    _ref.read(spineProvider.notifier).sendIntent({
      'intent': 'patrol_start',
      'loop': true,
      'points': [
        for (final p in points)
          {
            'x': p.x, 'y': p.y, 'z': p.z, 'rotation': p.rotation,
            'name': p.name,
            if (p.description?.trim().isNotEmpty == true)
              'arrivalText': p.description!.trim(),
          }
      ],
    });
  }

  /// Stop the running patrol (also cancels the active leg).
  void patrolStop() {
    _ref.read(spineProvider.notifier).sendIntent({'intent': 'patrol_stop'});
  }

  /// Start a Follow-Me escort over [route] in order. Unlike patrol, the spine
  /// verifies a person is present (camera check) at each waypoint and every
  /// ~2m mid-leg before proceeding; nobody within the timeout stops the escort.
  void escortStart(List<NavPoint> route) {
    _ref.read(spineProvider.notifier).sendIntent({
      'intent': 'escort_start',
      'points': [
        for (final p in route)
          {
            'x': p.x, 'y': p.y, 'z': p.z, 'rotation': p.rotation,
            'name': p.name,
            if (p.description?.trim().isNotEmpty == true)
              'arrivalText': p.description!.trim(),
          }
      ],
    });
  }

  /// Stop the running escort (also cancels the active leg).
  void escortStop() {
    _ref.read(spineProvider.notifier).sendIntent({'intent': 'escort_stop'});
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
