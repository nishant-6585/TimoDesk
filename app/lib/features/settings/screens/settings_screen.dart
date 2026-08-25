import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';
import '../../../core/spine_base.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_provider.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _robotIp = defaultRobotIp ?? '';
  String _port = '$robotCameraPort';
  String _signalingServer = 'ws://192.168.1.42:8081';
  String _reconnectTimeout = '5000';
  bool _collisionSafety = true;
  bool _autoSnapshot = false;
  bool _notifications = true;
  String _speed = '0.5x';

  // Robot identity (relayed to the robot app via spine set_config).
  final _robotName = TextEditingController(text: 'Mini');
  final _companyName = TextEditingController(text: 'xboom');
  final _greetVisitor =
      TextEditingController(text: 'Hello! Welcome to xboom!');
  final _greetStaff = TextEditingController();
  final _regreetMins = TextEditingController();

  // Behaviour + escort settings mirrored from the robot's Settings screen.
  // Seeded once from the robot's config_report; edits push back via set_config.
  bool _gateEnabled = true;
  bool _autoOpenMic = false;
  final _gateYaw = TextEditingController();
  final _gateFacePct = TextEditingController();
  final _escortSecs = TextEditingController();
  final _escortText = TextEditingController();
  final _escortLost = TextEditingController();
  bool _behaviorSeeded = false; // seed text fields only once (don't clobber edits)

  // ElevenLabs credentials. The API key is write-only (never fetched back — a
  // blank field is not pushed, so it won't overwrite a saved one). Agent/Voice
  // ids DO sync back from the robot; the key syncs only as a masked status.
  final _elevenApiKey = TextEditingController();
  final _elevenAgentId = TextEditingController();
  final _elevenVoiceId = TextEditingController();
  String _elevenKeyStatus = 'Checking robot…'; // masked key state from the robot

  // Voice engine switch (ElevenLabs ↔ OpenAI Realtime) + OpenAI key (write-only).
  final _openaiApiKey = TextEditingController();
  String _voiceProvider = 'elevenlabs'; // reflects the robot's current engine
  String? _pendingProvider; // engine the user just picked, awaiting robot confirm
  String _openaiKeyStatus = '';

  @override
  void initState() {
    super.initState();
    // Seed from the shared settings provider so the field reflects (and edits)
    // the same robot IP the live camera view consumes.
    _robotIp = ref.read(settingsProvider).robotIp;
    _loadRobotKeys();
  }

  /// Pull the robot's current (masked) ElevenLabs state from the spine so the
  /// admin reflects what's actually on the robot — the robot→admin half of
  /// two-way sync. Agent/Voice ids populate their fields; the API key shows a
  /// masked "set ✓ · …last4" status only (the secret never leaves the robot).
  Future<void> _loadRobotKeys() async {
    try {
      final res = await http
          .get(Uri.parse('$spineHttpBase/robot/config'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return;
      final eleven =
          (jsonDecode(res.body) as Map<String, dynamic>)['eleven'];
      if (eleven is! Map || !mounted) {
        if (mounted) setState(() => _elevenKeyStatus = 'Robot not reporting yet');
        return;
      }
      setState(() {
        final agent = (eleven['eleven_agent_id'] ?? '').toString();
        final voice = (eleven['eleven_voice_id'] ?? '').toString();
        if (agent.isNotEmpty && _elevenAgentId.text.isEmpty) _elevenAgentId.text = agent;
        if (voice.isNotEmpty && _elevenVoiceId.text.isEmpty) _elevenVoiceId.text = voice;
        final isSet = eleven['eleven_api_key_set'] == true;
        final hint = (eleven['eleven_api_key_hint'] ?? '').toString();
        _elevenKeyStatus = isSet
            ? 'On robot: set ✓${hint.isNotEmpty ? ' · …$hint' : ''}'
            : 'On robot: not set';
        // Voice engine + OpenAI state. If the user JUST picked an engine, keep
        // that optimistic selection until the robot's report actually confirms it
        // (a stale report — e.g. robot momentarily offline — must not bounce the
        // toggle back). Adopt the report only when nothing's pending or it matches.
        final prov = (eleven['voice_provider'] ?? '').toString();
        if (prov == 'openai' || prov == 'elevenlabs') {
          if (_pendingProvider == null || prov == _pendingProvider) {
            _voiceProvider = prov;
            _pendingProvider = null;
          }
        }
        final oSet = eleven['openai_api_key_set'] == true;
        final oHint = (eleven['openai_api_key_hint'] ?? '').toString();
        _openaiKeyStatus = oSet
            ? 'On robot: set ✓${oHint.isNotEmpty ? ' · …$oHint' : ''}'
            : 'On robot: not set';
        // Seed the behaviour/identity fields from the robot's actual state,
        // once — later refreshes must not clobber in-progress edits.
        if (!_behaviorSeeded && eleven.containsKey('robot_name')) {
          _behaviorSeeded = true;
          String s(dynamic v) => (v ?? '').toString();
          if (s(eleven['robot_name']).isNotEmpty) {
            _robotName.text = s(eleven['robot_name']);
          }
          if (s(eleven['company_name']).isNotEmpty) {
            _companyName.text = s(eleven['company_name']);
          }
          if (s(eleven['greet_visitor']).isNotEmpty) {
            _greetVisitor.text = s(eleven['greet_visitor']);
          }
          if (s(eleven['greet_staff']).isNotEmpty) {
            _greetStaff.text = s(eleven['greet_staff']);
          }
          if (eleven['regreet_minutes'] is num) {
            _regreetMins.text = (eleven['regreet_minutes'] as num).toInt().toString();
          }
          if (eleven['attention_gate'] is bool) {
            _gateEnabled = eleven['attention_gate'] as bool;
          }
          if (eleven['auto_open_mic'] is bool) {
            _autoOpenMic = eleven['auto_open_mic'] as bool;
          }
          if (eleven['attention_max_yaw_deg'] is num) {
            _gateYaw.text =
                (eleven['attention_max_yaw_deg'] as num).toStringAsFixed(0);
          }
          if (eleven['attention_min_face_ratio'] is num) {
            _gateFacePct.text =
                ((eleven['attention_min_face_ratio'] as num) * 100)
                    .toStringAsFixed(0);
          }
          if (eleven['escort_reassure_seconds'] is num) {
            _escortSecs.text =
                (eleven['escort_reassure_seconds'] as num).toInt().toString();
          }
          if (s(eleven['escort_reassure_text']).isNotEmpty) {
            _escortText.text = s(eleven['escort_reassure_text']);
          }
          _escortLost.text = s(eleven['escort_lost_text']);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _elevenKeyStatus = 'Robot unreachable');
    }
  }

  @override
  void dispose() {
    _robotName.dispose();
    _companyName.dispose();
    _greetVisitor.dispose();
    _greetStaff.dispose();
    _regreetMins.dispose();
    _gateYaw.dispose();
    _gateFacePct.dispose();
    _escortSecs.dispose();
    _escortText.dispose();
    _escortLost.dispose();
    _elevenApiKey.dispose();
    _elevenAgentId.dispose();
    _elevenVoiceId.dispose();
    _openaiApiKey.dispose();
    super.dispose();
  }

  /// Relay robot-side config to the robot app (spine set_config → config_update).
  void _sendConfig(Map<String, dynamic> config) {
    ref.read(spineProvider.notifier).sendIntent({
      'intent': 'set_config',
      'config': config,
    });
  }

  void _saveIdentity() {
    final cfg = <String, dynamic>{
      'robot_name': _robotName.text.trim(),
      'company_name': _companyName.text.trim(),
      'greet_visitor': _greetVisitor.text.trim(),
    };
    if (_greetStaff.text.trim().isNotEmpty) {
      cfg['greet_staff'] = _greetStaff.text.trim();
    }
    final mins = int.tryParse(_regreetMins.text.trim());
    if (mins != null) cfg['regreet_minutes'] = mins;
    _sendConfig(cfg);
    _toast(Icons.check_circle, MikeeColors.success,
        'Sent to robot — applies immediately');
  }

  /// Push the attention-gate + mic behaviour settings to the robot.
  void _saveBehavior() {
    final cfg = <String, dynamic>{
      'attention_gate': _gateEnabled,
      'auto_open_mic': _autoOpenMic,
    };
    final yaw = double.tryParse(_gateYaw.text.trim());
    if (yaw != null) cfg['attention_max_yaw_deg'] = yaw;
    final facePct = double.tryParse(_gateFacePct.text.trim());
    if (facePct != null) cfg['attention_min_face_ratio'] = facePct / 100;
    _sendConfig(cfg);
    _toast(Icons.check_circle, MikeeColors.success,
        'Behaviour pushed to robot — applies immediately');
  }

  /// Push the escort ("follow me") phrases + cadence to the robot.
  void _saveEscort() {
    final cfg = <String, dynamic>{
      // Empty lost-text is meaningful (turns the phrase off) — always send it.
      'escort_lost_text': _escortLost.text.trim(),
    };
    final secs = int.tryParse(_escortSecs.text.trim());
    if (secs != null) cfg['escort_reassure_seconds'] = secs;
    if (_escortText.text.trim().isNotEmpty) {
      cfg['escort_reassure_text'] = _escortText.text.trim();
    }
    _sendConfig(cfg);
    _toast(Icons.check_circle, MikeeColors.success,
        'Escort settings pushed to robot');
  }

  void _saveKeys() {
    // Push only the fields the user filled in — blanks never overwrite a saved
    // credential on the robot (the robot ignores empty values too).
    final cfg = <String, dynamic>{};
    if (_elevenApiKey.text.trim().isNotEmpty) {
      cfg['elevenlabs_api_key'] = _elevenApiKey.text.trim();
    }
    if (_elevenAgentId.text.trim().isNotEmpty) {
      cfg['elevenlabs_agent_id'] = _elevenAgentId.text.trim();
    }
    if (_elevenVoiceId.text.trim().isNotEmpty) {
      cfg['elevenlabs_voice_id'] = _elevenVoiceId.text.trim();
    }
    if (_openaiApiKey.text.trim().isNotEmpty) {
      cfg['openai_api_key'] = _openaiApiKey.text.trim();
    }
    if (cfg.isEmpty) {
      _toast(Icons.info_outline, MikeeColors.warning,
          'Nothing to push — fill a field first');
      return;
    }
    _sendConfig(cfg);
    // Clear the API keys after sending so the secrets aren't left on screen.
    _elevenApiKey.clear();
    _openaiApiKey.clear();
    _toast(Icons.check_circle, MikeeColors.success,
        'Keys pushed to robot — voice applies on next reply');
    // The robot applies + reports its masked state back; re-pull it so the
    // status line confirms the new key's last-4.
    setState(() => _elevenKeyStatus = 'Applying on robot…');
    Future.delayed(const Duration(milliseconds: 1800), _loadRobotKeys);
  }

  /// Flip the live voice engine on the robot immediately (the robot rebuilds its
  /// provider on the next session). One engine runs at a time.
  void _switchProvider(String provider) {
    if (provider == _voiceProvider && _pendingProvider == null) return;
    setState(() {
      _voiceProvider = provider; // optimistic — sticks until robot confirms
      _pendingProvider = provider;
    });
    _sendConfig({'voice_provider': provider});
    _toast(Icons.check_circle, MikeeColors.success,
        'Voice engine → ${provider == 'openai' ? 'OpenAI Realtime' : 'ElevenLabs'} '
        '(applies on next session)');
    // Give the round-trip room (robot applies → reports → spine stores) before
    // confirming; the optimistic value holds until then.
    Future.delayed(const Duration(milliseconds: 3000), _loadRobotKeys);
  }

  void _toast(IconData icon, Color color, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      ]),
      backgroundColor: MikeeColors.cardTop,
      duration: const Duration(seconds: 2),
    ));
  }

  /// Real connection test — checks the robot's actual reachability via spine.
  void _testConnection() {
    final spine = ref.read(spineProvider);
    final online = spine.connected && (spine.status?.online ?? false);
    if (online) {
      _toast(Icons.check_circle, MikeeColors.success,
          'Robot online — spine connected, battery ${spine.status?.battery ?? '?'}%');
    } else if (spine.connected) {
      _toast(Icons.warning_amber_rounded, MikeeColors.warning,
          'Spine connected but robot unreachable — check the robot/Wi-Fi');
    } else {
      _toast(Icons.error_outline, MikeeColors.error,
          'Not connected to spine — check the spine server + robot IP');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.settings, size: 28, color: MikeeColors.primary), const SizedBox(width: 12), Text('Settings', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 4),
              Text('Robot, network, and safety configuration', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
            ]),
            const SizedBox(height: 24),
            // ── ROBOT IDENTITY — relays to the robot app (name/company/greeting).
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
                  border: Border.all(color: MikeeColors.border),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ROBOT IDENTITY',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.12,
                        color: MikeeColors.textSecondary)),
                const SizedBox(height: 4),
                Text('Pushed to the robot instantly — no need to touch its screen.',
                    style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
                const SizedBox(height: 14),
                _IdField('Robot name', _robotName, 'e.g. Mini, Rocky'),
                const SizedBox(height: 12),
                _IdField('Company name', _companyName, 'e.g. xboom'),
                const SizedBox(height: 12),
                _IdField('Visitor greeting', _greetVisitor,
                    'Spoken to visitors on approach — {hello} {welcome} {company}'),
                const SizedBox(height: 12),
                _IdField('Staff greeting (recognised face)', _greetStaff,
                    'Placeholders: {hello} {name} {welcome} {company}'),
                const SizedBox(height: 12),
                _IdField('Re-greet after (minutes)', _regreetMins,
                    'How long before the same person is greeted again'),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _saveIdentity,
                    icon: const Icon(Icons.cloud_upload, size: 16),
                    label: Text('Push to robot',
                        style: GoogleFonts.inter(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: MikeeColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            // ── KEYS & VOICE — ElevenLabs credentials, pushed to the robot.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
                  border: Border.all(color: MikeeColors.border),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('KEYS & VOICE',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.12,
                        color: MikeeColors.textSecondary)),
                const SizedBox(height: 4),
                Text('Credentials are stored on the robot only, never shown back '
                    'here. Leave a field blank to keep what\'s saved.',
                    style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
                const SizedBox(height: 14),
                // Voice engine switch — one runs at a time; flips immediately.
                Text('Voice engine',
                    style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textSecondary)),
                const SizedBox(height: 6),
                Row(children: [
                  _EngineChip('ElevenLabs', _voiceProvider == 'elevenlabs',
                      () => _switchProvider('elevenlabs')),
                  const SizedBox(width: 8),
                  _EngineChip('OpenAI Realtime', _voiceProvider == 'openai',
                      () => _switchProvider('openai')),
                ]),
                const SizedBox(height: 16),
                _IdField('ElevenLabs API key', _elevenApiKey, 'sk_… (enables the spoken voice)',
                    obscure: true),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(
                      _elevenKeyStatus.contains('set ✓')
                          ? Icons.check_circle
                          : Icons.info_outline,
                      size: 13,
                      color: _elevenKeyStatus.contains('set ✓')
                          ? MikeeColors.success
                          : MikeeColors.textMuted),
                  const SizedBox(width: 6),
                  Text(_elevenKeyStatus,
                      style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textSecondary)),
                  const Spacer(),
                  InkWell(
                    onTap: _loadRobotKeys,
                    child: Row(children: [
                      Icon(Icons.refresh, size: 13, color: MikeeColors.textMuted),
                      const SizedBox(width: 3),
                      Text('Refresh',
                          style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                _IdField('Agent ID', _elevenAgentId, 'agent_… (conversational AI)'),
                const SizedBox(height: 12),
                _IdField('Voice ID', _elevenVoiceId, 'e.g. 6AUOG2nbfr0yFEeI0784'),
                const SizedBox(height: 16),
                _IdField('OpenAI API key', _openaiApiKey, 'sk-… (for OpenAI Realtime)',
                    obscure: true),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(
                      _openaiKeyStatus.contains('set ✓')
                          ? Icons.check_circle
                          : Icons.info_outline,
                      size: 13,
                      color: _openaiKeyStatus.contains('set ✓')
                          ? MikeeColors.success
                          : MikeeColors.textMuted),
                  const SizedBox(width: 6),
                  Text(_openaiKeyStatus.isEmpty ? 'OpenAI key' : _openaiKeyStatus,
                      style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textSecondary)),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _saveKeys,
                    icon: const Icon(Icons.key, size: 16),
                    label: Text('Push keys to robot',
                        style: GoogleFonts.inter(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: MikeeColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            // ── GREETING BEHAVIOUR — attention gate + mic, mirrors the robot.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
                  border: Border.all(color: MikeeColors.border),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('GREETING BEHAVIOUR',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.12,
                        color: MikeeColors.textSecondary)),
                const SizedBox(height: 4),
                Text('Mirrors the robot\'s own Settings — pushed instantly.',
                    style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
                const SizedBox(height: 6),
                _SettingRow('Greet only when looking at the camera', _gateEnabled,
                    (v) => setState(() => _gateEnabled = v)),
                _SettingRow('Auto-open mic after greeting', _autoOpenMic,
                    (v) => setState(() => _autoOpenMic = v)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                      child: _IdField('Max head turn (°)', _gateYaw,
                          'Beyond this = looking away')),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _IdField('Min face size (% of frame)', _gateFacePct,
                          'Smaller = too far away')),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _saveBehavior,
                    icon: const Icon(Icons.cloud_upload, size: 16),
                    label: Text('Push to robot',
                        style: GoogleFonts.inter(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: MikeeColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            // ── ESCORT ("FOLLOW ME") — phrases + cadence, mirrors the robot.
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
                  border: Border.all(color: MikeeColors.border),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ESCORT — "FOLLOW ME"',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.12,
                        color: MikeeColors.textSecondary)),
                const SizedBox(height: 14),
                _IdField('Reassure every (seconds)', _escortSecs,
                    'Mid-route "stay with me" cadence — 0 = off'),
                const SizedBox(height: 12),
                _IdField('Reassurance phrase', _escortText,
                    'Spoken repeatedly while leading a visitor'),
                const SizedBox(height: 12),
                _IdField('Lost-visitor phrase (after arrival)', _escortLost,
                    '{name} = the point. Empty = off.'),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _saveEscort,
                    icon: const Icon(Icons.cloud_upload, size: 16),
                    label: Text('Push to robot',
                        style: GoogleFonts.inter(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: MikeeColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            _SettingCard('NETWORK', [
              _SettingField('Robot IP', _robotIp, (v) {
                setState(() => _robotIp = v);
                ref.read(settingsProvider.notifier).setRobotIp(v.trim());
              }),
              _SettingField('Port', _port, (v) => setState(() => _port = v)),
              _SettingField('Signaling Server', _signalingServer, (v) => setState(() => _signalingServer = v)),
              _SettingField('Reconnect timeout', _reconnectTimeout, (v) => setState(() => _reconnectTimeout = v)),
            ], const SizedBox(height: 16), SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(onPressed: _testConnection, icon: const Icon(Icons.wifi, size: 16), label: Text('Test connection', style: GoogleFonts.inter(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))))),
            const SizedBox(height: 20),
            _SafetyCard(
              collisionSafety: _collisionSafety,
              autoSnapshot: _autoSnapshot,
              notifications: _notifications,
              speed: _speed,
              onCollisionChange: (v) {
                setState(() => _collisionSafety = v);
                _sendConfig({'collision_safety': v});
              },
              onSnapshotChange: (v) {
                setState(() => _autoSnapshot = v);
                _sendConfig({'auto_snapshot': v});
              },
              onNotificationsChange: (v) {
                setState(() => _notifications = v);
                _sendConfig({'event_notifications': v});
              },
              onSpeedChange: (v) {
                setState(() => _speed = v);
                // Relay the numeric default speed (0.3/0.5/0.8) to the robot.
                final n = double.tryParse(v.replaceAll('x', '')) ?? 0.5;
                _sendConfig({'default_speed': n});
              },
            ),
            const SizedBox(height: 20),
            _AccountCard(),
          ]),
        ),
      ),
    );
  }
}

/// Labelled text field for the Robot Identity card.
class _IdField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  const _IdField(this.label, this.controller, this.hint, {this.obscure = false});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: GoogleFonts.inter(
              fontSize: 11, color: MikeeColors.textSecondary)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        obscureText: obscure,
        enableSuggestions: !obscure,
        autocorrect: !obscure,
        style: GoogleFonts.inter(fontSize: 14, color: MikeeColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textMuted),
          filled: true,
          fillColor: MikeeColors.inset,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: MikeeColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: MikeeColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: MikeeColors.primary)),
        ),
      ),
    ]);
  }
}

/// A segmented selector chip for the voice-engine switch.
class _EngineChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _EngineChip(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? MikeeColors.primary : MikeeColors.inset,
              border: Border.all(
                  color: active ? MikeeColors.primary : MikeeColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (active) ...[
                const Icon(Icons.check, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: active ? Colors.white : MikeeColors.textSecondary)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final String title;
  final List<Widget> fields;
  final Widget spacing;
  final Widget button;
  const _SettingCard(this.title, this.fields, this.spacing, this.button);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
        const SizedBox(height: 12),
        GridView.count(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 3, children: fields),
        spacing,
        button,
      ]),
    );
  }
}

class _SettingField extends StatefulWidget {
  final String label, initialValue;
  final Function(String) onChanged;
  const _SettingField(this.label, this.initialValue, this.onChanged);
  @override
  State<_SettingField> createState() => _SettingFieldState();
}

class _SettingFieldState extends State<_SettingField> {
  late TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textSecondary, height: 1.0)),
      const SizedBox(height: 4),
      TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: GoogleFonts.jetBrainsMono(fontSize: 12),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: MikeeColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: MikeeColors.primary.withOpacity(0.6), width: 1.5)),
          filled: true,
          fillColor: const Color(0xFF141414),
        ),
      ),
    ]);
  }
}

class _SafetyCard extends StatelessWidget {
  final bool collisionSafety, autoSnapshot, notifications;
  final String speed;
  final Function(bool) onCollisionChange, onSnapshotChange, onNotificationsChange;
  final Function(String) onSpeedChange;

  const _SafetyCard({
    required this.collisionSafety,
    required this.autoSnapshot,
    required this.notifications,
    required this.speed,
    required this.onCollisionChange,
    required this.onSnapshotChange,
    required this.onNotificationsChange,
    required this.onSpeedChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('SAFETY & BEHAVIOR', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
        const SizedBox(height: 16),
        _SettingRow('Collision safety stop', collisionSafety, (v) => onCollisionChange(v)),
        _SettingRow('Auto-snapshot on face detect', autoSnapshot, (v) => onSnapshotChange(v)),
        _SettingRow('Event notifications', notifications, (v) => onNotificationsChange(v)),
        Container(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Default drive speed', style: GoogleFonts.inter(fontSize: 12)), Row(children: ['0.3x', '0.5x', '0.8x'].asMap().entries.map((e) => [Padding(padding: EdgeInsets.only(left: e.key == 0 ? 0 : 8), child: _SpeedChip(e.value, speed == e.value, () => onSpeedChange(e.value)))]).expand((x) => x).toList())])),
      ]),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool) onChanged;
  const _SettingRow(this.label, this.value, this.onChanged);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12)),
        Switch(value: value, onChanged: onChanged, activeColor: MikeeColors.primary),
      ]),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SpeedChip(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Material(color: Colors.transparent, child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: active ? MikeeColors.primary : MikeeColors.inset, border: Border.all(color: active ? MikeeColors.primary : MikeeColors.border), borderRadius: BorderRadius.circular(6)), child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: active ? Colors.white : MikeeColors.textSecondary)))));
  }
}

class _AccountCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]), border: Border.all(color: MikeeColors.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ACCOUNT', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Nishant K.', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)), const SizedBox(height: 2), Text('admin · NK · last login just now', style: GoogleFonts.inter(fontSize: 10, color: MikeeColors.textSecondary))]), TextButton(onPressed: () {}, child: Text('Sign out', style: GoogleFonts.inter(fontSize: 12)))]),
        const SizedBox(height: 16),
        Divider(color: MikeeColors.border, height: 1),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mini', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)), const SizedBox(height: 2), Text('v2.4.1 · xboom · Land Air Water', style: GoogleFonts.inter(fontSize: 10, color: MikeeColors.textSecondary))]), Text('build 2406', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: MikeeColors.textMuted))]),
      ]),
    );
  }
}
