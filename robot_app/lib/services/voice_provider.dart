import 'dart:typed_data';

/// Voice pipeline events surfaced to the face state machine (#80). Shared by
/// every [VoiceProvider] implementation (ElevenLabs, OpenAI Realtime) so the
/// ambient face + dashboard react identically regardless of which engine is live.
enum VoiceEventKind {
  sessionStarted, // connected + ready
  userSpeaking, // user audio detected → face: listening
  agentThinking, // STT done, LLM processing → face: thinking
  agentSpeaking, // TTS audio arriving → face: speaking
  audioChunk, // raw audio to play + amplitude for lip-sync
  toolCall, // the agent invoked a tool (navigate_to, check_in, …)
  sessionEnded, // conversation finished
  error,
}

class VoiceEvent {
  final VoiceEventKind kind;
  final String? text; // agent/user text (for logging / on-device command match)
  final Uint8List? audioChunk; // raw 16 kHz mono 16-bit PCM chunk for playback
  final double? amplitude; // 0..1 energy of the chunk (drives mouthOpen)
  // True on an error/sessionEnded that looks like the voice service being
  // unavailable — a failed connect or the server dropping us right after
  // connecting (expired subscription / out of credits / disabled key). The UI
  // shows an alert so it's not mistaken for an app bug.
  final bool serviceUnavailable;
  // Tool call (kind == toolCall): the LLM decided to invoke one of the agent's
  // configured tools. The app runs it locally and returns a result via
  // [VoiceProvider.sendToolResult].
  final String? toolName;
  final Map<String, dynamic>? toolParams;
  final String? toolCallId;
  const VoiceEvent(this.kind,
      {this.text,
      this.audioChunk,
      this.amplitude,
      this.serviceUnavailable = false,
      this.toolName,
      this.toolParams,
      this.toolCallId});
}

/// A pluggable conversational-voice engine. One implementation is live at a
/// time, chosen by `RobotConfig.voiceProvider` and switchable from Settings
/// (robot) or the admin app. The ambient face talks to THIS interface only, so
/// swapping ElevenLabs ↔ OpenAI Realtime needs no change above this line.
///
/// Contract for every implementation:
/// - audio in/out is 16 kHz mono 16-bit PCM (resample internally if the wire
///   format differs, e.g. OpenAI Realtime's 24 kHz);
/// - tool calls surface as [VoiceEventKind.toolCall] with a stable
///   `toolCallId`, and results go back via [sendToolResult];
/// - a server drop shortly after connecting sets `serviceUnavailable` so the UI
///   can flag "out of credits / bad key" rather than a normal end.
abstract class VoiceProvider {
  /// Human-facing engine label for logs / Settings (e.g. "ElevenLabs").
  String get name;

  Stream<VoiceEvent> get events;

  /// A session (WebSocket) is currently open.
  bool get isActive;

  /// The spoken-language code the next/current session uses (e.g. 'en', 'hi').
  String get languageCode;

  /// Rolling {role,text,ts} turns for /voice/log + the barge-in echo guard.
  List<Map<String, dynamic>> get transcript;

  /// Most recent assistant reply text ('' if none) — used by the barge-in gate
  /// to reject the vendor CAE's echo of the robot's own voice.
  String get lastAgentText;

  /// Open the conversation socket. No-op if one is already open.
  Future<void> startSession();

  /// End the conversation and close the socket (emits sessionEnded).
  Future<void> endSession();

  /// Stream a chunk of 16 kHz mono 16-bit PCM mic audio to the engine.
  void sendAudioChunk(Uint8List pcmBytes);

  /// Send the user's utterance as TEXT (used when the transcript comes from the
  /// vendor ASR instead of streaming audio — barge-in / half-duplex path).
  void sendUserText(String text);

  /// Reply to a tool call so the agent's turn isn't left hanging.
  void sendToolResult(String toolCallId, String result, {bool isError});

  /// Switch the spoken language, reconnecting in place if a session is live.
  Future<void> switchLanguage(String code);

  /// Queue a one-shot context line delivered as the FIRST user turn of the next
  /// session (e.g. "STAFF_RECOGNIZED: Nishant" → a by-name greeting).
  void injectGreeting(String context);

  void dispose();
}
