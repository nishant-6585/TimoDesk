import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Web MJPEG renderer. Browsers natively decode multipart/x-mixed-replace inside
/// an <img>, so we mount a plain ImageElement via HtmlElementView — exactly the
/// approach `viewer_web/index.html` uses.
final Set<String> _registered = {};

Widget buildMjpegView(BuildContext context, String url, BoxFit fit, {bool crossOrigin = false}) {
  // Key the factory by crossOrigin too — the same URL may be mounted for plain
  // display (no crossOrigin) and for enrollment pixel-reading (crossOrigin on).
  final viewType = 'mjpeg::${crossOrigin ? 'co::' : ''}$url';
  if (!_registered.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = fit == BoxFit.contain ? 'contain' : 'cover'
        ..style.border = 'none';
      // Only request CORS when frames will be read back (canvas pixel access).
      // Setting it for plain display breaks MJPEG <img> rendering in Chrome.
      if (crossOrigin) img.crossOrigin = 'anonymous';
      return img;
    });
    _registered.add(viewType);
  }
  return HtmlElementView(viewType: viewType);
}
