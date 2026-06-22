import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../models/patrol_route_model.dart';
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

    return Scaffold(
      backgroundColor: MikeeColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // Header
              _buildHeader(context),
              // Content
              Expanded(
                child: Row(
                  children: [
                    if (!compact) _buildSidebar(context),
                    Expanded(
                      child: SingleChildScrollView(
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
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(color: MikeeColors.surface.withOpacity(0.8), border: const Border(bottom: BorderSide(color: MikeeColors.border))),
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [MikeeColors.primary, MikeeColors.primaryDark]), boxShadow: [BoxShadow(color: MikeeColors.primary.withOpacity(0.35), blurRadius: 16)]), child: Center(child: Text('X', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
          const SizedBox(width: 12),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mikee', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: MikeeColors.textPrimary, height: 1.0)), Text('xboom', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.15, color: MikeeColors.textMuted, height: 1.0))])
        ]),
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: MikeeColors.success.withOpacity(0.08), border: Border.all(color: MikeeColors.success.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)), child: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: MikeeColors.success)), const SizedBox(width: 8), Text('ONLINE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: MikeeColors.success))])),
          const SizedBox(width: 12),
          Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MikeeColors.border, width: 2), color: const Color(0xFF2A2A2A)), child: Center(child: Text('NK', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)))),
        ]),
      ]),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(color: MikeeColors.surface, border: const Border(right: BorderSide(color: MikeeColors.border))),
      child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(12), children: [
          _NavItem('Dashboard', Icons.space_dashboard, false, () => context.go('/')),
          _NavItem('Control', Icons.sports_esports, false, () => context.go('/control')),
          _NavItem('Live Feed', Icons.videocam, false, () => context.go('/live-feed')),
          _NavItem('Gallery', Icons.photo_library, false, () => context.go('/gallery')),
          _NavItem('Event Log', Icons.receipt_long, false, () => context.go('/event-log')),
          _NavItem('Patrol Routes', Icons.route, true, () {}),
          _NavItem('Settings', Icons.settings, false, () => context.go('/settings')),
        ]))
      ]),
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

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _NavItem(this.label, this.icon, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: active ? MikeeColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              if (active) Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: MikeeColors.primary, borderRadius: BorderRadius.circular(999))),
              Icon(icon, size: 20, color: active ? MikeeColors.primary : MikeeColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: active ? FontWeight.w500 : FontWeight.normal, color: active ? MikeeColors.primary : MikeeColors.textSecondary)))
            ]),
          ),
        ),
      ),
    );
  }
}
