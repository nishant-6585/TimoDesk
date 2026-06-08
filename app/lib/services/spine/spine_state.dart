import 'package:freezed_annotation/freezed_annotation.dart';

part 'spine_state.freezed.dart';

// Phase 1A sensor enums
enum ObstacleState {
  running('running'),
  blocked('blocked'),
  waitShort('wait_short'),
  waitLong('wait_long'),
  unknown('unknown');

  final String value;
  const ObstacleState(this.value);

  static ObstacleState fromString(String? s) {
    if (s == null) return ObstacleState.unknown;
    return ObstacleState.values.firstWhere(
      (e) => e.value == s,
      orElse: () => ObstacleState.unknown,
    );
  }
}

enum LocalizationQuality {
  low('low'),
  normal('normal'),
  unknown('unknown');

  final String value;
  const LocalizationQuality(this.value);

  static LocalizationQuality fromString(String? s) {
    if (s == null) return LocalizationQuality.unknown;
    return LocalizationQuality.values.firstWhere(
      (e) => e.value == s,
      orElse: () => LocalizationQuality.unknown,
    );
  }
}

enum SensorState {
  ok('ok'),
  warn('warn'),
  error('error');

  final String value;
  const SensorState(this.value);

  static SensorState fromString(String? s) {
    if (s == null) return SensorState.error;
    return SensorState.values.firstWhere(
      (e) => e.value == s,
      orElse: () => SensorState.error,
    );
  }
}

@freezed
class SensorHealth with _$SensorHealth {
  const factory SensorHealth({
    required SensorState lidar,
    required SensorState rgbd,
    required SensorState sonar,
  }) = _SensorHealth;

  factory SensorHealth.fromJson(Map<String, dynamic> json) {
    return SensorHealth(
      lidar: SensorState.fromString(json['lidar'] as String?),
      rgbd: SensorState.fromString(json['rgbd'] as String?),
      sonar: SensorState.fromString(json['sonar'] as String?),
    );
  }
}

@freezed
class SpineState with _$SpineState {
  const factory SpineState({
    required bool connected,
    required bool stopped, // Global STOP active
    required RobotStatus? status,
  }) = _SpineState;

  factory SpineState.initial() => const SpineState(
    connected: false,
    stopped: false,
    status: null,
  );
}

@freezed
class RobotStatus with _$RobotStatus {
  const factory RobotStatus({
    required bool online,
    required int battery,
    required bool isMoving,
    required int headLR,
    required int headUD,
    required int leftArm,
    required int rightArm,
    required bool isWaving,
    // Phase 1A sensor fields
    required ObstacleState obstacleState,
    required LocalizationQuality localizationQuality,
    SensorHealth? sensorHealth,
    required bool personDetected,
    DateTime? lastObstacleEventAt,
  }) = _RobotStatus;

  factory RobotStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parseEventTime(String? isoString) {
      if (isoString == null || isoString.isEmpty) return null;
      try {
        return DateTime.parse(isoString);
      } catch (_) {
        return null;
      }
    }

    return RobotStatus(
      online: json['online'] ?? false,
      battery: json['battery'] ?? 0,
      isMoving: json['isMoving'] ?? false,
      headLR: json['headLR'] ?? 50,
      headUD: json['headUD'] ?? 50,
      leftArm: json['leftArm'] ?? 50,
      rightArm: json['rightArm'] ?? 50,
      isWaving: json['isWaving'] ?? false,
      obstacleState: ObstacleState.fromString(json['obstacleState'] as String?),
      localizationQuality: LocalizationQuality.fromString(json['localizationQuality'] as String?),
      sensorHealth: json['sensorHealth'] != null
          ? SensorHealth.fromJson(json['sensorHealth'] as Map<String, dynamic>)
          : null,
      personDetected: json['personDetected'] ?? false,
      lastObstacleEventAt: parseEventTime(json['lastObstacleEventAt'] as String?),
    );
  }
}
