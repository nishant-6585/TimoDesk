// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'spine_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$SensorHealth {
  SensorState get lidar => throw _privateConstructorUsedError;
  SensorState get rgbd => throw _privateConstructorUsedError;
  SensorState get sonar => throw _privateConstructorUsedError;

  /// Create a copy of SensorHealth
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SensorHealthCopyWith<SensorHealth> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SensorHealthCopyWith<$Res> {
  factory $SensorHealthCopyWith(
          SensorHealth value, $Res Function(SensorHealth) then) =
      _$SensorHealthCopyWithImpl<$Res, SensorHealth>;
  @useResult
  $Res call({SensorState lidar, SensorState rgbd, SensorState sonar});
}

/// @nodoc
class _$SensorHealthCopyWithImpl<$Res, $Val extends SensorHealth>
    implements $SensorHealthCopyWith<$Res> {
  _$SensorHealthCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SensorHealth
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? lidar = null,
    Object? rgbd = null,
    Object? sonar = null,
  }) {
    return _then(_value.copyWith(
      lidar: null == lidar
          ? _value.lidar
          : lidar // ignore: cast_nullable_to_non_nullable
              as SensorState,
      rgbd: null == rgbd
          ? _value.rgbd
          : rgbd // ignore: cast_nullable_to_non_nullable
              as SensorState,
      sonar: null == sonar
          ? _value.sonar
          : sonar // ignore: cast_nullable_to_non_nullable
              as SensorState,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SensorHealthImplCopyWith<$Res>
    implements $SensorHealthCopyWith<$Res> {
  factory _$$SensorHealthImplCopyWith(
          _$SensorHealthImpl value, $Res Function(_$SensorHealthImpl) then) =
      __$$SensorHealthImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({SensorState lidar, SensorState rgbd, SensorState sonar});
}

/// @nodoc
class __$$SensorHealthImplCopyWithImpl<$Res>
    extends _$SensorHealthCopyWithImpl<$Res, _$SensorHealthImpl>
    implements _$$SensorHealthImplCopyWith<$Res> {
  __$$SensorHealthImplCopyWithImpl(
      _$SensorHealthImpl _value, $Res Function(_$SensorHealthImpl) _then)
      : super(_value, _then);

  /// Create a copy of SensorHealth
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? lidar = null,
    Object? rgbd = null,
    Object? sonar = null,
  }) {
    return _then(_$SensorHealthImpl(
      lidar: null == lidar
          ? _value.lidar
          : lidar // ignore: cast_nullable_to_non_nullable
              as SensorState,
      rgbd: null == rgbd
          ? _value.rgbd
          : rgbd // ignore: cast_nullable_to_non_nullable
              as SensorState,
      sonar: null == sonar
          ? _value.sonar
          : sonar // ignore: cast_nullable_to_non_nullable
              as SensorState,
    ));
  }
}

/// @nodoc

class _$SensorHealthImpl implements _SensorHealth {
  const _$SensorHealthImpl(
      {required this.lidar, required this.rgbd, required this.sonar});

  @override
  final SensorState lidar;
  @override
  final SensorState rgbd;
  @override
  final SensorState sonar;

  @override
  String toString() {
    return 'SensorHealth(lidar: $lidar, rgbd: $rgbd, sonar: $sonar)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SensorHealthImpl &&
            (identical(other.lidar, lidar) || other.lidar == lidar) &&
            (identical(other.rgbd, rgbd) || other.rgbd == rgbd) &&
            (identical(other.sonar, sonar) || other.sonar == sonar));
  }

  @override
  int get hashCode => Object.hash(runtimeType, lidar, rgbd, sonar);

  /// Create a copy of SensorHealth
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SensorHealthImplCopyWith<_$SensorHealthImpl> get copyWith =>
      __$$SensorHealthImplCopyWithImpl<_$SensorHealthImpl>(this, _$identity);
}

abstract class _SensorHealth implements SensorHealth {
  const factory _SensorHealth(
      {required final SensorState lidar,
      required final SensorState rgbd,
      required final SensorState sonar}) = _$SensorHealthImpl;

  @override
  SensorState get lidar;
  @override
  SensorState get rgbd;
  @override
  SensorState get sonar;

  /// Create a copy of SensorHealth
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SensorHealthImplCopyWith<_$SensorHealthImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SpineState {
  bool get connected => throw _privateConstructorUsedError;
  bool get stopped => throw _privateConstructorUsedError; // Global STOP active
  RobotStatus? get status => throw _privateConstructorUsedError;

  /// Create a copy of SpineState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpineStateCopyWith<SpineState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpineStateCopyWith<$Res> {
  factory $SpineStateCopyWith(
          SpineState value, $Res Function(SpineState) then) =
      _$SpineStateCopyWithImpl<$Res, SpineState>;
  @useResult
  $Res call({bool connected, bool stopped, RobotStatus? status});

  $RobotStatusCopyWith<$Res>? get status;
}

/// @nodoc
class _$SpineStateCopyWithImpl<$Res, $Val extends SpineState>
    implements $SpineStateCopyWith<$Res> {
  _$SpineStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpineState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connected = null,
    Object? stopped = null,
    Object? status = freezed,
  }) {
    return _then(_value.copyWith(
      connected: null == connected
          ? _value.connected
          : connected // ignore: cast_nullable_to_non_nullable
              as bool,
      stopped: null == stopped
          ? _value.stopped
          : stopped // ignore: cast_nullable_to_non_nullable
              as bool,
      status: freezed == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as RobotStatus?,
    ) as $Val);
  }

  /// Create a copy of SpineState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $RobotStatusCopyWith<$Res>? get status {
    if (_value.status == null) {
      return null;
    }

    return $RobotStatusCopyWith<$Res>(_value.status!, (value) {
      return _then(_value.copyWith(status: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SpineStateImplCopyWith<$Res>
    implements $SpineStateCopyWith<$Res> {
  factory _$$SpineStateImplCopyWith(
          _$SpineStateImpl value, $Res Function(_$SpineStateImpl) then) =
      __$$SpineStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({bool connected, bool stopped, RobotStatus? status});

  @override
  $RobotStatusCopyWith<$Res>? get status;
}

/// @nodoc
class __$$SpineStateImplCopyWithImpl<$Res>
    extends _$SpineStateCopyWithImpl<$Res, _$SpineStateImpl>
    implements _$$SpineStateImplCopyWith<$Res> {
  __$$SpineStateImplCopyWithImpl(
      _$SpineStateImpl _value, $Res Function(_$SpineStateImpl) _then)
      : super(_value, _then);

  /// Create a copy of SpineState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connected = null,
    Object? stopped = null,
    Object? status = freezed,
  }) {
    return _then(_$SpineStateImpl(
      connected: null == connected
          ? _value.connected
          : connected // ignore: cast_nullable_to_non_nullable
              as bool,
      stopped: null == stopped
          ? _value.stopped
          : stopped // ignore: cast_nullable_to_non_nullable
              as bool,
      status: freezed == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as RobotStatus?,
    ));
  }
}

/// @nodoc

class _$SpineStateImpl implements _SpineState {
  const _$SpineStateImpl(
      {required this.connected, required this.stopped, required this.status});

  @override
  final bool connected;
  @override
  final bool stopped;
// Global STOP active
  @override
  final RobotStatus? status;

  @override
  String toString() {
    return 'SpineState(connected: $connected, stopped: $stopped, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpineStateImpl &&
            (identical(other.connected, connected) ||
                other.connected == connected) &&
            (identical(other.stopped, stopped) || other.stopped == stopped) &&
            (identical(other.status, status) || other.status == status));
  }

  @override
  int get hashCode => Object.hash(runtimeType, connected, stopped, status);

  /// Create a copy of SpineState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpineStateImplCopyWith<_$SpineStateImpl> get copyWith =>
      __$$SpineStateImplCopyWithImpl<_$SpineStateImpl>(this, _$identity);
}

abstract class _SpineState implements SpineState {
  const factory _SpineState(
      {required final bool connected,
      required final bool stopped,
      required final RobotStatus? status}) = _$SpineStateImpl;

  @override
  bool get connected;
  @override
  bool get stopped; // Global STOP active
  @override
  RobotStatus? get status;

  /// Create a copy of SpineState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpineStateImplCopyWith<_$SpineStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$RobotStatus {
  bool get online => throw _privateConstructorUsedError;
  int get battery => throw _privateConstructorUsedError;
  bool get isMoving => throw _privateConstructorUsedError;
  int get headLR => throw _privateConstructorUsedError;
  int get headUD => throw _privateConstructorUsedError;
  int get leftArm => throw _privateConstructorUsedError;
  int get rightArm => throw _privateConstructorUsedError;
  bool get isWaving =>
      throw _privateConstructorUsedError; // Phase 1A sensor fields
  ObstacleState get obstacleState => throw _privateConstructorUsedError;
  LocalizationQuality get localizationQuality =>
      throw _privateConstructorUsedError;
  SensorHealth? get sensorHealth => throw _privateConstructorUsedError;
  bool get personDetected => throw _privateConstructorUsedError;
  DateTime? get lastObstacleEventAt => throw _privateConstructorUsedError;

  /// Create a copy of RobotStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RobotStatusCopyWith<RobotStatus> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RobotStatusCopyWith<$Res> {
  factory $RobotStatusCopyWith(
          RobotStatus value, $Res Function(RobotStatus) then) =
      _$RobotStatusCopyWithImpl<$Res, RobotStatus>;
  @useResult
  $Res call(
      {bool online,
      int battery,
      bool isMoving,
      int headLR,
      int headUD,
      int leftArm,
      int rightArm,
      bool isWaving,
      ObstacleState obstacleState,
      LocalizationQuality localizationQuality,
      SensorHealth? sensorHealth,
      bool personDetected,
      DateTime? lastObstacleEventAt});

  $SensorHealthCopyWith<$Res>? get sensorHealth;
}

/// @nodoc
class _$RobotStatusCopyWithImpl<$Res, $Val extends RobotStatus>
    implements $RobotStatusCopyWith<$Res> {
  _$RobotStatusCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RobotStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? online = null,
    Object? battery = null,
    Object? isMoving = null,
    Object? headLR = null,
    Object? headUD = null,
    Object? leftArm = null,
    Object? rightArm = null,
    Object? isWaving = null,
    Object? obstacleState = null,
    Object? localizationQuality = null,
    Object? sensorHealth = freezed,
    Object? personDetected = null,
    Object? lastObstacleEventAt = freezed,
  }) {
    return _then(_value.copyWith(
      online: null == online
          ? _value.online
          : online // ignore: cast_nullable_to_non_nullable
              as bool,
      battery: null == battery
          ? _value.battery
          : battery // ignore: cast_nullable_to_non_nullable
              as int,
      isMoving: null == isMoving
          ? _value.isMoving
          : isMoving // ignore: cast_nullable_to_non_nullable
              as bool,
      headLR: null == headLR
          ? _value.headLR
          : headLR // ignore: cast_nullable_to_non_nullable
              as int,
      headUD: null == headUD
          ? _value.headUD
          : headUD // ignore: cast_nullable_to_non_nullable
              as int,
      leftArm: null == leftArm
          ? _value.leftArm
          : leftArm // ignore: cast_nullable_to_non_nullable
              as int,
      rightArm: null == rightArm
          ? _value.rightArm
          : rightArm // ignore: cast_nullable_to_non_nullable
              as int,
      isWaving: null == isWaving
          ? _value.isWaving
          : isWaving // ignore: cast_nullable_to_non_nullable
              as bool,
      obstacleState: null == obstacleState
          ? _value.obstacleState
          : obstacleState // ignore: cast_nullable_to_non_nullable
              as ObstacleState,
      localizationQuality: null == localizationQuality
          ? _value.localizationQuality
          : localizationQuality // ignore: cast_nullable_to_non_nullable
              as LocalizationQuality,
      sensorHealth: freezed == sensorHealth
          ? _value.sensorHealth
          : sensorHealth // ignore: cast_nullable_to_non_nullable
              as SensorHealth?,
      personDetected: null == personDetected
          ? _value.personDetected
          : personDetected // ignore: cast_nullable_to_non_nullable
              as bool,
      lastObstacleEventAt: freezed == lastObstacleEventAt
          ? _value.lastObstacleEventAt
          : lastObstacleEventAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }

  /// Create a copy of RobotStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SensorHealthCopyWith<$Res>? get sensorHealth {
    if (_value.sensorHealth == null) {
      return null;
    }

    return $SensorHealthCopyWith<$Res>(_value.sensorHealth!, (value) {
      return _then(_value.copyWith(sensorHealth: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$RobotStatusImplCopyWith<$Res>
    implements $RobotStatusCopyWith<$Res> {
  factory _$$RobotStatusImplCopyWith(
          _$RobotStatusImpl value, $Res Function(_$RobotStatusImpl) then) =
      __$$RobotStatusImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool online,
      int battery,
      bool isMoving,
      int headLR,
      int headUD,
      int leftArm,
      int rightArm,
      bool isWaving,
      ObstacleState obstacleState,
      LocalizationQuality localizationQuality,
      SensorHealth? sensorHealth,
      bool personDetected,
      DateTime? lastObstacleEventAt});

  @override
  $SensorHealthCopyWith<$Res>? get sensorHealth;
}

/// @nodoc
class __$$RobotStatusImplCopyWithImpl<$Res>
    extends _$RobotStatusCopyWithImpl<$Res, _$RobotStatusImpl>
    implements _$$RobotStatusImplCopyWith<$Res> {
  __$$RobotStatusImplCopyWithImpl(
      _$RobotStatusImpl _value, $Res Function(_$RobotStatusImpl) _then)
      : super(_value, _then);

  /// Create a copy of RobotStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? online = null,
    Object? battery = null,
    Object? isMoving = null,
    Object? headLR = null,
    Object? headUD = null,
    Object? leftArm = null,
    Object? rightArm = null,
    Object? isWaving = null,
    Object? obstacleState = null,
    Object? localizationQuality = null,
    Object? sensorHealth = freezed,
    Object? personDetected = null,
    Object? lastObstacleEventAt = freezed,
  }) {
    return _then(_$RobotStatusImpl(
      online: null == online
          ? _value.online
          : online // ignore: cast_nullable_to_non_nullable
              as bool,
      battery: null == battery
          ? _value.battery
          : battery // ignore: cast_nullable_to_non_nullable
              as int,
      isMoving: null == isMoving
          ? _value.isMoving
          : isMoving // ignore: cast_nullable_to_non_nullable
              as bool,
      headLR: null == headLR
          ? _value.headLR
          : headLR // ignore: cast_nullable_to_non_nullable
              as int,
      headUD: null == headUD
          ? _value.headUD
          : headUD // ignore: cast_nullable_to_non_nullable
              as int,
      leftArm: null == leftArm
          ? _value.leftArm
          : leftArm // ignore: cast_nullable_to_non_nullable
              as int,
      rightArm: null == rightArm
          ? _value.rightArm
          : rightArm // ignore: cast_nullable_to_non_nullable
              as int,
      isWaving: null == isWaving
          ? _value.isWaving
          : isWaving // ignore: cast_nullable_to_non_nullable
              as bool,
      obstacleState: null == obstacleState
          ? _value.obstacleState
          : obstacleState // ignore: cast_nullable_to_non_nullable
              as ObstacleState,
      localizationQuality: null == localizationQuality
          ? _value.localizationQuality
          : localizationQuality // ignore: cast_nullable_to_non_nullable
              as LocalizationQuality,
      sensorHealth: freezed == sensorHealth
          ? _value.sensorHealth
          : sensorHealth // ignore: cast_nullable_to_non_nullable
              as SensorHealth?,
      personDetected: null == personDetected
          ? _value.personDetected
          : personDetected // ignore: cast_nullable_to_non_nullable
              as bool,
      lastObstacleEventAt: freezed == lastObstacleEventAt
          ? _value.lastObstacleEventAt
          : lastObstacleEventAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc

class _$RobotStatusImpl implements _RobotStatus {
  const _$RobotStatusImpl(
      {required this.online,
      required this.battery,
      required this.isMoving,
      required this.headLR,
      required this.headUD,
      required this.leftArm,
      required this.rightArm,
      required this.isWaving,
      required this.obstacleState,
      required this.localizationQuality,
      this.sensorHealth,
      required this.personDetected,
      this.lastObstacleEventAt});

  @override
  final bool online;
  @override
  final int battery;
  @override
  final bool isMoving;
  @override
  final int headLR;
  @override
  final int headUD;
  @override
  final int leftArm;
  @override
  final int rightArm;
  @override
  final bool isWaving;
// Phase 1A sensor fields
  @override
  final ObstacleState obstacleState;
  @override
  final LocalizationQuality localizationQuality;
  @override
  final SensorHealth? sensorHealth;
  @override
  final bool personDetected;
  @override
  final DateTime? lastObstacleEventAt;

  @override
  String toString() {
    return 'RobotStatus(online: $online, battery: $battery, isMoving: $isMoving, headLR: $headLR, headUD: $headUD, leftArm: $leftArm, rightArm: $rightArm, isWaving: $isWaving, obstacleState: $obstacleState, localizationQuality: $localizationQuality, sensorHealth: $sensorHealth, personDetected: $personDetected, lastObstacleEventAt: $lastObstacleEventAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RobotStatusImpl &&
            (identical(other.online, online) || other.online == online) &&
            (identical(other.battery, battery) || other.battery == battery) &&
            (identical(other.isMoving, isMoving) ||
                other.isMoving == isMoving) &&
            (identical(other.headLR, headLR) || other.headLR == headLR) &&
            (identical(other.headUD, headUD) || other.headUD == headUD) &&
            (identical(other.leftArm, leftArm) || other.leftArm == leftArm) &&
            (identical(other.rightArm, rightArm) ||
                other.rightArm == rightArm) &&
            (identical(other.isWaving, isWaving) ||
                other.isWaving == isWaving) &&
            (identical(other.obstacleState, obstacleState) ||
                other.obstacleState == obstacleState) &&
            (identical(other.localizationQuality, localizationQuality) ||
                other.localizationQuality == localizationQuality) &&
            (identical(other.sensorHealth, sensorHealth) ||
                other.sensorHealth == sensorHealth) &&
            (identical(other.personDetected, personDetected) ||
                other.personDetected == personDetected) &&
            (identical(other.lastObstacleEventAt, lastObstacleEventAt) ||
                other.lastObstacleEventAt == lastObstacleEventAt));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      online,
      battery,
      isMoving,
      headLR,
      headUD,
      leftArm,
      rightArm,
      isWaving,
      obstacleState,
      localizationQuality,
      sensorHealth,
      personDetected,
      lastObstacleEventAt);

  /// Create a copy of RobotStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RobotStatusImplCopyWith<_$RobotStatusImpl> get copyWith =>
      __$$RobotStatusImplCopyWithImpl<_$RobotStatusImpl>(this, _$identity);
}

abstract class _RobotStatus implements RobotStatus {
  const factory _RobotStatus(
      {required final bool online,
      required final int battery,
      required final bool isMoving,
      required final int headLR,
      required final int headUD,
      required final int leftArm,
      required final int rightArm,
      required final bool isWaving,
      required final ObstacleState obstacleState,
      required final LocalizationQuality localizationQuality,
      final SensorHealth? sensorHealth,
      required final bool personDetected,
      final DateTime? lastObstacleEventAt}) = _$RobotStatusImpl;

  @override
  bool get online;
  @override
  int get battery;
  @override
  bool get isMoving;
  @override
  int get headLR;
  @override
  int get headUD;
  @override
  int get leftArm;
  @override
  int get rightArm;
  @override
  bool get isWaving; // Phase 1A sensor fields
  @override
  ObstacleState get obstacleState;
  @override
  LocalizationQuality get localizationQuality;
  @override
  SensorHealth? get sensorHealth;
  @override
  bool get personDetected;
  @override
  DateTime? get lastObstacleEventAt;

  /// Create a copy of RobotStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RobotStatusImplCopyWith<_$RobotStatusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
