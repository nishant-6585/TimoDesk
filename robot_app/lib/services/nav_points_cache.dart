import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nav_points_api.dart';

/// The last nav-point list the spine served, persisted on device.
///
/// Why this exists: driving is entirely native — [NavPointsApi] only supplies
/// the *list*, and the actual motion goes through ChassisControlPlugin's `navi`
/// (with arrival detection over `naviEvents`), which needs no server at all.
/// But migration 017 removed `anon`'s access to `nav_points`, so the spine is
/// the only reader; with the spine down the list came back EMPTY, leaving no
/// tiles to tap and nothing for `NavVoice` to match "take me to David" against.
/// Navigation looked dead while the drive stack underneath was fine.
///
/// So every successful fetch is written here and replayed at boot. Points move
/// rarely (a desk is re-captured, not re-positioned daily), so a stale list is
/// overwhelmingly better than no list.
///
/// Read-through only. Capture/rename/delete still require the spine — those are
/// writes to Supabase under the service-role credential, which is exactly what
/// 017 was for and must never come back into the APK.
class NavPointsCache {
  NavPointsCache._();

  static const _kPoints = 'nav_points_cache_v1';
  static const _kSavedAt = 'nav_points_cache_saved_at';

  /// Overwrite the cache with [points]. Best-effort: a cache write must never
  /// fail a load that already succeeded.
  static Future<void> save(List<NavPoint> points) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kPoints, jsonEncode([for (final p in points) p.toJson()]));
      await prefs.setString(_kSavedAt, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('NavPointsCache.save: $e');
    }
  }

  /// The cached list, or null when nothing has ever been cached (or the stored
  /// blob is unreadable — a schema change, a half-written string).
  static Future<NavPointsCacheEntry?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPoints);
      if (raw == null || raw.isEmpty) return null;
      final rows = jsonDecode(raw) as List;
      final points = [
        for (final r in rows) NavPoint.fromJson(Map<String, dynamic>.from(r as Map))
      ];
      final savedAt = DateTime.tryParse(prefs.getString(_kSavedAt) ?? '');
      return NavPointsCacheEntry(points, savedAt);
    } catch (e) {
      debugPrint('NavPointsCache.read: $e');
      return null;
    }
  }

  /// Drop the cache (Settings → clear, or after a map change invalidates poses).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPoints);
      await prefs.remove(_kSavedAt);
    } catch (e) {
      debugPrint('NavPointsCache.clear: $e');
    }
  }
}

/// A cached list plus when it was written, so the UI can say how stale it is.
@immutable
class NavPointsCacheEntry {
  const NavPointsCacheEntry(this.points, this.savedAt);

  final List<NavPoint> points;
  final DateTime? savedAt;
}
