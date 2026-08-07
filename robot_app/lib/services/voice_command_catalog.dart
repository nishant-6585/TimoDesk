import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'intent_registry.dart';

/// Fetches the voice command catalog from the spine (GET /voice-commands) and
/// builds the on-device [IntentRegistry] from it — so enabling / disabling a
/// command in the Admin "Voice Commands" screen changes what the robot
/// recognizes with NO rebuild.
///
/// Offline-safe: any failure (spine down, timeout, bad body) falls back to the
/// hardcoded [IntentRegistry.standard]. The safety/offline reflex commands
/// (stop, dock, saved-points) must keep working without the network, so we never
/// end up with an empty registry.
class VoiceCommandCatalog {
  static Uri _url() => Uri.parse('${RobotConfig.spineBaseUrl}/voice-commands');
  static Map<String, String> get _headers =>
      {'Authorization': 'Bearer ${RobotConfig.kioskToken}'};

  /// Fetch the catalog rows, or `[]` on any failure.
  static Future<List<CatalogCommand>> fetch() async {
    try {
      final res =
          await http.get(_url(), headers: _headers).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) return const [];
      return (data['commands'] as List)
          .map((e) => CatalogCommand.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Build the registry from the spine catalog; offline → the hardcoded set.
  static Future<IntentRegistry> load() async {
    final rows = await fetch();
    return rows.isEmpty ? IntentRegistry.standard : IntentRegistry.fromCatalog(rows);
  }
}

/// The registry the ambient-face voice dispatch matches against. Kept alive for
/// the session; `ref.invalidate(intentRegistryProvider)` re-fetches after an
/// admin edit. While it resolves (or if the spine is slow), callers should fall
/// back to [IntentRegistry.standard] so the reflex commands never go dead.
final intentRegistryProvider = FutureProvider<IntentRegistry>((ref) async {
  return VoiceCommandCatalog.load();
});
