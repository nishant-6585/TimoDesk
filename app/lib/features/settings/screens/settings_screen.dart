import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _robotIp = defaultRobotIp;
  String _port = '$robotCameraPort';
  String _signalingServer = 'ws://192.168.1.42:8081';
  String _reconnectTimeout = '5000';
  bool _collisionSafety = true;
  bool _autoSnapshot = false;
  bool _notifications = true;
  String _speed = '0.5x';

  @override
  void initState() {
    super.initState();
    // Seed from the shared settings provider so the field reflects (and edits)
    // the same robot IP the live camera view consumes.
    _robotIp = ref.read(settingsProvider).robotIp;
  }

  void _testConnection() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [Icon(Icons.check_circle, color: MikeeColors.success, size: 20), const SizedBox(width: 12), Text('Connection successful', style: GoogleFonts.inter(fontSize: 13))]),
        backgroundColor: MikeeColors.cardTop,
        duration: const Duration(seconds: 2),
      ),
    );
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
              onCollisionChange: (v) => setState(() => _collisionSafety = v),
              onSnapshotChange: (v) => setState(() => _autoSnapshot = v),
              onNotificationsChange: (v) => setState(() => _notifications = v),
              onSpeedChange: (v) => setState(() => _speed = v),
            ),
            const SizedBox(height: 20),
            _AccountCard(),
          ]),
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
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mikee', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)), const SizedBox(height: 2), Text('v2.4.1 · xboom · Land Air Water', style: GoogleFonts.inter(fontSize: 10, color: MikeeColors.textSecondary))]), Text('build 2406', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: MikeeColors.textMuted))]),
      ]),
    );
  }
}
