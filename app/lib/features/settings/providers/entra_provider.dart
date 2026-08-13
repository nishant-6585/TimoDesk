import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/spine_base.dart';

final String _spineBase = spineHttpBase;

String _authToken() =>
    Supabase.instance.client.auth.currentSession?.accessToken ?? 'test-token';

Map<String, String> get _headers => {
      'Authorization': 'Bearer ${_authToken()}',
      'Content-Type': 'application/json',
    };

/// Spine GET /entra/status — Entra ID integration config + last/next sync run.
/// Config lives in the spine's .env (secrets never reach this app); this is a
/// read-only mirror plus the "Sync now" trigger.
class EntraStatus {
  final bool configured;
  final String consentMode; // 'group' | 'all'
  final bool consentGroupSet;
  final int syncIntervalMin; // 0 = manual-only
  final int offboardPurgeDays;
  final String? secretExpires; // ISO date recorded by ops, null = unknown
  final DateTime? lastRunAt;
  final bool? lastRunOk;
  final String? lastRunError;
  final Map<String, dynamic>? lastSummary;
  final DateTime? nextRunAt;

  EntraStatus({
    required this.configured,
    required this.consentMode,
    required this.consentGroupSet,
    required this.syncIntervalMin,
    required this.offboardPurgeDays,
    this.secretExpires,
    this.lastRunAt,
    this.lastRunOk,
    this.lastRunError,
    this.lastSummary,
    this.nextRunAt,
  });

  factory EntraStatus.fromJson(Map<String, dynamic> j) {
    final lastRun = j['last_run'] as Map<String, dynamic>?;
    return EntraStatus(
      configured: (j['configured'] ?? false) as bool,
      consentMode: (j['consent_mode'] ?? 'group') as String,
      consentGroupSet: (j['consent_group_set'] ?? false) as bool,
      syncIntervalMin: (j['sync_interval_min'] as num?)?.toInt() ?? 0,
      offboardPurgeDays: (j['offboard_purge_days'] as num?)?.toInt() ?? 0,
      secretExpires: j['secret_expires'] as String?,
      lastRunAt: lastRun == null ? null : DateTime.tryParse((lastRun['at'] ?? '') as String),
      lastRunOk: lastRun?['ok'] as bool?,
      lastRunError: lastRun?['error'] as String?,
      lastSummary: lastRun?['summary'] as Map<String, dynamic>?,
      nextRunAt: DateTime.tryParse((j['next_run_at'] ?? '') as String),
    );
  }

  /// Days until the recorded client-secret expiry; null when unknown.
  int? get secretDaysLeft {
    final exp = DateTime.tryParse(secretExpires ?? '');
    return exp?.difference(DateTime.now()).inDays;
  }
}

final entraStatusProvider = FutureProvider.autoDispose<EntraStatus>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/entra/status'), headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Failed to load Entra status');
  return EntraStatus.fromJson(data);
});

/// POST /entra/sync — run the full sync now (users → photos → offboard purge).
/// Returns the summary payload for the result snackbar. Slow on a first full
/// import (photo downloads + embeddings), hence the long timeout.
Future<Map<String, dynamic>> entraSyncNow() async {
  final res = await http
      .post(Uri.parse('$_spineBase/entra/sync'), headers: _headers)
      .timeout(const Duration(minutes: 10));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Sync failed');
  return data;
}
