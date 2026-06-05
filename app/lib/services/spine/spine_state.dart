import 'package:freezed_annotation/freezed_annotation.dart';

part 'spine_state.freezed.dart';

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
  }) = _RobotStatus;

  factory RobotStatus.fromJson(Map<String, dynamic> json) {
    return RobotStatus(
      online: json['online'] ?? false,
      battery: json['battery'] ?? 0,
      isMoving: json['isMoving'] ?? false,
      headLR: json['headLR'] ?? 50,
      headUD: json['headUD'] ?? 50,
      leftArm: json['leftArm'] ?? 50,
      rightArm: json['rightArm'] ?? 50,
      isWaving: json['isWaving'] ?? false,
    );
  }
}
