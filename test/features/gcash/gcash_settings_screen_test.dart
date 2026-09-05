import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:raze_store/features/gcash/gcash_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

GcashFeeSettings _smallSettings() {
  final defaults = GcashFeeSettings.defaults();
  return defaults.copyWith(
    shared: defaults.shared.copyWith(
      tiers: defaults.shared.tiers.take(2).toList(),
    ),
  );
}

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  Object? saved,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    gcashFeeSettingsPreferenceKey:
        saved ?? jsonEncode(_smallSettings().toJson()),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const GcashSettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('gcash-settings-edit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'opens one read-only profit table and saves one fee for both kinds',
    (tester) async {
      final container = await _pumpSettings(tester);
      expect(find.text('Amount range'), findsOneWidget);
      expect(find.text('Profit charge'), findsOneWidget);
      expect(
        find.text('One charge table for Cash In & Cash Out.'),
        findsOneWidget,
      );
      expect(find.text('₱500.01 – ₱1,000'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byKey(const ValueKey('gcash-settings-reset')), findsNothing);
      expect(find.byKey(const ValueKey('gcash-settings-save')), findsNothing);
      expect(find.textContaining('Saved transactions keep'), findsOneWidget);

      await _edit(tester);
      await tester.enterText(
        find.byKey(const ValueKey('gcash-shared-fee-0')),
        '15.50',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('gcash-settings-save')));
      await tester.pumpAndSettle();

      final settings = container.read(gcashFeeSettingsProvider).requireValue;
      for (final kind in GcashKind.values) {
        expect(settings.feeFor(kind, 50000), 1550);
        expect(settings.feeFor(kind, 50001), 2000);
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.text('₱15.50'), findsOneWidget);
      expect(find.text('GCash charges saved.'), findsOneWidget);
      final reader = ProviderContainer();
      addTearDown(reader.dispose);
      expect(
        (await reader.read(gcashFeeSettingsProvider.future)).toJson(),
        settings.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel discards tier, toggle and reset edits without writing', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    final preferences = await SharedPreferences.getInstance();
    final before = preferences.getString(gcashFeeSettingsPreferenceKey);
    await _edit(tester);
    await tester.enterText(
      find.byKey(const ValueKey('gcash-shared-fee-0')),
      '99',
    );
    await tester.tap(find.byKey(const ValueKey('gcash-shared-auto-fill')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('gcash-settings-reset')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gcash-settings-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gcash-settings-cancel')));
    await tester.pumpAndSettle();

    expect(
      container.read(gcashFeeSettingsProvider).requireValue.toJson(),
      _smallSettings().toJson(),
    );
    expect(preferences.getString(gcashFeeSettingsPreferenceKey), before);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Automatic charge on'), findsOneWidget);
    await _edit(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('gcash-shared-fee-0')))
          .controller!
          .text,
      '10.00',
    );
    expect(find.byKey(const ValueKey('gcash-shared-limit-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates ordered limits and keeps persisted settings', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    await _edit(tester);
    await tester.enterText(
      find.byKey(const ValueKey('gcash-shared-limit-1')),
      '500',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('gcash-settings-save')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Tier 2 needs an upper limit greater than'),
      findsOneWidget,
    );
    expect(
      container
          .read(gcashFeeSettingsProvider)
          .requireValue
          .shared
          .tiers
          .last
          .upperLimitCentavos,
      100000,
    );
    expect(find.text('GCash charges saved.'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(4));
  });

  testWidgets('shared toggle and tier add/delete work at 320 pixels', (
    tester,
  ) async {
    final container = await _pumpSettings(tester, width: 320);
    await _edit(tester);
    await tester.tap(find.byKey(const ValueKey('gcash-shared-auto-fill')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('gcash-shared-add-tier')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gcash-shared-add-tier')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Delete tier 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete tier 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gcash-settings-save')));
    await tester.pumpAndSettle();

    final settings = container.read(gcashFeeSettingsProvider).requireValue;
    expect(settings.shared.tiers.length, 2);
    for (final kind in GcashKind.values) {
      expect(settings.autoFillFor(kind), isFalse);
      expect(settings.feeFor(kind, 50000), isNull);
    }
    expect(find.text('Manual charge entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'added tier persists and covers the next centavo for both kinds',
    (tester) async {
      final container = await _pumpSettings(tester);
      await _edit(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('gcash-shared-add-tier')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('gcash-shared-add-tier')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('gcash-shared-fee-2')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('gcash-shared-fee-2')),
        '35',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('gcash-settings-save')));
      await tester.pumpAndSettle();

      final settings = container.read(gcashFeeSettingsProvider).requireValue;
      expect(settings.shared.tiers.length, 3);
      for (final kind in GcashKind.values) {
        expect(settings.feeFor(kind, 100000), 2000);
        expect(settings.feeFor(kind, 100001), 3500);
        expect(settings.feeFor(kind, 150000), 3500);
        expect(settings.feeFor(kind, 150001), isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid saved settings offer explicit example recovery', (
    tester,
  ) async {
    final container = await _pumpSettings(tester, saved: '{bad json');
    expect(
      find.textContaining('GCash charges could not be loaded'),
      findsOneWidget,
    );
    await tester.tap(find.text('Edit example charges'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gcash-shared-limit-19')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('gcash-settings-save')));
    await tester.pumpAndSettle();

    expect(
      container.read(gcashFeeSettingsProvider).requireValue.shared.tiers.length,
      20,
    );
    expect(find.text('GCash charges saved.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset examples remains a draft until explicitly saved', (
    tester,
  ) async {
    final container = await _pumpSettings(tester);
    await _edit(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('gcash-settings-reset')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gcash-settings-reset')));
    await tester.pumpAndSettle();
    expect(
      container.read(gcashFeeSettingsProvider).requireValue.shared.tiers.length,
      2,
    );
    await tester.tap(find.byKey(const ValueKey('gcash-settings-save')));
    await tester.pumpAndSettle();
    expect(
      container.read(gcashFeeSettingsProvider).requireValue.shared.tiers.length,
      20,
    );
    expect(find.byKey(const ValueKey('gcash-shared-row-19')), findsOneWidget);
    expect(find.byKey(const ValueKey('gcash-settings-reset')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'read-only table and edit controls fit larger text at 320 pixels',
    (tester) async {
      await _pumpSettings(tester, width: 320, textScale: 1.5);
      expect(tester.takeException(), isNull);
      await _edit(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
