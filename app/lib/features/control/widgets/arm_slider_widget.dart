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
            color: disabled ? MikeeColors.textSecondary : MikeeColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: disabled ? MikeeColors.textSecondary : MikeeColors.primary,
                  inactiveTrackColor: MikeeColors.border,
                  thumbColor: disabled ? MikeeColors.textSecondary : MikeeColors.primary,
                  overlayColor: (disabled ? MikeeColors.textSecondary : MikeeColors.primary).withOpacity(0.2),
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
                  color: MikeeColors.textSecondary,
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
