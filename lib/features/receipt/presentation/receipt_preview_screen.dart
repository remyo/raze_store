import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:raze_store/features/receipt/domain/receipt_draft.dart';
import 'package:raze_store/features/receipt/presentation/receipt_view.dart';
import 'package:share_plus/share_plus.dart';

typedef ReceiptImageSaveCallback =
    Future<void> Function(Uint8List pngBytes, String fileName);
typedef ReceiptImageShareCallback =
    Future<void> Function(
      Uint8List pngBytes,
      String fileName,
      Rect? sharePositionOrigin,
    );

/// Previews a temporary cart receipt and exports the rendered customer copy.
///
/// The screen only receives an immutable [ReceiptDraft]. It neither depends on
/// a router nor knows about the cart/database, so saving or sharing cannot mark
/// items sold or clear the cart.
class ReceiptPreviewScreen extends StatefulWidget {
  const ReceiptPreviewScreen({
    super.key,
    required this.draft,
    this.onSaveImage,
    this.onShareImage,
    this.onClose,
  });

  final ReceiptDraft draft;

  /// Optional injection point for tests or a custom image destination.
  /// Defaults to saving the PNG to the device gallery with `gal`.
  final ReceiptImageSaveCallback? onSaveImage;

  /// Optional injection point for tests or a custom sharing flow.
  /// Defaults to the native share sheet from `share_plus`.
  final ReceiptImageShareCallback? onShareImage;

  /// Called by the close button. Defaults to [Navigator.maybePop].
  final VoidCallback? onClose;

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

enum _ReceiptAction { save, share }

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final GlobalKey _receiptKey = GlobalKey();
  _ReceiptAction? _busyAction;

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
                            'This creates an image only. Your cart stays unchanged and no sale is recorded.',
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
      final save = widget.onSaveImage ?? _saveToGallery;
      await save(image.bytes, image.fileName);
      if (mounted) {
        _showMessage('Receipt saved to your gallery.');
      }
    });
  }

  Future<void> _share(BuildContext buttonContext) async {
    final origin = _shareOrigin(buttonContext);
    await _runAction(_ReceiptAction.share, (image) async {
      final share = widget.onShareImage ?? _shareWithSystemSheet;
      await share(image.bytes, image.fileName, origin);
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
    } on GalException catch (error) {
      if (mounted) _showMessage(_galleryErrorMessage(error), isError: true);
    } catch (_) {
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
    final mediaRatio = MediaQuery.devicePixelRatioOf(context);
    await WidgetsBinding.instance.endOfFrame;
    final receiptContext = _receiptKey.currentContext;
    final boundary = receiptContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || boundary.size.isEmpty) {
      throw StateError('The receipt is not ready to capture.');
    }

    if (boundary.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
    }

    final preferredRatio = math.max(2.0, math.min(3.0, mediaRatio));
    const maxPixels = 16000000.0;
    const maxImageDimension = 8192.0;
    final size = boundary.size;
    final safePixelRatio = math.sqrt(maxPixels / (size.width * size.height));
    final safeDimensionRatio = math.min(
      maxImageDimension / size.width,
      maxImageDimension / size.height,
    );
    final pixelRatio = math.max(
      0.25,
      math.min(preferredRatio, math.min(safePixelRatio, safeDimensionRatio)),
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
        bytes: data.buffer.asUint8List(),
        fileName: _receiptFileName(widget.draft.createdAt),
      );
    } finally {
      renderedImage.dispose();
    }
  }

  Future<void> _saveToGallery(Uint8List bytes, String fileName) {
    final imageName = fileName.endsWith('.png')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    return Gal.putImageBytes(bytes, name: imageName);
  }

  Future<void> _shareWithSystemSheet(
    Uint8List bytes,
    String fileName,
    Rect? sharePositionOrigin,
  ) async {
    await SharePlus.instance.share(
      ShareParams(
        title: 'Receipt from ${widget.draft.storeName}',
        subject: 'Receipt from ${widget.draft.storeName}',
        text: 'Here is your receipt from ${widget.draft.storeName}.',
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
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
                busyAction == _ReceiptAction.save ? 'Saving…' : 'Save image',
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

String _galleryErrorMessage(GalException error) {
  return switch (error.type) {
    GalExceptionType.accessDenied =>
      'Gallery access was denied. Allow photo access in device settings, then try again.',
    GalExceptionType.notEnoughSpace =>
      'There is not enough device storage to save the receipt.',
    GalExceptionType.notSupportedFormat =>
      'This device could not save the receipt image format.',
    GalExceptionType.unexpected =>
      'Could not save the receipt to the gallery. Please try again.',
  };
}
