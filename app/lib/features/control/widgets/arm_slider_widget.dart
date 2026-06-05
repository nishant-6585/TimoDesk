import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class ArmSliderWidget extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool disabled;

  const ArmSliderWidget({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.disabled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: disabled ? TimoColors.textSecondary : TimoColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: disabled ? TimoColors.textSecondary : TimoColors.primary,
                  inactiveTrackColor: TimoColors.border,
                  thumbColor: disabled ? TimoColors.textSecondary : TimoColors.primary,
                  overlayColor: (disabled ? TimoColors.textSecondary : TimoColors.primary).withOpacity(0.2),
                  trackHeight: 4,
                  thumbShape: RoundSliderThumbShape(
                    elevation: 0,
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: 0,
                  max: 100,
                  onChanged: disabled ? null : onChanged,
                  divisions: 100,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 40,
              child: Text(
                '${value.toInt()}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TimoColors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
