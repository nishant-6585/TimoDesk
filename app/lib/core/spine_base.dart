import 'package:flutter/foundation.dart';

/// Where the spine broker lives. The spine always runs on the machine that
/// serves this web app, so on web we take the host out of the browser's own
/// address bar (dev `flutter run` → localhost, LAN-served build → the Mac's
/// LAN IP) instead of hardcoding localhost — which broke every device that
/// wasn't the dev machine. Non-web builds keep the localhost dev default.
String get spineHost {
  if (kIsWeb && Uri.base.host.isNotEmpty) return Uri.base.host;
  return 'localhost';
}

String get spineHttpBase => 'http://$spineHost:4000';
String get spineWsUrl => 'ws://$spineHost:4000';
