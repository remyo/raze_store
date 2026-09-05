import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:raze_store/features/receipt/application/receipt_export_service.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';
import 'package:raze_store/features/receipt/presentation/receipt_view.dart';

typedef ReceiptImageSaveCallback =
    Future<void> Function(Uint8List pngBytes, String fileName);
typedef ReceiptImageShareCallback =
    Future<void> Function(
      Uint8List pngBytes,
      String fileName,
      Rect? sharePositionOrigin,
    );
typedef ReceiptImageCaptureCallback = Future<Uint8List> Function();

/// Previews a receipt snapshot and exports the rendered customer copy.
///
/// The screen only receives an immutable [ReceiptDraft]. It neither depends on
/// a router nor knows whether the snapshot came from a cart preview or a saved
/// sale, so saving and sharing never mutate business data.
class ReceiptPreviewScreen extends StatefulWidget {
  const ReceiptPreviewScreen({
    super.key,
    required this.draft,
    this.onSaveImage,
    this.onShareImage,
    this.onClose,
    this.exportService,
    this.onCaptureImage,
  });

  final ReceiptDraft draft;

  /// Optional injection point for tests or a custom image destination.
  /// Defaults to opening the system file-save dialog for the PNG.
  final ReceiptImageSaveCallback? onSaveImage;

  /// Optional injection point for tests or a custom sharing flow.
  /// Defaults to the native share sheet from `share_plus`.
  final ReceiptImageShareCallback? onShareImage;

  /// Platform exporter used when callback overrides are not supplied.
  final ReceiptExportService? exportService;

  /// Optional renderer override used by tests and custom host integrations.
  final ReceiptImageCaptureCallback? onCaptureImage;

  /// Called by the close button. Defaults to [Navigator.maybePop].
  final VoidCallback? onClose;

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

enum _ReceiptAction { save, share }

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final GlobalKey _receiptKey = GlobalKey();
  _ReceiptAction? _busyAction;

  late final ReceiptExportService _exportService =
      widget.exportService ?? ReceiptExportService.device();

  bool get _isBusy => _busyAction != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt preview'),
        actions: [
          IconButton(
            tooltip: 'Close preview',
            onPressed: _isBusy ? null : _close,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Column(
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      maxWidth: receiptPreferredWidth,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: colors.onSecondaryContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Saving or sharing this receipt image does not change your cart or sales history.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onSecondaryContainer,
                                  height: 1.35,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: RepaintBoundary(
                      key: _receiptKey,
                      child: ColoredBox(
                        color: const Color(0xFFF3F0EA),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: ReceiptView(draft: widget.draft),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _ReceiptActionBar(
            busyAction: _busyAction,
            onSave: _isBusy ? null : _save,
            onShare: _isBusy ? null : _share,
          ),
        ],
      ),
    );
  }

  void _close() {
    final callback = widget.onClose;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _save() async {
    await _runAction(_ReceiptAction.save, (image) async {
      final saveOverride = widget.onSaveImage;
      if (saveOverride != null) {
        await saveOverride(image.bytes, image.fileName);
        if (mounted) _showMessage('Receipt PNG saved.');
        return;
      } else {
        final result = await _exportService.savePng(
          bytes: image.bytes,
          fileName: image.fileName,
        );
        if (result == ReceiptSaveResult.cancelled) {
          if (mounted) _showMessage('Receipt download cancelled.');
          return;
        }
      }
      if (mounted) _showMessage('Receipt PNG saved to Files.');
    });
  }

  Future<void> _share(BuildContext buttonContext) async {
    final origin = _shareOrigin(buttonContext);
    await _runAction(_ReceiptAction.share, (image) async {
      final shareOverride = widget.onShareImage;
      if (shareOverride != null) {
        await shareOverride(image.bytes, image.fileName, origin);
        return;
      }
      await _exportService.sharePng(
        bytes: image.bytes,
        fileName: image.fileName,
        storeName: widget.draft.storeName,
        sharePositionOrigin: origin,
      );
    });
  }

  Future<void> _runAction(
    _ReceiptAction action,
    Future<void> Function(_CapturedReceipt image) operation,
  ) async {
    if (_isBusy) return;
    setState(() => _busyAction = action);

    try {
      final image = await _captureReceipt();
      await operation(image);
    } catch (error, stackTrace) {
      debugPrint('Receipt ${action.name} failed: $error\n$stackTrace');
      if (mounted) {
        _showMessage(
          action == _ReceiptAction.save
              ? 'Could not save the receipt. Please try again.'
              : 'Could not share the receipt. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<_CapturedReceipt> _captureReceipt() async {
    final captureOverride = widget.onCaptureImage;
    if (captureOverride != null) {
      return _CapturedReceipt(
        bytes: await captureOverride(),
        fileName: _receiptFileName(widget.draft.createdAt),
      );
    }

    final mediaRatio = MediaQuery.devicePixelRatioOf(context);
    final receiptContext = _receiptKey.currentContext;
    final boundary = receiptContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) {
      throw StateError('The receipt is not ready to capture.');
    }

    if (boundary.debugNeedsPaint) {
      WidgetsBinding.instance.ensureVisualUpdate();
      await WidgetsBinding.instance.endOfFrame;
      if (boundary.debugNeedsPaint) {
        throw StateError('The receipt is still being painted.');
      }
    }

    final size = boundary.size;
    final pixelRatio = receiptCapturePixelRatio(
      logicalSize: size,
      devicePixelRatio: mediaRatio,
    );

    final renderedImage = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final data = await renderedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (data == null) {
        throw StateError('Flutter could not encode the receipt image.');
      }
      return _CapturedReceipt(
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        fileName: _receiptFileName(widget.draft.createdAt),
      );
    } finally {
      renderedImage.dispose();
    }
  }

  Rect? _shareOrigin(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _showMessage(String message, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? colors.error : null,
        ),
      );
  }
}

double receiptCapturePixelRatio({
  required Size logicalSize,
  required double devicePixelRatio,
}) {
  if (logicalSize.isEmpty ||
      !logicalSize.width.isFinite ||
      !logicalSize.height.isFinite) {
    throw ArgumentError.value(logicalSize, 'logicalSize');
  }
  final preferredRatio = math.max(2.0, math.min(3.0, devicePixelRatio));
  const maxPixels = 16000000.0;
  const maxImageDimension = 8192.0;
  final safePixelRatio = math.sqrt(
    maxPixels / (logicalSize.width * logicalSize.height),
  );
  final safeDimensionRatio = math.min(
    maxImageDimension / logicalSize.width,
    maxImageDimension / logicalSize.height,
  );
  return math.min(preferredRatio, math.min(safePixelRatio, safeDimensionRatio));
}

class _ReceiptActionBar extends StatelessWidget {
  const _ReceiptActionBar({
    required this.busyAction,
    required this.onSave,
    required this.onShare,
  });

  final _ReceiptAction? busyAction;
  final VoidCallback? onSave;
  final void Function(BuildContext context)? onShare;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final saveButton = OutlinedButton.icon(
              key: const ValueKey('receipt-save-button'),
              onPressed: onSave,
              icon: _ActionIcon(
                isBusy: busyAction == _ReceiptAction.save,
                idleIcon: Icons.download_rounded,
              ),
              label: Text(
                busyAction == _ReceiptAction.save ? 'Saving…' : 'Download PNG',
              ),
            );
            final shareButton = Builder(
              builder: (buttonContext) => FilledButton.icon(
                key: const ValueKey('receipt-share-button'),
                onPressed: onShare == null
                    ? null
                    : () => onShare!(buttonContext),
                icon: _ActionIcon(
                  isBusy: busyAction == _ReceiptAction.share,
                  idleIcon: Icons.share_rounded,
                ),
                label: Text(
                  busyAction == _ReceiptAction.share ? 'Preparing…' : 'Share',
                ),
              ),
            );

            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 48, child: shareButton),
                  const SizedBox(height: 8),
                  SizedBox(height: 48, child: saveButton),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: SizedBox(height: 48, child: saveButton)),
                const SizedBox(width: 12),
                Expanded(child: SizedBox(height: 48, child: shareButton)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.isBusy, required this.idleIcon});

  final bool isBusy;
  final IconData idleIcon;

  @override
  Widget build(BuildContext context) {
    if (!isBusy) return Icon(idleIcon);
    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _CapturedReceipt {
  const _CapturedReceipt({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

String _receiptFileName(DateTime createdAt) {
  final local = createdAt.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return 'raze-store-receipt-'
      '${local.year}${twoDigits(local.month)}${twoDigits(local.day)}-'
      '${twoDigits(local.hour)}${twoDigits(local.minute)}${twoDigits(local.second)}.png';
}
