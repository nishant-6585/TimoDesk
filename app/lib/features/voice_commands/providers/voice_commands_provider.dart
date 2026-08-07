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

/// One row of the voice command catalog, served by the spine from the
/// `voice_commands` table. Editing these repoints what the robot recognizes with
/// no APK rebuild.
class VoiceCommand {
  final String id;
  final String intent;
  final String skill; // system | navigation | social | reception | persona
  final String label;
  final String tier; // reflex (on-device) | llm (ElevenLabs)
  final List<String> examplePhrases;
  final bool confirm;
  final bool enabled;
  final int sortOrder;

  VoiceCommand({
    required this.id,
    required this.intent,
    required this.skill,
    required this.label,
    required this.tier,
    required this.examplePhrases,
    required this.confirm,
    required this.enabled,
    required this.sortOrder,
  });

  factory VoiceCommand.fromJson(Map<String, dynamic> j) => VoiceCommand(
        id: (j['id'] ?? '') as String,
        intent: (j['intent'] ?? '') as String,
        skill: (j['skill'] ?? 'system') as String,
        label: (j['label'] ?? '') as String,
        tier: (j['tier'] ?? 'reflex') as String,
        examplePhrases:
            ((j['example_phrases'] ?? const []) as List).map((e) => '$e').toList(),
        confirm: (j['confirm'] ?? false) as bool,
        enabled: (j['enabled'] ?? true) as bool,
        sortOrder: (j['sort_order'] ?? 0) as int,
      );
}

/// The catalog, grouped-friendly (already sorted by sort_order on the spine).
final voiceCommandsProvider =
    FutureProvider.autoDispose<List<VoiceCommand>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/voice-commands'), headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) {
    throw Exception(data['reason'] ?? 'Failed to load voice commands');
  }
  return (data['commands'] as List)
      .map((e) => VoiceCommand.fromJson(e as Map<String, dynamic>))
      .toList();
});

Future<void> voiceCommandAdd({
  required String intent,
  required String label,
  required String skill,
  required List<String> examplePhrases,
  String tier = 'reflex',
  bool confirm = false,
}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/voice-commands'),
          headers: _headers,
          body: jsonEncode({
            'intent': intent,
            'label': label,
            'skill': skill,
            'tier': tier,
            'confirm': confirm,
            'example_phrases': examplePhrases,
          }))
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'add failed');
}

Future<void> voiceCommandPatch(
  String id,
  Map<String, dynamic> patch,
) async {
  final res = await http
      .patch(Uri.parse('$_spineBase/voice-commands/${Uri.encodeComponent(id)}'),
          headers: _headers, body: jsonEncode(patch))
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'update failed');
}

Future<void> voiceCommandRemove(String id) async {
  final res = await http
      .delete(Uri.parse('$_spineBase/voice-commands/${Uri.encodeComponent(id)}'),
          headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'remove failed');
}
