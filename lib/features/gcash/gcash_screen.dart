import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:raze_store/features/catalog/application/product_text_recognizer.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';
import 'package:raze_store/features/receipt/application/receipt_export_service.dart';
import 'gcash_parser.dart';
import 'gcash_record.dart';
import 'gcash_repository.dart';

String _money(int value) =>
    NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(value / 100);

class GcashScreen extends ConsumerStatefulWidget {
  const GcashScreen({super.key});
  @override
  ConsumerState<GcashScreen> createState() => _GcashScreenState();
}

class _GcashScreenState extends ConsumerState<GcashScreen> {
  int _days = 7;
  int _limit = 40;
  GcashKind? _kind;
  late Stream<List<GcashRecord>> _records;
  late Stream<({int cashIn, int cashOut, int fees})> _totals;
  DateTimeRange? _range;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final since =
        _range?.start ??
        (_days == 0 ? null : today.subtract(Duration(days: _days - 1)));
    final until = _range == null
        ? (_days == 0 ? null : today.add(const Duration(days: 1)))
        : _range!.end.add(const Duration(days: 1));
    _totals = ref
        .read(gcashRepositoryProvider)
        .totals(since: since, until: until, kind: _kind);
    _records = ref
        .read(gcashRepositoryProvider)
        .watch(since: since, until: until, kind: _kind, limit: _limit + 1);
  }

  Future<void> _open({
    GcashRecord? record,
    GcashKind kind = GcashKind.cashIn,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GcashFormScreen(kind: kind, record: record),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('GCash Services'),
      actions: [
        IconButton(
          tooltip: 'Choose date range',
          icon: const Icon(Icons.date_range_outlined),
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime(2200),
              initialDateRange: _range,
            );
            if (range != null && mounted) {
              setState(() {
                _range = range;
                _limit = 40;
                _load();
              });
            }
          },
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  for (final kind in GcashKind.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilledButton.icon(
                          onPressed: () => _open(kind: kind),
                          icon: Icon(
                            kind == GcashKind.cashIn
                                ? Icons.add_circle_outline
                                : Icons.payments_outlined,
                          ),
                          label: Text(kind.label),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final days in [1, 7, 30, 0])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(switch (days) {
                            1 => 'Today',
                            7 => '7 days',
                            30 => '30 days',
                            _ => 'All dates',
                          }),
                          selected: _range == null && _days == days,
                          onSelected: (_) => setState(() {
                            _days = days;
                            _range = null;
                            _limit = 40;
                            _load();
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              DropdownButton<GcashKind?>(
                value: _kind,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Cash In & Cash Out'),
                  ),
                  for (final kind in GcashKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (value) => setState(() {
                  _kind = value;
                  _limit = 40;
                  _load();
                }),
              ),
              if (_range != null)
                Text(
                  '${DateFormat.yMMMd().format(_range!.start)} – ${DateFormat.yMMMd().format(_range!.end)}',
                ),
              StreamBuilder<({int cashIn, int cashOut, int fees})>(
                stream: _totals,
                builder: (context, snapshot) {
                  final totals = snapshot.data;
                  if (snapshot.hasError) {
                    return const Text('Totals unavailable');
                  }
                  return Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'In: ${totals == null ? '…' : _money(totals.cashIn)}',
                      ),
                      Text(
                        'Out: ${totals == null ? '…' : _money(totals.cashOut)}',
                      ),
                      Text(
                        'Fees: ${totals == null ? '…' : _money(totals.fees)}',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<GcashRecord>>(
            stream: _records,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Could not load records. Retry'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No GCash records for these dates.'),
                );
              }
              final hasMore = rows.length > _limit;
              return NotificationListener<ScrollNotification>(
                onNotification: (event) {
                  if (hasMore &&
                      event.metrics.extentAfter < 240 &&
                      event is ScrollUpdateNotification) {
                    setState(() {
                      _limit += 40;
                      _load();
                    });
                  }
                  return false;
                },
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    if (index == _limit) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final record = rows[index];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: record.receipt == null
                            ? const SizedBox(
                                width: 44,
                                height: 52,
                                child: Icon(Icons.receipt_long_outlined),
                              )
                            : Image.memory(
                                record.receipt!,
                                width: 44,
                                height: 52,
                                fit: BoxFit.cover,
                              ),
                      ),
                      title: Text(
                        record.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${record.kind.label} · ${DateFormat('MMM d, h:mm a').format(record.date)}\n${record.number}',
                        maxLines: 2,
                      ),
                      trailing: Text(_money(record.amount)),
                      onTap: () => _open(record: record, kind: record.kind),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class GcashFormScreen extends ConsumerStatefulWidget {
  const GcashFormScreen({super.key, required this.kind, this.record});
  final GcashKind kind;
  final GcashRecord? record;
  @override
  ConsumerState<GcashFormScreen> createState() => _GcashFormScreenState();
}

class _GcashFormScreenState extends ConsumerState<GcashFormScreen> {
  final _form = GlobalKey<FormState>();
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
  late final String _id;
  @override
  void initState() {
    super.initState();
    final record = widget.record;
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
  }

  @override
  void dispose() {
    for (final controller in [_name, _number, _amount, _fee, _reference]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pick(bool camera) async {
    setState(() => _busy = true);
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
        _verified = false;
        _rawText = null;
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
          // A replacement receipt must never retain another transaction's details.
          _name.text = details.name ?? '';
          _number.text = details.number ?? '';
          _amount.text = details.amount == null
              ? ''
              : (details.amount! / 100).toStringAsFixed(2);
          _reference.text = details.reference ?? '';
          _date = details.date;
        });
        _message('Review the extracted details. Fill in anything missing.');
      } catch (_) {
        _message(
          'Photo attached. Text could not be read; enter the details manually.',
        );
      }
    } catch (_) {
      _message(
        'Could not open the photo. Check camera/photos access and try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDate() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
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
    if (!_form.currentState!.validate()) return;
    if (_date == null) {
      _message('Choose the transaction date and time.');
      return;
    }
    if (widget.kind == GcashKind.cashOut && !_verified) {
      _message(
        'Confirm payment in GCash before recording a completed Cash Out.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(gcashRepositoryProvider)
          .save(
            GcashRecord(
              id: _id,
              kind: widget.kind,
              name: _name.text.trim(),
              number: _number.text.trim(),
              amount: gcashCentavos(_amount.text)!,
              fee: gcashCentavos(_fee.text)!,
              reference: _reference.text,
              date: _date!,
              receipt: _receipt,
            ),
          );
      if (mounted) {
        Navigator.pop(context);
        _message('GCash record saved.');
      }
    } on DuplicateGcashReference {
      _message(
        'This reference number already exists. Open the existing record in GCash history.',
      );
    } catch (_) {
      _message('Could not save. Check the details and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
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
    setState(() => _busy = true);
    try {
      await ref.read(gcashRepositoryProvider).delete(_id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _message('Could not delete the record.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(bool share, BuildContext anchor) async {
    setState(() => _busy = true);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.record == null
              ? 'New ${widget.kind.label}'
              : widget.kind.label,
        ),
        actions: [
          if (widget.record != null)
            IconButton(
              onPressed: _busy ? null : _delete,
              tooltip: 'Delete record',
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.kind.description),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(true),
                      icon: const Icon(Icons.document_scanner_outlined),
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
              const Text(
                'Or enter details manually. Receipt reading works on this phone.',
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_receipt != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: InteractiveViewer(
                        child: Image.memory(_receipt!, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  child: Image.memory(
                    _receipt!,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                      onPressed: () => setState(() => _receipt = null),
                      child: const Text('Remove photo'),
                    ),
                  ],
                ),
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
                  Expanded(child: _field(_amount, 'Amount (₱)', money: true)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(
                      _fee,
                      'Service fee (₱)',
                      money: true,
                      allowZero: true,
                    ),
                  ),
                ],
              ),
              _field(
                _reference,
                'Reference / transaction number',
                maxLength: 80,
                reference: true,
              ),
              OutlinedButton.icon(
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  _date == null
                      ? 'Choose transaction date & time'
                      : DateFormat('MMM d, yyyy · h:mm a').format(_date!),
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
                  contentPadding: EdgeInsets.zero,
                  value: _verified,
                  onChanged: (value) =>
                      setState(() => _verified = value ?? false),
                  title: const Text('I checked the payment in GCash'),
                  subtitle: const Text(
                    'Check the official app before releasing cash. A screenshot alone does not confirm payment.',
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _save,
                child: Text(
                  widget.record == null ? 'Save GCash record' : 'Save changes',
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool money = false,
    bool allowZero = false,
    bool reference = false,
    int maxLength = 20,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLength: maxLength,
      keyboardType: money
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Required';
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
}
