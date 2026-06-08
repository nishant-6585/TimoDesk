import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../services/spine/spine_state.dart';

class SensorStatusCard extends StatelessWidget {
  final RobotStatus status;

  const SensorStatusCard({Key? key, required this.status}) : super(key: key);

  Color _obstacleStateColor() {
    switch (status.obstacleState) {
      case ObstacleState.running:
        return TimoColors.success;
      case ObstacleState.waitShort:
      case ObstacleState.waitLong:
        return const Color(0xFFF59E0B); // warning amber
      case ObstacleState.blocked:
        return TimoColors.error;
      case ObstacleState.unknown:
        return TimoColors.textMuted;
    }
  }

  String _obstacleStateLabel() {
    switch (status.obstacleState) {
      case ObstacleState.running:
        return 'RUNNING';
      case ObstacleState.blocked:
        return 'BLOCKED';
      case ObstacleState.waitShort:
        return 'WAIT (short)';
      case ObstacleState.waitLong:
        return 'WAIT (long)';
      case ObstacleState.unknown:
        return 'UNKNOWN';
    }
  }

  Color _sensorStateColor(SensorState state) {
    switch (state) {
      case SensorState.ok:
        return TimoColors.success;
      case SensorState.warn:
        return const Color(0xFFF59E0B);
      case SensorState.error:
        return TimoColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [TimoColors.cardTop, TimoColors.cardBottom],
        ),
        border: Border.all(color: TimoColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SENSORS',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.12,
              color: TimoColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          // Obstacle State
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Obstacle',
                style: GoogleFonts.inter(fontSize: 12, color: TimoColors.textSecondary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _obstacleStateColor().withOpacity(0.15),
                  border: Border.all(color: _obstacleStateColor().withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _obstacleStateLabel(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _obstacleStateColor(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Localization Quality
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Localization',
                style: GoogleFonts.inter(fontSize: 12, color: TimoColors.textSecondary),
              ),
              Text(
                status.localizationQuality == LocalizationQuality.normal
                    ? 'Normal'
                    : status.localizationQuality == LocalizationQuality.low
                        ? 'Low'
                        : 'Unknown',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: status.localizationQuality == LocalizationQuality.normal
                      ? TimoColors.success
                      : status.localizationQuality == LocalizationQuality.low
                          ? const Color(0xFFF59E0B)
                          : TimoColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Person Detected
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Person',
                style: GoogleFonts.inter(fontSize: 12, color: TimoColors.textSecondary),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status.personDetected ? TimoColors.success.withOpacity(0.15) : TimoColors.inset,
                ),
                child: Center(
                  child: Icon(
                    status.personDetected ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 14,
                    color: status.personDetected ? TimoColors.success : TimoColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Sensor Health Pills
          if (status.sensorHealth != null)
            Column(
              children: [
                Text(
                  'Health',
                  style: GoogleFonts.inter(fontSize: 11, color: TimoColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SensorHealthPill('LIDAR', status.sensorHealth!.lidar),
                    _SensorHealthPill('RGBD', status.sensorHealth!.rgbd),
                    _SensorHealthPill('SONAR', status.sensorHealth!.sonar),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SensorHealthPill extends StatelessWidget {
  final String label;
  final SensorState state;

  const _SensorHealthPill(this.label, this.state);

  Color get _color {
    switch (state) {
      case SensorState.ok:
        return TimoColors.success;
      case SensorState.warn:
        return const Color(0xFFF59E0B);
      case SensorState.error:
        return TimoColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        border: Border.all(color: _color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(fontSize: 9, color: _color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
