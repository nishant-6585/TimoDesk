import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../providers/patrol_route_provider.dart';
import '../widgets/map_canvas.dart';
import '../widgets/patrol_panels.dart';

class PatrolRoutesScreen extends ConsumerStatefulWidget {
  const PatrolRoutesScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PatrolRoutesScreen> createState() => _PatrolRoutesScreenState();
}

class _PatrolRoutesScreenState extends ConsumerState<PatrolRoutesScreen> with TickerProviderStateMixin {
  late AnimationController _previewController;
  late TextEditingController _newRouteController;

  @override
  void initState() {
    super.initState();
    _previewController = AnimationController(duration: const Duration(milliseconds: 40), vsync: this);
    _previewController.addListener(() => setState(() {}));
    _newRouteController = TextEditingController();
  }

  @override
  void dispose() {
    _previewController.dispose();
    _newRouteController.dispose();
    super.dispose();
  }

  void _showAddRouteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Route', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
        backgroundColor: MikeeColors.cardTop,
        content: TextField(
          controller: _newRouteController,
          decoration: InputDecoration(
            hintText: 'Route name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.inter(color: MikeeColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(patrolRouteProvider.notifier).createRoute(_newRouteController.text);
              _newRouteController.clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: MikeeColors.primary),
            child: Text('Create', style: GoogleFonts.inter(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 900;
    final state = ref.watch(patrolRouteProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPageHeader(),
              const SizedBox(height: 24),
              if (!compact) _buildDesktopLayout(state) else _buildMobileLayout(state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.route, size: 28, color: MikeeColors.primary), const SizedBox(width: 12), Text('Patrol Routes', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold))]),
      const SizedBox(height: 4),
      Text('Design autonomous patrol paths — place, sequence, and narrate waypoints', style: GoogleFonts.inter(fontSize: 13, color: MikeeColors.textSecondary)),
    ]);
  }

  Widget _buildDesktopLayout(PatrolRouteState state) {
    final selectedRoute = state.selectedRoute;
    final selectedWaypoint = state.selectedWaypoint;

    return GridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 0.5,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // Routes Panel
        RoutesPanel(
          routes: state.routes,
          selectedRouteId: state.selectedRouteId,
          onAddRoute: _showAddRouteDialog,
          onSelectRoute: (id) => ref.read(patrolRouteProvider.notifier).selectRoute(id),
          onDeleteRoute: (id) => ref.read(patrolRouteProvider.notifier).deleteRoute(id),
        ),
        // Map Panel
        SizedBox(
          child: Column(
            children: [
              Expanded(
                child: MapCanvas(
                  waypoints: selectedRoute?.waypoints ?? [],
                  selectedWaypointId: state.selectedWaypointId,
                  onEmptyMapClick: () => _addWaypointAtLast(state),
                  onWaypointDrag: (offset) => _updateWaypointPosition(offset, state),
                  onWaypointTap: (id) => ref.read(patrolRouteProvider.notifier).selectWaypoint(id),
                  isPreviewRunning: state.isPreviewRunning,
                  previewProgress: _previewController.value,
                ),
              ),
              const SizedBox(height: 12),
              if (selectedRoute != null && selectedRoute.waypoints.length > 1)
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (state.isPreviewRunning) {
                        _previewController.stop();
                      } else {
                        _previewController.repeat();
                      }
                      ref.read(patrolRouteProvider.notifier).togglePreview();
                    },
                    icon: Icon(state.isPreviewRunning ? Icons.stop : Icons.play_arrow, size: 16),
                    label: Text(
                      state.isPreviewRunning ? 'Stop Preview' : 'Preview Route',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.isPreviewRunning ? MikeeColors.success : MikeeColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Properties/Waypoint Editor Panel
        if (selectedRoute != null)
          selectedWaypoint != null
              ? WaypointEditorPanel(
                  waypoint: selectedWaypoint,
                  onClose: () => ref.read(patrolRouteProvider.notifier).deselect(),
                  onUpdate: (w) => ref.read(patrolRouteProvider.notifier).updateWaypoint(w),
                  onDelete: () => ref.read(patrolRouteProvider.notifier).deleteWaypoint(selectedWaypoint.id),
                  onMoveUp: () => ref.read(patrolRouteProvider.notifier).moveWaypointUp(selectedWaypoint.id),
                  onMoveDown: () => ref.read(patrolRouteProvider.notifier).moveWaypointDown(selectedWaypoint.id),
                  canMoveUp: selectedWaypoint.sequence > 1,
                  canMoveDown: selectedWaypoint.sequence < selectedRoute.waypoints.length,
                )
              : RoutePropertiesPanel(
                  route: selectedRoute,
                  onSave: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route saved', style: GoogleFonts.inter()))),
                  onDelete: () => ref.read(patrolRouteProvider.notifier).deleteRoute(selectedRoute.id),
                  onUpdate: (r) => ref.read(patrolRouteProvider.notifier).updateRoute(r),
                )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
              border: Border.all(color: MikeeColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 48, color: const Color(0xFF3a3a3a)),
                  const SizedBox(height: 12),
                  Text('Select a route to begin', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF5a5a5a))),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileLayout(PatrolRouteState state) {
    final selectedRoute = state.selectedRoute;
    final selectedWaypoint = state.selectedWaypoint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MapCanvas(
          waypoints: selectedRoute?.waypoints ?? [],
          selectedWaypointId: state.selectedWaypointId,
          onEmptyMapClick: () => _addWaypointAtLast(state),
          onWaypointDrag: (offset) => _updateWaypointPosition(offset, state),
          onWaypointTap: (id) => ref.read(patrolRouteProvider.notifier).selectWaypoint(id),
        ),
        const SizedBox(height: 20),
        RoutesPanel(
          routes: state.routes,
          selectedRouteId: state.selectedRouteId,
          onAddRoute: _showAddRouteDialog,
          onSelectRoute: (id) => ref.read(patrolRouteProvider.notifier).selectRoute(id),
          onDeleteRoute: (id) => ref.read(patrolRouteProvider.notifier).deleteRoute(id),
        ),
        const SizedBox(height: 20),
        if (selectedRoute != null)
          selectedWaypoint != null
              ? WaypointEditorPanel(
                  waypoint: selectedWaypoint,
                  onClose: () => ref.read(patrolRouteProvider.notifier).deselect(),
                  onUpdate: (w) => ref.read(patrolRouteProvider.notifier).updateWaypoint(w),
                  onDelete: () => ref.read(patrolRouteProvider.notifier).deleteWaypoint(selectedWaypoint.id),
                  onMoveUp: () => ref.read(patrolRouteProvider.notifier).moveWaypointUp(selectedWaypoint.id),
                  onMoveDown: () => ref.read(patrolRouteProvider.notifier).moveWaypointDown(selectedWaypoint.id),
                  canMoveUp: selectedWaypoint.sequence > 1,
                  canMoveDown: selectedWaypoint.sequence < selectedRoute.waypoints.length,
                )
              : RoutePropertiesPanel(
                  route: selectedRoute,
                  onSave: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route saved', style: GoogleFonts.inter()))),
                  onDelete: () => ref.read(patrolRouteProvider.notifier).deleteRoute(selectedRoute.id),
                  onUpdate: (r) => ref.read(patrolRouteProvider.notifier).updateRoute(r),
                ),
      ],
    );
  }

  void _addWaypointAtLast(PatrolRouteState state) {
    if (state.selectedRoute == null) return;
    // This will be called when clicking on empty map, position from gesture
    // For now, just add a waypoint at a default position
    ref.read(patrolRouteProvider.notifier).addWaypoint(5.0, 3.5);
  }

  void _updateWaypointPosition(Offset offset, PatrolRouteState state) {
    if (state.selectedWaypoint == null) return;
    ref.read(patrolRouteProvider.notifier).updateWaypoint(
      state.selectedWaypoint!.copyWith(x: offset.dx, y: offset.dy),
    );
  }
}
