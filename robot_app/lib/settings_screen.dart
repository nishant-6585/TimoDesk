import 'package:flutter/material.dart';
import 'config.dart';
import 'enroll_screen.dart' show kAuthToken;

const _orange = Color(0xFFFF6B35);

/// Settings dashboard tile — edit + persist spine/camera URLs (RobotConfig).
/// Kiosk auth is read-only for now (see HANDOFF go-live: needs an operator login).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _spine;
  late final TextEditingController _camera;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _spine = TextEditingController(text: RobotConfig.spineBaseUrl);
    _camera = TextEditingController(text: RobotConfig.cameraBaseUrl);
  }

  @override
  void dispose() {
    _spine.dispose();
    _camera.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await RobotConfig.setSpineBaseUrl(_spine.text);
    await RobotConfig.setCameraBaseUrl(_camera.text);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved'), backgroundColor: _orange),
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
          const SizedBox(height: 24),
          // Kiosk auth — read-only for now.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kiosk auth token (read-only)',
                  style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(kAuthToken, style: const TextStyle(color: _orange, fontFamily: 'monospace')),
              const SizedBox(height: 6),
              const Text('TODO: production kiosk needs a real Supabase operator login (see HANDOFF).',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
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
