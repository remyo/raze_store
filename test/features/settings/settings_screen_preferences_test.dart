import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_data_section.dart';
import 'package:raze_store/features/settings/application/app_storage_providers.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/app_storage_usage.dart';
import 'package:raze_store/features/settings/domain/app_preferences.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';
import 'package:raze_store/features/settings/presentation/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('keeps configurable setting groups closed by default', (
    tester,
  ) async {
    await _pumpSettings(tester);

    for (final key in <String>[
      'settings-section-receipt',
      'settings-section-scanner',
      'settings-section-appearance',
      'settings-section-backup-reminders',
      'settings-section-catalog-files',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }

    expect(find.text('Receipt details'), findsOneWidget);
    expect(find.text('Barcode scanner'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Backup reminders'), findsOneWidget);
    expect(find.text('Catalog files'), findsOneWidget);

    expect(find.text('Store name'), findsNothing);
    expect(find.byKey(const ValueKey('scanner-sound-setting')), findsNothing);
    expect(find.byType(SegmentedButton<ThemeMode>), findsNothing);
    expect(
      find.byKey(const ValueKey('backup-reminder-frequency-setting')),
      findsNothing,
    );
    expect(find.byType(CatalogDataSection), findsNothing);

    await _openSettingsSection(
      tester,
      const ValueKey('settings-section-catalog-files'),
    );

    expect(find.byType(CatalogDataSection), findsOneWidget);
    expect(
      find.byKey(const ValueKey('catalog-pack-expansion')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('complete-backup-expansion')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('csv-tools-expansion')), findsOneWidget);
    expect(find.byKey(const ValueKey('import-catalog-pack')), findsNothing);
  });

  testWidgets('shows and persists scanner behavior controls', (tester) async {
    await _pumpSettings(tester);

    expect(find.text('Barcode scanner'), findsOneWidget);
    expect(find.byKey(const ValueKey('scanner-sound-setting')), findsNothing);

    await _openSettingsSection(
      tester,
      const ValueKey('settings-section-scanner'),
    );

    expect(find.text('Scan sound'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.text('Add main unit automatically'), findsOneWidget);
    expect(find.text('Repeat-scan cooldown'), findsOneWidget);

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('scanner-sound-setting')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('scanner-vibration-setting')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('scanner-auto-main-unit-setting')),
          )
          .value,
      isFalse,
    );
    expect(find.text('500 ms'), findsOneWidget);

    final autoMain = find.byKey(
      const ValueKey('scanner-auto-main-unit-setting'),
    );
    await tester.scrollUntilVisible(
      autoMain,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(autoMain);
    await tester.pumpAndSettle();

    final stored = await SharedPreferences.getInstance();
    expect(stored.getBool(autoAddMainUnitOnScanPreferenceKey), isTrue);
  });

  testWidgets('offers off, weekly, and monthly backup reminders', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(
      find.byKey(const ValueKey('backup-reminder-frequency-setting')),
      findsNothing,
    );
    await _openSettingsSection(
      tester,
      const ValueKey('settings-section-backup-reminders'),
    );

    final frequency = find.byKey(
      const ValueKey('backup-reminder-frequency-setting'),
    );
    await tester.scrollUntilVisible(
      frequency,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Backup reminders'), findsOneWidget);
    expect(find.text('Every week'), findsOneWidget);
    expect(
      find.text('No successful backup has been created yet.'),
      findsOneWidget,
    );

    await tester.tap(frequency);
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Every month'), findsOneWidget);
    await tester.tap(find.text('Every month').last);
    await tester.pumpAndSettle();

    final stored = await SharedPreferences.getInstance();
    expect(
      stored.getString(backupReminderFrequencyPreferenceKey),
      BackupReminderFrequency.monthly.name,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProfileProvider.overrideWith(
          (ref) => Stream.value(StoreProfile.defaults),
        ),
        appStorageUsageProvider.overrideWith(
          (ref) async => AppStorageUsage(
            databaseBytes: 1024,
            productImageBytes: 0,
            temporaryReceiptBytes: 0,
            backgroundRemovalBytes: 0,
            cacheBytes: 0,
            measuredAt: DateTime.utc(2026, 9, 4),
          ),
        ),
        appPreferencesClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 4),
        ),
        catalogPackUndoSummaryProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSettingsSection(
  WidgetTester tester,
  ValueKey<String> key,
) async {
  final section = find.byKey(key);
  await tester.scrollUntilVisible(
    section,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(section);
  await tester.pumpAndSettle();
}
