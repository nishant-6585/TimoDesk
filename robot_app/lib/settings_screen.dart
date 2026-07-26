import 'dart:async';

import 'package:flutter/material.dart';
import 'config.dart';
import 'models/voice_language.dart';
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
  late final TextEditingController _company;
  late final TextEditingController _greetStaff;
  late final TextEditingController _greetVisitor;
  late final TextEditingController _regreetMins;
  late final TextEditingController _gateYaw;
  late final TextEditingController _gateFacePct;
  late final TextEditingController _escortSecs;
  late final TextEditingController _escortText;
  late final TextEditingController _escortLost;
  bool _gateEnabled = RobotConfig.attentionGateEnabled;
  bool _saved = false;

  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _spine = TextEditingController(text: RobotConfig.spineBaseUrl);
    _camera = TextEditingController(text: RobotConfig.cameraBaseUrl);
    _kiosk = TextEditingController(text: RobotConfig.kioskToken);
    _elevenKey = TextEditingController(text: RobotConfig.elevenLabsApiKey);
    _elevenAgent = TextEditingController(text: RobotConfig.elevenLabsAgentId);
    _company = TextEditingController(text: RobotConfig.companyName);
    _greetStaff = TextEditingController(text: RobotConfig.greetStaffTemplate);
    _greetVisitor = TextEditingController(text: RobotConfig.greetVisitorTemplate);
    _regreetMins =
        TextEditingController(text: RobotConfig.regreetMinutes.toString());
    _gateYaw = TextEditingController(
        text: RobotConfig.attentionMaxYawDeg.toStringAsFixed(0));
    _gateFacePct = TextEditingController(
        text: (RobotConfig.attentionMinFaceRatio * 100).toStringAsFixed(0));
    _escortSecs = TextEditingController(
        text: RobotConfig.escortReassureSeconds.toString());
    _escortText = TextEditingController(text: RobotConfig.escortReassureText);
    _escortLost = TextEditingController(text: RobotConfig.escortLostText);
  }

  @override
  void dispose() {
    _spine.dispose();
    _camera.dispose();
    _kiosk.dispose();
    _elevenKey.dispose();
    _elevenAgent.dispose();
    _company.dispose();
    _greetStaff.dispose();
    _greetVisitor.dispose();
    _regreetMins.dispose();
    _gateYaw.dispose();
    _gateFacePct.dispose();
    _escortSecs.dispose();
    _escortText.dispose();
    _escortLost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await RobotConfig.setSpineBaseUrl(_spine.text);
    await RobotConfig.setCameraBaseUrl(_camera.text);
    await RobotConfig.setKioskToken(_kiosk.text);
    await RobotConfig.setElevenLabsApiKey(_elevenKey.text);
    await RobotConfig.setElevenLabsAgentId(_elevenAgent.text);
    await RobotConfig.updateGreetingConfig(
      company: _company.text,
      staffTemplate: _greetStaff.text,
      visitorTemplate: _greetVisitor.text,
      regreetMins:
          int.tryParse(_regreetMins.text.trim()) ?? RobotConfig.regreetMinutes,
      gateEnabled: _gateEnabled,
      gateMaxYawDeg: double.tryParse(_gateYaw.text.trim()) ??
          RobotConfig.attentionMaxYawDeg,
      gateMinFaceRatio: (double.tryParse(_gateFacePct.text.trim()) ??
              RobotConfig.attentionMinFaceRatio * 100) /
          100,
    );
    await RobotConfig.updateEscortConfig(
      reassureSeconds: int.tryParse(_escortSecs.text.trim()) ??
          RobotConfig.escortReassureSeconds,
      reassureText: _escortText.text,
      lostText: _escortLost.text,
    );
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

  /// Live preview of both greeting templates rendered in the active voice
  /// language, so the operator sees exactly what Mikee will say before saving.
  Widget _greetingPreview() {
    final lang = languageForCode(RobotConfig.voiceLanguageCode);
    final staff = lang.renderGreeting(_greetStaff.text,
        name: 'Nishant', company: _company.text);
    final visitor =
        lang.renderGreeting(_greetVisitor.text, company: _company.text);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Preview (${lang.name})',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 8),
        Text('Staff:  “$staff”',
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 4),
        Text('Visitor:  “$visitor”',
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ]),
    );
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
          const Text('GREETINGS',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 12),
          TextField(
            controller: _company,
            style: const TextStyle(fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: _dec('Company name',
                'Replaces the brand in {welcome} — e.g. "Welcome to <company>"'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _greetStaff,
            style: const TextStyle(fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: _dec('Staff greeting (recognised face)',
                'Placeholders: {hello} {name} {welcome} {company}'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _greetVisitor,
            style: const TextStyle(fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: _dec('Visitor greeting (unrecognised face)',
                'Placeholders: {hello} {welcome} {company} — no {name}'),
          ),
          const SizedBox(height: 12),
          _greetingPreview(),
          const SizedBox(height: 20),
          TextField(
            controller: _regreetMins,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            decoration: _dec('Re-greet after (minutes)',
                'How long before the same person is greeted again'),
          ),
          const SizedBox(height: 28),
          const Text('ATTENTION GATE',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 4),
          SwitchListTile(
            value: _gateEnabled,
            onChanged: (v) => setState(() => _gateEnabled = v),
            activeThumbColor: _orange,
            contentPadding: EdgeInsets.zero,
            title: const Text('Greet only when looking at the camera',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: const Text(
                'Off = greet on any detected face (old behaviour). Greetings '
                'never trigger from the person sensor (LIDAR) either way.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _gateYaw,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 16),
                decoration: _dec('Max head turn (°)',
                    'Beyond this = looking away'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _gateFacePct,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 16),
                decoration: _dec('Min face size (% of frame)',
                    'Smaller = person too far away'),
              ),
            ),
          ]),
          const SizedBox(height: 28),
          const Text('ESCORT ("FOLLOW ME")',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 12),
          TextField(
            controller: _escortSecs,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            decoration: _dec('Reassure every (seconds)',
                'Mid-route "stay with me" cadence. 0 = off.'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _escortText,
            style: const TextStyle(fontSize: 16),
            decoration: _dec('Reassurance phrase',
                'Spoken repeatedly while leading a visitor'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _escortLost,
            style: const TextStyle(fontSize: 16),
            decoration: _dec('Lost-visitor phrase (after arrival)',
                'Spoken when nobody appears after arriving. {name} = the point. '
                'Empty = off.'),
          ),
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
