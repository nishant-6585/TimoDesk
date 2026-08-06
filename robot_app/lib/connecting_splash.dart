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

  // Boot animation length: 138 frames @ 25fps (verified against the ANMF
  // frame durations inside the webp).
  static const _animLoop = Duration(milliseconds: 5520);

  String _status = 'Starting Mikee…';

  // Decoding the 1920x1080 138-frame webp takes noticeable time on the chest
  // tablet, so the animation starts well after initState. Anchor the "played
  // through once" clock to the first frame actually delivered, not to boot.
  final _firstFrame = Completer<DateTime>();
  ImageStream? _animStream;
  ImageStreamListener? _animListener;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animStream == null) {
      final stream = const AssetImage('assets/splash_animation.webp')
          .resolve(createLocalImageConfiguration(context));
      _animListener = ImageStreamListener((_, __) {
        if (!_firstFrame.isCompleted) _firstFrame.complete(DateTime.now());
      }, onError: (_, __) {
        if (!_firstFrame.isCompleted) _firstFrame.complete(DateTime.now());
      });
      stream.addListener(_animListener!);
      _animStream = stream;
    }
  }

  @override
  void dispose() {
    if (_animListener != null) _animStream?.removeListener(_animListener!);
    super.dispose();
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

    // Wait for the animation to actually start (hard cap so a broken asset
    // never blocks boot), then hold until it completes a full loop. If the
    // probe outlived the first loop, hold to the NEXT loop boundary so the
    // handoff never cuts the animation mid-play.
    final t0 = await _firstFrame.future
        .timeout(const Duration(seconds: 8), onTimeout: () => DateTime.now());
    final played = DateTime.now().difference(t0);
    final loops = (played.inMilliseconds / _animLoop.inMilliseconds).ceil();
    final end = t0.add(_animLoop * (loops < 1 ? 1 : loops));
    final remain = end.difference(DateTime.now());
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
