import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'audio_bridge.dart';

/// Standalone OpenAI text-to-speech for the robot's ANNOUNCEMENTS (nav / escort /
/// greeting / check-in). The counterpart to ElevenLabsTts, used when the OpenAI
/// engine is selected so every bit of the robot's speech — conversation AND
/// announcements — uses one consistent voice (and doesn't depend on ElevenLabs
/// credits). Uses the /v1/audio/speech REST API with pcm output (24 kHz),
/// resampled to the robot's 16 kHz speaker, played in even-aligned chunks.
class OpenAiTts {
  OpenAiTts({required this.audio});
  final AudioBridge audio;
  final http.Client _client = http.Client();

  Future<bool> speak(String text) async {
    final key = RobotConfig.openaiApiKey;
    if (key.isEmpty || text.trim().isEmpty) return false;
    try {
      final res = await _client
          .post(
            Uri.parse('https://api.openai.com/v1/audio/speech'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini-tts',
              'voice': RobotConfig.openaiVoice,
              'input': text.trim(),
              'response_format': 'pcm', // 24 kHz 16-bit mono little-endian
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        if (kDebugMode) debugPrint('OpenAiTts HTTP ${res.statusCode}');
        return false;
      }
      final pcm = _resample16(res.bodyBytes, 24000, 16000);
      if (pcm.isEmpty) return false;
      const step = 6400; // 200 ms @ 16 kHz mono 16-bit (even)
      for (var i = 0; i < pcm.length; i += step) {
        final end = (i + step < pcm.length) ? i + step : pcm.length;
        await audio.playChunk(Uint8List.sublistView(pcm, i, end));
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('OpenAiTts failed: $e');
      return false;
    }
  }

  /// Linear-interpolate mono 16-bit LE PCM between sample rates (byte-based, so
  /// it never trips on buffer alignment).
  static Uint8List _resample16(Uint8List input, int inRate, int outRate) {
    if (inRate == outRate || input.length < 4) return input;
    final inN = input.length ~/ 2;
    final outN = (inN * outRate / inRate).floor();
    if (outN <= 0) return Uint8List(0);
    final out = Uint8List(outN * 2);
    final stepR = inRate / outRate;
    for (int i = 0; i < outN; i++) {
      final pos = i * stepR;
      final idx = pos.floor();
      final frac = pos - idx;
      final a = (input[2 * idx] | (input[2 * idx + 1] << 8)).toSigned(16);
      final bIdx = idx + 1 < inN ? idx + 1 : idx;
      final b = (input[2 * bIdx] | (input[2 * bIdx + 1] << 8)).toSigned(16);
      var v = (a + (b - a) * frac).round();
      if (v > 32767) v = 32767;
      if (v < -32768) v = -32768;
      out[2 * i] = v & 0xff;
      out[2 * i + 1] = (v >> 8) & 0xff;
    }
    return out;
  }

  void dispose() => _client.close();
}
