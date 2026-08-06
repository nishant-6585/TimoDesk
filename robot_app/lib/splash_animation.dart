import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Frame-driven player for the boot animation (assets/splash_animation.webp,
/// 138 frames @ 40ms).
///
/// Image.asset's built-in animation is fire-and-forget: it exposes no signal
/// for "one full pass has been shown", which made the splash hand off to the
/// face screen mid-play on slow decodes. Driving ui.Codec manually gives an
/// exact completion callback (same guarantee a Lottie controller would give,
/// but without converting the raster frames to a fake-vector Lottie).
class SplashAnimation {
  SplashAnimation._();
  static final SplashAnimation instance = SplashAnimation._();

  Future<ui.Codec?>? _codecFuture;

  /// Starts asset load + codec setup. Called from main() BEFORE runApp so the
  /// decode overlaps engine/app init instead of adding to on-screen blank time.
  Future<ui.Codec?> preload() {
    return _codecFuture ??= () async {
      try {
        final bytes = await rootBundle.load('assets/splash_animation.webp');
        return await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      } catch (e) {
        debugPrint('[SplashAnimation] preload failed: $e');
        return null;
      }
    }();
  }
}

/// Renders the animation fullscreen. Plays through once, fires
/// [onCompletedOnce] after the LAST frame has been displayed for its full
/// duration, then keeps looping (the codec wraps around) until disposed —
/// so a slow spine probe never shows a frozen frame.
///
/// A broken/missing asset fires [onCompletedOnce] immediately: the splash
/// must never block boot.
class SplashAnimationPlayer extends StatefulWidget {
  const SplashAnimationPlayer({super.key, required this.onCompletedOnce});

  final VoidCallback onCompletedOnce;

  @override
  State<SplashAnimationPlayer> createState() => _SplashAnimationPlayerState();
}

class _SplashAnimationPlayerState extends State<SplashAnimationPlayer> {
  ui.Image? _frame;
  int _shown = 0;
  bool _completedOnce = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _run() async {
    ui.Codec? codec;
    try {
      codec = await SplashAnimation.instance
          .preload()
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      codec = null;
    }
    if (_disposed) return;
    if (codec == null || codec.frameCount == 0) {
      _finishOnce();
      return;
    }

    final frameCount = codec.frameCount;
    while (!_disposed) {
      ui.FrameInfo info;
      try {
        info = await codec.getNextFrame();
      } catch (e) {
        debugPrint('[SplashAnimation] getNextFrame failed: $e');
        _finishOnce();
        return;
      }
      if (_disposed) return;
      setState(() => _frame = info.image);
      _shown++;
      final hold = info.duration == Duration.zero
          ? const Duration(milliseconds: 40)
          : info.duration;
      await Future.delayed(hold);
      if (_shown >= frameCount) _finishOnce();
    }
  }

  void _finishOnce() {
    if (_completedOnce) return;
    _completedOnce = true;
    widget.onCompletedOnce();
  }

  @override
  Widget build(BuildContext context) {
    // Black until the first frame lands (the intro frames are near-black
    // anyway, so this reads as part of the animation).
    if (_frame == null) return const ColoredBox(color: Colors.black);
    return SizedBox.expand(
      child: RawImage(image: _frame, fit: BoxFit.cover),
    );
  }
}
