// Smoke tests for core helpers. (Replaces the stale `flutter create` counter
// test, which referenced a non-existent `MyApp` and never compiled against this
// project — the root widget is `TimoDeskApp`.)

import 'package:flutter_test/flutter_test.dart';
import 'package:timo_admin/core/constants.dart';

void main() {
  group('robotStreamUrl', () {
    test('builds the MJPEG stream URL from a robot IP', () {
      expect(robotStreamUrl('192.168.1.50'), 'http://192.168.1.50:8080/stream');
    });

    test('uses the shared camera port constant', () {
      expect(robotStreamUrl(defaultRobotIp), contains(':$robotCameraPort/stream'));
    });
  });
}
