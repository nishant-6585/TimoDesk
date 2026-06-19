/// Native stub for the web-only face-api seam. Browser face-api enrollment does
/// not exist off the web; callers kIsWeb-guard the enrollment UI so these are
/// never reached. They throw as a safety net if that guard is ever missed.
const String _msg = 'Browser face-api enrollment is web-only';

Future<bool> faceApiLoadModels(String modelBaseUrl) =>
    throw UnsupportedError(_msg);

Future<Map<String, dynamic>> faceApiDetect(String elementSelector) =>
    throw UnsupportedError(_msg);

Future<String?> faceApiCapture(String elementSelector) =>
    throw UnsupportedError(_msg);
