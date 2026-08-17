/// Single-speaker arbiter — "one agent voice at a time".
///
/// The robot has more than one thing that can drive the speaker: the switchable
/// conversation agent (ElevenLabs / OpenAI, via [VoiceProvider]) and the robot's
/// own standalone announcements (nav "follow me", escort reassurance, arrival)
/// spoken through [RobotTts]. With no coordination these overlap — the escort was
/// chanting "please stay with me" while the OpenAI agent was mid-reply, so the
/// visitor heard two voices at once.
///
/// [agentActive] is the one fact every announcement checks before it speaks: a
/// conversation-agent session currently owns the speaker (open session, or the
/// agent is mid-utterance). While it's true, standalone announcements stay
/// silent — the live conversation wins. (A conversation can't start *over* an
/// escort separately: greetings are already gated on `navigatingTo == null`.)
///
/// Deliberately tiny global process state (not Riverpod): the producers live in
/// different layers (a StreamController agent, a Riverpod nav provider, a screen)
/// and all need a cheap synchronous read on the hot path.
class VoiceArbiter {
  VoiceArbiter._();

  static bool agentActive = false;
}
