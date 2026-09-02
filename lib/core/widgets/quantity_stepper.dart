import 'package:flutter/material.dart';
import 'package:raze_store/app/theme/theme.dart';

/// Accessible quantity controls for a cart line.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.minimum = 1,
    this.maximum,
    this.step = 1,
    this.semanticLabel = 'Quantity',
  }) : assert(step > 0),
       assert(value >= minimum),
       assert(maximum == null || value <= maximum),
       assert(maximum == null || maximum >= minimum);

  final int value;
  final ValueChanged<int> onChanged;
  final int minimum;
  final int? maximum;
  final int step;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDecrease = value > minimum;
    final canIncrease = maximum == null || value < maximum!;

    return Semantics(
      container: true,
      label: semanticLabel,
      value: '$value',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppRadius.control,
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: canDecrease
                  ? () => onChanged(
                      (value - step).clamp(minimum, maximum ?? value).toInt(),
                    )
                  : null,
              tooltip: 'Decrease quantity',
              icon: const Icon(Icons.remove_rounded),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              onPressed: canIncrease
                  ? () => onChanged(
                      (value + step)
                          .clamp(minimum, maximum ?? value + step)
                          .toInt(),
                    )
                  : null,
              tooltip: 'Increase quantity',
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
