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

/// One external MCP server registered on the spine's plugin platform.
/// Tokens never leave the spine — only `hasToken` comes back.
class McpPlugin {
  final String name;
  final String url;
  final bool enabled;
  final bool hasToken;
  final String? description;

  McpPlugin({
    required this.name,
    required this.url,
    required this.enabled,
    required this.hasToken,
    this.description,
  });

  factory McpPlugin.fromJson(Map<String, dynamic> j) => McpPlugin(
        name: (j['name'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        enabled: (j['enabled'] ?? false) as bool,
        hasToken: (j['has_token'] ?? false) as bool,
        description: j['description'] as String?,
      );
}

final mcpPluginsProvider = FutureProvider.autoDispose<List<McpPlugin>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/mcp/plugins'), headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Failed to load plugins');
  return (data['plugins'] as List)
      .map((e) => McpPlugin.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Register a new MCP server. Token is write-only (spine never returns it).
Future<void> mcpPluginAdd({
  required String name,
  required String url,
  String? authorizationToken,
  String? description,
  bool enabled = true,
}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/mcp/plugins'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'url': url,
            'enabled': enabled,
            if (authorizationToken != null && authorizationToken.isNotEmpty)
              'authorization_token': authorizationToken,
            if (description != null && description.isNotEmpty)
              'description': description,
          }))
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'add failed');
}

Future<void> mcpPluginSetEnabled(String name, bool enabled) async {
  final action = enabled ? 'enable' : 'disable';
  final res = await http
      .post(Uri.parse('$_spineBase/mcp/plugins/${Uri.encodeComponent(name)}/$action'),
          headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? '$action failed');
}

Future<void> mcpPluginRemove(String name) async {
  final res = await http
      .delete(Uri.parse('$_spineBase/mcp/plugins/${Uri.encodeComponent(name)}'),
          headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'remove failed');
}
