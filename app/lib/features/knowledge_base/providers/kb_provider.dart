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

class KbChunk {
  final String id;
  final String? topic;
  final String content;
  final bool isFaq;
  final String? source;
  final String? updatedAt;

  KbChunk({
    required this.id,
    this.topic,
    required this.content,
    required this.isFaq,
    this.source,
    this.updatedAt,
  });

  factory KbChunk.fromJson(Map<String, dynamic> j) => KbChunk(
        id: j['id'].toString(),
        topic: j['topic'] as String?,
        content: (j['content'] ?? '') as String,
        isFaq: (j['is_faq'] ?? false) as bool,
        source: j['source'] as String?,
        updatedAt: j['updated_at'] as String?,
      );
}

/// Which halves of the voice brain are configured — drives the status banner
/// so a half-configured KB is obvious instead of silently broken.
class KbStatus {
  final int chunks;
  final int faqChunks;
  final bool embeddingsReady; // VOYAGE_API_KEY (ingest + search)
  final bool llmReady; // ANTHROPIC_API_KEY (grounded answers)
  final bool voiceGroundingReady; // ELEVENLABS_TOOL_SECRET (agent webhook)
  final bool ready;

  KbStatus({
    required this.chunks,
    required this.faqChunks,
    required this.embeddingsReady,
    required this.llmReady,
    required this.voiceGroundingReady,
    required this.ready,
  });

  factory KbStatus.fromJson(Map<String, dynamic> j) => KbStatus(
        chunks: (j['chunks'] ?? 0) as int,
        faqChunks: (j['faq_chunks'] ?? 0) as int,
        embeddingsReady: (j['embeddings_ready'] ?? false) as bool,
        llmReady: (j['llm_ready'] ?? false) as bool,
        voiceGroundingReady: (j['voice_grounding_ready'] ?? false) as bool,
        ready: (j['ready'] ?? false) as bool,
      );
}

class KbAnswer {
  final String answer;
  final String source; // 'kb' (FAQ fast-path) | 'claude' | 'handoff'
  final double? similarity;

  KbAnswer({required this.answer, required this.source, this.similarity});
}

final kbChunksProvider = FutureProvider.autoDispose<List<KbChunk>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/kb/chunks'), headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'Failed to load KB');
  return (data['chunks'] as List)
      .map((e) => KbChunk.fromJson(e as Map<String, dynamic>))
      .toList();
});

final kbStatusProvider = FutureProvider.autoDispose<KbStatus>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/kb/status'), headers: _headers)
      .timeout(const Duration(seconds: 10));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'status failed');
  return KbStatus.fromJson(data);
});

/// Add a block of text to the KB. Returns the number of chunks stored.
Future<int> kbIngestText(String text, {String? topic, bool isFaq = false}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/kb/ingest'),
          headers: _headers,
          body: jsonEncode({
            'text': text,
            if (topic != null && topic.isNotEmpty) 'topic': topic,
            'is_faq': isFaq,
          }))
      .timeout(const Duration(seconds: 60));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'ingest failed');
  return (data['chunks'] ?? 0) as int;
}

/// Fetch a public web page, strip it to text and ingest it.
Future<int> kbIngestUrl(String url, {String? topic}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/kb/ingest-url'),
          headers: _headers,
          body: jsonEncode({
            'url': url,
            if (topic != null && topic.isNotEmpty) 'topic': topic,
          }))
      .timeout(const Duration(seconds: 90));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'ingest failed');
  return (data['chunks'] ?? 0) as int;
}

/// Upload a document (pdf, docx, txt, md) for ingestion. Bytes go as base64.
Future<int> kbIngestFile(String filename, List<int> bytes, {String? topic}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/kb/ingest-file'),
          headers: _headers,
          body: jsonEncode({
            'filename': filename,
            'file_b64': base64Encode(bytes),
            if (topic != null && topic.isNotEmpty) 'topic': topic,
          }))
      .timeout(const Duration(seconds: 120));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'file ingest failed');
  return (data['chunks'] ?? 0) as int;
}

/// A background website-crawl job on the spine (BFS over same-origin pages).
class KbCrawlJob {
  final String id;
  final String seedUrl;
  final String status; // 'running' | 'done' | 'error'
  final int maxPages;
  final int pagesCrawled;
  final int chunks;
  final List<String> errors;

  KbCrawlJob({
    required this.id,
    required this.seedUrl,
    required this.status,
    required this.maxPages,
    required this.pagesCrawled,
    required this.chunks,
    required this.errors,
  });

  bool get running => status == 'running';

  factory KbCrawlJob.fromJson(Map<String, dynamic> j) => KbCrawlJob(
        id: j['id'].toString(),
        seedUrl: (j['seed_url'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        maxPages: (j['max_pages'] ?? 0) as int,
        pagesCrawled: (j['pages_crawled'] ?? 0) as int,
        chunks: (j['chunks'] ?? 0) as int,
        errors: ((j['errors'] ?? []) as List).map((e) => e.toString()).toList(),
      );
}

final kbCrawlJobsProvider = FutureProvider.autoDispose<List<KbCrawlJob>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/kb/crawl'), headers: _headers)
      .timeout(const Duration(seconds: 10));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'crawl list failed');
  return (data['jobs'] as List)
      .map((e) => KbCrawlJob.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Start a website crawl. Returns the job (poll kbCrawlJobsProvider for progress).
Future<KbCrawlJob> kbCrawlStart(String url, {int? maxPages, String? topic}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/kb/crawl'),
          headers: _headers,
          body: jsonEncode({
            'url': url,
            if (maxPages != null) 'max_pages': maxPages,
            if (topic != null && topic.isNotEmpty) 'topic': topic,
          }))
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'crawl failed to start');
  return KbCrawlJob.fromJson(data['job'] as Map<String, dynamic>);
}

/// An external ("3rd-party") knowledge source, asked only after a local-KB miss.
class KbSource {
  final String name;
  final String url;
  final int priority;
  final bool enabled;
  final bool hasToken;
  final String? description;

  KbSource({
    required this.name,
    required this.url,
    required this.priority,
    required this.enabled,
    required this.hasToken,
    this.description,
  });

  factory KbSource.fromJson(Map<String, dynamic> j) => KbSource(
        name: (j['name'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        priority: (j['priority'] ?? 0) as int,
        enabled: (j['enabled'] ?? false) as bool,
        hasToken: (j['has_token'] ?? false) as bool,
        description: j['description'] as String?,
      );
}

final kbSourcesProvider = FutureProvider.autoDispose<List<KbSource>>((ref) async {
  final res = await http
      .get(Uri.parse('$_spineBase/kb/providers'), headers: _headers)
      .timeout(const Duration(seconds: 10));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'sources failed');
  return (data['providers'] as List)
      .map((e) => KbSource.fromJson(e as Map<String, dynamic>))
      .toList();
});

Future<void> kbSourceAdd({
  required String name,
  required String url,
  String? authorizationToken,
  int? priority,
  String? description,
}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/kb/providers'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'url': url,
            if (authorizationToken != null && authorizationToken.isNotEmpty)
              'authorization_token': authorizationToken,
            if (priority != null) 'priority': priority,
            if (description != null && description.isNotEmpty) 'description': description,
          }))
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'add source failed');
}

Future<void> kbSourceUpdate(String name, {int? priority, bool? enabled}) async {
  final res = await http
      .post(Uri.parse('$_spineBase/kb/providers/${Uri.encodeComponent(name)}'),
          headers: _headers,
          body: jsonEncode({
            if (priority != null) 'priority': priority,
            if (enabled != null) 'enabled': enabled,
          }))
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'update source failed');
}

Future<void> kbSourceRemove(String name) async {
  final res = await http
      .delete(Uri.parse('$_spineBase/kb/providers/${Uri.encodeComponent(name)}'),
          headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'remove source failed');
}

Future<void> kbDeleteChunk(String id) async {
  final res = await http
      .delete(Uri.parse('$_spineBase/kb/chunks/$id'), headers: _headers)
      .timeout(const Duration(seconds: 15));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'delete failed');
}

/// Ask the grounded brain (same pipeline the robot's voice uses).
Future<KbAnswer> kbAsk(String question) async {
  final res = await http
      .post(Uri.parse('$_spineBase/ask'),
          headers: _headers, body: jsonEncode({'question': question}))
      .timeout(const Duration(seconds: 45));
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  if (data['ok'] != true) throw Exception(data['reason'] ?? 'ask failed');
  return KbAnswer(
    answer: (data['answer'] ?? '') as String,
    source: (data['source'] ?? 'kb') as String,
    similarity: (data['similarity'] as num?)?.toDouble(),
  );
}
