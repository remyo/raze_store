import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme_mode_controller.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/app_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'creates safe defaults and starts the first weekly interval now',
    () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.utc(2026, 9, 4, 8, 30);
      final container = ProviderContainer(
        overrides: [appPreferencesClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);

      final preferences = await container.read(appPreferencesProvider.future);

      expect(preferences.scannerSoundEnabled, isTrue);
      expect(preferences.scannerVibrationEnabled, isTrue);
      expect(
        preferences.scannerRepeatCooldownMs,
        defaultScannerRepeatCooldownMilliseconds,
      );
      expect(preferences.autoAddMainUnitOnScan, isFalse);
      expect(preferences.productsViewLayout, CatalogViewLayout.grid);
      expect(preferences.quickUnitsViewLayout, CatalogViewLayout.grid);
      expect(
        preferences.backupReminderFrequency,
        BackupReminderFrequency.weekly,
      );
      expect(preferences.reminderAnchorAtUtc, now);
      expect(preferences.isBackupReminderDue(now), isFalse);
      expect(
        preferences.isBackupReminderDue(now.add(const Duration(days: 7))),
        isTrue,
      );

      final stored = await SharedPreferences.getInstance();
      expect(
        stored.getString(backupReminderAnchorPreferenceKey),
        now.toIso8601String(),
      );
    },
  );

  test(
    'loads valid values and replaces malformed values with defaults',
    () async {
      final anchor = DateTime.utc(2026, 8, 1);
      final lastBackup = DateTime.utc(2026, 8, 20);
      SharedPreferences.setMockInitialValues({
        scannerSoundEnabledPreferenceKey: false,
        scannerVibrationEnabledPreferenceKey: false,
        scannerRepeatCooldownPreferenceKey: 750,
        autoAddMainUnitOnScanPreferenceKey: true,
        productsViewLayoutPreferenceKey: 'not-a-layout',
        quickUnitsViewLayoutPreferenceKey: 1,
        backupReminderFrequencyPreferenceKey: 'not-a-frequency',
        backupReminderAnchorPreferenceKey: anchor.toIso8601String(),
        lastSuccessfulBackupPreferenceKey: lastBackup.toIso8601String(),
        backupReminderSnoozedUntilPreferenceKey: 'not-a-date',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final preferences = await container.read(appPreferencesProvider.future);

      expect(preferences.scannerSoundEnabled, isFalse);
      expect(preferences.scannerVibrationEnabled, isFalse);
      expect(
        preferences.scannerRepeatCooldownMs,
        defaultScannerRepeatCooldownMilliseconds,
      );
      // Existing installs keep an explicitly saved scanner choice even though
      // new installs now ask for a selling unit by default.
      expect(preferences.autoAddMainUnitOnScan, isTrue);
      expect(preferences.productsViewLayout, CatalogViewLayout.grid);
      expect(preferences.quickUnitsViewLayout, CatalogViewLayout.grid);
      expect(
        preferences.backupReminderFrequency,
        BackupReminderFrequency.weekly,
      );
      expect(preferences.reminderAnchorAtUtc, anchor);
      expect(preferences.lastSuccessfulBackupAtUtc, lastBackup);
      expect(preferences.snoozedUntilUtc, isNull);
    },
  );

  test('loads and persists product layouts independently', () async {
    SharedPreferences.setMockInitialValues({
      productsViewLayoutPreferenceKey: CatalogViewLayout.list.name,
      quickUnitsViewLayoutPreferenceKey: CatalogViewLayout.grid.name,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final loaded = await container.read(appPreferencesProvider.future);
    expect(loaded.productsViewLayout, CatalogViewLayout.list);
    expect(loaded.quickUnitsViewLayout, CatalogViewLayout.grid);

    final controller = container.read(appPreferencesProvider.notifier);
    await controller.setQuickUnitsViewLayout(CatalogViewLayout.list);

    final quickUnitsUpdated = container
        .read(appPreferencesProvider)
        .requireValue;
    expect(quickUnitsUpdated.productsViewLayout, CatalogViewLayout.list);
    expect(quickUnitsUpdated.quickUnitsViewLayout, CatalogViewLayout.list);

    await controller.setProductsViewLayout(CatalogViewLayout.grid);

    final productsUpdated = container.read(appPreferencesProvider).requireValue;
    expect(productsUpdated.productsViewLayout, CatalogViewLayout.grid);
    expect(productsUpdated.quickUnitsViewLayout, CatalogViewLayout.list);

    final stored = await SharedPreferences.getInstance();
    expect(
      stored.getString(productsViewLayoutPreferenceKey),
      CatalogViewLayout.grid.name,
    );
    expect(
      stored.getString(quickUnitsViewLayoutPreferenceKey),
      CatalogViewLayout.list.name,
    );
  });

  test('a layout change requested during initialization is not lost', () async {
    SharedPreferences.setMockInitialValues({
      productsViewLayoutPreferenceKey: CatalogViewLayout.grid.name,
    });
    final stored = await SharedPreferences.getInstance();
    final preferencesGate = Completer<SharedPreferences>();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => preferencesGate.future),
      ],
    );
    addTearDown(container.dispose);

    final initialization = container.read(appPreferencesProvider.future);
    final update = container
        .read(appPreferencesProvider.notifier)
        .setProductsViewLayout(CatalogViewLayout.list);

    preferencesGate.complete(stored);
    await Future.wait([initialization, update]);

    final value = container.read(appPreferencesProvider).requireValue;
    expect(value.productsViewLayout, CatalogViewLayout.list);
    expect(value.quickUnitsViewLayout, CatalogViewLayout.grid);
    expect(
      stored.getString(productsViewLayoutPreferenceKey),
      CatalogViewLayout.list.name,
    );
  });

  test(
    'controller updates and persists scanner and reminder settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime.utc(2026, 9, 4, 9);
      final container = ProviderContainer(
        overrides: [appPreferencesClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);
      await container.read(appPreferencesProvider.future);
      final controller = container.read(appPreferencesProvider.notifier);

      await controller.setScannerSoundEnabled(false);
      await controller.setScannerVibrationEnabled(false);
      await controller.setScannerRepeatCooldownMs(2000);
      await controller.setAutoAddMainUnitOnScan(false);
      await controller.setBackupReminderFrequency(
        BackupReminderFrequency.monthly,
      );

      now = DateTime.utc(2026, 9, 10, 12);
      await controller.markBackupCompleted();
      now = DateTime.utc(2026, 10, 10, 13);
      await controller.snoozeBackupReminder();

      final value = container.read(appPreferencesProvider).requireValue;
      expect(value.scannerSoundEnabled, isFalse);
      expect(value.scannerVibrationEnabled, isFalse);
      expect(value.scannerRepeatCooldownMs, 2000);
      expect(value.autoAddMainUnitOnScan, isFalse);
      expect(value.backupReminderFrequency, BackupReminderFrequency.monthly);
      expect(value.lastSuccessfulBackupAtUtc, DateTime.utc(2026, 9, 10, 12));
      expect(value.snoozedUntilUtc, DateTime.utc(2026, 10, 11, 13));

      final stored = await SharedPreferences.getInstance();
      expect(stored.getBool(scannerSoundEnabledPreferenceKey), isFalse);
      expect(stored.getBool(scannerVibrationEnabledPreferenceKey), isFalse);
      expect(stored.getInt(scannerRepeatCooldownPreferenceKey), 2000);
      expect(stored.getBool(autoAddMainUnitOnScanPreferenceKey), isFalse);
      expect(
        stored.getString(backupReminderFrequencyPreferenceKey),
        BackupReminderFrequency.monthly.name,
      );
      expect(
        stored.getString(lastSuccessfulBackupPreferenceKey),
        DateTime.utc(2026, 9, 10, 12).toIso8601String(),
      );
      expect(
        stored.getString(backupReminderSnoozedUntilPreferenceKey),
        DateTime.utc(2026, 10, 11, 13).toIso8601String(),
      );
    },
  );

  test('rejects unsupported cooldown and a non-positive snooze', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(appPreferencesProvider.future);
    final controller = container.read(appPreferencesProvider.notifier);

    expect(
      () => controller.setScannerRepeatCooldownMs(750),
      throwsArgumentError,
    );
    expect(
      () => controller.snoozeBackupReminder(duration: Duration.zero),
      throwsArgumentError,
    );
  });

  test('off disables reminders and snoozing postpones an overdue reminder', () {
    final anchor = DateTime.utc(2026, 9, 1);
    final overdue = AppPreferences.defaults(anchor: anchor);
    final now = anchor.add(const Duration(days: 8));

    expect(overdue.isBackupReminderDue(now), isTrue);
    expect(
      overdue
          .copyWith(snoozedUntilUtc: now.add(const Duration(days: 1)))
          .isBackupReminderDue(now),
      isFalse,
    );
    expect(
      overdue
          .copyWith(backupReminderFrequency: BackupReminderFrequency.off)
          .isBackupReminderDue(now),
      isFalse,
    );
  });
}
