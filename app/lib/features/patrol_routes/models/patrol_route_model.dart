import 'package:freezed_annotation/freezed_annotation.dart';

part 'patrol_route_model.freezed.dart';
part 'patrol_route_model.g.dart';

@freezed
class Waypoint with _$Waypoint {
  const factory Waypoint({
    required String id,
    required int sequence,
    required double x, // 0-10 m
    required double y, // 0-7.5 m
    required int heading, // 0-359 degrees
    required int dwellSeconds,
    String? narration,
  }) = _Waypoint;

  factory Waypoint.fromJson(Map<String, dynamic> json) =>
      _$WaypointFromJson(json);
}

@freezed
class PatrolRoute with _$PatrolRoute {
  const factory PatrolRoute({
    required String id,
    required String name,
    required bool enabled,
    required String activeFrom, // HH:MM
    required String activeTo, // HH:MM
    required List<Waypoint> waypoints,
  }) = _PatrolRoute;

  factory PatrolRoute.fromJson(Map<String, dynamic> json) =>
      _$PatrolRouteFromJson(json);
}
