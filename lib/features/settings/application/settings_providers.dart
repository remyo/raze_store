import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme_mode_controller.dart';
import '../../../core/database/database_provider.dart';
import '../data/local_settings_repository.dart';
import '../domain/app_preferences.dart';
import '../domain/settings_repository.dart';
import '../domain/store_profile.dart';

const scannerSoundEnabledPreferenceKey =
    'raze_store.settings.scanner_sound_enabled';
const scannerVibrationEnabledPreferenceKey =
    'raze_store.settings.scanner_vibration_enabled';
const scannerRepeatCooldownPreferenceKey =
    'raze_store.settings.scanner_repeat_cooldown_ms';
const autoAddMainUnitOnScanPreferenceKey =
    'raze_store.settings.auto_add_main_unit_on_scan';
const backupReminderFrequencyPreferenceKey =
    'raze_store.settings.backup_reminder_frequency';
const backupReminderAnchorPreferenceKey =
    'raze_store.backup.reminder_anchor_at_utc';
const lastSuccessfulBackupPreferenceKey =
    'raze_store.backup.last_successful_at_utc';
const backupReminderSnoozedUntilPreferenceKey =
    'raze_store.backup.snoozed_until_utc';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return LocalSettingsRepository(ref.watch(appDatabaseProvider));
});

final storeProfileProvider = StreamProvider<StoreProfile>((ref) {
  return ref.watch(settingsRepositoryProvider).watchStoreProfile();
});

final appPreferencesClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final appPreferencesProvider =
    AsyncNotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
    );

class AppPreferencesController extends AsyncNotifier<AppPreferences> {
  @override
  Future<AppPreferences> build() async {
    final preferences = await ref.watch(sharedPreferencesProvider.future);
    final now = _now();
    var reminderAnchor = _readDateTime(
      preferences,
      backupReminderAnchorPreferenceKey,
    );
    if (reminderAnchor == null) {
      reminderAnchor = now;
      await preferences.setString(
        backupReminderAnchorPreferenceKey,
        reminderAnchor.toIso8601String(),
      );
    }

    return AppPreferences(
      scannerSoundEnabled:
          _readBool(preferences, scannerSoundEnabledPreferenceKey) ?? true,
      scannerVibrationEnabled:
          _readBool(preferences, scannerVibrationEnabledPreferenceKey) ?? true,
      scannerRepeatCooldownMs: _readCooldown(preferences),
      autoAddMainUnitOnScan:
          _readBool(preferences, autoAddMainUnitOnScanPreferenceKey) ?? true,
      backupReminderFrequency: _readReminderFrequency(preferences),
      reminderAnchorAtUtc: reminderAnchor,
      lastSuccessfulBackupAtUtc: _readDateTime(
        preferences,
        lastSuccessfulBackupPreferenceKey,
      ),
      snoozedUntilUtc: _readDateTime(
        preferences,
        backupReminderSnoozedUntilPreferenceKey,
      ),
    );
  }

  Future<void> setScannerSoundEnabled(bool enabled) => _update(
    (current) => current.copyWith(scannerSoundEnabled: enabled),
    (preferences, _) =>
        preferences.setBool(scannerSoundEnabledPreferenceKey, enabled),
  );

  Future<void> setScannerVibrationEnabled(bool enabled) => _update(
    (current) => current.copyWith(scannerVibrationEnabled: enabled),
    (preferences, _) =>
        preferences.setBool(scannerVibrationEnabledPreferenceKey, enabled),
  );

  Future<void> setScannerRepeatCooldownMs(int milliseconds) {
    if (!allowedScannerRepeatCooldownMilliseconds.contains(milliseconds)) {
      throw ArgumentError.value(
        milliseconds,
        'milliseconds',
        'Use one of $allowedScannerRepeatCooldownMilliseconds.',
      );
    }
    return _update(
      (current) => current.copyWith(scannerRepeatCooldownMs: milliseconds),
      (preferences, _) =>
          preferences.setInt(scannerRepeatCooldownPreferenceKey, milliseconds),
    );
  }

  Future<void> setAutoAddMainUnitOnScan(bool enabled) => _update(
    (current) => current.copyWith(autoAddMainUnitOnScan: enabled),
    (preferences, _) =>
        preferences.setBool(autoAddMainUnitOnScanPreferenceKey, enabled),
  );

  Future<void> setBackupReminderFrequency(BackupReminderFrequency frequency) {
    final now = _now();
    return _update(
      (current) => current.copyWith(
        backupReminderFrequency: frequency,
        reminderAnchorAtUtc: now,
        clearSnoozedUntilUtc: true,
      ),
      (preferences, next) async {
        final frequencySaved = await preferences.setString(
          backupReminderFrequencyPreferenceKey,
          frequency.name,
        );
        final anchorSaved = await preferences.setString(
          backupReminderAnchorPreferenceKey,
          next.reminderAnchorAtUtc.toIso8601String(),
        );
        final snoozeCleared = await preferences.remove(
          backupReminderSnoozedUntilPreferenceKey,
        );
        return frequencySaved && anchorSaved && snoozeCleared;
      },
    );
  }

  Future<void> markBackupCompleted() {
    final now = _now();
    return _update(
      (current) => current.copyWith(
        reminderAnchorAtUtc: now,
        lastSuccessfulBackupAtUtc: now,
        clearSnoozedUntilUtc: true,
      ),
      (preferences, next) async {
        final value = now.toIso8601String();
        final backupSaved = await preferences.setString(
          lastSuccessfulBackupPreferenceKey,
          value,
        );
        final anchorSaved = await preferences.setString(
          backupReminderAnchorPreferenceKey,
          value,
        );
        final snoozeCleared = await preferences.remove(
          backupReminderSnoozedUntilPreferenceKey,
        );
        return backupSaved && anchorSaved && snoozeCleared;
      },
    );
  }

  Future<void> snoozeBackupReminder({
    Duration duration = const Duration(days: 1),
  }) {
    if (duration.inMicroseconds <= 0) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive.');
    }
    final snoozedUntil = _now().add(duration);
    return _update(
      (current) => current.copyWith(snoozedUntilUtc: snoozedUntil),
      (preferences, _) => preferences.setString(
        backupReminderSnoozedUntilPreferenceKey,
        snoozedUntil.toIso8601String(),
      ),
    );
  }

  DateTime _now() => ref.read(appPreferencesClockProvider)().toUtc();

  Future<void> _update(
    AppPreferences Function(AppPreferences current) update,
    Future<bool> Function(SharedPreferences preferences, AppPreferences next)
    persist,
  ) async {
    final previous = state.value ?? await future;
    final next = update(previous);
    state = AsyncData(next);
    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      final saved = await persist(preferences, next);
      if (!saved) throw StateError('Could not save app preferences.');
    } catch (error, stackTrace) {
      if (ref.mounted && identical(state.value, next)) {
        state = AsyncData(previous);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static bool? _readBool(SharedPreferences preferences, String key) {
    final value = preferences.get(key);
    return value is bool ? value : null;
  }

  static int _readCooldown(SharedPreferences preferences) {
    final value = preferences.get(scannerRepeatCooldownPreferenceKey);
    return value is int &&
            allowedScannerRepeatCooldownMilliseconds.contains(value)
        ? value
        : defaultScannerRepeatCooldownMilliseconds;
  }

  static BackupReminderFrequency _readReminderFrequency(
    SharedPreferences preferences,
  ) {
    final value = preferences.get(backupReminderFrequencyPreferenceKey);
    if (value is String) {
      for (final frequency in BackupReminderFrequency.values) {
        if (frequency.name == value) return frequency;
      }
    }
    return BackupReminderFrequency.weekly;
  }

  static DateTime? _readDateTime(SharedPreferences preferences, String key) {
    final value = preferences.get(key);
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
