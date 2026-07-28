import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../config.dart';
import 'audio_bridge.dart';

/// One-shot ElevenLabs text-to-speech in the SAME voice as the conversational
/// face agent (same `voiceId`), streamed as 16 kHz mono PCM through the existing
/// speaker path ([AudioBridge.playChunk]). Used by the dashboard action tiles so
/// Mikee speaks canned phrases in his real voice — not the device's Google TTS.
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

  /// Constructor value kept for call-site compatibility; speak() always reads
  /// the CURRENT config so a runtime voice change ("change your voice to…")
  /// applies to every later utterance without rebuilding the callers'
  /// long-lived ElevenLabsTts instances.
  final String voiceId;
  final AudioBridge audio;

  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 8);

  Future<bool> speak(String text) async {
    final liveVoiceId = RobotConfig.elevenLabsVoiceId.isNotEmpty
        ? RobotConfig.elevenLabsVoiceId
        : voiceId;
    if (apiKey.isEmpty || liveVoiceId.isEmpty || text.trim().isEmpty) return false;
    try {
      final uri = Uri.parse(
        'https://api.elevenlabs.io/v1/text-to-speech/$liveVoiceId/stream?output_format=pcm_16000',
      );
      final req = await _client.postUrl(uri);
      req.headers.set('xi-api-key', apiKey);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'text': text,
        // Match the conversational agent so the dashboard voice sounds identical to
        // the face screen: same v3 family (the agent uses eleven_v3_conversational,
        // which is agent-only; eleven_v3 is the closest TTS-accessible model) + the
        // agent's exact voice settings (stability 0.5 / similarity 0.8 / speed 1.0).
        'model_id': 'eleven_v3',
        'voice_settings': {
          'stability': 0.5,
          'similarity_boost': 0.8,
          'speed': 1.0,
        },
      })));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        if (kDebugMode) debugPrint('ElevenLabsTts HTTP ${resp.statusCode}');
        await resp.drain<void>();
        return false;
      }
      // Collect the full PCM, then feed it to the speaker in EVEN-length chunks.
      // The HTTP stream splits at arbitrary byte counts; feeding an odd-length
      // buffer to the 16-bit AudioTrack misaligns every following sample → clicks
      // / static. Buffering and only writing 2-byte-aligned chunks plays clean.
      final acc = BytesBuilder(copy: false);
      await for (final chunk in resp) {
        acc.add(chunk);
      }
      final pcm = acc.takeBytes();
      if (pcm.isEmpty) return false;
      const step = 6400; // 200 ms @ 16 kHz mono 16-bit (even)
      for (var i = 0; i < pcm.length; i += step) {
        final end = (i + step < pcm.length) ? i + step : pcm.length;
        await audio.playChunk(Uint8List.sublistView(pcm, i, end));
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('ElevenLabsTts failed: $e');
      return false;
    }
  }

  void dispose() => _client.close(force: true);
}
