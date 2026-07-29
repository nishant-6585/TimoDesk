import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/spine_base.dart';

// Mirrors staff_list_provider — the spine base + auth token pattern. The
// hardcoded localhost is the same #91 tech-debt as elsewhere; not this task.
final String _spineBase = spineHttpBase;

String _authToken() =>
    Supabase.instance.client.auth.currentSession?.accessToken ?? 'test-token';

/// One admin snapshot (F7) — the stored image + who took it, when.
class Snapshot {
  final String id;
  final DateTime? takenAt;
  final String? actor;
  final String? imageUrl;

  Snapshot({required this.id, this.takenAt, this.actor, this.imageUrl});

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        id: j['id'] as String,
        takenAt: j['taken_at'] != null ? DateTime.tryParse(j['taken_at'] as String)?.toLocal() : null,
        actor: j['actor'] as String?,
        imageUrl: j['image_url'] as String?,
      );
}

/// Recent admin snapshots (newest first). Re-fetches when invalidated so the
/// short-lived signed image URLs stay fresh.
final snapshotListProvider = FutureProvider.autoDispose<List<Snapshot>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/captures'), headers: {'Authorization': 'Bearer ${_authToken()}'})
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Failed to load snapshots');
  return (data['captures'] as List).map((e) => Snapshot.fromJson(e as Map<String, dynamic>)).toList();
});

/// Delete a snapshot (storage object + capture row on spine).
Future<void> deleteSnapshot(String id) async {
  final res = await http
      .delete(Uri.parse('$_spineBase/captures/$id'),
          headers: {'Authorization': 'Bearer ${_authToken()}'})
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'delete failed');
}
