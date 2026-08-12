import 'audio_bridge.dart';
import 'elevenlabs_tts.dart';
import 'openai_tts.dart';
import '../config.dart';

/// Provider-agnostic TTS for the robot's standalone announcements (nav / escort /
/// greeting / check-in). Picks the engine that matches the selected
/// conversational voice (RobotConfig.voiceProvider) so ALL of the robot's speech
/// uses ONE voice — the same engine the visitor is talking to — instead of the
/// conversation being OpenAI while announcements stay on ElevenLabs.
///
/// Drop-in for ElevenLabsTts: `speak()` returns false on failure so callers keep
/// their device-TTS fallback. Both underlying engines read their key/voice LIVE
/// from RobotConfig, so a switch or key push applies on the next utterance.
class RobotTts {
  RobotTts({required AudioBridge audio})
      : _eleven = ElevenLabsTts(
          apiKey: RobotConfig.elevenLabsApiKey,
          voiceId: RobotConfig.elevenLabsVoiceId,
          audio: audio,
        ),
        _openai = OpenAiTts(audio: audio);

  final ElevenLabsTts _eleven;
  final OpenAiTts _openai;

  Future<bool> speak(String text) {
    if (RobotConfig.voiceProvider == RobotConfig.voiceProviderOpenAi) {
      return _openai.speak(text);
    }
    return _eleven.speak(text);
  }

  void dispose() {
    _eleven.dispose();
    _openai.dispose();
  }
}
