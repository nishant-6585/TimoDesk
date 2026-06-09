import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';

const _methodCh = MethodChannel('com.timoDesk/camera_stream');

class BatteryService {
  static const int PORT = 8090;
  HttpServer? _server;

  Future<void> start() async {
    try {
      _server = await HttpServer.bind('0.0.0.0', PORT);
      print('[BatteryService] HTTP server started on port $PORT');

      await for (HttpRequest request in _server!) {
        if (request.uri.path == '/battery' && request.method == 'GET') {
          await _handleBatteryRequest(request);
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      }
    } catch (e) {
      print('[BatteryService] Error starting server: $e');
    }
  }

  Future<void> _handleBatteryRequest(HttpRequest request) async {
    try {
      // Get battery from CSJBot SDK via native method channel
      final res = await _methodCh.invokeMethod<Map>('getConfig');

      // For now, return the device battery
      // In Phase 2, we'll integrate direct CSJBot SDK access
      final battery = await _getDeviceBattery();

      final response = {
        'battery': battery,
        'timestamp': DateTime.now().toIso8601String(),
      };

      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(response));
      await request.response.close();

      print('[BatteryService] Battery request: $battery%');
    } catch (e) {
      print('[BatteryService] Error: $e');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
  }

  Future<int> _getDeviceBattery() async {
    // For now return a default
    // Phase 2: Query CSJBot SDK directly from native code
    return 85;
  }

  void stop() {
    _server?.close();
  }
}
