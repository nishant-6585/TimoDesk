import 'dart:async';

import 'package:flutter/material.dart';
import 'config.dart';
import 'services/face_enroll.dart';
import 'services/voice_agent.dart';

const _orange = Color(0xFFFF6B35);

/// Settings dashboard tile — edit + persist spine/camera URLs, kiosk token, and
/// the ElevenLabs voice credentials (RobotConfig). The kiosk token must match
/// spine's KIOSK_TOKEN for the chest screen to authenticate in production
/// (HANDOFF go-live item #5). The ElevenLabs agent (LLM/voice/KB/prompt) is
/// configured in the ElevenLabs dashboard — here we only store the API key + id.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _spine;
  late final TextEditingController _camera;
  late final TextEditingController _kiosk;
  late final TextEditingController _elevenKey;
  late final TextEditingController _elevenAgent;
  late final TextEditingController _enrollName;
  bool _saved = false;

  bool _testing = false;
  String? _testResult;

  bool _enrolling = false;
  String? _enrollResult;

  @override
  void initState() {
    super.initState();
    _spine = TextEditingController(text: RobotConfig.spineBaseUrl);
    _camera = TextEditingController(text: RobotConfig.cameraBaseUrl);
    _kiosk = TextEditingController(text: RobotConfig.kioskToken);
    _elevenKey = TextEditingController(text: RobotConfig.elevenLabsApiKey);
    _elevenAgent = TextEditingController(text: RobotConfig.elevenLabsAgentId);
    _enrollName = TextEditingController();
  }

  @override
  void dispose() {
    _spine.dispose();
    _camera.dispose();
    _kiosk.dispose();
    _elevenKey.dispose();
    _elevenAgent.dispose();
    _enrollName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await RobotConfig.setSpineBaseUrl(_spine.text);
    await RobotConfig.setCameraBaseUrl(_camera.text);
    await RobotConfig.setKioskToken(_kiosk.text);
    await RobotConfig.setElevenLabsApiKey(_elevenKey.text);
    await RobotConfig.setElevenLabsAgentId(_elevenAgent.text);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved'), backgroundColor: _orange),
    );
  }

  /// Open + immediately close an ElevenLabs session to confirm the credentials
  /// work off-robot (no mic needed). Uses the CURRENT field values.
  Future<void> _testVoice() async {
    final agent = VoiceAgent(
      agentId: _elevenAgent.text.trim(),
      apiKey: _elevenKey.text.trim(),
    );
    setState(() {
      _testing = true;
      _testResult = null;
    });
    String result;
    StreamSubscription? sub;
    try {
      final done = Completer<String>();
      sub = agent.events.listen((e) {
        if (done.isCompleted) return;
        if (e.kind == VoiceEventKind.sessionStarted) done.complete('Connected ✓');
        if (e.kind == VoiceEventKind.error) {
          done.complete('Failed: ${e.text ?? 'unknown'}');
        }
      });
      await agent.startSession();
      result = await done.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => 'Failed: timed out',
      );
    } catch (e) {
      result = 'Failed: $e';
    } finally {
      await sub?.cancel();
      await agent.endSession();
      agent.dispose();
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _enroll() async {
    final name = _enrollName.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a staff name first')),
      );
      return;
    }
    setState(() {
      _enrolling = true;
      _enrollResult = null;
    });
    final ok = await FaceEnroll.saveFace(name);
    if (!mounted) return;
    setState(() {
      _enrolling = false;
      _enrollResult = ok ? 'Enrolled "$name" ✓' : 'Enrollment failed — ensure face is visible';
    });
    if (ok) _enrollName.clear();
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        helperText: hint,
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final testOk = _testResult?.startsWith('Connected') ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A1A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _spine, style: const TextStyle(fontSize: 16),
              decoration: _dec('Spine base URL', 'Where spine runs — used by enrollment + check-face')),
          const SizedBox(height: 20),
          TextField(controller: _camera, style: const TextStyle(fontSize: 16),
              decoration: _dec('Camera base URL', "The robot's own MJPEG/snapshot server")),
          const SizedBox(height: 20),
          TextField(
            controller: _kiosk,
            style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
            decoration: _dec('Kiosk token',
                "Must match spine's KIOSK_TOKEN. Empty = dev bypass only."),
          ),
          const SizedBox(height: 28),
          const Text('VOICE (#80 — ElevenLabs)',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 12),
          TextField(
            controller: _elevenKey,
            obscureText: true,
            style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
            decoration: _dec('ElevenLabs API key', 'xi-api-key from elevenlabs.io'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _elevenAgent,
            style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
            decoration: _dec('ElevenLabs Agent ID', 'Conversational AI agent id'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _testing ? null : _testVoice,
              icon: _testing
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Test voice agent'),
            ),
            const SizedBox(width: 12),
            if (_testResult != null)
              Expanded(
                child: Text(
                  _testResult!,
                  style: TextStyle(
                      color: testOk ? const Color(0xFF4ADE80) : Colors.redAccent,
                      fontSize: 13),
                ),
              ),
          ]),
          const SizedBox(height: 28),
          const Text('STAFF FACE ENROLLMENT',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(
            'Stand the staff member in front of the robot camera, enter their name, then tap Enroll. '
            'The robot captures and stores the face on-device. Recognised staff will be greeted by name.',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _enrollName,
            style: const TextStyle(fontSize: 16),
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Staff name', 'e.g. Nishant — used in the greeting'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton.icon(
              onPressed: _enrolling ? null : _enroll,
              icon: _enrolling
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.face_retouching_natural),
              label: Text(_enrolling ? 'Enrolling…' : 'Enroll Face'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            ),
            const SizedBox(width: 12),
            if (_enrollResult != null)
              Expanded(
                child: Text(
                  _enrollResult!,
                  style: TextStyle(
                    color: _enrollResult!.endsWith('✓')
                        ? const Color(0xFF4ADE80)
                        : Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _save,
            icon: Icon(_saved ? Icons.check : Icons.save),
            label: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            style: FilledButton.styleFrom(
                backgroundColor: _orange, padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ]),
      ),
    );
  }
}
