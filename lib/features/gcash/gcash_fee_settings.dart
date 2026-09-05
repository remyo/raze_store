import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme_mode_controller.dart';
import 'gcash_record.dart';

const gcashFeeSettingsPreferenceKey = 'raze_store.gcash.fee_settings';
const gcashFeeMaximumCentavos = 99999999999;
const gcashFeeMaximumTiers = 100;

/// An inclusive upper bound. The previous tier's bound plus one centavo is
/// this tier's lower bound, so fractional-peso amounts never fall into gaps.
class GcashFeeTier {
  const GcashFeeTier({
    required this.upperLimitCentavos,
    required this.feeCentavos,
  });

  final int upperLimitCentavos;
  final int feeCentavos;

  Map<String, Object?> toJson() => {
    'upperLimitCentavos': upperLimitCentavos,
    'feeCentavos': feeCentavos,
  };

  factory GcashFeeTier.fromJson(Map<String, dynamic> json) {
    _expectFields(json, {'upperLimitCentavos', 'feeCentavos'});
    final upperLimit = json['upperLimitCentavos'];
    final fee = json['feeCentavos'];
    if (upperLimit is! int || fee is! int) {
      throw const FormatException('Fee amounts must be whole centavos.');
    }
    final result = GcashFeeTier(
      upperLimitCentavos: upperLimit,
      feeCentavos: fee,
    );
    result._validate();
    return result;
  }

  void _validate() {
    if (upperLimitCentavos <= 0 ||
        upperLimitCentavos > gcashFeeMaximumCentavos ||
        feeCentavos < 0 ||
        feeCentavos > gcashFeeMaximumCentavos) {
      throw const FormatException('Check the fee tier amounts.');
    }
  }
}

class GcashFeeSchedule {
  GcashFeeSchedule({
    required this.autoFillEnabled,
    required List<GcashFeeTier> tiers,
  }) : tiers = List.unmodifiable(tiers) {
    if (this.tiers.isEmpty || this.tiers.length > gcashFeeMaximumTiers) {
      throw const FormatException('Use between 1 and 100 fee tiers.');
    }
    var previousLimit = 0;
    for (final tier in this.tiers) {
      tier._validate();
      if (tier.upperLimitCentavos <= previousLimit) {
        throw const FormatException(
          'Tier upper limits must increase in order.',
        );
      }
      previousLimit = tier.upperLimitCentavos;
    }
  }

  final bool autoFillEnabled;
  final List<GcashFeeTier> tiers;

  GcashFeeSchedule copyWith({
    bool? autoFillEnabled,
    List<GcashFeeTier>? tiers,
  }) => GcashFeeSchedule(
    autoFillEnabled: autoFillEnabled ?? this.autoFillEnabled,
    tiers: tiers ?? this.tiers,
  );

  Map<String, Object?> toJson() => {
    'autoFillEnabled': autoFillEnabled,
    'tiers': tiers.map((tier) => tier.toJson()).toList(),
  };

  factory GcashFeeSchedule.fromJson(Map<String, dynamic> json) {
    _expectFields(json, {'autoFillEnabled', 'tiers'});
    final enabled = json['autoFillEnabled'];
    final tiers = json['tiers'];
    if (enabled is! bool || tiers is! List) {
      throw const FormatException('Invalid fee schedule.');
    }
    if (tiers.isEmpty || tiers.length > gcashFeeMaximumTiers) {
      throw const FormatException('Use between 1 and 100 fee tiers.');
    }
    return GcashFeeSchedule(
      autoFillEnabled: enabled,
      tiers: tiers
          .map((tier) => GcashFeeTier.fromJson(_expectObject(tier)))
          .toList(),
    );
  }
}

class GcashFeeSettings {
  /// Cash In and Cash Out use one store charge table. Legacy callers may still
  /// supply either name; Cash In takes precedence if both are supplied.
  GcashFeeSettings({
    GcashFeeSchedule? shared,
    GcashFeeSchedule? cashIn,
    GcashFeeSchedule? cashOut,
  }) : shared =
           shared ??
           cashIn ??
           cashOut ??
           (throw const FormatException('A shared fee schedule is required.'));

  factory GcashFeeSettings.defaults() {
    return GcashFeeSettings(
      shared: GcashFeeSchedule(
        autoFillEnabled: true,
        tiers: List.generate(
          20,
          (index) => GcashFeeTier(
            upperLimitCentavos: (index + 1) * 50000,
            feeCentavos: (index + 1) * 1000,
          ),
        ),
      ),
    );
  }

  final GcashFeeSchedule shared;

  GcashFeeSchedule get cashIn => shared;
  GcashFeeSchedule get cashOut => shared;

  GcashFeeSchedule scheduleFor(GcashKind kind) => shared;

  bool autoFillFor(GcashKind kind) => scheduleFor(kind).autoFillEnabled;

  int? feeFor(GcashKind kind, int amountCentavos) {
    final schedule = scheduleFor(kind);
    if (!schedule.autoFillEnabled || amountCentavos <= 0) return null;
    for (final tier in schedule.tiers) {
      if (amountCentavos <= tier.upperLimitCentavos) return tier.feeCentavos;
    }
    return null;
  }

  GcashFeeSettings copyWith({
    GcashFeeSchedule? shared,
    GcashFeeSchedule? cashIn,
    GcashFeeSchedule? cashOut,
  }) => GcashFeeSettings(shared: shared ?? cashIn ?? cashOut ?? this.shared);

  Map<String, Object?> toJson() => {'version': 2, 'shared': shared.toJson()};

  factory GcashFeeSettings.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int || (version != 1 && version != 2)) {
      throw const FormatException('Unsupported GCash fee settings version.');
    }
    if (version == 1) {
      _expectFields(json, {'version', 'cashIn', 'cashOut'});
      final cashIn = GcashFeeSchedule.fromJson(_expectObject(json['cashIn']));
      // Validate the entire older payload before importing anything. Its saved
      // Cash In schedule becomes shared; historical transaction fees are stored
      // separately and are never recalculated by this migration.
      GcashFeeSchedule.fromJson(_expectObject(json['cashOut']));
      return GcashFeeSettings(shared: cashIn);
    }
    _expectFields(json, {'version', 'shared'});
    return GcashFeeSettings(
      shared: GcashFeeSchedule.fromJson(_expectObject(json['shared'])),
    );
  }
}

Map<String, dynamic> _expectObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected a GCash fee settings object.');
  }
  return value;
}

void _expectFields(Map<String, dynamic> json, Set<String> expected) {
  if (json.length != expected.length || !expected.every(json.containsKey)) {
    throw const FormatException('Invalid GCash fee settings fields.');
  }
}

final gcashFeeSettingsProvider =
    AsyncNotifierProvider<GcashFeeSettingsController, GcashFeeSettings>(
      GcashFeeSettingsController.new,
      retry: (_, _) => null,
    );

class GcashFeeSettingsController extends AsyncNotifier<GcashFeeSettings> {
  Future<void>? _pendingSave;

  @override
  Future<GcashFeeSettings> build() async {
    final preferences = await ref.watch(sharedPreferencesProvider.future);
    final saved = preferences.get(gcashFeeSettingsPreferenceKey);
    if (saved == null) return GcashFeeSettings.defaults();
    if (saved is! String) {
      throw const FormatException('Saved GCash fee settings are invalid.');
    }
    return GcashFeeSettings.fromJson(_expectObject(jsonDecode(saved)));
  }

  Future<void> save(GcashFeeSettings settings) {
    if (_pendingSave != null) {
      return Future.error(StateError('GCash fee settings are already saving.'));
    }
    final operation = _save(settings);
    _pendingSave = operation;
    return operation.whenComplete(() => _pendingSave = null);
  }

  Future<void> _save(GcashFeeSettings settings) async {
    // Validate the full payload before replacing any stored configuration.
    final payload = jsonEncode(
      GcashFeeSettings.fromJson(settings.toJson()).toJson(),
    );
    // Set loading only once initial loading has completed, including a failed
    // load; users can explicitly replace a malformed saved table with examples.
    if (state.isLoading) {
      try {
        await future;
      } catch (_) {
        // Saving an explicit replacement is allowed after a load error.
      }
    }
    if (!ref.mounted) return;
    state = const AsyncLoading();
    try {
      final preferences = await ref.read(sharedPreferencesProvider.future);
      final saved = await preferences.setString(
        gcashFeeSettingsPreferenceKey,
        payload,
      );
      if (!saved) throw StateError('Could not save GCash fee settings.');
      if (ref.mounted) state = AsyncData(settings);
    } catch (error, stackTrace) {
      if (ref.mounted) state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
