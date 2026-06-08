import 'package:flutter_test/flutter_test.dart';
import 'package:timo_admin/services/spine/spine_state.dart';

void main() {
  group('RobotStatus.fromJson', () {
    test('parses all 5 Phase 1A sensor fields correctly', () {
      final json = {
        'online': true,
        'battery': 85,
        'isMoving': false,
        'headLR': 50,
        'headUD': 50,
        'leftArm': 50,
        'rightArm': 50,
        'isWaving': false,
        'obstacleState': 'blocked',
        'localizationQuality': 'normal',
        'sensorHealth': {
          'lidar': 'ok',
          'rgbd': 'warn',
          'sonar': 'error',
        },
        'personDetected': true,
        'lastObstacleEventAt': '2026-06-08T12:00:00Z',
      };

      final status = RobotStatus.fromJson(json);

      // Verify sensor fields were parsed
      expect(status.obstacleState.value, 'blocked');
      expect(status.localizationQuality.value, 'normal');
      expect(status.sensorHealth?.lidar.value, 'ok');
      expect(status.sensorHealth?.rgbd.value, 'warn');
      expect(status.sensorHealth?.sonar.value, 'error');
      expect(status.personDetected, true);
      expect(status.lastObstacleEventAt, isNotNull);
    });

    test('falls back safely on missing sensor fields', () {
      final json = {
        'online': true,
        'battery': 85,
        'isMoving': false,
        'headLR': 50,
        'headUD': 50,
        'leftArm': 50,
        'rightArm': 50,
        'isWaving': false,
      };

      final status = RobotStatus.fromJson(json);

      expect(status.obstacleState.value, 'unknown');
      expect(status.localizationQuality.value, 'unknown');
      expect(status.sensorHealth, isNull);
      expect(status.personDetected, false);
      expect(status.lastObstacleEventAt, isNull);
    });

    test('handles invalid obstacleState with fallback to unknown', () {
      final json = {
        'online': true,
        'battery': 85,
        'isMoving': false,
        'headLR': 50,
        'headUD': 50,
        'leftArm': 50,
        'rightArm': 50,
        'isWaving': false,
        'obstacleState': 'invalid_value',
      };

      final status = RobotStatus.fromJson(json);
      expect(status.obstacleState.value, 'unknown');
    });

    test('parses ISO-8601 timestamp correctly', () {
      final json = {
        'online': true,
        'battery': 85,
        'isMoving': false,
        'headLR': 50,
        'headUD': 50,
        'leftArm': 50,
        'rightArm': 50,
        'isWaving': false,
        'lastObstacleEventAt': '2026-06-08T15:30:45.123Z',
      };

      final status = RobotStatus.fromJson(json);
      expect(status.lastObstacleEventAt, isNotNull);
      expect(status.lastObstacleEventAt!.year, 2026);
      expect(status.lastObstacleEventAt!.month, 6);
      expect(status.lastObstacleEventAt!.day, 8);
    });

    test('handles malformed timestamp gracefully', () {
      final json = {
        'online': true,
        'battery': 85,
        'isMoving': false,
        'headLR': 50,
        'headUD': 50,
        'leftArm': 50,
        'rightArm': 50,
        'isWaving': false,
        'lastObstacleEventAt': 'not-a-date',
      };

      final status = RobotStatus.fromJson(json);
      expect(status.lastObstacleEventAt, isNull);
    });
  });
}
