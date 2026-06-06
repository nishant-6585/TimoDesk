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
  bool get isWaving => throw _privateConstructorUsedError;

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
      bool isWaving});
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
    ) as $Val);
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
      bool isWaving});
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
      required this.isWaving});

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

  @override
  String toString() {
    return 'RobotStatus(online: $online, battery: $battery, isMoving: $isMoving, headLR: $headLR, headUD: $headUD, leftArm: $leftArm, rightArm: $rightArm, isWaving: $isWaving)';
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
                other.isWaving == isWaving));
  }

  @override
  int get hashCode => Object.hash(runtimeType, online, battery, isMoving,
      headLR, headUD, leftArm, rightArm, isWaving);

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
      required final bool isWaving}) = _$RobotStatusImpl;

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
  bool get isWaving;

  /// Create a copy of RobotStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RobotStatusImplCopyWith<_$RobotStatusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
