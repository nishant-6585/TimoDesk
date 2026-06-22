import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import 'audio_bridge.dart';

/// One-shot ElevenLabs text-to-speech in the SAME voice as the conversational
/// face agent (same `voiceId`), streamed as 16 kHz mono PCM through the existing
/// speaker path ([AudioBridge.playChunk]). Used by the dashboard action tiles so
/// Timo speaks canned phrases in his real voice — not the device's Google TTS.
///
/// Returns `true` if audio played, `false` on any failure (no key/voice, network,
/// non-200) so the caller can fall back to the on-device TTS.
class ElevenLabsTts {
  ElevenLabsTts({
    required this.apiKey,
    required this.voiceId,
    required this.audio,
  });

  final String apiKey;
  final String voiceId;
  final AudioBridge audio;

  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

  Future<bool> speak(String text) async {
    if (apiKey.isEmpty || voiceId.isEmpty || text.trim().isEmpty) return false;
    try {
      final uri = Uri.parse(
        'https://api.elevenlabs.io/v1/text-to-speech/$voiceId/stream?output_format=pcm_16000',
      );
      final req = await _client.postUrl(uri);
      req.headers.set('xi-api-key', apiKey);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'text': text,
        // Fast, low-latency model for short phrases; voice timbre comes from voiceId.
        'model_id': 'eleven_flash_v2_5',
      })));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('ElevenLabsTts HTTP ${resp.statusCode}');
        await resp.drain<void>();
        return false;
      }
      // Stream raw PCM straight to the speaker (AudioTrack buffers it).
      var played = false;
      await for (final chunk in resp) {
        if (chunk.isEmpty) continue;
        await audio.playChunk(Uint8List.fromList(chunk));
        played = true;
      }
      return played;
    } catch (e) {
      if (kDebugMode) debugPrint('ElevenLabsTts failed: $e');
      return false;
    }
  }

  void dispose() => _client.close(force: true);
}
