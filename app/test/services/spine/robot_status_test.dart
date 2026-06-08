import 'package:flutter_test/flutter_test.dart';
import 'package:timodesk/services/spine/spine_state.dart';

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

      expect(status.obstacleState, ObstacleState.blocked);
      expect(status.localizationQuality, LocalizationQuality.normal);
      expect(status.sensorHealth?.lidar, SensorState.ok);
      expect(status.sensorHealth?.rgbd, SensorState.warn);
      expect(status.sensorHealth?.sonar, SensorState.error);
      expect(status.personDetected, true);
      expect(status.lastObstacleEventAt, isNotNull);
    });

    test('falls back to unknown/null safely on missing fields', () {
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

      expect(status.obstacleState, ObstacleState.unknown);
      expect(status.localizationQuality, LocalizationQuality.unknown);
      expect(status.sensorHealth, isNull);
      expect(status.personDetected, false);
      expect(status.lastObstacleEventAt, isNull);
    });

    test('handles invalid obstacleState enum value with fallback', () {
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
      expect(status.obstacleState, ObstacleState.unknown);
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

  group('ObstacleState enum', () {
    test('fromString returns correct enum values', () {
      expect(ObstacleState.fromString('running'), ObstacleState.running);
      expect(ObstacleState.fromString('blocked'), ObstacleState.blocked);
      expect(ObstacleState.fromString('wait_short'), ObstacleState.waitShort);
      expect(ObstacleState.fromString('wait_long'), ObstacleState.waitLong);
    });

    test('fromString defaults to unknown on invalid value', () {
      expect(ObstacleState.fromString('invalid'), ObstacleState.unknown);
      expect(ObstacleState.fromString(null), ObstacleState.unknown);
    });
  });

  group('SensorState enum', () {
    test('fromString returns correct enum values', () {
      expect(SensorState.fromString('ok'), SensorState.ok);
      expect(SensorState.fromString('warn'), SensorState.warn);
      expect(SensorState.fromString('error'), SensorState.error);
    });

    test('fromString defaults to error on invalid value', () {
      expect(SensorState.fromString('invalid'), SensorState.error);
      expect(SensorState.fromString(null), SensorState.error);
    });
  });
}
