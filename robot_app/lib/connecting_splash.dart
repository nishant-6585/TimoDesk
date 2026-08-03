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

    // Keep the splash on screen a minimum time so it reads as intentional.
    final elapsed = DateTime.now().difference(started);
    final remain = const Duration(milliseconds: 1600) - elapsed;
    if (remain > Duration.zero) await Future.delayed(remain);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AmbientFaceScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/xboom_logo.png', width: 160, height: 160),
            const SizedBox(height: 28),
            const Text(
              'Mikee',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            const Text('Reception Robot · xboom',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 40),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(_accent)),
            ),
            const SizedBox(height: 18),
            Text(_status,
                style: const TextStyle(color: Colors.white60, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
