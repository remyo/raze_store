import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final scanFeedbackServiceProvider = Provider<ScanFeedbackService>((ref) {
  return const SystemScanFeedbackService();
});

abstract interface class ScanFeedbackService {
  Future<void> confirmProductAdded({
    required bool soundEnabled,
    required bool vibrationEnabled,
  });
}

final class SystemScanFeedbackService implements ScanFeedbackService {
  const SystemScanFeedbackService();

  @override
  Future<void> confirmProductAdded({
    required bool soundEnabled,
    required bool vibrationEnabled,
  }) async {
    if (soundEnabled) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {
        // Feedback is optional and must never turn a successful cart write
        // into an error on devices that do not support system sounds.
      }
    }
    if (vibrationEnabled) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {
        // Some devices and test environments do not provide haptic feedback.
      }
    }
  }
}
