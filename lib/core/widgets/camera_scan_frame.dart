import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:raze_store/app/theme/theme.dart';

/// Shared scan-window styling for barcode and focused product-label cameras.
class CameraScanFrame extends StatelessWidget {
  const CameraScanFrame({
    super.key,
    required this.widthFactor,
    required this.aspectRatio,
    this.center = const Offset(0.5, 0.5),
    this.overlayOpacity = 0.08,
    this.maximumWidth = double.infinity,
    this.frameKey,
  }) : assert(widthFactor > 0 && widthFactor <= 1),
       assert(aspectRatio > 0),
       assert(overlayOpacity >= 0 && overlayOpacity <= 1),
       assert(maximumWidth > 0);

  final double widthFactor;
  final double aspectRatio;

  /// Fractional position of the scan window's center inside the preview.
  final Offset center;
  final double overlayOpacity;
  final double maximumWidth;

  /// Optional key on the painted scan window rather than the full overlay.
  final Key? frameKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black.withValues(alpha: overlayOpacity)),
        LayoutBuilder(
          builder: (context, constraints) {
            final frameWidth = math.min(
              constraints.maxWidth * widthFactor,
              maximumWidth,
            );
            final frameHeight = frameWidth / aspectRatio;
            final left = (constraints.maxWidth * center.dx - frameWidth / 2)
                .clamp(0.0, constraints.maxWidth - frameWidth);
            final top = (constraints.maxHeight * center.dy - frameHeight / 2)
                .clamp(0.0, constraints.maxHeight - frameHeight);

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: frameWidth,
                  height: frameHeight,
                  child: DecoratedBox(
                    key: frameKey,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2.5),
                      borderRadius: AppRadius.card,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x73000000),
                          blurRadius: 14,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
