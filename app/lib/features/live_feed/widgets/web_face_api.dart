// Web-only face-api seam (mirrors mjpeg_view.dart's conditional-import trio):
//  - web   → dart:js eval into browser face-api.js (web_face_api_web.dart)
//  - other → throws UnsupportedError (native callers must kIsWeb-guard first)
// live_feed_screen calls these typed functions instead of touching dart:js, so
// the screen compiles natively. Same signatures in both variants.
export 'web_face_api_stub.dart'
    if (dart.library.html) 'web_face_api_web.dart';
