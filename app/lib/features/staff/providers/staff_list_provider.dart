import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/spine_base.dart';

final String _spineBase = spineHttpBase;

String _authToken() =>
    Supabase.instance.client.auth.currentSession?.accessToken ?? 'test-token';

class StaffMember {
  final String id;
  final String fullName;
  final String? phone;
  final String? personType;
  final String? role;
  final int embeddingCount;
  final bool active;
  final String? photoUrl;
  // Desk/location SLAM pose captured via the robot (migration 013). Null = not captured.
  final double? deskX;
  final double? deskY;
  final double? deskZ;
  final double? deskRotation;

  StaffMember({
    required this.id,
    required this.fullName,
    this.phone,
    this.personType,
    this.role,
    required this.embeddingCount,
    required this.active,
    this.photoUrl,
    this.deskX,
    this.deskY,
    this.deskZ,
    this.deskRotation,
  });

  bool get hasDesk => deskX != null && deskY != null;

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'] as String,
        fullName: (j['full_name'] ?? '') as String,
        phone: j['phone'] as String?,
        personType: j['person_type'] as String?,
        role: j['role'] as String?,
        embeddingCount: (j['embedding_count'] ?? 0) as int,
        active: (j['active'] ?? true) as bool,
        photoUrl: j['photo_url'] as String?,
        deskX: (j['desk_x'] as num?)?.toDouble(),
        deskY: (j['desk_y'] as num?)?.toDouble(),
        deskZ: (j['desk_z'] as num?)?.toDouble(),
        deskRotation: (j['desk_rotation'] as num?)?.toDouble(),
      );
}

/// Live list of enrolled staff (re-fetches when invalidated).
final staffListProvider = FutureProvider.autoDispose<List<StaffMember>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/staff'), headers: {'Authorization': 'Bearer ${_authToken()}'})
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Failed to load staff');
  return (data['staff'] as List).map((e) => StaffMember.fromJson(e as Map<String, dynamic>)).toList();
});

Future<void> updateStaff(String id, Map<String, dynamic> fields) async {
  final res = await http
      .patch(
        Uri.parse('$_spineBase/staff/$id'),
        headers: {'Authorization': 'Bearer ${_authToken()}', 'Content-Type': 'application/json'},
        body: jsonEncode(fields),
      )
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Update failed');
}

/// Deletes a staff member and cascade-erases their face embeddings (DPDP).
/// Returns how many embeddings were erased.
Future<int> deleteStaff(String id) async {
  final res = await http
      .delete(Uri.parse('$_spineBase/staff/$id'), headers: {'Authorization': 'Bearer ${_authToken()}'})
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Delete failed');
  return (data['embeddings_erased'] ?? 0) as int;
}
