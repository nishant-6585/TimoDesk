import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'ambient_face_screen.dart';
import 'splash_animation.dart';

/// Branded boot splash: plays the animated brand intro while probing the spine
/// once so the operator sees whether the server is reachable. Hands off to the
/// ambient face screen only after BOTH the probe settled AND the animation has
/// played through once (SplashAnimationPlayer's completion callback — never a
/// wall-clock guess). Neither wait can block startup: the probe has its own
/// timeout and a broken animation asset completes immediately.
class ConnectingSplash extends StatefulWidget {
  const ConnectingSplash({super.key});

  @override
  State<ConnectingSplash> createState() => _ConnectingSplashState();
}

class _ConnectingSplashState extends State<ConnectingSplash> {
  static const _accent = Color(0xFFFF6B35);

  String _status = 'Starting Mikee…';
  final _playedOnce = Completer<void>();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
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

    // Let the animation finish its first full pass. Hard cap well above the
    // nominal 5.52s so a pathologically slow decode still can't wedge boot.
    try {
      await _playedOnce.future.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      // proceed anyway
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AmbientFaceScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SplashAnimationPlayer(onCompletedOnce: () {
            if (!_playedOnce.isCompleted) _playedOnce.complete();
          }),
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
