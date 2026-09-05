import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/features/receipt/application/receipt_export_service.dart';

import 'gcash_record.dart';
import 'gcash_repository.dart';

enum _RecordAction { download, share, delete }

/// Existing receipt and deletion actions, without exposing an edit form.
class GcashRecordActions extends ConsumerStatefulWidget {
  const GcashRecordActions({
    super.key,
    required this.record,
    required this.onDeleted,
    this.exportService,
  });

  final GcashRecord record;
  final VoidCallback onDeleted;
  final ReceiptExportService? exportService;

  @override
  ConsumerState<GcashRecordActions> createState() => _GcashRecordActionsState();
}

class _GcashRecordActionsState extends ConsumerState<GcashRecordActions> {
  final _anchor = GlobalKey();
  bool _busy = false;
  bool _confirming = false;
  bool _deleted = false;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export({required bool share}) async {
    final record = widget.record;
    final receipt = record.receipt;
    if (_busy || _confirming || _deleted || receipt == null) return;
    // The popup item disappears on selection. Anchor iPad sharing to the
    // persistent app-bar button instead of the dismissed menu's render box.
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _busy = true);
    try {
      final service = widget.exportService ?? ReceiptExportService.device();
      if (share) {
        await service.sharePng(
          bytes: receipt,
          fileName: 'gcash-${record.id}.png',
          storeName: 'GCash receipt',
          sharePositionOrigin: origin,
        );
      } else {
        final result = await service.savePng(
          bytes: receipt,
          fileName: 'gcash-${record.id}.png',
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

  Future<void> _delete() async {
    if (_busy || _confirming || _deleted) return;
    final record = widget.record;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete GCash record?'),
        content: Text(
          '${record.name}\nTransaction no. ${record.reference}\n\n'
          'This removes the saved record and its receipt from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(gcashRepositoryProvider).delete(record.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _deleted = true;
      });
      // Let the route's PopScope observe the cleared busy state before the
      // caller navigates away, including callers that use maybePop().
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) widget.onDeleted();
    } catch (_) {
      _message('Could not delete the record.');
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SizedBox(
      key: _anchor,
      width: 48,
      height: 48,
      child: PopupMenuButton<_RecordAction>(
        key: const ValueKey('gcash-record-actions'),
        tooltip: 'Record actions',
        enabled: !_busy && !_confirming && !_deleted,
        icon: _busy
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  key: const ValueKey('gcash-record-actions-progress'),
                  strokeWidth: 2,
                  color:
                      Theme.of(context).appBarTheme.foregroundColor ??
                      IconTheme.of(context).color,
                ),
              )
            : const Icon(Icons.more_vert_rounded),
        onSelected: (action) {
          switch (action) {
            case _RecordAction.download:
              _export(share: false);
            case _RecordAction.share:
              _export(share: true);
            case _RecordAction.delete:
              _delete();
          }
        },
        itemBuilder: (context) => [
          if (widget.record.receipt != null) ...[
            const PopupMenuItem(
              value: _RecordAction.download,
              child: Text('Download receipt'),
            ),
            const PopupMenuItem(
              value: _RecordAction.share,
              child: Text('Share receipt'),
            ),
          ],
          const PopupMenuItem(
            value: _RecordAction.delete,
            child: Text('Delete record'),
          ),
        ],
      ),
    ),
  );
}
