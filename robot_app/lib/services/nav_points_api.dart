import 'dart:convert';
import 'package:http/http.dart' as http;

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

/// Thin Supabase PostgREST client for the `nav_points` table.
///
/// WHY REST (not supabase_flutter): the robot_app deliberately keeps its
/// dependency surface tiny and has no `supabase_flutter` package — face
/// enrollment talks to the spine over plain `http`. We reuse the same project
/// URL + anon key the web admin uses (`app/lib/core/supabase.dart`) and hit the
/// REST endpoint directly. The `nav_points` RLS policy is `USING (true)` for the
/// select/write roles, so the anon key suffices (same effective access the web
/// admin gets after login).
class NavPointsApi {
  // Same Supabase project the web admin (app/lib/core/supabase.dart) uses.
  static const String _supabaseUrl = 'https://agjygqllxdclyzfxidgy.supabase.co';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFnanlncWxseGRjbHl6ZnhpZGd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2NTY0MzIsImV4cCI6MjA5NjIzMjQzMn0.TbdiNQqayGDRuTnJn4HiO9mNCsg7zaVU7cl2Js8odgg';

  static const String _table = 'nav_points';

  Uri _u(String query) =>
      Uri.parse('$_supabaseUrl/rest/v1/$_table?$query');

  Map<String, String> get _headers => {
        'apikey': _anonKey,
        'Authorization': 'Bearer $_anonKey',
        'Content-Type': 'application/json',
      };

  /// Read all saved points, ordered by sort_order then created_at.
  Future<List<NavPoint>> list() async {
    final res = await http
        .get(
          _u('select=*&order=sort_order.asc,created_at.asc'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('Load failed (${res.statusCode}): ${res.body}');
    }
    final rows = jsonDecode(res.body) as List;
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
        .post(
          _u('select=*'),
          headers: {..._headers, 'Prefer': 'return=representation'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Save failed (${res.statusCode}): ${res.body}');
    }
    final rows = jsonDecode(res.body) as List;
    return NavPoint.fromJson(rows.first as Map<String, dynamic>);
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
          _u('id=eq.${Uri.encodeComponent(id)}'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Update failed (${res.statusCode}): ${res.body}');
    }
  }

  /// Delete a point by id.
  Future<void> delete(String id) async {
    final res = await http
        .delete(
          _u('id=eq.${Uri.encodeComponent(id)}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Delete failed (${res.statusCode}): ${res.body}');
    }
  }
}
