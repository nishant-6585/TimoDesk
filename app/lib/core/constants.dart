// Timeouts and magic numbers
const Duration spineReconnectDelay = Duration(seconds: 3);
const Duration joystickThrottleMs = Duration(milliseconds: 50);
const int joystickRadius = 90;

// REAL ROBOT NETWORK SETTINGS
// Default values for emulator/dev environment
// For real device testing or field deployments, load from SharedPreferences via settings_provider
const String defaultSpineUrl = 'ws://localhost:4000';
const String defaultRobotIp = '192.168.10.23';

// Robot camera (MJPEG server in robot_app/CameraStreamPlugin, port 8080)
const int robotCameraPort = 8080;
String robotStreamUrl(String robotIp) => 'http://$robotIp:$robotCameraPort/stream';

// SharedPreferences keys - used to persist user-configured spine URL and robot IP
const String spineUrlKey = 'spine_url';
const String robotIpKey = 'robot_ip';

// Supabase realtime limits
const int maxEventsToPull = 50;

// UI constants
const double cardBorderRadius = 16.0;
const double buttonBorderRadius = 12.0;
const double smallBorderRadius = 8.0;

// URL Validation Helper
class UrlValidator {
  static bool isValidWebSocketUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return (uri.scheme == 'ws' || uri.scheme == 'wss') &&
          uri.host.isNotEmpty &&
          uri.port > 0;
    } catch (e) {
      return false;
    }
  }
}
