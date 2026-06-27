// Timeouts and magic numbers
const Duration spineReconnectDelay = Duration(seconds: 3);
const Duration joystickThrottleMs = Duration(milliseconds: 50);
const int joystickRadius = 90;

// REAL ROBOT NETWORK SETTINGS
// Default values are environment-specific and set at build time via flavors or build args
// For development: ws://localhost:4000 and 192.168.10.23
// For production: values must be configured via environment variables or build configuration
// Never rely on hardcoded defaults for production deployments
// Users can override these via SharedPreferences (settings_provider) after app initialization
const String defaultSpineUrl = String.fromEnvironment('SPINE_URL', defaultValue: 'ws://localhost:4000');
const String defaultRobotIp = String.fromEnvironment('ROBOT_IP', defaultValue: '192.168.10.23');

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
