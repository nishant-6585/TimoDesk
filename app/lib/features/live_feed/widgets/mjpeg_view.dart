import 'package:flutter/material.dart';

// Platform-split implementation:
//  - web    → native <img> via HtmlElementView (browser renders multipart MJPEG)
//  - io     → pure-Dart JPEG frame parser over an http streamed response
//  - other  → stub
import 'mjpeg_view_stub.dart'
    if (dart.library.io) 'mjpeg_view_io.dart'
    if (dart.library.html) 'mjpeg_view_web.dart';

/// Renders an MJPEG (multipart/x-mixed-replace) stream — e.g. the Mikee robot's
/// camera at `http://<robot-ip>:8080/stream`. The robot_app `CameraStreamPlugin`
/// serves this; `viewer_web` renders the same URL with a plain <img>.
class MjpegView extends StatelessWidget {
  /// Full stream URL, e.g. `http://192.168.1.100:8080/stream`.
  final String url;
  final BoxFit fit;

  /// Set `crossOrigin="anonymous"` on the web <img>. ONLY needed when the
  /// frames are read back pixel-by-pixel (e.g. face-api enrollment over the
  /// robot stream). Keep it OFF for plain display: Chrome fails to render a
  /// multipart/x-mixed-replace MJPEG <img> when crossOrigin is set, even with
  /// `Access-Control-Allow-Origin: *` present. No-op off the web.
  final bool crossOrigin;

  const MjpegView({Key? key, required this.url, this.fit = BoxFit.cover, this.crossOrigin = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) => buildMjpegView(context, url, fit, crossOrigin: crossOrigin);
}
