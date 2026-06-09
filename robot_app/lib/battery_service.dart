import 'dart:io';
import 'dart:convert';

class BatteryService {
  static const int PORT = 8090;
  static int _currentBattery = 85;
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

  // Setter to update battery from native code or CSJBot SDK
  static void setBattery(int level) {
    _currentBattery = level;
    print('[BatteryService] Battery level set to: $level%');
  }

  void stop() {
    _server?.close();
  }
}
