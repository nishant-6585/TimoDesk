import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/patrol_route_model.dart';

class MapCanvas extends StatefulWidget {
  final List<Waypoint> waypoints;
  final String? selectedWaypointId;
  final VoidCallback onEmptyMapClick;
  final Function(Offset) onWaypointDrag;
  final Function(String) onWaypointTap;
  final bool isPreviewRunning;
  final double previewProgress; // 0-1

  const MapCanvas({
    Key? key,
    required this.waypoints,
    this.selectedWaypointId,
    required this.onEmptyMapClick,
    required this.onWaypointDrag,
    required this.onWaypointTap,
    this.isPreviewRunning = false,
    this.previewProgress = 0,
  }) : super(key: key);

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  String? _draggingWaypointId;

  void _handlePointerDown(PointerDownEvent event) {
    // Check if clicking on a waypoint
    for (var waypoint in widget.waypoints) {
      final pos = _waypointScreenPosition(waypoint);
      final distance = (pos - event.position).distance;
      if (distance < 20) {
        setState(() => _draggingWaypointId = waypoint.id);
        widget.onWaypointTap(waypoint.id);
        return;
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_draggingWaypointId == null) return;
    final waypoint = widget.waypoints.firstWhere((w) => w.id == _draggingWaypointId);
    final offset = _screenToRoom(event.position);
    widget.onWaypointDrag(offset);
  }

  void _handlePointerUp(PointerUpEvent event) {
    setState(() => _draggingWaypointId = null);
  }

  void _handleMapTap(TapDownDetails details) {
    if (widget.waypoints.isEmpty) {
      final offset = _screenToRoom(details.globalPosition);
      widget.onEmptyMapClick();
      // offset will be used by parent
    }
  }

  Offset _screenToRoom(Offset screenPos) {
    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(screenPos);

    // Calculate room bounds within container
    final containerSize = renderBox.size;
    final containerAspect = containerSize.width / containerSize.height;

    late Offset roomTopLeft;
    late Size roomSize;

    if (containerAspect > 4 / 3) {
      // Width-constrained
      roomSize = Size(containerSize.height * 4 / 3, containerSize.height);
      roomTopLeft = Offset((containerSize.width - roomSize.width) / 2, 0);
    } else {
      // Height-constrained
      roomSize = Size(containerSize.width, containerSize.width * 3 / 4);
      roomTopLeft = Offset(0, (containerSize.height - roomSize.height) / 2);
    }

    final x = ((localPos.dx - roomTopLeft.dx) / roomSize.width) * 10;
    final y = ((localPos.dy - roomTopLeft.dy) / roomSize.height) * 7.5;

    return Offset(x.clamp(0, 10), y.clamp(0, 7.5));
  }

  Offset _waypointScreenPosition(Waypoint waypoint) {
    final renderBox = context.findRenderObject() as RenderBox;
    final containerSize = renderBox.size;
    final containerAspect = containerSize.width / containerSize.height;

    late Offset roomTopLeft;
    late Size roomSize;

    if (containerAspect > 4 / 3) {
      roomSize = Size(containerSize.height * 4 / 3, containerSize.height);
      roomTopLeft = Offset((containerSize.width - roomSize.width) / 2, 0);
    } else {
      roomSize = Size(containerSize.width, containerSize.width * 3 / 4);
      roomTopLeft = Offset(0, (containerSize.height - roomSize.height) / 2);
    }

    final screenX = roomTopLeft.dx + (waypoint.x / 10) * roomSize.width;
    final screenY = roomTopLeft.dy + (waypoint.y / 7.5) * roomSize.height;

    return Offset(screenX, screenY);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      child: GestureDetector(
        onTapDown: _handleMapTap,
        child: MouseRegion(
          cursor: widget.waypoints.isEmpty ? SystemMouseCursors.click : MouseCursor.defer,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF070707),
              border: Border.all(color: const Color(0xFF2A2A2A)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  // Background
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
                      border: Border.all(color: const Color(0xFF1f1f1f)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: EdgeInsets.symmetric(
                      horizontal: MediaQuery.of(context).size.width > 1600 ? 0 : 0,
                    ),
                  ),
                  // Custom paint (grid, path, rays, markers)
                  CustomPaint(
                    painter: MapPainter(
                      waypoints: widget.waypoints,
                      selectedWaypointId: widget.selectedWaypointId,
                      draggingWaypointId: _draggingWaypointId,
                      previewRunning: widget.isPreviewRunning,
                      previewProgress: widget.previewProgress,
                    ),
                    child: Container(),
                  ),
                  // Empty state
                  if (widget.waypoints.isEmpty)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_location, size: 48, color: const Color(0xFF3a3a3a)),
                          const SizedBox(height: 12),
                          Text(
                            'Click anywhere on the map to place waypoint 1',
                            style: TextStyle(fontSize: 13, color: const Color(0xFF5a5a5a)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MapPainter extends CustomPainter {
  final List<Waypoint> waypoints;
  final String? selectedWaypointId;
  final String? draggingWaypointId;
  final bool previewRunning;
  final double previewProgress;

  MapPainter({
    required this.waypoints,
    this.selectedWaypointId,
    this.draggingWaypointId,
    required this.previewRunning,
    required this.previewProgress,
  });

  late Size _containerSize;
  late Offset _roomTopLeft;
  late Size _roomSize;

  void _calculateRoomBounds() {
    final containerAspect = _containerSize.width / _containerSize.height;
    if (containerAspect > 4 / 3) {
      _roomSize = Size(_containerSize.height * 4 / 3, _containerSize.height);
      _roomTopLeft = Offset((_containerSize.width - _roomSize.width) / 2, 0);
    } else {
      _roomSize = Size(_containerSize.width, _containerSize.width * 3 / 4);
      _roomTopLeft = Offset(0, (_containerSize.height - _roomSize.height) / 2);
    }
  }

  Offset _roomToScreen(double x, double y) {
    return Offset(
      _roomTopLeft.dx + (x / 10) * _roomSize.width,
      _roomTopLeft.dy + (y / 7.5) * _roomSize.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _containerSize = size;
    _calculateRoomBounds();

    // Draw grid
    _drawGrid(canvas);

    // Draw path
    if (waypoints.length > 1) {
      _drawPath(canvas);
    }

    // Draw heading rays
    for (var waypoint in waypoints) {
      _drawHeadingRay(canvas, waypoint);
    }

    // Draw waypoint markers
    for (var waypoint in waypoints) {
      _drawWaypoint(canvas, waypoint);
    }

    // Draw preview robot
    if (previewRunning && waypoints.length > 1) {
      _drawPreviewRobot(canvas);
    }

    // Draw chrome (legend, scale bar)
    _drawChrome(canvas);
  }

  void _drawGrid(Canvas canvas) {
    final minorPaint = Paint()
      ..color = const Color(0xFF2f2f2f).withOpacity(0.55)
      ..strokeWidth = 1;

    final majorPaint = Paint()
      ..color = const Color(0xFF3a3a3a).withOpacity(0.9)
      ..strokeWidth = 2;

    // Draw grid lines (1m = _roomSize.width / 10)
    for (int i = 0; i <= 10; i++) {
      final x = _roomTopLeft.dx + (i / 10) * _roomSize.width;
      final paint = i % 5 == 0 ? majorPaint : minorPaint;
      canvas.drawLine(
        Offset(x, _roomTopLeft.dy),
        Offset(x, _roomTopLeft.dy + _roomSize.height),
        paint,
      );
    }

    for (int i = 0; i <= 7; i++) {
      final y = _roomTopLeft.dy + (i / 7.5) * _roomSize.height;
      final paint = i % 5 == 0 ? majorPaint : minorPaint;
      canvas.drawLine(
        Offset(_roomTopLeft.dx, y),
        Offset(_roomTopLeft.dx + _roomSize.width, y),
        paint,
      );
    }
  }

  void _drawPath(Canvas canvas) {
    final pathPaint = Paint()
      ..color = const Color(0xFF4a4a4a)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < waypoints.length; i++) {
      final pos = _roomToScreen(waypoints[i].x, waypoints[i].y);
      if (i == 0) {
        path.moveTo(pos.dx, pos.dy);
      } else {
        path.lineTo(pos.dx, pos.dy);
      }
    }
    canvas.drawPath(path, pathPaint);

    // Draw arrowheads
    for (int i = 0; i < waypoints.length - 1; i++) {
      _drawArrowhead(canvas, waypoints[i], waypoints[i + 1]);
    }
  }

  void _drawArrowhead(Canvas canvas, Waypoint from, Waypoint to) {
    final fromPos = _roomToScreen(from.x, from.y);
    final toPos = _roomToScreen(to.x, to.y);

    final dx = toPos.dx - fromPos.dx;
    final dy = toPos.dy - fromPos.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    if (distance < 10) return;

    // Arrowhead at midpoint
    final midX = (fromPos.dx + toPos.dx) / 2;
    final midY = (fromPos.dy + toPos.dy) / 2;

    final angle = math.atan2(dy, dx);
    final arrowSize = 8.0;

    final paint = Paint()
      ..color = const Color(0xFFFF6B35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final p1 = Offset(
      midX - arrowSize * math.cos(angle - math.pi / 6),
      midY - arrowSize * math.sin(angle - math.pi / 6),
    );
    final p2 = Offset(
      midX - arrowSize * math.cos(angle + math.pi / 6),
      midY - arrowSize * math.sin(angle + math.pi / 6),
    );

    canvas.drawLine(Offset(midX, midY), p1, paint);
    canvas.drawLine(Offset(midX, midY), p2, paint);
  }

  void _drawHeadingRay(Canvas canvas, Waypoint waypoint) {
    final pos = _roomToScreen(waypoint.x, waypoint.y);
    final angle = waypoint.heading * math.pi / 180;
    final rayLength = 30.0;

    final endPos = Offset(
      pos.dx + rayLength * math.sin(angle),
      pos.dy - rayLength * math.cos(angle), // Negate Y for screen coords
    );

    final paint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(pos, endPos, paint);
  }

  void _drawWaypoint(Canvas canvas, Waypoint waypoint) {
    final pos = _roomToScreen(waypoint.x, waypoint.y);
    final isSelected = waypoint.id == selectedWaypointId;
    final isDragging = waypoint.id == draggingWaypointId;

    final radius = isSelected || isDragging ? 18.0 : 16.0;

    // Circle
    final circlePaint = Paint()
      ..color = waypoint.sequence == 1 ? const Color(0xFFFF6B35) : Colors.transparent
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFFFF6B35)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (waypoint.sequence == 1) {
      canvas.drawCircle(pos, radius, circlePaint);
    } else {
      canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = const Color(0xFFFF6B35).withOpacity(0.16)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawCircle(pos, radius, borderPaint);

    // Selection ring
    if (isSelected) {
      canvas.drawCircle(
        pos,
        radius + 6,
        Paint()
          ..color = const Color(0xFFFF6B35).withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }

    // Number
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${waypoint.sequence}',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      pos - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawPreviewRobot(Canvas canvas) {
    // Interpolate position along path
    double totalDistance = 0;
    final distances = <double>[0];

    for (int i = 0; i < waypoints.length - 1; i++) {
      final dx = waypoints[i + 1].x - waypoints[i].x;
      final dy = waypoints[i + 1].y - waypoints[i].y;
      totalDistance += math.sqrt(dx * dx + dy * dy);
      distances.add(totalDistance);
    }

    final targetDistance = previewProgress * totalDistance;

    late Offset robotPos;
    for (int i = 0; i < waypoints.length - 1; i++) {
      if (targetDistance >= distances[i] && targetDistance <= distances[i + 1]) {
        final segmentProgress = (targetDistance - distances[i]) / (distances[i + 1] - distances[i]);
        final from = waypoints[i];
        final to = waypoints[i + 1];
        robotPos = _roomToScreen(
          from.x + (to.x - from.x) * segmentProgress,
          from.y + (to.y - from.y) * segmentProgress,
        );
        break;
      }
    }

    canvas.drawCircle(
      robotPos,
      12,
      Paint()..color = const Color(0xFF4ADE80),
    );
  }

  void _drawChrome(Canvas canvas) {
    // Grid pill (top-left)
    const textStyle = TextStyle(fontSize: 10, color: Color(0xFF9CA3AF));
    final textPainter = TextPainter(
      text: const TextSpan(text: '1 m grid · 10×7.5 m', style: textStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          _roomTopLeft.dx + 12,
          _roomTopLeft.dy + 12,
          textPainter.width + 12,
          textPainter.height + 8,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFF1A1A1A).withOpacity(0.8),
    );
    textPainter.paint(
      canvas,
      Offset(_roomTopLeft.dx + 18, _roomTopLeft.dy + 16),
    );
  }

  @override
  bool shouldRepaint(MapPainter oldDelegate) {
    return oldDelegate.waypoints != waypoints ||
        oldDelegate.selectedWaypointId != selectedWaypointId ||
        oldDelegate.draggingWaypointId != draggingWaypointId ||
        oldDelegate.previewProgress != previewProgress;
  }
}
