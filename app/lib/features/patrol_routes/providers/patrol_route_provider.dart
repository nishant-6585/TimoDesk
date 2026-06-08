import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/patrol_route_model.dart';

// Sample routes
const _sampleRoutes = [
  PatrolRoute(
    id: 'route-1',
    name: 'Lobby & Conference',
    enabled: true,
    activeFrom: '09:00',
    activeTo: '17:00',
    waypoints: [
      Waypoint(id: 'w1', sequence: 1, x: 2.0, y: 1.5, heading: 90, dwellSeconds: 10, narration: 'Greeting visitors'),
      Waypoint(id: 'w2', sequence: 2, x: 5.0, y: 3.0, heading: 180, dwellSeconds: 5, narration: 'Conference room'),
      Waypoint(id: 'w3', sequence: 3, x: 7.5, y: 5.0, heading: 270, dwellSeconds: 8, narration: 'Check exits'),
    ],
  ),
];

class PatrolRouteState {
  final List<PatrolRoute> routes;
  final String? selectedRouteId;
  final String? selectedWaypointId;
  final bool isPreviewRunning;

  PatrolRouteState({
    required this.routes,
    this.selectedRouteId,
    this.selectedWaypointId,
    this.isPreviewRunning = false,
  });

  PatrolRoute? get selectedRoute =>
      routes.firstWhere((r) => r.id == selectedRouteId, orElse: () => PatrolRoute(id: '', name: '', enabled: false, activeFrom: '00:00', activeTo: '23:59', waypoints: []));

  Waypoint? get selectedWaypoint {
    if (selectedWaypointId == null || selectedRoute == null) return null;
    return selectedRoute!.waypoints.firstWhere((w) => w.id == selectedWaypointId, orElse: () => Waypoint(id: '', sequence: 0, x: 0, y: 0, heading: 0, dwellSeconds: 0));
  }

  PatrolRouteState copyWith({
    List<PatrolRoute>? routes,
    String? selectedRouteId,
    String? selectedWaypointId,
    bool? isPreviewRunning,
  }) =>
      PatrolRouteState(
        routes: routes ?? this.routes,
        selectedRouteId: selectedRouteId ?? this.selectedRouteId,
        selectedWaypointId: selectedWaypointId ?? this.selectedWaypointId,
        isPreviewRunning: isPreviewRunning ?? this.isPreviewRunning,
      );
}

class PatrolRouteNotifier extends StateNotifier<PatrolRouteState> {
  PatrolRouteNotifier() : super(PatrolRouteState(routes: List.from(_sampleRoutes)));

  void selectRoute(String routeId) {
    state = state.copyWith(selectedRouteId: routeId, selectedWaypointId: null);
  }

  void selectWaypoint(String waypointId) {
    state = state.copyWith(selectedWaypointId: waypointId);
  }

  void deselect() {
    state = state.copyWith(selectedRouteId: null, selectedWaypointId: null);
  }

  void createRoute(String name) {
    const uuid = Uuid();
    final newRoute = PatrolRoute(
      id: uuid.v4(),
      name: name.isEmpty ? 'New Route' : name,
      enabled: true,
      activeFrom: '09:00',
      activeTo: '17:00',
      waypoints: [],
    );
    state = state.copyWith(routes: [...state.routes, newRoute], selectedRouteId: newRoute.id);
  }

  void updateRoute(PatrolRoute route) {
    final updated = state.routes.map((r) => r.id == route.id ? route : r).toList();
    state = state.copyWith(routes: updated);
  }

  void deleteRoute(String routeId) {
    final updated = state.routes.where((r) => r.id != routeId).toList();
    state = state.copyWith(routes: updated, selectedRouteId: null, selectedWaypointId: null);
  }

  void addWaypoint(double x, double y) {
    if (state.selectedRoute?.id == null) return;
    const uuid = Uuid();
    final route = state.selectedRoute!;
    final newWaypoint = Waypoint(
      id: uuid.v4(),
      sequence: route.waypoints.length + 1,
      x: x.clamp(0, 10),
      y: y.clamp(0, 7.5),
      heading: 0,
      dwellSeconds: 5,
    );
    final updatedRoute = route.copyWith(waypoints: [...route.waypoints, newWaypoint]);
    updateRoute(updatedRoute);
    selectWaypoint(newWaypoint.id);
  }

  void updateWaypoint(Waypoint waypoint) {
    if (state.selectedRoute?.id == null) return;
    final route = state.selectedRoute!;
    final updated = route.waypoints.map((w) => w.id == waypoint.id ? waypoint : w).toList();
    updateRoute(route.copyWith(waypoints: updated));
  }

  void deleteWaypoint(String waypointId) {
    if (state.selectedRoute?.id == null) return;
    final route = state.selectedRoute!;
    final updated = route.waypoints.where((w) => w.id != waypointId).toList();
    final renumbered = updated.asMap().entries.map((e) => e.value.copyWith(sequence: e.key + 1)).toList();
    updateRoute(route.copyWith(waypoints: renumbered));
    state = state.copyWith(selectedWaypointId: null);
  }

  void moveWaypointUp(String waypointId) {
    if (state.selectedRoute?.id == null) return;
    final route = state.selectedRoute!;
    final index = route.waypoints.indexWhere((w) => w.id == waypointId);
    if (index <= 0) return;
    final waypoints = List<Waypoint>.from(route.waypoints);
    final temp = waypoints[index - 1];
    waypoints[index - 1] = waypoints[index];
    waypoints[index] = temp;
    final renumbered = waypoints.asMap().entries.map((e) => e.value.copyWith(sequence: e.key + 1)).toList();
    updateRoute(route.copyWith(waypoints: renumbered));
  }

  void moveWaypointDown(String waypointId) {
    if (state.selectedRoute?.id == null) return;
    final route = state.selectedRoute!;
    final index = route.waypoints.indexWhere((w) => w.id == waypointId);
    if (index >= route.waypoints.length - 1) return;
    final waypoints = List<Waypoint>.from(route.waypoints);
    final temp = waypoints[index + 1];
    waypoints[index + 1] = waypoints[index];
    waypoints[index] = temp;
    final renumbered = waypoints.asMap().entries.map((e) => e.value.copyWith(sequence: e.key + 1)).toList();
    updateRoute(route.copyWith(waypoints: renumbered));
  }

  void togglePreview() {
    state = state.copyWith(isPreviewRunning: !state.isPreviewRunning);
  }
}

final patrolRouteProvider = StateNotifierProvider<PatrolRouteNotifier, PatrolRouteState>((ref) {
  return PatrolRouteNotifier();
});
