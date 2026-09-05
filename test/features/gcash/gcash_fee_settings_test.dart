import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme_mode_controller.dart';
import 'package:raze_store/features/gcash/gcash_fee_settings.dart';
import 'package:raze_store/features/gcash/gcash_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('GCash fee schedules', () {
    test('defaults apply every tier at its inclusive amount boundaries', () {
      final settings = GcashFeeSettings.defaults();

      expect(settings.cashIn, same(settings.shared));
      expect(settings.cashOut, same(settings.shared));
      for (final kind in GcashKind.values) {
        final schedule = settings.scheduleFor(kind);
        expect(settings.autoFillFor(kind), isTrue);
        expect(schedule.tiers, hasLength(20));
        for (var tier = 1; tier <= 20; tier++) {
          final lower = (tier - 1) * 50000 + 1;
          final upper = tier * 50000;
          expect(schedule.tiers[tier - 1].upperLimitCentavos, upper);
          expect(schedule.tiers[tier - 1].feeCentavos, tier * 1000);
          expect(
            settings.feeFor(kind, lower),
            tier * 1000,
            reason: '${kind.name}: the first centavo of tier $tier',
          );
          expect(
            settings.feeFor(kind, upper),
            tier * 1000,
            reason: '${kind.name}: the last centavo of tier $tier',
          );
        }
        expect(settings.feeFor(kind, -1), isNull);
        expect(settings.feeFor(kind, 0), isNull);
        expect(settings.feeFor(kind, 1000001), isNull);
        expect(settings.feeFor(kind, 99999999999), isNull);
      }
    });

    test('shared edits and auto-fill apply to both transaction kinds', () {
      final original = GcashFeeSettings.defaults();
      final changed = original.copyWith(
        shared: original.shared.copyWith(
          tiers: const [
            GcashFeeTier(upperLimitCentavos: 20000, feeCentavos: 0),
            GcashFeeTier(upperLimitCentavos: 70000, feeCentavos: 1500),
          ],
        ),
      );

      expect(changed.scheduleFor(GcashKind.cashIn), same(changed.cashIn));
      expect(changed.scheduleFor(GcashKind.cashOut), same(changed.cashOut));
      for (final kind in GcashKind.values) {
        expect(changed.autoFillFor(kind), isTrue);
        expect(changed.feeFor(kind, 1), 0);
        expect(changed.feeFor(kind, 20000), 0);
        expect(changed.feeFor(kind, 20001), 1500);
        expect(changed.feeFor(kind, 70000), 1500);
        expect(changed.feeFor(kind, 70001), isNull);
      }
      expect(original.autoFillFor(GcashKind.cashIn), isTrue);
      expect(original.feeFor(GcashKind.cashIn, 10000), 1000);
      expect(original.feeFor(GcashKind.cashOut, 20000), 1000);

      final disabled = changed.copyWith(
        shared: changed.shared.copyWith(autoFillEnabled: false),
      );
      for (final kind in GcashKind.values) {
        expect(disabled.autoFillFor(kind), isFalse);
        expect(disabled.feeFor(kind, 10000), isNull);
      }
      expect(changed.copyWith().toJson(), changed.toJson());
    });

    test('legacy constructor and copy names address the same schedule', () {
      final first = GcashFeeSettings.defaults().shared;
      final second = first.copyWith(autoFillEnabled: false);
      final legacy = GcashFeeSettings(cashIn: first, cashOut: second);
      expect(legacy.shared, same(first));
      expect(legacy.cashOut, same(first));
      expect(legacy.copyWith(cashOut: second).cashIn, same(second));
      expect(legacy.copyWith(cashIn: second).cashOut, same(second));
    });

    test('copies input tiers and exposes an immutable list', () {
      final source = [
        const GcashFeeTier(upperLimitCentavos: 100, feeCentavos: 5),
      ];
      final schedule = GcashFeeSchedule(autoFillEnabled: true, tiers: source);
      source[0] = const GcashFeeTier(upperLimitCentavos: 200, feeCentavos: 10);
      source.clear();

      expect(schedule.tiers.single.upperLimitCentavos, 100);
      expect(schedule.tiers.single.feeCentavos, 5);
      expect(() => schedule.tiers.clear(), throwsUnsupportedError);
      expect(
        () => schedule.tiers[0] = const GcashFeeTier(
          upperLimitCentavos: 200,
          feeCentavos: 10,
        ),
        throwsUnsupportedError,
      );

      final replacement = [
        const GcashFeeTier(upperLimitCentavos: 300, feeCentavos: 15),
      ];
      final copied = schedule.copyWith(tiers: replacement);
      replacement.clear();
      expect(copied.tiers.single.upperLimitCentavos, 300);
      expect(schedule.tiers.single.upperLimitCentavos, 100);
      expect(() => copied.tiers.removeLast(), throwsUnsupportedError);
    });

    test('validates programmatic construction and copyWith', () {
      expect(
        () => GcashFeeSchedule(autoFillEnabled: true, tiers: []),
        throwsFormatException,
      );
      expect(
        () => GcashFeeSettings.defaults().cashIn.copyWith(
          tiers: const [
            GcashFeeTier(upperLimitCentavos: 200, feeCentavos: 10),
            GcashFeeTier(upperLimitCentavos: 100, feeCentavos: 20),
          ],
        ),
        throwsFormatException,
      );
    });
  });

  group('GCash fee settings JSON', () {
    test('uses version 2 and round trips the shared schedule', () {
      final json = _validJson();
      final settings = GcashFeeSettings.fromJson(json);

      expect(settings.toJson(), json);
      expect(settings.cashIn.autoFillEnabled, isTrue);
      expect(settings.cashOut.autoFillEnabled, isTrue);
      expect(settings.cashIn.tiers[0].feeCentavos, 0);
      expect(settings.cashOut.tiers.last.feeCentavos, 1750);
      expect(
        GcashFeeSettings.fromJson(
          jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
        ).toJson(),
        json,
      );
      expect(() => settings.cashIn.tiers.clear(), throwsUnsupportedError);
    });

    test(
      'migrates version 1 using saved Cash In charges and automatic flag',
      () {
        final legacy = _legacyJson();
        final migrated = GcashFeeSettings.fromJson(legacy);
        expect(migrated.toJson(), _validJson());
        expect(migrated.cashOut, same(migrated.cashIn));
        expect(migrated.feeFor(GcashKind.cashOut, 50001), 1750);
        expect(migrated.autoFillFor(GcashKind.cashOut), isTrue);
        (legacy['cashIn'] as Map<String, dynamic>)['autoFillEnabled'] = false;
        (legacy['cashOut'] as Map<String, dynamic>)['autoFillEnabled'] = true;
        final disabled = GcashFeeSettings.fromJson(legacy);
        for (final kind in GcashKind.values) {
          expect(disabled.autoFillFor(kind), isFalse);
          expect(disabled.feeFor(kind, 100), isNull);
        }
      },
    );

    test('validates unused Cash Out data before importing legacy settings', () {
      final legacy = _legacyJson();
      (legacy['cashOut'] as Map<String, dynamic>)['tiers'] = [];
      expect(() => GcashFeeSettings.fromJson(legacy), throwsFormatException);
      legacy.remove('cashOut');
      expect(() => GcashFeeSettings.fromJson(legacy), throwsFormatException);
    });

    test('accepts maximum supported values and exactly 100 tiers', () {
      final json = _validJson();
      _schedule(json)['tiers'] = List.generate(
        100,
        (index) => <String, dynamic>{
          'upperLimitCentavos': index == 99 ? 99999999999 : index + 1,
          'feeCentavos': index == 99 ? 99999999999 : 0,
        },
      );

      final settings = GcashFeeSettings.fromJson(json);
      expect(settings.cashIn.tiers, hasLength(100));
      expect(settings.feeFor(GcashKind.cashIn, 1), 0);
      expect(settings.feeFor(GcashKind.cashIn, 99999999999), 99999999999);
      expect(settings.feeFor(GcashKind.cashIn, 100000000000), isNull);
    });

    final invalidCases = <String, void Function(Map<String, dynamic>)>{
      'missing version': (json) => json.remove('version'),
      'unsupported version': (json) => json['version'] = 3,
      'double version': (json) => json['version'] = 2.0,
      'string version': (json) => json['version'] = '2',
      'unknown root field': (json) => json['other'] = true,
      'missing shared schedule': (json) => json.remove('shared'),
      'null schedule': (json) => json['shared'] = null,
      'non-map schedule': (json) => json['shared'] = [],
      'unknown schedule field': (json) => _schedule(json)['other'] = true,
      'missing auto-fill flag': (json) =>
          _schedule(json).remove('autoFillEnabled'),
      'string auto-fill flag': (json) =>
          _schedule(json)['autoFillEnabled'] = 'true',
      'null auto-fill flag': (json) =>
          _schedule(json)['autoFillEnabled'] = null,
      'missing tiers': (json) => _schedule(json).remove('tiers'),
      'non-list tiers': (json) => _schedule(json)['tiers'] = {},
      'empty tiers': (json) => _schedule(json)['tiers'] = [],
      'more than 100 tiers': (json) => _schedule(json)['tiers'] = List.generate(
        101,
        (index) => {'upperLimitCentavos': index + 1, 'feeCentavos': 0},
      ),
      'null tier': (json) => _tiers(json)[0] = null,
      'non-map tier': (json) => _tiers(json)[0] = 50000,
      'missing upper limit': (json) => _tier(json).remove('upperLimitCentavos'),
      'missing fee': (json) => _tier(json).remove('feeCentavos'),
      'unknown tier field': (json) => _tier(json)['other'] = 1,
      'double upper limit': (json) =>
          _tier(json)['upperLimitCentavos'] = 50000.0,
      'string upper limit': (json) =>
          _tier(json)['upperLimitCentavos'] = '50000',
      'null upper limit': (json) => _tier(json)['upperLimitCentavos'] = null,
      'zero upper limit': (json) => _tier(json)['upperLimitCentavos'] = 0,
      'negative upper limit': (json) => _tier(json)['upperLimitCentavos'] = -1,
      'upper limit above maximum': (json) =>
          _tier(json, index: 1)['upperLimitCentavos'] = 100000000000,
      'unsorted upper limits': (json) =>
          _tier(json, index: 1)['upperLimitCentavos'] = 49999,
      'duplicate upper limits': (json) =>
          _tier(json, index: 1)['upperLimitCentavos'] = 50000,
      'double fee': (json) => _tier(json)['feeCentavos'] = 1000.0,
      'string fee': (json) => _tier(json)['feeCentavos'] = '1000',
      'null fee': (json) => _tier(json)['feeCentavos'] = null,
      'negative fee': (json) => _tier(json)['feeCentavos'] = -1,
      'fee above maximum': (json) => _tier(json)['feeCentavos'] = 100000000000,
      'invalid shared schedule while disabled': (json) {
        _schedule(json)['autoFillEnabled'] = false;
        _schedule(json)['tiers'] = [];
      },
    };

    for (final entry in invalidCases.entries) {
      test('rejects ${entry.key} with a FormatException', () {
        final json = _validJson();
        entry.value(json);
        expect(() => GcashFeeSettings.fromJson(json), throwsFormatException);
      });
    }
  });

  group('GCash fee settings persistence', () {
    test('missing preference loads defaults without writing storage', () async {
      final container = ProviderContainer(retry: (_, _) => null);
      addTearDown(container.dispose);

      final settings = await container.read(gcashFeeSettingsProvider.future);
      final preferences = await SharedPreferences.getInstance();

      expect(gcashFeeSettingsPreferenceKey, 'raze_store.gcash.fee_settings');
      expect(settings.toJson(), GcashFeeSettings.defaults().toJson());
      expect(container.read(gcashFeeSettingsProvider).hasValue, isTrue);
      expect(preferences.getKeys(), isEmpty);
    });

    test(
      'saves one JSON string and reloads shared charges for both kinds',
      () async {
        SharedPreferences.setMockInitialValues({'unrelated': 'keep'});
        final writer = ProviderContainer(retry: (_, _) => null);
        addTearDown(writer.dispose);
        await writer.read(gcashFeeSettingsProvider.future);
        final settings = GcashFeeSettings.fromJson(_validJson());

        await writer.read(gcashFeeSettingsProvider.notifier).save(settings);

        expect(
          writer.read(gcashFeeSettingsProvider).requireValue.toJson(),
          settings.toJson(),
        );
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getKeys(), {
          'unrelated',
          gcashFeeSettingsPreferenceKey,
        });
        expect(preferences.getString('unrelated'), 'keep');
        expect(
          jsonDecode(preferences.getString(gcashFeeSettingsPreferenceKey)!),
          _validJson(),
        );

        final reader = ProviderContainer(retry: (_, _) => null);
        addTearDown(reader.dispose);
        final reloaded = await reader.read(gcashFeeSettingsProvider.future);
        expect(reloaded.toJson(), _validJson());
        expect(reloaded.feeFor(GcashKind.cashIn, 50001), 1750);
        expect(reloaded.autoFillFor(GcashKind.cashOut), isTrue);
        expect(reloaded.feeFor(GcashKind.cashOut, 50001), 1750);
      },
    );

    test(
      'loads legacy preferences without a write and saves version 2',
      () async {
        final legacy = jsonEncode(_legacyJson());
        SharedPreferences.setMockInitialValues({
          gcashFeeSettingsPreferenceKey: legacy,
        });
        final container = ProviderContainer(retry: (_, _) => null);
        addTearDown(container.dispose);
        final settings = await container.read(gcashFeeSettingsProvider.future);
        final preferences = await SharedPreferences.getInstance();
        expect(settings.toJson(), _validJson());
        expect(preferences.getString(gcashFeeSettingsPreferenceKey), legacy);
        await container.read(gcashFeeSettingsProvider.notifier).save(settings);
        expect(
          jsonDecode(preferences.getString(gcashFeeSettingsPreferenceKey)!),
          _validJson(),
        );
      },
    );

    for (final corrupt in ['not JSON', 'null', '[]', '{}', '{"version":2}']) {
      test('corrupt saved value $corrupt exposes a loading error', () async {
        SharedPreferences.setMockInitialValues({
          gcashFeeSettingsPreferenceKey: corrupt,
        });
        final container = ProviderContainer(retry: (_, _) => null);
        addTearDown(container.dispose);

        await expectLater(
          container.read(gcashFeeSettingsProvider.future),
          throwsFormatException,
        );

        expect(container.read(gcashFeeSettingsProvider).hasError, isTrue);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString(gcashFeeSettingsPreferenceKey), corrupt);
      });
    }

    test('non-string saved preference exposes an error', () async {
      SharedPreferences.setMockInitialValues({
        gcashFeeSettingsPreferenceKey: 7,
      });
      final container = ProviderContainer(retry: (_, _) => null);
      addTearDown(container.dispose);

      await expectLater(
        container.read(gcashFeeSettingsProvider.future),
        throwsA(anything),
      );

      expect(container.read(gcashFeeSettingsProvider).hasError, isTrue);
    });

    test('storage initialization failures remain visible', () async {
      final failure = StateError('Storage unavailable');
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => throw failure),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(gcashFeeSettingsProvider.future),
        throwsA(same(failure)),
      );

      expect(container.read(gcashFeeSettingsProvider).hasError, isTrue);
    });

    test('rejected persistence does not apply unsaved fee settings', () async {
      final stored = jsonEncode(_validJson());
      final preferences = _RejectingPreferences(stored);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) => preferences),
        ],
      );
      addTearDown(container.dispose);
      final before = await container.read(gcashFeeSettingsProvider.future);

      await expectLater(
        container
            .read(gcashFeeSettingsProvider.notifier)
            .save(GcashFeeSettings.defaults()),
        throwsA(anything),
      );

      expect(preferences.attemptedKey, gcashFeeSettingsPreferenceKey);
      expect(
        jsonDecode(preferences.attemptedValue!),
        GcashFeeSettings.defaults().toJson(),
      );
      expect(preferences.getString(gcashFeeSettingsPreferenceKey), stored);
      expect(container.read(gcashFeeSettingsProvider).hasError, isTrue);
      expect(
        container.read(gcashFeeSettingsProvider).requireValue.toJson(),
        before.toJson(),
      );
      container.invalidate(gcashFeeSettingsProvider);
      expect(
        (await container.read(gcashFeeSettingsProvider.future)).toJson(),
        before.toJson(),
      );
    });
  });
}

Map<String, dynamic> _validJson() => {
  'version': 2,
  'shared': <String, dynamic>{
    'autoFillEnabled': true,
    'tiers': <dynamic>[
      <String, dynamic>{'upperLimitCentavos': 50000, 'feeCentavos': 0},
      <String, dynamic>{'upperLimitCentavos': 100000, 'feeCentavos': 1750},
    ],
  },
};

Map<String, dynamic> _legacyJson() => {
  'version': 1,
  'cashIn': _validJson()['shared'],
  'cashOut': <String, dynamic>{
    'autoFillEnabled': false,
    'tiers': <dynamic>[
      <String, dynamic>{'upperLimitCentavos': 30000, 'feeCentavos': 125},
    ],
  },
};

Map<String, dynamic> _schedule(Map<String, dynamic> json) =>
    json['shared'] as Map<String, dynamic>;

List<dynamic> _tiers(Map<String, dynamic> json) =>
    _schedule(json)['tiers'] as List<dynamic>;

Map<String, dynamic> _tier(Map<String, dynamic> json, {int index = 0}) =>
    _tiers(json)[index] as Map<String, dynamic>;

class _RejectingPreferences extends Fake implements SharedPreferences {
  _RejectingPreferences(this.saved);

  final String saved;
  String? attemptedKey;
  String? attemptedValue;

  @override
  Object? get(String key) =>
      key == gcashFeeSettingsPreferenceKey ? saved : null;

  @override
  String? getString(String key) =>
      key == gcashFeeSettingsPreferenceKey ? saved : null;

  @override
  bool containsKey(String key) => key == gcashFeeSettingsPreferenceKey;

  @override
  Future<bool> setString(String key, String value) async {
    attemptedKey = key;
    attemptedValue = value;
    return false;
  }
}
