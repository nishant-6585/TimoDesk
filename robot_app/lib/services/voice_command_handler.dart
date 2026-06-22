import 'package:flutter/material.dart';

/// The robot actions a spoken command can trigger.
enum VoiceCommandKind {
  driveForward,
  driveBack,
  driveLeft,
  driveRight,
  stop,
  resume,
  wave,
  snapshot,
  reset,
  sleep,
  wake,
}

/// A recognized voice command: what to do + how to surface it on the dashboard.
class VoiceCommand {
  const VoiceCommand(this.kind, this.label, this.icon);
  final VoiceCommandKind kind;
  final String label; // shown in the "▶ Executing: …" pill
  final IconData icon;
}

/// Keyword matcher that maps a spoken transcript to a [VoiceCommand].
///
/// On the robot the app drives the chassis/head/arms directly through the
/// native CSJBot bridges (the d-pads do the same), so instead of a SpineClient
/// this hands the matched command to a single [onCommand] dispatcher that the
/// dashboard routes to the Riverpod providers + [RobotGestures]. Matching is
/// substring-based and longest/most-specific patterns are checked first.
class VoiceCommandHandler {
  VoiceCommandHandler(this.onCommand);

  /// Invoked with the matched command (UI thread). No-op when nothing matches.
  final void Function(VoiceCommand command) onCommand;

  // Order matters: more specific phrases first so "emergency stop" / "turn left"
  // win before generic "stop" / "left".
  static const List<(List<String>, VoiceCommandKind, String, IconData)> _rules = [
    (['turn left', 'go left'], VoiceCommandKind.driveLeft, 'turn left', Icons.turn_left_rounded),
    (['turn right', 'go right'], VoiceCommandKind.driveRight, 'turn right', Icons.turn_right_rounded),
    (['go forward', 'move forward', 'move ahead', 'come forward'],
        VoiceCommandKind.driveForward, 'go forward', Icons.arrow_upward_rounded),
    (['go back', 'move back', 'back up', 'reverse'],
        VoiceCommandKind.driveBack, 'go back', Icons.arrow_downward_rounded),
    (['emergency stop', 'stop', 'halt'], VoiceCommandKind.stop, 'stop', Icons.pan_tool_rounded),
    (['resume', 'continue'], VoiceCommandKind.resume, 'resume', Icons.play_arrow_rounded),
    (['wave', 'greet', 'say hello'], VoiceCommandKind.wave, 'wave', Icons.waving_hand_rounded),
    (['snapshot', 'take a picture', 'take a photo'],
        VoiceCommandKind.snapshot, 'snapshot', Icons.photo_camera_rounded),
    (['reset position', 'stand straight', 'reset'],
        VoiceCommandKind.reset, 'reset position', Icons.restart_alt_rounded),
    (['wake up', 'attention'], VoiceCommandKind.wake, 'wake up', Icons.visibility_rounded),
    (['go to sleep', 'sleep', 'rest'], VoiceCommandKind.sleep, 'sleep', Icons.bedtime_rounded),
  ];

  /// Match [transcript] against the keyword table. Returns the command, or null.
  VoiceCommand? match(String transcript) {
    final t = transcript.toLowerCase();
    for (final (phrases, kind, label, icon) in _rules) {
      for (final p in phrases) {
        if (t.contains(p)) return VoiceCommand(kind, label, icon);
      }
    }
    return null;
  }

  /// Parse [transcript] and dispatch the matched command. Returns true if one
  /// was recognized.
  bool handle(String transcript) {
    final cmd = match(transcript);
    if (cmd == null) return false;
    onCommand(cmd);
    return true;
  }
}
