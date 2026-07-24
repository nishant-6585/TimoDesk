import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Voice pipeline events surfaced to the face state machine (#80).
enum VoiceEventKind {
  sessionStarted, // connected + ready
  userSpeaking, // user audio detected → face: listening
  agentThinking, // STT done, LLM processing → face: thinking
  agentSpeaking, // TTS audio arriving → face: speaking
  audioChunk, // raw audio to play (Phase B) + amplitude for lip-sync
  sessionEnded, // conversation finished
  error,
}

class VoiceEvent {
  final VoiceEventKind kind;
  final String? text; // agent response text (for logging)
  final Uint8List? audioChunk; // raw PCM chunk for playback (Phase B)
  final double? amplitude; // 0..1 energy of the chunk (drives mouthOpen)
  // True on an error/sessionEnded that looks like ElevenLabs being unavailable —
  // a failed connect or the server dropping us right after connecting (the
  // signature of an expired subscription / out of credits / disabled key). The UI
  // shows an alert so it's not mistaken for an app bug.
  final bool serviceUnavailable;
  const VoiceEvent(this.kind,
      {this.text, this.audioChunk, this.amplitude, this.serviceUnavailable = false});
}

/// Manages ONE ElevenLabs Conversational AI WebSocket session (#80, Phase A).
///
/// ElevenLabs handles the full STT → LLM (Claude Haiku) → TTS pipeline server-side
/// over a single WS. This client streams mic audio IN (Phase B — CSJBot mic) and
/// maps the server events OUT to [VoiceEvent]s that drive the animated face.
///
/// Uses dart:io WebSocket (no new dependency — same as SpineClient). The
/// `xi-api-key` header is supported by WebSocket.connect on Android.
class VoiceAgent {
  VoiceAgent({required this.agentId, required this.apiKey, String languageCode = 'en'})
      : _languageCode = languageCode;

  final String agentId;
  final String apiKey;

  // ElevenLabs language override sent in conversation_config_override.agent.language.
  // The agent is multilingual (configured in the dashboard); this picks the one
  // it speaks for a session. Defaults to English; persisted via RobotConfig.
  String _languageCode;
  String get languageCode => _languageCode;

  static const String _base =
      'wss://api.elevenlabs.io/v1/convai/conversation?agent_id=';

  final _events = StreamController<VoiceEvent>.broadcast();
  Stream<VoiceEvent> get events => _events.stream;

  WebSocket? _channel;
  StreamSubscription? _sub;

  // One-shot context to send as the first user turn of the NEXT session (e.g.
  // "STAFF_RECOGNIZED: Nishant"), so the agent opens with a personalised greeting.
  // Cleared after it's sent. See [injectGreeting].
  String? _pendingContext;
  bool _speaking = false; // emit agentSpeaking once per turn, not per audio chunk
  int _connectedAtMs = 0; // when the WS connected — to spot early server drops
  bool get isActive => _channel != null;

  // A server-initiated close within this window of connecting is treated as an
  // ElevenLabs availability problem (expired subscription / no credits / bad key),
  // not a normal end-of-conversation.
  static const int _earlyDropMs = 20000;

  // Accumulated turns for /voice/log. Public getter — callers must NOT reach into
  // a private field across files.
  final List<Map<String, dynamic>> _transcript = [];
  List<Map<String, dynamic>> get transcript => List.unmodifiable(_transcript);

  /// Queue a one-shot context line to deliver as the FIRST user turn of the next
  /// session — e.g. `injectGreeting('STAFF_RECOGNIZED: Nishant')` so the agent
  /// greets that staff member by name (the agent's system prompt interprets the
  /// `STAFF_RECOGNIZED:` prefix). No-op silent if the session is already open;
  /// it applies to the NEXT [startSession]. Cleared once sent.
  void injectGreeting(String context) {
    if (context.isNotEmpty) _pendingContext = context;
  }

  Future<void> startSession() async {
    if (_channel != null) return;
    if (agentId.isEmpty) {
      _emit(const VoiceEvent(VoiceEventKind.error, text: 'No ElevenLabs agent id'));
      return;
    }
    _transcript.clear();
    _speaking = false;
    _connectedAtMs = 0;
    try {
      final ws = await WebSocket.connect(
        '$_base$agentId',
        headers: {'xi-api-key': apiKey},
      ).timeout(const Duration(seconds: 8));
      _channel = ws;
      _connectedAtMs = DateTime.now().millisecondsSinceEpoch;

      // Per the ElevenLabs API: initiate the conversation.
      ws.add(jsonEncode({
        'type': 'conversation_initiation_client_data',
        'conversation_config_override': {
          'agent': {
            'prompt': {'prompt': null}, // use the agent's dashboard prompt
            'language': _languageCode,
          },
          // Force 16 kHz mono 16-bit PCM out — exactly what AudioTrack playback +
          // _rms() expect. Without this ElevenLabs sends MP3 and the bytes decode
          // as garbled noise (#80 Phase B critical fix).
          'tts': {'output_format': 'pcm_16000'},
        },
      }));

      // One-shot recognised-staff context → first user turn, so the agent opens
      // with a by-name greeting. Sent right after init (the WS preserves order, so
      // the server processes the initiation first). Cleared so it fires only once.
      final ctx = _pendingContext;
      _pendingContext = null;
      if (ctx != null && ctx.isNotEmpty) {
        ws.add(jsonEncode({'type': 'user_message', 'text': ctx}));
      }

      _sub = ws.listen(_onMessage, onDone: _onDone, onError: (e) {
        _emit(VoiceEvent(VoiceEventKind.error, text: e.toString()));
        _onDone();
      }, cancelOnError: true);

      _emit(const VoiceEvent(VoiceEventKind.sessionStarted));
    } catch (e) {
      _channel = null;
      // Couldn't even open the socket — network down, or ElevenLabs rejected the
      // key (disabled / unpaid). Surface as a service-unavailable alert.
      _emit(VoiceEvent(VoiceEventKind.error,
          text: 'Could not connect to ElevenLabs ($e).', serviceUnavailable: true));
    }
  }

  /// Stream a chunk of 16-bit PCM mic audio to the agent.
  /// Phase B: fed by the CSJBot microphone capture.
  /// Send the user's utterance as TEXT (ElevenLabs convai user_message).
  /// Used when speech-to-text comes from the robot's vendor ASR instead of
  /// streaming raw audio — the agent replies in voice exactly as usual.
  void sendUserText(String text) {
    final ws = _channel;
    if (ws == null || text.trim().isEmpty) return;
    ws.add(jsonEncode({'type': 'user_message', 'text': text.trim()}));
  }

  void sendAudioChunk(Uint8List pcmBytes) {
    final ws = _channel;
    if (ws == null) return;
    ws.add(jsonEncode({'user_audio_chunk': base64Encode(pcmBytes)}));
  }

  Future<void> endSession() async {
    final ws = _channel;
    if (ws == null) return;
    try {
      ws.add(jsonEncode({'type': 'end_of_turn'}));
      // Give the server a moment to flush, then close.
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {}
    await _closeSocket();
    _emit(const VoiceEvent(VoiceEventKind.sessionEnded));
  }

  /// Switch the spoken language. Persisted by the caller (RobotConfig). If a
  /// session is live, it reconnects in place with the new language: the old
  /// socket is closed *quietly* (the subscription is cancelled first, so no
  /// `sessionEnded` fires and the screen keeps the mic running) and a new one is
  /// opened, which emits `sessionStarted` for the UI to react to. If no session
  /// is active, this just sets the language for the next one. Any in-flight reply
  /// is cut off because the socket closes (the screen clears playback on
  /// `sessionStarted`). No-op if the language is unchanged.
  Future<void> switchLanguage(String code) async {
    if (code == _languageCode) return;
    _languageCode = code;
    if (_channel != null) {
      await _closeSocket(); // quiet: _sub cancelled before close → no sessionEnded
      await startSession(); // reconnect with the new language → emits sessionStarted
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return; // ignore non-JSON / binary keepalives
    }
    switch (msg['type']) {
      case 'user_transcript':
        // STT finished → the agent is now thinking. Capture the user turn AND
        // surface the recognized text on the event so the dashboard can run
        // keyword voice-commands against it (the only place the user transcript
        // crosses out of this client).
        _speaking = false;
        final t = _nested(msg, 'user_transcription_event', 'user_transcript');
        final userText = (t is String && t.isNotEmpty) ? t : null;
        if (userText != null) {
          _transcript.add({'role': 'user', 'text': userText, 'ts': _nowIso()});
        }
        _emit(VoiceEvent(VoiceEventKind.agentThinking, text: userText));
        return;

      case 'agent_response':
        // The agent's text reply — captured for logging only. Do NOT change face
        // state here: this text arrives alongside / just before the audio, so
        // emitting "thinking" would flip the face out of speaking mid-sentence.
        // The face goes to "speaking" when the first audio chunk arrives (below),
        // and "thinking" is owned solely by user_transcript (genuine processing gap).
        final t = _nested(msg, 'agent_response_event', 'agent_response');
        if (t is String && t.isNotEmpty) {
          _transcript.add({'role': 'assistant', 'text': t, 'ts': _nowIso()});
        }
        return;

      case 'agent_response_correction':
        // Agent revised its last reply (e.g. after interruption) → patch the tail.
        final t = _nested(msg, 'agent_response_correction_event', 'corrected_agent_response');
        if (t is String && _transcript.isNotEmpty && _transcript.last['role'] == 'assistant') {
          _transcript.last['text'] = t;
        }
        return;

      case 'audio':
        final b64 = _nested(msg, 'audio_event', 'audio_base_64') ??
            _nested(msg, 'audio_event', 'audio_base64');
        if (b64 is String && b64.isNotEmpty) {
          final bytes = base64Decode(b64);
          // Enter "speaking" once per turn, not on every chunk.
          if (!_speaking) {
            _speaking = true;
            _emit(const VoiceEvent(VoiceEventKind.agentSpeaking));
          }
          _emit(VoiceEvent(
            VoiceEventKind.audioChunk,
            audioChunk: bytes,
            amplitude: _rms(bytes),
          ));
        }
        return;

      case 'interruption':
        _speaking = false;
        _emit(const VoiceEvent(VoiceEventKind.userSpeaking));
        return;

      case 'ping':
        // Keepalive — reply so the server doesn't drop us.
        final id = _nested(msg, 'ping_event', 'event_id');
        _channel?.add(jsonEncode({'type': 'pong', 'event_id': id}));
        return;

      default:
        return;
    }
  }

  void _onDone() {
    // Reaches here only on a SERVER-initiated close (endSession/switchLanguage
    // cancel the subscription before closing, so this callback doesn't fire for
    // our own closes). If it happens right after connecting, it's almost always
    // ElevenLabs out of credits / subscription expired / key disabled — flag it.
    final code = _channel?.closeCode;
    final reason = _channel?.closeReason;
    final elapsed = _connectedAtMs == 0
        ? 1 << 30
        : DateTime.now().millisecondsSinceEpoch - _connectedAtMs;
    final likelyUnavailable = elapsed < _earlyDropMs;
    _closeSocket();
    if (_events.isClosed) return;
    if (likelyUnavailable) {
      _emit(VoiceEvent(VoiceEventKind.error,
          text: 'ElevenLabs closed the connection'
              '${code != null ? ' (code $code'
                  '${reason != null && reason.isNotEmpty ? ', $reason' : ''})' : ''}.',
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

  void dispose() {
    _closeSocket();
    _events.close();
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  // Safely read msg[outer][inner] without throwing on shape drift.
  dynamic _nested(Map<String, dynamic> msg, String outer, String inner) {
    final o = msg[outer];
    if (o is Map) return o[inner];
    return null;
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  double _rms(Uint8List bytes) => pcmRms(bytes);

  /// RMS energy of a 16-bit little-endian PCM chunk, normalized 0..1. A cheap
  /// audio-amplitude estimate — drives TTS mouthOpen lip-sync AND the mic-level
  /// "listening" meter in the UI.
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
