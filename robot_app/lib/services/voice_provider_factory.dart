import '../config.dart';
import 'openai_realtime_agent.dart';
import 'voice_agent.dart';
import 'voice_provider.dart';

/// Build the conversational-voice engine currently selected in RobotConfig.
/// Switching engines = call this again and swap the returned provider (see
/// ambient_face_screen._rebuildVoiceProvider). Defaults to ElevenLabs.
VoiceProvider buildVoiceProvider() {
  if (RobotConfig.voiceProvider == RobotConfig.voiceProviderOpenAi) {
    return OpenAiRealtimeAgent(
      apiKey: RobotConfig.openaiApiKey,
      voice: RobotConfig.openaiVoice,
      languageCode: RobotConfig.voiceLanguageCode,
    );
  }
  return VoiceAgent(
    agentId: RobotConfig.elevenLabsAgentId,
    apiKey: RobotConfig.elevenLabsApiKey,
    languageCode: RobotConfig.voiceLanguageCode,
  );
}
