const defaultScannerRepeatCooldownMilliseconds = 500;

const allowedScannerRepeatCooldownMilliseconds = <int>[500, 1000, 1500, 2000];

enum BackupReminderFrequency {
  off,
  weekly,
  monthly;

  Duration? get interval => switch (this) {
    BackupReminderFrequency.off => null,
    BackupReminderFrequency.weekly => const Duration(days: 7),
    BackupReminderFrequency.monthly => const Duration(days: 30),
  };
}

enum CatalogViewLayout { grid, list }

/// Lightweight, device-local behavior settings that do not belong in the
/// product or sales database.
final class AppPreferences {
  const AppPreferences({
    required this.scannerSoundEnabled,
    required this.scannerVibrationEnabled,
    required this.scannerRepeatCooldownMs,
    required this.autoAddMainUnitOnScan,
    required this.backupReminderFrequency,
    required this.reminderAnchorAtUtc,
    this.productsViewLayout = CatalogViewLayout.grid,
    this.quickUnitsViewLayout = CatalogViewLayout.grid,
    this.lastSuccessfulBackupAtUtc,
    this.snoozedUntilUtc,
  });

  factory AppPreferences.defaults({required DateTime anchor}) => AppPreferences(
    scannerSoundEnabled: true,
    scannerVibrationEnabled: true,
    scannerRepeatCooldownMs: defaultScannerRepeatCooldownMilliseconds,
    autoAddMainUnitOnScan: false,
    backupReminderFrequency: BackupReminderFrequency.weekly,
    reminderAnchorAtUtc: anchor.toUtc(),
  );

  final bool scannerSoundEnabled;
  final bool scannerVibrationEnabled;
  final int scannerRepeatCooldownMs;

  /// When enabled, scanning a product with sub-unit prices immediately adds
  /// its main package. When disabled, the scanner asks which unit to sell.
  final bool autoAddMainUnitOnScan;

  final BackupReminderFrequency backupReminderFrequency;

  /// Each catalog surface remembers its own device-local list/grid choice.
  final CatalogViewLayout productsViewLayout;
  final CatalogViewLayout quickUnitsViewLayout;

  /// Starts the first reminder interval without immediately nagging an
  /// existing installation when this feature first appears.
  final DateTime reminderAnchorAtUtc;
  final DateTime? lastSuccessfulBackupAtUtc;
  final DateTime? snoozedUntilUtc;

  DateTime? get nextBackupReminderAtUtc {
    final interval = backupReminderFrequency.interval;
    if (interval == null) return null;

    final lastBackup = lastSuccessfulBackupAtUtc;
    final reference =
        lastBackup != null && lastBackup.isAfter(reminderAnchorAtUtc)
        ? lastBackup
        : reminderAnchorAtUtc;
    var nextReminder = reference.add(interval);
    final snoozedUntil = snoozedUntilUtc;
    if (snoozedUntil != null && snoozedUntil.isAfter(nextReminder)) {
      nextReminder = snoozedUntil;
    }
    return nextReminder;
  }

  bool isBackupReminderDue(DateTime now) {
    final nextReminder = nextBackupReminderAtUtc;
    return nextReminder != null && !now.toUtc().isBefore(nextReminder);
  }

  AppPreferences copyWith({
    bool? scannerSoundEnabled,
    bool? scannerVibrationEnabled,
    int? scannerRepeatCooldownMs,
    bool? autoAddMainUnitOnScan,
    BackupReminderFrequency? backupReminderFrequency,
    CatalogViewLayout? productsViewLayout,
    CatalogViewLayout? quickUnitsViewLayout,
    DateTime? reminderAnchorAtUtc,
    DateTime? lastSuccessfulBackupAtUtc,
    DateTime? snoozedUntilUtc,
    bool clearSnoozedUntilUtc = false,
  }) => AppPreferences(
    scannerSoundEnabled: scannerSoundEnabled ?? this.scannerSoundEnabled,
    scannerVibrationEnabled:
        scannerVibrationEnabled ?? this.scannerVibrationEnabled,
    scannerRepeatCooldownMs:
        scannerRepeatCooldownMs ?? this.scannerRepeatCooldownMs,
    autoAddMainUnitOnScan: autoAddMainUnitOnScan ?? this.autoAddMainUnitOnScan,
    backupReminderFrequency:
        backupReminderFrequency ?? this.backupReminderFrequency,
    productsViewLayout: productsViewLayout ?? this.productsViewLayout,
    quickUnitsViewLayout: quickUnitsViewLayout ?? this.quickUnitsViewLayout,
    reminderAnchorAtUtc: (reminderAnchorAtUtc ?? this.reminderAnchorAtUtc)
        .toUtc(),
    lastSuccessfulBackupAtUtc:
        (lastSuccessfulBackupAtUtc ?? this.lastSuccessfulBackupAtUtc)?.toUtc(),
    snoozedUntilUtc: clearSnoozedUntilUtc
        ? null
        : (snoozedUntilUtc ?? this.snoozedUntilUtc)?.toUtc(),
  );
}
