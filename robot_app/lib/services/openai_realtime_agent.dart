import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'voice_provider.dart';

/// OpenAI Realtime voice engine — the switchable alternative to [VoiceAgent]
/// (ElevenLabs). Speech-to-speech over one WebSocket: it does STT + reasoning +
/// tool-calling + TTS server-side (gpt-4o-realtime), which is why it tends to
/// hear Indian-accented staff names better than ElevenLabs's ASR.
///
/// Implements the shared [VoiceProvider] contract so the ambient face is engine-
/// agnostic. Two format details it hides from callers:
///  • audio in/out on the wire is 24 kHz pcm16; the robot mic + speaker are
///    16 kHz, so every chunk is resampled 16k→24k (in) and 24k→16k (out);
///  • the action tools (navigate_to / check_in / raise_enquiry / place_order)
///    surface as [VoiceEventKind.toolCall] for the app to run — identical to the
///    ElevenLabs path — while `ask_knowledge_base` is answered in-agent by
///    calling the spine `/ask` (Claude RAG), so Claude stays the knowledge brain.
class OpenAiRealtimeAgent implements VoiceProvider {
  OpenAiRealtimeAgent({
    required this.apiKey,
    required this.voice,
    String languageCode = 'en',
    this.model = 'gpt-realtime',
  }) : _languageCode = languageCode;

  final String apiKey;
  final String voice;
  final String model;

  @override
  String get name => 'OpenAI Realtime';

  static const int _wireRate = 24000; // OpenAI Realtime pcm16 sample rate
  static const int _deviceRate = 16000; // robot mic + AudioTrack playback rate

  String _languageCode;
  @override
  String get languageCode => _languageCode;

  final _events = StreamController<VoiceEvent>.broadcast();
  @override
  Stream<VoiceEvent> get events => _events.stream;

  WebSocket? _channel;
  StreamSubscription? _sub;
  bool _speaking = false;
  int _connectedAtMs = 0;
  static const int _earlyDropMs = 20000;
  final http.Client _http = http.Client();

  String? _pendingContext;

  @override
  bool get isActive => _channel != null;

  final List<Map<String, dynamic>> _transcript = [];
  @override
  List<Map<String, dynamic>> get transcript => List.unmodifiable(_transcript);

  @override
  String get lastAgentText {
    for (var i = _transcript.length - 1; i >= 0; i--) {
      if (_transcript[i]['role'] == 'assistant') {
        return (_transcript[i]['text'] as String?) ?? '';
      }
    }
    return '';
  }

  @override
  void injectGreeting(String context) {
    if (context.isNotEmpty) _pendingContext = context;
  }

  @override
  Future<void> startSession() async {
    if (_channel != null) return;
    if (apiKey.isEmpty) {
      _emit(const VoiceEvent(VoiceEventKind.error,
          text: 'No OpenAI API key', serviceUnavailable: true));
      return;
    }
    _transcript.clear();
    _speaking = false;
    _connectedAtMs = 0;
    try {
      final ws = await WebSocket.connect(
        'wss://api.openai.com/v1/realtime?model=$model',
        // GA Realtime API — NO 'OpenAI-Beta: realtime=v1' header (that selects the
        // retired beta API and the server closes with code 4000).
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 8));
      _channel = ws;
      _connectedAtMs = DateTime.now().millisecondsSinceEpoch;

      // Configure the session (GA schema): instructions + tools, 24 kHz pcm both
      // ways nested under audio.input/output, server-side VAD so the model
      // responds when the visitor stops talking, and whisper transcription so we
      // get the user's text for on-device command matching + logging.
      ws.add(jsonEncode({
        'type': 'session.update',
        'session': {
          'type': 'realtime',
          'instructions': _instructions(),
          'audio': {
            'input': {
              'format': {'type': 'audio/pcm', 'rate': _wireRate},
              'turn_detection': {
                'type': 'server_vad',
                'threshold': 0.5,
                'silence_duration_ms': 500,
              },
              // Pin transcription to the configured language so accented English
              // isn't mis-detected as Hindi (the same drift we fixed on EL).
              'transcription': {'model': 'whisper-1', 'language': _languageCode},
            },
            'output': {
              'format': {'type': 'audio/pcm', 'rate': _wireRate},
              'voice': voice,
            },
          },
          'tools': _tools,
          'tool_choice': 'auto',
        },
      }));

      // One-shot recognised-staff context → a real user turn so the agent opens
      // with a by-name greeting (the instructions interpret STAFF_RECOGNIZED:).
      final ctx = _pendingContext;
      _pendingContext = null;
      if (ctx != null && ctx.isNotEmpty) {
        _sendUserItem(ctx, respond: true);
      }

      _sub = ws.listen(_onMessage, onDone: _onDone, onError: (e) {
        _emit(VoiceEvent(VoiceEventKind.error, text: e.toString()));
        _onDone();
      }, cancelOnError: true);

      _emit(const VoiceEvent(VoiceEventKind.sessionStarted));
    } catch (e) {
      _channel = null;
      _emit(VoiceEvent(VoiceEventKind.error,
          text: 'Could not connect to OpenAI Realtime ($e).',
          serviceUnavailable: true));
    }
  }

  @override
  void sendAudioChunk(Uint8List pcmBytes) {
    final ws = _channel;
    if (ws == null || pcmBytes.isEmpty) return;
    final up = _resamplePcm16(pcmBytes, _deviceRate, _wireRate);
    ws.add(jsonEncode({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(up),
    }));
  }

  @override
  void sendUserText(String text) {
    if (text.trim().isEmpty) return;
    _sendUserItem(text.trim(), respond: true);
  }

  void _sendUserItem(String text, {required bool respond}) {
    final ws = _channel;
    if (ws == null) return;
    ws.add(jsonEncode({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': text}
        ],
      },
    }));
    if (respond) ws.add(jsonEncode({'type': 'response.create'}));
  }

  @override
  void sendToolResult(String toolCallId, String result, {bool isError = false}) {
    final ws = _channel;
    if (ws == null) return;
    // OpenAI carries the outcome back as a function_call_output item keyed by the
    // call_id, then a fresh response so the agent speaks the result.
    ws.add(jsonEncode({
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': toolCallId,
        'output': isError ? 'ERROR: $result' : result,
      },
    }));
    ws.add(jsonEncode({'type': 'response.create'}));
  }

  @override
  Future<void> endSession() async {
    await _closeSocket();
    _emit(const VoiceEvent(VoiceEventKind.sessionEnded));
  }

  @override
  Future<void> switchLanguage(String code) async {
    if (code == _languageCode) return;
    _languageCode = code;
    if (_channel != null) {
      await _closeSocket(); // quiet: _sub cancelled first → no sessionEnded
      await startSession(); // reconnect with the new-language instructions
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'input_audio_buffer.speech_started':
        _speaking = false;
        _emit(const VoiceEvent(VoiceEventKind.userSpeaking));
        return;

      case 'conversation.item.input_audio_transcription.completed':
        // Whisper finished the user's turn → agent is thinking. Surface the text
        // so the ambient screen can run on-device commands against it too.
        final t = msg['transcript'];
        final userText = (t is String && t.trim().isNotEmpty) ? t.trim() : null;
        if (userText != null) {
          _transcript.add({'role': 'user', 'text': userText, 'ts': _nowIso()});
        }
        _emit(VoiceEvent(VoiceEventKind.agentThinking, text: userText));
        return;

      // GA renamed audio events with an `output_` prefix; accept both.
      case 'response.audio.delta':
      case 'response.output_audio.delta':
        final b64 = msg['delta'];
        if (b64 is String && b64.isNotEmpty) {
          final down = _resamplePcm16(base64Decode(b64), _wireRate, _deviceRate);
          if (!_speaking) {
            _speaking = true;
            _emit(const VoiceEvent(VoiceEventKind.agentSpeaking));
          }
          _emit(VoiceEvent(VoiceEventKind.audioChunk,
              audioChunk: down, amplitude: pcmRms(down)));
        }
        return;

      case 'response.audio_transcript.done':
      case 'response.output_audio_transcript.done':
        final t = msg['transcript'];
        if (t is String && t.isNotEmpty) {
          _transcript.add({'role': 'assistant', 'text': t, 'ts': _nowIso()});
        }
        return;

      case 'response.function_call_arguments.done':
        _onFunctionCall(msg);
        return;

      case 'response.output_item.done':
        // GA delivers a completed function call as an output item; map it to the
        // same handler shape (name / call_id / arguments) if that's what it is.
        final item = msg['item'];
        if (item is Map && item['type'] == 'function_call') {
          _onFunctionCall({
            'name': item['name'],
            'call_id': item['call_id'],
            'arguments': item['arguments'],
          });
        }
        return;

      case 'error':
        final err = msg['error'];
        final text = err is Map ? (err['message']?.toString() ?? 'error') : 'error';
        _emit(VoiceEvent(VoiceEventKind.error, text: 'OpenAI Realtime: $text'));
        return;

      default:
        return;
    }
  }

  void _onFunctionCall(Map<String, dynamic> msg) {
    final tool = msg['name'] as String?;
    final callId = msg['call_id'] as String?;
    if (tool == null || callId == null) return;
    Map<String, dynamic> args = const {};
    final raw = msg['arguments'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) args = d.cast<String, dynamic>();
      } catch (_) {}
    }
    // ask_knowledge_base is answered in-agent by the spine (Claude RAG) so the
    // model never invents company facts; the action tools go to the app.
    if (tool == 'ask_knowledge_base') {
      _answerFromKb(callId, (args['question'] ?? '').toString());
      return;
    }
    _emit(VoiceEvent(VoiceEventKind.toolCall,
        toolName: tool, toolCallId: callId, toolParams: args));
  }

  Future<void> _answerFromKb(String callId, String question) async {
    if (question.trim().isEmpty) {
      sendToolResult(callId, 'No question provided.', isError: true);
      return;
    }
    try {
      final res = await _http
          .post(
            Uri.parse('${RobotConfig.spineBaseUrl}/ask'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${RobotConfig.authToken}',
            },
            body: jsonEncode({'question': question}),
          )
          .timeout(const Duration(seconds: 30));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final answer = (body['ok'] == true) ? (body['answer'] ?? '') as String : '';
      sendToolResult(callId,
          answer.isNotEmpty ? answer : 'Let me get someone to help with that.');
    } catch (e) {
      sendToolResult(callId, 'Let me get someone to help with that.', isError: true);
    }
  }

  void _onDone() {
    final code = _channel?.closeCode;
    final elapsed = _connectedAtMs == 0
        ? 1 << 30
        : DateTime.now().millisecondsSinceEpoch - _connectedAtMs;
    final likelyUnavailable = elapsed < _earlyDropMs;
    _closeSocket();
    if (_events.isClosed) return;
    if (likelyUnavailable) {
      _emit(VoiceEvent(VoiceEventKind.error,
          text: 'OpenAI closed the connection'
              '${code != null ? ' (code $code)' : ''}.',
          serviceUnavailable: true));
    }
    _emit(const VoiceEvent(VoiceEventKind.sessionEnded));
  }

  Future<void> _closeSocket() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.close();
    _channel = null;
  }

  void _emit(VoiceEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  void dispose() {
    _closeSocket();
    _http.close();
    _events.close();
  }

  // ── Instructions + tools ─────────────────────────────────────────────────────
  // Kept in sync with docs/elevenlabs_agent_tools.md so both engines behave the
  // same. (Follow-up: source these from the spine so there's one definition.)
  static const Map<String, String> _langNames = {
    'en': 'English', 'hi': 'Hindi', 'ta': 'Tamil', 'te': 'Telugu',
    'kn': 'Kannada', 'ml': 'Malayalam', 'mr': 'Marathi', 'bn': 'Bengali',
    'gu': 'Gujarati', 'pa': 'Punjabi', 'ur': 'Urdu', 'es': 'Spanish',
    'fr': 'French', 'de': 'German', 'ar': 'Arabic', 'zh': 'Chinese', 'ja': 'Japanese',
  };

  String _instructions() {
    final n = RobotConfig.robotName;
    final langName = _langNames[_languageCode] ?? 'English';
    // Force the configured language on EVERY reply — OpenAI Realtime otherwise
    // free-runs and drifts (it was answering in Hindi with English selected).
    final langLine =
        '\n\nLANGUAGE: You MUST speak ONLY in $langName. Even if the visitor '
        'speaks another language, always reply in $langName. Never switch languages.';
    return '''
You are $n, the reception robot at xboom Utilities in India. You are warm, curious, and concise — your words are heard aloud, so speak in short, natural sentences.

You are a MOBILE physical robot at the front desk. You can drive and physically guide visitors to places and staff desks, answer questions about xboom from the knowledge base, greet enrolled staff by name, check visitors in to a host, and log product enquiries and orders.

Tools — always take the real action, never just talk about it. When a request matches a tool, CALL it in the same turn:
- navigate_to — PHYSICALLY DRIVE the visitor somewhere ("take me to…", "go to…", "where is…", a place or a staff desk). Resolve pronouns to a concrete destination first.
- check_in — NOTIFY a staff member that a visitor is here to SEE them (not to be driven — that is navigate_to).
- raise_enquiry — the visitor wants product info / a quote (not buying yet).
- place_order — the visitor wants to buy / order now.
- ask_knowledge_base — for ANY factual question about xboom (products, services, hours, location, people, policies). Pass the question verbatim and answer from the returned text in your own warm voice. NEVER answer company questions from your own memory.

When you receive a message starting with "STAFF_RECOGNIZED:", the text after the colon is a staff member you just recognized — greet them warmly by name, briefly, then ask how you can help. Never reveal you recognized them by camera.

If the knowledge base can't help, say "Let me get someone to help you with that." Keep replies to 2–3 short sentences.$langLine''';
  }

  static const List<Map<String, dynamic>> _tools = [
    {
      'type': 'function',
      'name': 'navigate_to',
      'description':
          'Physically drive/guide the visitor to a location or a staff member\'s desk.',
      'parameters': {
        'type': 'object',
        'properties': {
          'destination': {
            'type': 'string',
            'description':
                'The place or person to go to, e.g. "Reception", "the restroom", or a staff name like "Nishant". Resolve pronouns to the concrete name.',
          }
        },
        'required': ['destination'],
      },
    },
    {
      'type': 'function',
      'name': 'check_in',
      'description':
          'Notify a staff member that a visitor is here to SEE them (announce arrival).',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'The staff member the visitor is here to see.',
          }
        },
        'required': ['host'],
      },
    },
    {
      'type': 'function',
      'name': 'raise_enquiry',
      'description':
          'Log a product ENQUIRY (visitor wants info/quote, not buying yet).',
      'parameters': {
        'type': 'object',
        'properties': {
          'product': {'type': 'string', 'description': 'The product/model asked about.'},
          'customer_name': {'type': 'string', 'description': 'Visitor name if given.'},
          'phone': {'type': 'string', 'description': 'Contact number if given.'},
          'notes': {'type': 'string', 'description': 'Any extra detail.'},
        },
        'required': ['product'],
      },
    },
    {
      'type': 'function',
      'name': 'place_order',
      'description': 'Log a product ORDER (visitor wants to buy now).',
      'parameters': {
        'type': 'object',
        'properties': {
          'product': {'type': 'string', 'description': 'The product/model to order.'},
          'quantity': {'type': 'number', 'description': 'How many units, if stated.'},
          'customer_name': {'type': 'string', 'description': 'Visitor name if given.'},
          'phone': {'type': 'string', 'description': 'Contact number if given.'},
        },
        'required': ['product'],
      },
    },
    {
      'type': 'function',
      'name': 'ask_knowledge_base',
      'description':
          'Answer ANY factual question about xboom from the company knowledge base. Pass the visitor\'s question verbatim.',
      'parameters': {
        'type': 'object',
        'properties': {
          'question': {'type': 'string', 'description': 'The visitor\'s question, verbatim.'},
        },
        'required': ['question'],
      },
    },
  ];

  // ── Audio resampling (linear interpolation, 16-bit LE PCM) ───────────────────
  /// Resample mono 16-bit little-endian PCM between sample rates. Byte-based so
  /// it never trips on buffer alignment from base64Decode.
  static Uint8List _resamplePcm16(Uint8List input, int inRate, int outRate) {
    if (inRate == outRate || input.length < 4) return input;
    final inN = input.length ~/ 2;
    final outN = (inN * outRate / inRate).floor();
    if (outN <= 0) return Uint8List(0);
    final out = Uint8List(outN * 2);
    final step = inRate / outRate;
    for (int i = 0; i < outN; i++) {
      final pos = i * step;
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

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// RMS energy of a 16-bit LE PCM chunk, normalized 0..1 (mouthOpen lip-sync).
  static double pcmRms(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    double sum = 0;
    int n = 0;
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final s = (bytes[i] | (bytes[i + 1] << 8)).toSigned(16);
      sum += s * s;
      n++;
    }
    if (n == 0) return 0;
    return (sqrt(sum / n) / 32768.0).clamp(0.0, 1.0);
  }
}
