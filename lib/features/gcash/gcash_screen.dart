import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:raze_store/core/widgets/app_toast.dart';
import 'package:raze_store/features/catalog/application/product_text_recognizer.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';
import 'package:raze_store/features/receipt/application/receipt_export_service.dart';
import 'gcash_parser.dart';
import 'gcash_record.dart';
import 'gcash_repository.dart';
import 'gcash_fee_settings.dart';
import 'gcash_settings_screen.dart';
import 'gcash_theme.dart';
export 'gcash_form_sheet.dart' show showGcashFormSheet;
export 'gcash_history_screen.dart' show GcashScreen;

String _money(int value) =>
    NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(value / 100);

class GcashFormScreen extends ConsumerStatefulWidget {
  const GcashFormScreen({
    super.key,
    required this.kind,
    this.record,
    this.asBottomSheet = false,
    this.scrollController,
    this.onBusyChanged,
  });
  final GcashKind kind;
  final GcashRecord? record;
  final bool asBottomSheet;
  final ScrollController? scrollController;
  final ValueChanged<bool>? onBusyChanged;
  @override
  ConsumerState<GcashFormScreen> createState() => _GcashFormScreenState();
}

class _GcashFormScreenState extends ConsumerState<GcashFormScreen> {
  final _form = GlobalKey<FormState>();
  final _fieldKeys = <String, GlobalKey<FormFieldState<String>>>{};
  final _dateKey = GlobalKey();
  final _verificationKey = GlobalKey();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _amount = TextEditingController();
  final _fee = TextEditingController(text: '0.00');
  final _reference = TextEditingController();
  DateTime? _date;
  Uint8List? _receipt;
  bool _busy = false;
  bool _verified = false;
  String? _rawText;
  String? _receiptNotice;
  late final String _id;
  bool _customFee = false;
  AsyncValue<GcashFeeSettings> _feeSettings = const AsyncLoading();
  late final ProviderSubscription<AsyncValue<GcashFeeSettings>>
  _feeSubscription;
  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _customFee = record != null;
    _id = record?.id ?? const Uuid().v4();
    if (record != null) {
      _name.text = record.name;
      _number.text = record.number;
      _amount.text = (record.amount / 100).toStringAsFixed(2);
      _fee.text = (record.fee / 100).toStringAsFixed(2);
      _reference.text = record.reference;
      _date = record.date;
      _receipt = record.receipt;
      _verified = true;
    }
    _amount.addListener(_amountChanged);
    _feeSubscription = ref.listenManual(gcashFeeSettingsProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      setState(() {
        _feeSettings = next;
        _applyDefaultFee();
      });
    }, fireImmediately: true);
  }

  void _amountChanged() {
    if (mounted) setState(_applyDefaultFee);
  }

  void _applyDefaultFee() {
    if (_customFee) return;
    final settings = _feeSettings.value;
    if (settings == null) return;
    final amount = gcashCentavos(_amount.text);
    if (amount == null || amount == 0 || !settings.autoFillFor(widget.kind)) {
      _fee.text = '0.00';
      return;
    }
    final suggested = settings.feeFor(widget.kind, amount);
    _fee.text = suggested == null ? '' : (suggested / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _feeSubscription.close();
    _amount.removeListener(_amountChanged);
    for (final controller in [_name, _number, _amount, _fee, _reference]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _message(String message, {AppToastType type = AppToastType.info}) {
    if (mounted) {
      showToast(context, message, type: type);
    }
  }

  Future<void> _reveal(BuildContext? fieldContext) async {
    if (fieldContext == null || !fieldContext.mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 200),
      alignment: 0.15,
    );
  }

  void _setBusy(bool value) {
    if (!mounted || _busy == value) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  Future<void> _pick(bool camera) async {
    if (_busy) return;
    _setBusy(true);
    try {
      final file = camera
          ? await ref
                .read(productCaptureLauncherProvider)
                .capture(context, purpose: ProductCapturePurpose.gcashReceipt)
          : await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final original = await file.readAsBytes();
      if (original.length > 20000000) {
        _message('Choose an image smaller than 20 MB.');
        return;
      }
      final codec = await ui.instantiateImageCodec(
        original,
        targetWidth: 1000,
        allowUpscaling: false,
      );
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final receipt = data!.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (receipt.length > 2000000) {
        _message(
          'Crop the receipt more closely; the saved image must be under 2 MB.',
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _customFee = false;
        _verified = false;
        _rawText = null;
        _receiptNotice = null;
        _name.clear();
        _number.clear();
        _amount.clear();
        _reference.clear();
        _fee.text = '0.00';
        _date = null;
      });
      try {
        final result = await ref
            .read(productTextRecognizerProvider)
            .recognizeImagePath(file.path);
        if (!mounted) return;
        final details = parseGcashReceipt(result.rawText, widget.kind);
        setState(() {
          _rawText = result.rawText;
          _receiptNotice = !details.isGcashReceipt
              ? 'GCash receipt not recognized. Other receipts can be hard to read; enter and check the details manually.'
              : details.recipientOnly
              ? 'This Express Send receipt shows the recipient, not the sender. For Cash Out, enter the customer’s name and number manually.'
              : null;
          // A replacement receipt must never retain another transaction's details.
          _name.text = details.name ?? '';
          _number.text = details.number ?? '';
          _amount.text = details.amount == null
              ? ''
              : (details.amount! / 100).toStringAsFixed(2);
          _reference.text = details.reference ?? '';
          _date = details.date;
        });
        _message(
          'Receipt attached. Review the details before saving.',
          type: AppToastType.success,
        );
      } catch (_) {
        if (mounted) {
          setState(() {
            _receiptNotice =
                'The receipt text could not be read. Please enter the details manually.';
          });
        }
        _message(
          'Photo attached. Text could not be read; enter the details manually.',
        );
      }
    } catch (_) {
      _message(
        'Could not open the photo. Check camera/photos access and try again.',
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _chooseDate(BuildContext pageContext) async {
    final day = await showDatePicker(
      context: pageContext,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (day == null || !pageContext.mounted) return;
    final time = await showTimePicker(
      context: pageContext,
      initialTime: TimeOfDay.fromDateTime(_date ?? DateTime.now()),
    );
    if (time != null && mounted) {
      setState(
        () => _date = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_customFee && !_feeSettings.hasValue) {
      _message(
        _feeSettings.isLoading
            ? 'Loading your default charges…'
            : 'Enter the service fee manually or reload GCash settings.',
      );
      return;
    }
    final invalidFields = _form.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      final invalid = _fieldKeys.entries.firstWhere(
        (entry) => invalidFields.contains(entry.value.currentState),
      );
      final error = invalid.value.currentState!.errorText!;
      _message(
        error == 'Required' ? 'Enter ${invalid.key.toLowerCase()}.' : error,
        type: AppToastType.error,
      );
      await _reveal(invalid.value.currentContext);
      return;
    }
    if (_date == null) {
      _message(
        'Choose the transaction date and time.',
        type: AppToastType.error,
      );
      await _reveal(_dateKey.currentContext);
      return;
    }
    if (widget.kind == GcashKind.cashOut && !_verified) {
      _message(
        'Confirm payment in GCash before recording a completed Cash Out.',
        type: AppToastType.error,
      );
      await _reveal(_verificationKey.currentContext);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final record = GcashRecord(
      id: _id,
      kind: widget.kind,
      name: _name.text.trim(),
      number: _number.text.trim(),
      amount: gcashCentavos(_amount.text)!,
      fee: gcashCentavos(_fee.text)!,
      reference: normalizeGcashReference(_reference.text),
      date: _date!,
      receipt: _receipt,
    );
    _setBusy(true);
    try {
      await ref.read(gcashRepositoryProvider).save(record);
      if (mounted) {
        _setBusy(false);
        // Clear PopScope/drag guards before returning the committed record.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        _message('GCash record saved.', type: AppToastType.success);
        Navigator.of(context).pop<GcashRecord>(record);
      }
    } on DuplicateGcashReference {
      _message(
        'This reference number already exists. Open the existing record in GCash history.',
        type: AppToastType.error,
      );
      await _reveal(
        _fieldKeys['Reference / transaction number']?.currentContext,
      );
    } on FormatException catch (error) {
      _message(error.message, type: AppToastType.error);
    } catch (_) {
      _message(
        'Record not saved. Please try again; your details are still here.',
        type: AppToastType.error,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _delete(BuildContext pageContext) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (context) => AlertDialog(
        title: const Text('Delete GCash record?'),
        content: const Text(
          'This removes the saved record and its receipt from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _setBusy(true);
    try {
      await ref.read(gcashRepositoryProvider).delete(_id);
      if (mounted) {
        _setBusy(false);
        Navigator.pop(context);
      }
    } catch (_) {
      _message('Could not delete the record.');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _export(bool share, BuildContext anchor) async {
    if (_busy) return;
    _setBusy(true);
    try {
      final service = ReceiptExportService.device();
      final box = anchor.findRenderObject() as RenderBox?;
      if (share) {
        await service.sharePng(
          bytes: _receipt!,
          fileName: 'gcash-$_id.png',
          storeName: 'GCash receipt',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      } else {
        final result = await service.savePng(
          bytes: _receipt!,
          fileName: 'gcash-$_id.png',
        );
        if (result == ReceiptSaveResult.saved) {
          _message('Receipt saved to Files.');
        }
      }
    } catch (_) {
      _message('Could not export the receipt. Please try again.');
    } finally {
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) => GcashTheme(
    builder: (context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: widget.asBottomSheet
              ? IconButton(
                  tooltip: 'Close form',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          title: Text(
            widget.record == null
                ? 'New ${widget.kind.label}'
                : widget.kind.label,
          ),
          actions: [
            IconButton(
              tooltip: 'GCash settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GcashSettingsScreen(),
                      ),
                    ),
            ),
            if (widget.record != null)
              IconButton(
                onPressed: _busy ? null : () => _delete(context),
                tooltip: 'Delete record',
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: AbsorbPointer(
                absorbing: _busy,
                child: SingleChildScrollView(
                  key: const ValueKey('gcash-form-scroll'),
                  controller: widget.scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(widget.kind.description),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pick(true),
                                icon: const Icon(
                                  Icons.document_scanner_outlined,
                                ),
                                label: const Text('Scan receipt'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pick(false),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Recent photo'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Best with GCash receipts. Other receipts may be hard to read—enter the details manually. Reading stays on this phone.',
                          key: const ValueKey('gcash-receipt-guidance'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_busy) const LinearProgressIndicator(),
                        if (_receipt != null) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) => Dialog(
                                child: InteractiveViewer(
                                  child: Image.memory(
                                    _receipt!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                            child: Image.memory(
                              _receipt!,
                              key: const ValueKey('gcash-receipt-preview'),
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              Builder(
                                builder: (context) => TextButton(
                                  onPressed: () => _export(false, context),
                                  child: const Text('Download'),
                                ),
                              ),
                              Builder(
                                builder: (context) => TextButton(
                                  onPressed: () => _export(true, context),
                                  child: const Text('Share'),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _receipt = null),
                                child: const Text('Remove photo'),
                              ),
                            ],
                          ),
                        ],
                        if (_receiptNotice != null) ...[
                          const SizedBox(height: 12),
                          _receiptNoticeCard(context),
                        ],
                        const SizedBox(height: 12),
                        _field(_name, 'Customer name', maxLength: 150),
                        _field(
                          _number,
                          'Mobile number (as shown on receipt)',
                          maxLength: 40,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(_amount, 'Amount (₱)', money: true),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _field(
                                _fee,
                                'Service fee (₱)',
                                money: true,
                                allowZero: true,
                                onChanged: (_) =>
                                    setState(() => _customFee = true),
                              ),
                            ),
                          ],
                        ),
                        _feeHelp(),
                        _field(
                          _reference,
                          'Reference / transaction number',
                          maxLength: 80,
                          reference: true,
                        ),
                        OutlinedButton.icon(
                          key: _dateKey,
                          onPressed: () => _chooseDate(context),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            _date == null
                                ? 'Choose transaction date & time'
                                : DateFormat(
                                    'MMM d, yyyy · h:mm a',
                                  ).format(_date!),
                          ),
                        ),
                        if (_rawText != null)
                          ExpansionTile(
                            title: const Text('Text read from receipt'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(_rawText!),
                              ),
                            ],
                          ),
                        if (widget.kind == GcashKind.cashOut)
                          CheckboxListTile(
                            key: _verificationKey,
                            contentPadding: EdgeInsets.zero,
                            value: _verified,
                            onChanged: (value) =>
                                setState(() => _verified = value ?? false),
                            title: const Text('I checked the payment in GCash'),
                            subtitle: const Text(
                              'Check the official app before releasing cash. A screenshot alone does not confirm payment.',
                            ),
                          ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _saveBar(context),
          ],
        ),
      ),
    ),
  );

  Widget _receiptNoticeCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('gcash-receipt-warning'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _receiptNotice!,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveBar(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('gcash-save-bar'),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('gcash-save-record'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: Text(
              widget.record == null ? 'Save GCash record' : 'Save changes',
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool money = false,
    bool allowZero = false,
    bool reference = false,
    int maxLength = 20,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: _fieldKeys.putIfAbsent(label, GlobalKey<FormFieldState<String>>.new),
      controller: controller,
      onChanged: onChanged,
      maxLength: maxLength,
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          if (identical(controller, _fee)) {
            return 'Enter a service fee, or 0 if there is no charge.';
          }
          return 'Required';
        }
        if (value.length > maxLength) {
          return '$label must be $maxLength characters or fewer.';
        }
        if (money) {
          final amount = gcashCentavos(value);
          if (amount == null || (!allowZero && amount == 0)) {
            return 'Enter a valid amount';
          }
        }
        if (reference &&
            !RegExp(
              r'^[A-Z0-9]{4,80}$',
            ).hasMatch(normalizeGcashReference(value))) {
          return 'Check reference number';
        }
        return null;
      },
    ),
  );

  Widget _feeHelp() {
    final settings = _feeSettings.value;
    final amount = gcashCentavos(_amount.text);
    final enabled = settings?.autoFillFor(widget.kind) ?? false;
    final suggestion = amount == null
        ? null
        : settings?.feeFor(widget.kind, amount);
    final message = _customFee
        ? 'Custom charge for this transaction. Your saved rates are unchanged.'
        : _feeSettings.isLoading
        ? 'Loading default charges…'
        : _feeSettings.hasError
        ? 'Default charges could not load. Enter the charge manually.'
        : !enabled
        ? 'Automatic charges are off. Enter the service fee yourself.'
        : amount != null && amount > 0 && suggestion == null
        ? 'Amount is above your configured brackets. Enter a charge manually.'
        : 'Charge follows your shared profit-charge table. You can change it here.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodySmall),
          if (_customFee && enabled && suggestion != null)
            TextButton(
              onPressed: () => setState(() {
                _customFee = false;
                _applyDefaultFee();
              }),
              child: Text('Use default charge · ${_money(suggestion)}'),
            ),
          if (_feeSettings.hasError)
            TextButton(
              onPressed: () => ref.invalidate(gcashFeeSettingsProvider),
              child: const Text('Reload default charges'),
            ),
        ],
      ),
    );
  }
}
