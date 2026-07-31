import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'services/audio_bridge.dart';
import 'services/elevenlabs_tts.dart';
import 'services/thinking_filler.dart';

/// Voice Q&A — kiosk front-end for the spine's grounded brain (`POST /ask`).
///
/// The SAME pipeline the ElevenLabs agent uses via its server-tool webhook:
/// FAQ fast-path (exact curated answers) → Claude RAG over the company KB →
/// honest human handoff. Typed question in, answer shown AND spoken in
/// Mikee's voice — so the KB is demoable even without the voice loop.
class VoiceQaScreen extends StatefulWidget {
  const VoiceQaScreen({super.key});

  @override
  State<VoiceQaScreen> createState() => _VoiceQaScreenState();
}

class _VoiceQaScreenState extends State<VoiceQaScreen> {
  static const _bg = Color(0xFF0F0F0F);
  static const _panel = Color(0xFF16161A);
  static const _line = Color(0xFF26262E);
  static const _accent = Color(0xFFFF6B35);
  static const _muted = Color(0xFF8B8B93);

  final _controller = TextEditingController();
  final _audio = AudioBridge();
  late final ElevenLabsTts _tts = ElevenLabsTts(
    apiKey: RobotConfig.elevenLabsApiKey,
    voiceId: RobotConfig.elevenLabsVoiceId,
    audio: _audio,
  );

  bool _busy = false;
  String? _question;
  String? _answer;
  String? _source;
  String? _error;

  static const _examples = [
    'What does xboom do?',
    'What are the office hours?',
    'Where is the restroom?',
    'Who should I contact for a demo?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _controller.text).trim();
    if (q.isEmpty || _busy) return;
    if (preset != null) _controller.text = preset;
    setState(() {
      _busy = true;
      _question = q;
      _answer = null;
      _source = null;
      _error = null;
    });
    // Speak a filler NOW, before the round-trip — the grounded path can take
    // 2-4s and silence reads as a broken robot (blueprint §08). Not awaited:
    // the request must start immediately, and the TTS queue keeps the answer
    // behind the filler anyway.
    final filler = ThinkingFiller.next();
    unawaited(_tts.speak(filler).then((ok) async {
      if (!ok) await _audio.speak(filler);
    }).catchError((_) {/* filler is cosmetic — never block the answer */}));

    try {
      final res = await http
          .post(
            Uri.parse('${RobotConfig.spineBaseUrl}/ask'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${RobotConfig.authToken}',
            },
            body: jsonEncode({'question': q}),
          )
          .timeout(const Duration(seconds: 45));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['ok'] != true) {
        throw Exception(body['reason'] ?? 'HTTP ${res.statusCode}');
      }
      final answer = (body['answer'] ?? '') as String;
      if (!mounted) return;
      setState(() {
        _answer = answer;
        _source = (body['source'] ?? 'kb') as String;
      });
      // Speak it in Mikee's real voice; device TTS as the fallback.
      final ok = await _tts.speak(answer);
      if (!ok) await _audio.speak(answer);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'The knowledge base is not reachable right now ($e). '
            'Check the spine and its API keys.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.psychology_alt_rounded, color: _accent, size: 22),
          const SizedBox(width: 10),
          Text('Ask ${RobotConfig.robotName}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Column(children: [
            // Question input
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  onSubmitted: (_) => _ask(),
                  decoration: InputDecoration(
                    hintText: 'Ask me anything about xboom…',
                    hintStyle: const TextStyle(color: _muted),
                    filled: true,
                    fillColor: _panel,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _line)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _line)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _accent)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 54,
                width: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: _busy ? null : _ask,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            // Example questions — one tap for the demo.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _examples)
                  ActionChip(
                    label: Text(e,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 13)),
                    backgroundColor: _panel,
                    side: const BorderSide(color: _line),
                    onPressed: _busy ? null : () => _ask(e),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            // Answer area
            Expanded(
              child: _error != null
                  ? _messageCard(
                      icon: Icons.cloud_off_rounded,
                      color: const Color(0xFFF59E0B),
                      text: _error!)
                  : _answer != null
                      ? _answerCard()
                      : _messageCard(
                          icon: Icons.record_voice_over_rounded,
                          color: _muted,
                          text:
                              'Ask a question — I answer from the company knowledge '
                              'base and say it out loud.\n\nYou can also just talk '
                              'to me on the face screen.'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _messageCard(
      {required IconData icon, required Color color, required String text}) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _line),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(height: 14),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
        ]),
      ),
    );
  }

  Widget _answerCard() {
    final (srcLabel, srcColor) = switch (_source) {
      'kb' => ('From the company FAQ', const Color(0xFF4ADE80)),
      'claude' => ('From the knowledge base', const Color(0xFF3B82F6)),
      _ => ('Connecting you to a person', const Color(0xFFF59E0B)),
    };
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accent.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('“$_question”',
              style: const TextStyle(
                  color: _muted, fontSize: 14, fontStyle: FontStyle.italic)),
          const SizedBox(height: 14),
          Text(_answer!,
              style: const TextStyle(
                  color: Colors.white, fontSize: 19, height: 1.5)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: srcColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(srcLabel,
                style: TextStyle(color: srcColor, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
