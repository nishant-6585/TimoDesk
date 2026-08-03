import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// A named SLAM pose the robot can navigate to. Mirrors the `nav_points`
/// Supabase table (migration 010) — SHARED with the web admin app, so a point
/// captured on either the robot or the admin is navigable from both.
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

  /// The pose payload sent to the native chassis `navi` method.
  Map<String, double> get pose => {'x': x, 'y': y, 'z': z, 'rotation': rotation};
}

/// Nav-point client — talks to the SPINE, not to Supabase.
///
/// It used to hit PostgREST directly with the project's anon key hardcoded right
/// here. That key ships inside the APK, and it forced the `nav_points` RLS policy
/// to `USING (true)` with no role restriction — so anyone who pulled the key out
/// of the APK could rewrite where the robot drives. Migration 017 removed anon's
/// access; the spine (service role + kiosk-token auth) is the only writer now,
/// which also matches the rest of this app: everything else already goes through
/// the spine over plain `http`.
///
/// Auth is the kiosk token from Settings (`RobotConfig.kioskToken`), the same
/// credential the SpineClient WS and face enrollment use.
class NavPointsApi {
  String get _base => RobotConfig.spineBaseUrl;

  Uri _u(String path) => Uri.parse('$_base/nav-points$path');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${RobotConfig.kioskToken}',
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

  /// Read all saved points, ordered by sort_order then created_at.
  Future<List<NavPoint>> list() async {
    final res = await http
        .get(_u(''), headers: _headers)
        .timeout(const Duration(seconds: 12));
    final rows = _envelope(res, 'Load')['points'] as List;
    return rows
        .map((e) => NavPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Insert a new point and return the created row.
  Future<NavPoint> insert({
    required String name,
    String? description,
    required double x,
    required double y,
    required double z,
    required double rotation,
    String kind = 'navigation',
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (description != null && description.isNotEmpty) 'description': description,
      'x': x,
      'y': y,
      'z': z,
      'rotation': rotation,
      'kind': kind,
    };
    final res = await http
        .post(_u(''), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    final point = _envelope(res, 'Save')['point'] as Map<String, dynamic>;
    return NavPoint.fromJson(point);
  }

  /// Update a point's name and/or arrival announcement (description).
  /// Coordinates are left untouched — re-capture to move a point.
  Future<void> update(String id, {String? name, String? description}) async {
    final body = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      'description': (description == null || description.isEmpty) ? null : description,
    };
    final res = await http
        .patch(
          _u('/${Uri.encodeComponent(id)}'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    _envelope(res, 'Update');
  }

  /// Delete a point by id.
  Future<void> delete(String id) async {
    final res = await http
        .delete(_u('/${Uri.encodeComponent(id)}'), headers: _headers)
        .timeout(const Duration(seconds: 12));
    _envelope(res, 'Delete');
  }
}
