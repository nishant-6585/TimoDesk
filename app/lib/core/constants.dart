// Timeouts and magic numbers
const Duration spineReconnectDelay = Duration(seconds: 3);
const Duration joystickThrottleMs = Duration(milliseconds: 50);
const int joystickRadius = 90;

// Default network settings
const String defaultSpineUrl = 'ws://192.168.1.100:4000';
const String defaultRobotIp = '192.168.1.100';

// Robot camera (MJPEG server in robot_app/CameraStreamPlugin, port 8080)
const int robotCameraPort = 8080;
String robotStreamUrl(String robotIp) => 'http://$robotIp:$robotCameraPort/stream';

// SharedPreferences keys
const String spineUrlKey = 'spine_url';
const String robotIpKey = 'robot_ip';

// Supabase realtime limits
const int maxEventsToPull = 50;

// UI constants
const double cardBorderRadius = 16.0;
const double buttonBorderRadius = 12.0;
const double smallBorderRadius = 8.0;
