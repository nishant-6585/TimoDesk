import 'dart:async';
import 'package:flutter/material.dart';

import 'enroll_screen.dart';
import 'status_screen.dart';
import 'control_screen.dart';
import 'settings_screen.dart';

const _orange = Color(0xFFFF6B35);

/// Feature dashboard (opened from the ambient face). 2×2 real tiles + a disabled
/// placeholder row. Auto-returns to the face after 30s idle, or via back.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _idle;
  static const _idleReturn = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _resetIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  // Restart the 30s idle countdown; on expiry, return to the face.
  void _resetIdle() {
    _idle?.cancel();
    _idle = Timer(_idleReturn, () {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  // Open a sub-screen; pause idle while it's on top, resume on return.
  Future<void> _open(Widget screen) async {
    _idle?.cancel();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _resetIdle();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _resetIdle(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to face',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Timo — Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.4,
                children: [
                  _Tile(icon: Icons.person_add_alt_1, label: 'Enroll Staff',
                      onTap: () => _open(const EnrollScreen())),
                  _Tile(icon: Icons.insights, label: 'Robot Status',
                      onTap: () => _open(const RobotStatusScreen())),
                  _Tile(icon: Icons.sports_esports, label: 'Manual Control',
                      onTap: () => _open(const ManualControlScreen())),
                  _Tile(icon: Icons.settings, label: 'Settings',
                      onTap: () => _open(const SettingsScreen())),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Disabled placeholder row — "coming soon".
            const Row(children: [
              _Placeholder(icon: Icons.record_voice_over, label: 'Voice Q&A'),
              _Placeholder(icon: Icons.payments, label: 'Pay'),
              _Placeholder(icon: Icons.navigation, label: 'Navigate'),
              _Placeholder(icon: Icons.contacts, label: 'Directory'),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 48, color: _orange),
            const SizedBox(height: 14),
            Text(label,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Placeholder({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: 0.4,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF222222)),
          ),
          child: Column(children: [
            Icon(icon, size: 22, color: Colors.white54),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const Text('coming soon', style: TextStyle(fontSize: 8, color: Colors.white30)),
          ]),
        ),
      ),
    );
  }
}
