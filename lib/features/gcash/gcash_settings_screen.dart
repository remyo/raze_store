import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'gcash_fee_settings.dart';
import 'gcash_record.dart';
import 'gcash_theme.dart';

class GcashSettingsScreen extends ConsumerStatefulWidget {
  const GcashSettingsScreen({super.key});

  @override
  ConsumerState<GcashSettingsScreen> createState() =>
      _GcashSettingsScreenState();
}

class _GcashSettingsScreenState extends ConsumerState<GcashSettingsScreen> {
  GcashFeeSettings? _saved;
  _ScheduleDraft? _draft;
  bool _dirty = false;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  bool get _editing => _draft != null;

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  void _replaceDraft(_ScheduleDraft? next) {
    final previous = _draft;
    _draft = next;
    // Let text fields detach before releasing their controllers.
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _edit() => setState(() {
    _replaceDraft(_ScheduleDraft(_saved!.shared));
    _dirty = false;
    _message = null;
  });

  void _cancel() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _replaceDraft(null);
      _dirty = false;
      _message = null;
    });
  }

  void _changed() => setState(() {
    _dirty = true;
    _message = null;
  });

  void _reset() => setState(() {
    _replaceDraft(_ScheduleDraft(GcashFeeSettings.defaults().shared));
    _dirty = true;
    _message = 'Example charges restored. Save to apply them.';
    _messageIsError = false;
  });

  Future<void> _save() async {
    if (_saving) return;
    GcashFeeSettings next;
    try {
      next = GcashFeeSettings(shared: _draft!.read());
    } on FormatException catch (error) {
      setState(() {
        _message = error.message;
        _messageIsError = true;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(gcashFeeSettingsProvider.notifier).save(next);
      if (!mounted) return;
      setState(() {
        _saved = next;
        _replaceDraft(null);
        _dirty = false;
        _message = 'GCash charges saved.';
        _messageIsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message =
            'Charges could not be saved. Your edits are still here; try again.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(gcashFeeSettingsProvider);
    if (!_editing && settings.hasValue) _saved = settings.requireValue;
    return GcashTheme(
      builder: (context) => PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('GCash Settings'),
            actions: [
              if (!_editing && _saved != null)
                TextButton.icon(
                  key: const ValueKey('gcash-settings-edit'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: _edit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: _saved == null && !_editing
                ? _loadingBody(settings)
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(
                        key: const ValueKey('gcash-settings-list'),
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                        children: [
                          _heading(context),
                          const SizedBox(height: 18),
                          if (!_editing && _message != null) ...[
                            _notice(context),
                            const SizedBox(height: 12),
                          ],
                          if (_editing) ...[
                            _automaticChargeControl(),
                            const SizedBox(height: 16),
                            _editTable(context, _draft!),
                            const SizedBox(height: 12),
                            _editActions(),
                          ] else
                            _chargeTable(context, _saved!.shared),
                          const SizedBox(height: 16),
                          Text(
                            'Above the last amount, enter the charge manually. '
                            'Saved transactions keep their original fees.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  height: 1.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          bottomNavigationBar: _editing ? _saveBar(context) : null,
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _draft?.autoFillEnabled ?? _saved!.shared.autoFillEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profit charges',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'One charge table for Cash In & Cash Out.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (!_editing) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  enabled ? Icons.bolt_rounded : Icons.edit_note_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    enabled ? 'Automatic charge on' : 'Manual charge entry',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _chargeTable(BuildContext context, GcashFeeSchedule schedule) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('gcash-shared-charge-table'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tableHeader(context, 'Amount range', 'Profit charge'),
          for (var index = 0; index < schedule.tiers.length; index++)
            Container(
              key: ValueKey('gcash-shared-row-$index'),
              color: index.isOdd
                  ? theme.colorScheme.primary.withValues(alpha: 0.035)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${_tableMoney(index == 0 ? 1 : schedule.tiers[index - 1].upperLimitCentavos + 1)}'
                      ' – ${_tableMoney(schedule.tiers[index].upperLimitCentavos)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _tableMoney(schedule.tiers[index].feeCentavos),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tableHeader(BuildContext context, String left, String right) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(left, style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              right,
              textAlign: TextAlign.right,
              style: theme.textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _automaticChargeControl() => Card(
    child: SwitchListTile.adaptive(
      key: const ValueKey('gcash-shared-auto-fill'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      title: const Text('Automatic charge'),
      subtitle: const Text('Use this table for Cash In and Cash Out.'),
      value: _draft!.autoFillEnabled,
      onChanged: _saving
          ? null
          : (value) {
              _draft!.autoFillEnabled = value;
              _changed();
            },
    ),
  );

  Widget _editTable(BuildContext context, _ScheduleDraft draft) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        _tableHeader(context, 'Amount up to', 'Profit charge'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 0),
          child: Column(
            children: [
              for (var index = 0; index < draft.tiers.length; index++)
                _tierRow(context, draft, index),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _editActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        key: const ValueKey('gcash-shared-add-tier'),
        onPressed: _saving || _draft!.tiers.length >= gcashFeeMaximumTiers
            ? null
            : () {
                final last = gcashCentavos(_draft!.tiers.last.limit.text);
                final limit =
                    last == null || last > gcashFeeMaximumCentavos - 50000
                    ? ''
                    : _editableMoney(last + 50000);
                _draft!.tiers.add(_TierDraft(limit, ''));
                _changed();
              },
        icon: const Icon(Icons.add),
        label: const Text('Add tier'),
      ),
      const SizedBox(height: 4),
      TextButton.icon(
        key: const ValueKey('gcash-settings-reset'),
        onPressed: _saving ? null : _reset,
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset to example charges'),
      ),
    ],
  );

  Widget _saveBar(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      heightFactor: 1,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_message != null) ...[
                _notice(context),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('gcash-settings-cancel'),
                      onPressed: _saving ? null : _cancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const ValueKey('gcash-settings-save'),
                      onPressed: _saving || !_dirty ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check, size: 18),
                      label: Text(_saving ? 'Saving…' : 'Save charges'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _notice(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      _message!,
      key: const ValueKey('gcash-settings-message'),
      style: TextStyle(
        color: _messageIsError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _loadingBody(AsyncValue<GcashFeeSettings> settings) {
    if (!settings.hasError) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32),
            const SizedBox(height: 12),
            const Text(
              'GCash charges could not be loaded. Retry, or edit the example charges and save a replacement.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => ref.invalidate(gcashFeeSettingsProvider),
              child: const Text('Retry'),
            ),
            TextButton(
              onPressed: _reset,
              child: const Text('Edit example charges'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tierRow(BuildContext context, _ScheduleDraft draft, int index) {
    final tier = draft.tiers[index];
    final previous = index == 0
        ? 0
        : gcashCentavos(draft.tiers[index - 1].limit.text);
    final upper = gcashCentavos(tier.limit.text);
    final range = previous != null && upper != null && upper > previous
        ? '${_tableMoney(previous + 1)} – ${_tableMoney(upper)}'
        : 'Enter an upper limit greater than the previous tier.';
    return Padding(
      key: ObjectKey(tier),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tier ${index + 1} · $range',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _amountField(
                  key: ValueKey('gcash-shared-limit-$index'),
                  controller: tier.limit,
                  label: 'Up to',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _amountField(
                  key: ValueKey('gcash-shared-fee-$index'),
                  controller: tier.fee,
                  label: 'Charge',
                ),
              ),
              IconButton(
                tooltip: 'Delete tier ${index + 1}',
                visualDensity: VisualDensity.compact,
                onPressed: _saving || draft.tiers.length == 1
                    ? null
                    : () {
                        draft.tiers.removeAt(index);
                        draft.removedTiers.add(tier);
                        _changed();
                      },
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amountField({
    required Key key,
    required TextEditingController controller,
    required String label,
  }) => TextField(
    key: key,
    controller: controller,
    enabled: !_saving,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(
      labelText: label,
      prefixText: '₱ ',
      isDense: true,
    ),
    onChanged: (_) => _changed(),
  );
}

class _ScheduleDraft {
  _ScheduleDraft(GcashFeeSchedule schedule)
    : autoFillEnabled = schedule.autoFillEnabled,
      tiers = schedule.tiers
          .map(
            (tier) => _TierDraft(
              _editableMoney(tier.upperLimitCentavos),
              _editableMoney(tier.feeCentavos),
            ),
          )
          .toList();

  bool autoFillEnabled;
  final List<_TierDraft> tiers;
  final List<_TierDraft> removedTiers = [];

  GcashFeeSchedule read() {
    final values = <GcashFeeTier>[];
    var previous = 0;
    for (var index = 0; index < tiers.length; index++) {
      final tier = tiers[index];
      final upper = gcashCentavos(tier.limit.text);
      final fee = gcashCentavos(tier.fee.text);
      if (upper == null || upper <= previous) {
        throw FormatException(
          'Tier ${index + 1} needs an upper limit greater than '
          '${_tableMoney(previous)} (at most two decimal places).',
        );
      }
      if (fee == null) {
        throw FormatException(
          'Tier ${index + 1} needs a charge of zero or more '
          '(at most two decimal places).',
        );
      }
      values.add(GcashFeeTier(upperLimitCentavos: upper, feeCentavos: fee));
      previous = upper;
    }
    return GcashFeeSchedule(autoFillEnabled: autoFillEnabled, tiers: values);
  }

  void dispose() {
    for (final tier in [...tiers, ...removedTiers]) {
      tier.dispose();
    }
  }
}

class _TierDraft {
  _TierDraft(String upperLimit, String charge)
    : limit = TextEditingController(text: upperLimit),
      fee = TextEditingController(text: charge);

  final TextEditingController limit;
  final TextEditingController fee;

  void dispose() {
    limit.dispose();
    fee.dispose();
  }
}

String _editableMoney(int centavos) => (centavos / 100).toStringAsFixed(2);

final _wholeCurrency = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 0,
);
final _decimalCurrency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
String _tableMoney(int centavos) =>
    (centavos % 100 == 0 ? _wholeCurrency : _decimalCurrency).format(
      centavos / 100,
    );
