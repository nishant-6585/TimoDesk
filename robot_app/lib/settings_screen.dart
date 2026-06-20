import 'package:flutter/material.dart';
import 'config.dart';

const _orange = Color(0xFFFF6B35);

/// Settings dashboard tile — edit + persist spine/camera URLs + kiosk token
/// (RobotConfig). The kiosk token must match spine's KIOSK_TOKEN env for the
/// chest screen to authenticate in production (see HANDOFF go-live item #5).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _spine;
  late final TextEditingController _camera;
  late final TextEditingController _kiosk;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _spine = TextEditingController(text: RobotConfig.spineBaseUrl);
    _camera = TextEditingController(text: RobotConfig.cameraBaseUrl);
    _kiosk = TextEditingController(text: RobotConfig.kioskToken);
  }

  @override
  void dispose() {
    _spine.dispose();
    _camera.dispose();
    _kiosk.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await RobotConfig.setSpineBaseUrl(_spine.text);
    await RobotConfig.setCameraBaseUrl(_camera.text);
    await RobotConfig.setKioskToken(_kiosk.text);
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
          const SizedBox(height: 20),
          TextField(
            controller: _kiosk,
            style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
            decoration: _dec('Kiosk token',
                "Must match spine's KIOSK_TOKEN. Empty = dev bypass only."),
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
