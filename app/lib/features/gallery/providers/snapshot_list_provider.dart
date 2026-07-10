import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Mirrors staff_list_provider — the spine base + auth token pattern.
// TODO: Move to environment-based config (dotenv or Supabase env var) for production.
final String _spineBase = const String.fromEnvironment(
  'SPINE_BASE',
  defaultValue: 'http://localhost:4000',
);

String _authToken() {
  final token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) throw Exception('Not authenticated');
  return token;
}

/// One admin snapshot (F7) — the stored image + who took it, when.
class Snapshot {
  final String id;
  final DateTime? takenAt;
  final String? actor;
  final String? imageUrl;

  Snapshot({required this.id, this.takenAt, this.actor, this.imageUrl});

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        id: j['id'] as String,
        takenAt: j['taken_at'] is String ? DateTime.tryParse(j['taken_at'] as String)?.toLocal() ?? DateTime.now() : null,
        actor: j['actor'] is String ? j['actor'] as String : null,
        imageUrl: j['image_url'] is String ? j['image_url'] as String : null,
      );
}

/// Recent admin snapshots (newest first). Re-fetches when invalidated so the
/// short-lived signed image URLs stay fresh.
final snapshotListProvider = FutureProvider.autoDispose<List<Snapshot>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/captures'), headers: {'Authorization': 'Bearer ${_authToken()}'})
      .timeout(const Duration(seconds: 15));
  
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('HTTP ${res.statusCode}: ${res.body}');
  }
  
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Failed to load snapshots');
  
  final captures = data['captures'];
  if (captures == null || captures is! List) {
    throw Exception('Invalid captures format');
  }
  
  return captures.map((e) => Snapshot.fromJson(e as Map<String, dynamic>)).toList();
});
