import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Web MJPEG renderer. Browsers natively decode multipart/x-mixed-replace inside
/// an <img>, so we mount a plain ImageElement via HtmlElementView — exactly the
/// approach `viewer_web/index.html` uses.
final Set<String> _registered = {};

Widget buildMjpegView(BuildContext context, String url, BoxFit fit) {
  final viewType = 'mjpeg::$url';
  if (!_registered.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = url
        ..crossOrigin = 'anonymous'  // Allow canvas pixel-reading for face detection
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = fit == BoxFit.contain ? 'contain' : 'cover'
        ..style.border = 'none';
      return img;
    });
    _registered.add(viewType);
  }
  return HtmlElementView(viewType: viewType);
}
