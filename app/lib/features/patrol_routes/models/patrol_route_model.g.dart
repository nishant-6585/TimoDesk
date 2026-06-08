// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'patrol_route_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$WaypointImpl _$$WaypointImplFromJson(Map<String, dynamic> json) =>
    _$WaypointImpl(
      id: json['id'] as String,
      sequence: (json['sequence'] as num).toInt(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      heading: (json['heading'] as num).toInt(),
      dwellSeconds: (json['dwellSeconds'] as num).toInt(),
      narration: json['narration'] as String?,
    );

Map<String, dynamic> _$$WaypointImplToJson(_$WaypointImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sequence': instance.sequence,
      'x': instance.x,
      'y': instance.y,
      'heading': instance.heading,
      'dwellSeconds': instance.dwellSeconds,
      'narration': instance.narration,
    };

_$PatrolRouteImpl _$$PatrolRouteImplFromJson(Map<String, dynamic> json) =>
    _$PatrolRouteImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      enabled: json['enabled'] as bool,
      activeFrom: json['activeFrom'] as String,
      activeTo: json['activeTo'] as String,
      waypoints: (json['waypoints'] as List<dynamic>)
          .map((e) => Waypoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$PatrolRouteImplToJson(_$PatrolRouteImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'enabled': instance.enabled,
      'activeFrom': instance.activeFrom,
      'activeTo': instance.activeTo,
      'waypoints': instance.waypoints,
    };
