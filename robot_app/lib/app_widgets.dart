// Shared atom widgets used across the chest-screen UI (status chip, badges,
// labels). Extracted from main.dart; renamed to public for cross-file use.
import 'package:flutter/material.dart';
import 'providers.dart';

class BatteryIndicator extends StatelessWidget {
  final BatteryState state;
  const BatteryIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final level = state.level;
    final unknown = level == null;
    final charging = state.charge != null && state.charge! > 0;
    final color = unknown
        ? Colors.white38
        : level >= 50
            ? Colors.greenAccent
            : level >= 20
                ? Colors.amberAccent
                : Colors.redAccent;
    final icon = unknown
        ? Icons.battery_unknown
        : charging
            ? Icons.battery_charging_full
            : level >= 80
                ? Icons.battery_full
                : level >= 30
                    ? Icons.battery_5_bar
                    : Icons.battery_2_bar;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 4),
      Text(unknown ? '—' : '$level%',
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
    ]);
  }
}

// ── Enroll button ─────────────────────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
        color: Colors.white38, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.bold),
  );
}

// ── MJPEG Status card ─────────────────────────────────────────────────────────

class StatusDot extends StatelessWidget {
  final bool  active;
  final Color activeColor;
  const StatusDot({required this.active, required this.activeColor});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: 12, height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: active ? activeColor : Colors.redAccent,
      boxShadow: active
          ? [BoxShadow(color: activeColor.withValues(alpha: 0.5), blurRadius: 8)]
          : null,
    ),
  );
}

class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 0.8));
}

class FpsBadge extends StatelessWidget {
  final double fps;
  const FpsBadge({required this.fps});
  @override
  Widget build(BuildContext context) {
    final color = fps > 20 ? Colors.greenAccent : fps > 10 ? Colors.yellowAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text('${fps.toStringAsFixed(1)} fps',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
    );
  }
}

class SdkBadge extends StatelessWidget {
  final String status;
  const SdkBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'connected'  => ('SDK CONNECTED',  Colors.greenAccent),
      'error'      => ('SDK ERROR',       Colors.redAccent),
      _            => ('SDK CONNECTING',  Colors.yellowAccent),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: color,
              boxShadow: status == 'connected'
                  ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5)]
                  : null)),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
    ]);
  }
}

