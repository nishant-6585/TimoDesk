import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../models/patrol_route_model.dart';
import 'dart:math' as math;

class RoutesPanel extends StatelessWidget {
  final List<PatrolRoute> routes;
  final String? selectedRouteId;
  final VoidCallback onAddRoute;
  final Function(String) onSelectRoute;
  final Function(String) onDeleteRoute;

  const RoutesPanel({
    Key? key,
    required this.routes,
    this.selectedRouteId,
    required this.onAddRoute,
    required this.onSelectRoute,
    required this.onDeleteRoute,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ROUTES', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onAddRoute,
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add Route', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
              style: ElevatedButton.styleFrom(
                backgroundColor: MikeeColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: routes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final route = routes[index];
                final isSelected = route.id == selectedRouteId;

                return _RouteItem(
                  route: route,
                  isSelected: isSelected,
                  onTap: () => onSelectRoute(route.id),
                  onDelete: () => onDeleteRoute(route.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteItem extends StatefulWidget {
  final PatrolRoute route;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RouteItem({
    required this.route,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_RouteItem> createState() => _RouteItemState();
}

class _RouteItemState extends State<_RouteItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.isSelected ? MikeeColors.primary.withOpacity(0.1) : Colors.transparent,
              border: Border.all(
                color: widget.isSelected || _hovering ? MikeeColors.primary.withOpacity(0.5) : MikeeColors.border,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (widget.isSelected)
                  Container(width: 4, height: 20, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: MikeeColors.primary, borderRadius: BorderRadius.circular(999))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.route.name,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.route.waypoints.length} wp · ${widget.route.activeFrom}–${widget.route.activeTo}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 10, color: MikeeColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.route.enabled ? MikeeColors.success.withOpacity(0.1) : MikeeColors.textMuted.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.route.enabled ? MikeeColors.success : MikeeColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.route.enabled ? 'Active' : 'Inactive',
                        style: GoogleFonts.inter(fontSize: 10, color: widget.route.enabled ? MikeeColors.success : MikeeColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (_hovering) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline, size: 16, color: MikeeColors.error),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoutePropertiesPanel extends StatefulWidget {
  final PatrolRoute route;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final Function(PatrolRoute) onUpdate;

  const RoutePropertiesPanel({
    Key? key,
    required this.route,
    required this.onSave,
    required this.onDelete,
    required this.onUpdate,
  }) : super(key: key);

  @override
  State<RoutePropertiesPanel> createState() => _RoutePropertiesState();
}

class _RoutePropertiesState extends State<RoutePropertiesPanel> {
  late TextEditingController _nameController;
  late String _from;
  late String _to;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.route.name);
    _from = widget.route.activeFrom;
    _to = widget.route.activeTo;
    _enabled = widget.route.enabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveChanges() {
    widget.onUpdate(widget.route.copyWith(
      name: _nameController.text,
      activeFrom: _from,
      activeTo: _to,
      enabled: _enabled,
    ));
    widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ROUTE PROPERTIES', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.12, color: MikeeColors.textSecondary)),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Route Name', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textSecondary, height: 1.0)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                style: GoogleFonts.jetBrainsMono(fontSize: 12),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: MikeeColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: MikeeColors.primary.withOpacity(0.6), width: 1.5)),
                  filled: true,
                  fillColor: const Color(0xFF141414),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary, height: 1.0)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 40,
                      child: TextField(
                        readOnly: true,
                        onTap: () async {
                          final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                          if (time != null) {
                            setState(() => _from = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
                          }
                        },
                        decoration: InputDecoration(
                          hintText: _from,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: MikeeColors.border)),
                          filled: true,
                          fillColor: const Color(0xFF141414),
                        ),
                        style: GoogleFonts.jetBrainsMono(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('To', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary, height: 1.0)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 40,
                      child: TextField(
                        readOnly: true,
                        onTap: () async {
                          final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                          if (time != null) {
                            setState(() => _to = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
                          }
                        },
                        decoration: InputDecoration(
                          hintText: _to,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: MikeeColors.border)),
                          filled: true,
                          fillColor: const Color(0xFF141414),
                        ),
                        style: GoogleFonts.jetBrainsMono(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Enabled', style: GoogleFonts.inter(fontSize: 12)),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeColor: MikeeColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Est. loop time', style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            _estimateLoopTime(),
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: MikeeColors.textMuted),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: _saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: MikeeColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Save Route', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton(
              onPressed: widget.onDelete,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: MikeeColors.error),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Delete Route', style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.error)),
            ),
          ),
        ],
      ),
    );
  }

  String _estimateLoopTime() {
    if (widget.route.waypoints.isEmpty) return '0m 0s';

    double totalDwell = widget.route.waypoints.fold(0, (sum, w) => sum + w.dwellSeconds);
    double totalTravel = 0;

    for (int i = 0; i < widget.route.waypoints.length - 1; i++) {
      final dx = widget.route.waypoints[i + 1].x - widget.route.waypoints[i].x;
      final dy = widget.route.waypoints[i + 1].y - widget.route.waypoints[i].y;
      final distance = math.sqrt(dx * dx + dy * dy);
      totalTravel += distance / 0.6; // ~0.6 m/s
    }

    final total = totalDwell + totalTravel;
    final minutes = (total / 60).toInt();
    final seconds = (total % 60).toInt();

    return '${minutes}m ${seconds}s';
  }
}

class CompassRose extends StatefulWidget {
  final int heading; // 0-359
  final Function(int) onHeadingChanged;

  const CompassRose({Key? key, required this.heading, required this.onHeadingChanged}) : super(key: key);

  @override
  State<CompassRose> createState() => _CompassRoseState();
}

class _CompassRoseState extends State<CompassRose> {
  late int _heading;

  @override
  void initState() {
    super.initState();
    _heading = widget.heading;
  }

  void _updateHeading(Offset localPosition) {
    final center = Offset(116 / 2, 116 / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    // atan2 returns radians, convert to degrees. y-down screen coords, so invert
    var angle = math.atan2(dx, -dy) * 180 / math.pi;
    if (angle < 0) angle += 360;

    _heading = angle.toInt().clamp(0, 359);
    widget.onHeadingChanged(_heading);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        _updateHeading(details.localPosition);
        setState(() {});
      },
      child: Container(
        width: 116,
        height: 116,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          border: Border.all(color: MikeeColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: CustomPaint(
          painter: CompassPainter(heading: _heading),
          child: Container(),
        ),
      ),
    );
  }
}

class CompassPainter extends CustomPainter {
  final int heading;

  CompassPainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Cardinal labels
    const labelStyle = TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold);
    _drawLabel(canvas, 'N', Offset(center.dx, center.dy - 35), labelStyle);
    _drawLabel(canvas, 'E', Offset(center.dx + 35, center.dy), labelStyle);
    _drawLabel(canvas, 'S', Offset(center.dx, center.dy + 35), labelStyle);
    _drawLabel(canvas, 'W', Offset(center.dx - 35, center.dy), labelStyle);

    // Circle
    canvas.drawCircle(
      center,
      45,
      Paint()
        ..color = Colors.transparent
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    // Needle
    final angle = heading * math.pi / 180;
    final needleLength = 35.0;
    final needleEnd = Offset(
      center.dx + needleLength * math.sin(angle),
      center.dy - needleLength * math.cos(angle),
    );

    canvas.drawLine(
      center,
      needleEnd,
      Paint()
        ..color = const Color(0xFF3B82F6)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Center hub
    canvas.drawCircle(center, 4, Paint()..color = Colors.white);
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset - Offset(textPainter.width / 2, textPainter.height / 2));
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) => oldDelegate.heading != heading;
}

class WaypointEditorPanel extends StatefulWidget {
  final Waypoint waypoint;
  final VoidCallback onClose;
  final Function(Waypoint) onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final bool canMoveUp;
  final bool canMoveDown;

  const WaypointEditorPanel({
    Key? key,
    required this.waypoint,
    required this.onClose,
    required this.onUpdate,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.canMoveUp,
    required this.canMoveDown,
  }) : super(key: key);

  @override
  State<WaypointEditorPanel> createState() => _WaypointEditorPanelState();
}

class _WaypointEditorPanelState extends State<WaypointEditorPanel> {
  late TextEditingController _xController;
  late TextEditingController _yController;
  late TextEditingController _headingController;
  late TextEditingController _dwellController;
  late TextEditingController _narrationController;

  @override
  void initState() {
    super.initState();
    _xController = TextEditingController(text: widget.waypoint.x.toStringAsFixed(2));
    _yController = TextEditingController(text: widget.waypoint.y.toStringAsFixed(2));
    _headingController = TextEditingController(text: '${widget.waypoint.heading}');
    _dwellController = TextEditingController(text: '${widget.waypoint.dwellSeconds}');
    _narrationController = TextEditingController(text: widget.waypoint.narration ?? '');
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _headingController.dispose();
    _dwellController.dispose();
    _narrationController.dispose();
    super.dispose();
  }

  void _save() {
    final x = double.tryParse(_xController.text) ?? widget.waypoint.x;
    final y = double.tryParse(_yController.text) ?? widget.waypoint.y;
    final heading = int.tryParse(_headingController.text) ?? widget.waypoint.heading;
    final dwell = int.tryParse(_dwellController.text) ?? widget.waypoint.dwellSeconds;

    widget.onUpdate(widget.waypoint.copyWith(
      x: x.clamp(0, 10),
      y: y.clamp(0, 7.5),
      heading: heading.clamp(0, 359),
      dwellSeconds: dwell,
      narration: _narrationController.text.isEmpty ? null : _narrationController.text,
    ));
  }

  bool _isXOutOfBounds() {
    final x = double.tryParse(_xController.text) ?? widget.waypoint.x;
    return x < 0 || x > 10;
  }

  bool _isYOutOfBounds() {
    final y = double.tryParse(_yController.text) ?? widget.waypoint.y;
    return y < 0 || y > 7.5;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
        border: Border.all(color: MikeeColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(shape: BoxShape.circle, color: MikeeColors.primary),
                child: Center(
                  child: Text('${widget.waypoint.sequence}', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Waypoint ${widget.waypoint.sequence}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600))),
              Material(color: Colors.transparent, child: InkWell(onTap: widget.onClose, child: const Icon(Icons.close, size: 20))),
            ],
          ),
          const SizedBox(height: 16),
          Text('POSITION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildField('X (m)', _xController, _isXOutOfBounds()),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildField('Y (m)', _yController, _isYOutOfBounds()),
              ),
            ],
          ),
          if (_isXOutOfBounds() || _isYOutOfBounds())
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('0–10 m (X) · 0–7.5 m (Y)', style: GoogleFonts.inter(fontSize: 10, color: MikeeColors.error)),
            ),
          const SizedBox(height: 12),
          Text('HEADING', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              CompassRose(heading: widget.waypoint.heading, onHeadingChanged: (h) => _headingController.text = '$h'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Heading', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary, height: 1.0)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _headingController,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        suffixText: '°',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: MikeeColors.border)),
                        filled: true,
                        fillColor: const Color(0xFF141414),
                      ),
                      style: GoogleFonts.jetBrainsMono(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text('0° = North (up)', style: GoogleFonts.inter(fontSize: 9, color: MikeeColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('DWELL TIME', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.remove), onPressed: () => _dwellController.text = '${(int.tryParse(_dwellController.text) ?? 5) - 1}'),
              Expanded(child: Center(child: Text(_dwellController.text, style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold)))),
              IconButton(icon: const Icon(Icons.add), onPressed: () => _dwellController.text = '${(int.tryParse(_dwellController.text) ?? 5) + 1}'),
            ],
          ),
          const SizedBox(height: 12),
          Text('NARRATION', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: MikeeColors.textSecondary)),
          const SizedBox(height: 8),
          TextField(
            controller: _narrationController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Spoken line at this stop…',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: MikeeColors.border)),
              filled: true,
              fillColor: const Color(0xFF141414),
            ),
            style: GoogleFonts.inter(fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_upward, size: 16), onPressed: widget.canMoveUp ? widget.onMoveUp : null),
              IconButton(icon: const Icon(Icons.arrow_downward, size: 16), onPressed: widget.canMoveDown ? widget.onMoveDown : null),
              const Spacer(),
              SizedBox(
                width: 40,
                height: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: MikeeColors.error,
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: () {
                _save();
                widget.onClose();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: MikeeColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Done', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, bool error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: MikeeColors.textSecondary, height: 1.0)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: error ? MikeeColors.error : MikeeColors.border)),
            filled: true,
            fillColor: const Color(0xFF141414),
          ),
          style: GoogleFonts.jetBrainsMono(fontSize: 12),
        ),
      ],
    );
  }
}
