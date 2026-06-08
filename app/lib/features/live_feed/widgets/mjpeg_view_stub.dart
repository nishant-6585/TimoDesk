import 'package:flutter/material.dart';

/// Fallback when neither dart:io nor dart:html is available.
Widget buildMjpegView(BuildContext context, String url, BoxFit fit) {
  return const Center(
    child: Text('Live stream not supported on this platform'),
  );
}
