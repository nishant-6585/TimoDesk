// Platform-split webcam source (mirrors mjpeg_view.dart's conditional-import trio):
//  - web   → getUserMedia <video> via HtmlElementView (enroll_webcam_view_web.dart)
//  - other → a graceful "enroll on web / use the robot" placeholder (stub)
// Both variants expose the SAME public API: `DeviceWebcamView` + `kEnrollWebcamId`,
// so callers (live_feed_screen) don't change.
export 'enroll_webcam_view_stub.dart'
    if (dart.library.html) 'enroll_webcam_view_web.dart';
