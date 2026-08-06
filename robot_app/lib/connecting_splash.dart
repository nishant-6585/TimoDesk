import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'ambient_face_screen.dart';

/// Branded boot splash that shows the connection-establishing state (like the
/// vendor reception app), then hands off to the ambient face screen. It probes
/// the spine once so the operator sees whether the server is reachable, but
/// NEVER blocks startup — a min display + hard timeout guarantee it proceeds.
class ConnectingSplash extends StatefulWidget {
  const ConnectingSplash({super.key});

  @override
  State<ConnectingSplash> createState() => _ConnectingSplashState();
}

class _ConnectingSplashState extends State<ConnectingSplash> {
  static const _accent = Color(0xFFFF6B35);
  static const _bg = Color(0xFF0F0F0F);
  String _status = 'Starting Mikee…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    if (mounted) setState(() => _status = 'Establishing connection to server…');

    bool ok = false;
    try {
      final res = await http.get(
        Uri.parse('${RobotConfig.spineBaseUrl}/nav-points'),
        headers: {'Authorization': 'Bearer ${RobotConfig.kioskToken}'},
      ).timeout(const Duration(seconds: 6));
      ok = res.statusCode == 200;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() =>
        _status = ok ? 'Connected — starting up' : 'Server not reachable — starting offline');

    // Keep the splash on screen long enough for the boot animation (5.52s,
    // 138 frames @ 25fps) to play through once — it loops if the probe is slow.
    final elapsed = DateTime.now().difference(started);
    final remain = const Duration(milliseconds: 5600) - elapsed;
    if (remain > Duration.zero) await Future.delayed(remain);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AmbientFaceScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fullscreen animated boot splash (1920x1080, loops until handoff).
          Image.asset(
            'assets/splash_animation.webp',
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(_accent)),
                  ),
                  const SizedBox(width: 12),
                  Text(_status,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 6)])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
