// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'patrol_route_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Waypoint _$WaypointFromJson(Map<String, dynamic> json) {
  return _Waypoint.fromJson(json);
}

/// @nodoc
mixin _$Waypoint {
  String get id => throw _privateConstructorUsedError;
  int get sequence => throw _privateConstructorUsedError;
  double get x => throw _privateConstructorUsedError; // 0-10 m
  double get y => throw _privateConstructorUsedError; // 0-7.5 m
  int get heading => throw _privateConstructorUsedError; // 0-359 degrees
  int get dwellSeconds => throw _privateConstructorUsedError;
  String? get narration => throw _privateConstructorUsedError;

  /// Serializes this Waypoint to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Waypoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WaypointCopyWith<Waypoint> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WaypointCopyWith<$Res> {
  factory $WaypointCopyWith(Waypoint value, $Res Function(Waypoint) then) =
      _$WaypointCopyWithImpl<$Res, Waypoint>;
  @useResult
  $Res call(
      {String id,
      int sequence,
      double x,
      double y,
      int heading,
      int dwellSeconds,
      String? narration});
}

/// @nodoc
class _$WaypointCopyWithImpl<$Res, $Val extends Waypoint>
    implements $WaypointCopyWith<$Res> {
  _$WaypointCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Waypoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sequence = null,
    Object? x = null,
    Object? y = null,
    Object? heading = null,
    Object? dwellSeconds = null,
    Object? narration = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sequence: null == sequence
          ? _value.sequence
          : sequence // ignore: cast_nullable_to_non_nullable
              as int,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      heading: null == heading
          ? _value.heading
          : heading // ignore: cast_nullable_to_non_nullable
              as int,
      dwellSeconds: null == dwellSeconds
          ? _value.dwellSeconds
          : dwellSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      narration: freezed == narration
          ? _value.narration
          : narration // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WaypointImplCopyWith<$Res>
    implements $WaypointCopyWith<$Res> {
  factory _$$WaypointImplCopyWith(
          _$WaypointImpl value, $Res Function(_$WaypointImpl) then) =
      __$$WaypointImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      int sequence,
      double x,
      double y,
      int heading,
      int dwellSeconds,
      String? narration});
}

/// @nodoc
class __$$WaypointImplCopyWithImpl<$Res>
    extends _$WaypointCopyWithImpl<$Res, _$WaypointImpl>
    implements _$$WaypointImplCopyWith<$Res> {
  __$$WaypointImplCopyWithImpl(
      _$WaypointImpl _value, $Res Function(_$WaypointImpl) _then)
      : super(_value, _then);

  /// Create a copy of Waypoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sequence = null,
    Object? x = null,
    Object? y = null,
    Object? heading = null,
    Object? dwellSeconds = null,
    Object? narration = freezed,
  }) {
    return _then(_$WaypointImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      sequence: null == sequence
          ? _value.sequence
          : sequence // ignore: cast_nullable_to_non_nullable
              as int,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      heading: null == heading
          ? _value.heading
          : heading // ignore: cast_nullable_to_non_nullable
              as int,
      dwellSeconds: null == dwellSeconds
          ? _value.dwellSeconds
          : dwellSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      narration: freezed == narration
          ? _value.narration
          : narration // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WaypointImpl implements _Waypoint {
  const _$WaypointImpl(
      {required this.id,
      required this.sequence,
      required this.x,
      required this.y,
      required this.heading,
      required this.dwellSeconds,
      this.narration});

  factory _$WaypointImpl.fromJson(Map<String, dynamic> json) =>
      _$$WaypointImplFromJson(json);

  @override
  final String id;
  @override
  final int sequence;
  @override
  final double x;
// 0-10 m
  @override
  final double y;
// 0-7.5 m
  @override
  final int heading;
// 0-359 degrees
  @override
  final int dwellSeconds;
  @override
  final String? narration;

  @override
  String toString() {
    return 'Waypoint(id: $id, sequence: $sequence, x: $x, y: $y, heading: $heading, dwellSeconds: $dwellSeconds, narration: $narration)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WaypointImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sequence, sequence) ||
                other.sequence == sequence) &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.heading, heading) || other.heading == heading) &&
            (identical(other.dwellSeconds, dwellSeconds) ||
                other.dwellSeconds == dwellSeconds) &&
            (identical(other.narration, narration) ||
                other.narration == narration));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, sequence, x, y, heading, dwellSeconds, narration);

  /// Create a copy of Waypoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WaypointImplCopyWith<_$WaypointImpl> get copyWith =>
      __$$WaypointImplCopyWithImpl<_$WaypointImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WaypointImplToJson(
      this,
    );
  }
}

abstract class _Waypoint implements Waypoint {
  const factory _Waypoint(
      {required final String id,
      required final int sequence,
      required final double x,
      required final double y,
      required final int heading,
      required final int dwellSeconds,
      final String? narration}) = _$WaypointImpl;

  factory _Waypoint.fromJson(Map<String, dynamic> json) =
      _$WaypointImpl.fromJson;

  @override
  String get id;
  @override
  int get sequence;
  @override
  double get x; // 0-10 m
  @override
  double get y; // 0-7.5 m
  @override
  int get heading; // 0-359 degrees
  @override
  int get dwellSeconds;
  @override
  String? get narration;

  /// Create a copy of Waypoint
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WaypointImplCopyWith<_$WaypointImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PatrolRoute _$PatrolRouteFromJson(Map<String, dynamic> json) {
  return _PatrolRoute.fromJson(json);
}

/// @nodoc
mixin _$PatrolRoute {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  bool get enabled => throw _privateConstructorUsedError;
  String get activeFrom => throw _privateConstructorUsedError; // HH:MM
  String get activeTo => throw _privateConstructorUsedError; // HH:MM
  List<Waypoint> get waypoints => throw _privateConstructorUsedError;

  /// Serializes this PatrolRoute to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PatrolRoute
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PatrolRouteCopyWith<PatrolRoute> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PatrolRouteCopyWith<$Res> {
  factory $PatrolRouteCopyWith(
          PatrolRoute value, $Res Function(PatrolRoute) then) =
      _$PatrolRouteCopyWithImpl<$Res, PatrolRoute>;
  @useResult
  $Res call(
      {String id,
      String name,
      bool enabled,
      String activeFrom,
      String activeTo,
      List<Waypoint> waypoints});
}

/// @nodoc
class _$PatrolRouteCopyWithImpl<$Res, $Val extends PatrolRoute>
    implements $PatrolRouteCopyWith<$Res> {
  _$PatrolRouteCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PatrolRoute
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? enabled = null,
    Object? activeFrom = null,
    Object? activeTo = null,
    Object? waypoints = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      activeFrom: null == activeFrom
          ? _value.activeFrom
          : activeFrom // ignore: cast_nullable_to_non_nullable
              as String,
      activeTo: null == activeTo
          ? _value.activeTo
          : activeTo // ignore: cast_nullable_to_non_nullable
              as String,
      waypoints: null == waypoints
          ? _value.waypoints
          : waypoints // ignore: cast_nullable_to_non_nullable
              as List<Waypoint>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PatrolRouteImplCopyWith<$Res>
    implements $PatrolRouteCopyWith<$Res> {
  factory _$$PatrolRouteImplCopyWith(
          _$PatrolRouteImpl value, $Res Function(_$PatrolRouteImpl) then) =
      __$$PatrolRouteImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      bool enabled,
      String activeFrom,
      String activeTo,
      List<Waypoint> waypoints});
}

/// @nodoc
class __$$PatrolRouteImplCopyWithImpl<$Res>
    extends _$PatrolRouteCopyWithImpl<$Res, _$PatrolRouteImpl>
    implements _$$PatrolRouteImplCopyWith<$Res> {
  __$$PatrolRouteImplCopyWithImpl(
      _$PatrolRouteImpl _value, $Res Function(_$PatrolRouteImpl) _then)
      : super(_value, _then);

  /// Create a copy of PatrolRoute
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? enabled = null,
    Object? activeFrom = null,
    Object? activeTo = null,
    Object? waypoints = null,
  }) {
    return _then(_$PatrolRouteImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
      activeFrom: null == activeFrom
          ? _value.activeFrom
          : activeFrom // ignore: cast_nullable_to_non_nullable
              as String,
      activeTo: null == activeTo
          ? _value.activeTo
          : activeTo // ignore: cast_nullable_to_non_nullable
              as String,
      waypoints: null == waypoints
          ? _value._waypoints
          : waypoints // ignore: cast_nullable_to_non_nullable
              as List<Waypoint>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PatrolRouteImpl implements _PatrolRoute {
  const _$PatrolRouteImpl(
      {required this.id,
      required this.name,
      required this.enabled,
      required this.activeFrom,
      required this.activeTo,
      required final List<Waypoint> waypoints})
      : _waypoints = waypoints;

  factory _$PatrolRouteImpl.fromJson(Map<String, dynamic> json) =>
      _$$PatrolRouteImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final bool enabled;
  @override
  final String activeFrom;
// HH:MM
  @override
  final String activeTo;
// HH:MM
  final List<Waypoint> _waypoints;
// HH:MM
  @override
  List<Waypoint> get waypoints {
    if (_waypoints is EqualUnmodifiableListView) return _waypoints;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_waypoints);
  }

  @override
  String toString() {
    return 'PatrolRoute(id: $id, name: $name, enabled: $enabled, activeFrom: $activeFrom, activeTo: $activeTo, waypoints: $waypoints)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PatrolRouteImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.enabled, enabled) || other.enabled == enabled) &&
            (identical(other.activeFrom, activeFrom) ||
                other.activeFrom == activeFrom) &&
            (identical(other.activeTo, activeTo) ||
                other.activeTo == activeTo) &&
            const DeepCollectionEquality()
                .equals(other._waypoints, _waypoints));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, enabled, activeFrom,
      activeTo, const DeepCollectionEquality().hash(_waypoints));

  /// Create a copy of PatrolRoute
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PatrolRouteImplCopyWith<_$PatrolRouteImpl> get copyWith =>
      __$$PatrolRouteImplCopyWithImpl<_$PatrolRouteImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PatrolRouteImplToJson(
      this,
    );
  }
}

abstract class _PatrolRoute implements PatrolRoute {
  const factory _PatrolRoute(
      {required final String id,
      required final String name,
      required final bool enabled,
      required final String activeFrom,
      required final String activeTo,
      required final List<Waypoint> waypoints}) = _$PatrolRouteImpl;

  factory _PatrolRoute.fromJson(Map<String, dynamic> json) =
      _$PatrolRouteImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  bool get enabled;
  @override
  String get activeFrom; // HH:MM
  @override
  String get activeTo; // HH:MM
  @override
  List<Waypoint> get waypoints;

  /// Create a copy of PatrolRoute
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PatrolRouteImplCopyWith<_$PatrolRouteImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
