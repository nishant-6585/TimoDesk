// Timeouts and magic numbers
const Duration spineReconnectDelay = Duration(seconds: 3);
const Duration joystickThrottleMs = Duration(milliseconds: 50);
const int joystickRadius = 90;

// REAL ROBOT NETWORK SETTINGS
// Values must be explicitly configured via environment variables or secure configuration
// No hardcoded defaults - users must configure spine_url and robot_ip before first app launch
// Configuration can be set via:
// 1. Build environment variables (SPINE_URL, ROBOT_IP)
// 2. Onboarding flow on first app launch
// 3. Secure settings screen after app initialization
// Users can override via SharedPreferences (settings_provider) after initial configuration
const String? defaultSpineUrl = String.fromEnvironment('SPINE_URL');
const String? defaultRobotIp = String.fromEnvironment('ROBOT_IP');

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

// Validation helpers for required environment configuration
class ConfigurationValidator {
  static void validateRequiredConfig() {
    final missingVars = <String>[];
    
    if (defaultSpineUrl == null || defaultSpineUrl!.isEmpty) {
      missingVars.add('SPINE_URL');
    }
    if (defaultRobotIp == null || defaultRobotIp!.isEmpty) {
      missingVars.add('ROBOT_IP');
    }
    
    if (missingVars.isNotEmpty) {
      throw ConfigurationException(
        'Missing required environment variables: ${missingVars.join(', ')}. '
        'Please set SPINE_URL and ROBOT_IP before launching the app.',
      );
    }
  }
}

class ConfigurationException implements Exception {
  final String message;
  ConfigurationException(this.message);
  
  @override
  String toString() => 'ConfigurationException: $message';
}
