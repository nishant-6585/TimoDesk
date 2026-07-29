import 'dart:io';
import 'dart:convert';

class BatteryService {
  static const int PORT = 8090;
  // -1 = no real reading yet (the native BatteryPlugin overwrites this within
  // a few seconds via the SDK or the Android BatteryManager fallback).
  static int _currentBattery = -1;
  // Charging state from the SDK's charge_status (robot_info auto-report). Spine
  // polls /battery and reads this to drive the admin's ⚡ charging indicator.
  static bool _charging = false;
  HttpServer? _server;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', PORT);
      print('[BatteryService] ✅ HTTP server started on port $PORT');

      _handleRequests();
    } catch (e) {
      print('[BatteryService] ❌ Error starting server: $e');
    }
  }

  void _handleRequests() {
    _server?.listen((HttpRequest request) {
      if (request.uri.path == '/battery' && request.method == 'GET') {
        _handleBatteryRequest(request);
      } else {
        request.response.statusCode = 404;
        request.response.close();
      }
    });
  }

  void _handleBatteryRequest(HttpRequest request) {
    try {
      final response = {
        'battery': _currentBattery,
        'charging': _charging,
        'timestamp': DateTime.now().toIso8601String(),
      };

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      request.response.close();

      print('[BatteryService] 🔋 Battery request: $_currentBattery%');
    } catch (e) {
      print('[BatteryService] ❌ Error: $e');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': e.toString()}));
      request.response.close();
    }
  }

  // Setter to update battery + charging from native code / CSJBot SDK. A
  // negative [level] means "no fresh reading" — keep the last real battery but
  // still apply the charging update (dock/undock can arrive without a new %).
  static void setBattery(int level, {bool? charging}) {
    if (level >= 0) _currentBattery = level;
    if (charging != null) _charging = charging;
    print('[BatteryService] Battery set to: $_currentBattery% charging=$_charging');
  }

  void stop() {
    _server?.close();
  }
}
