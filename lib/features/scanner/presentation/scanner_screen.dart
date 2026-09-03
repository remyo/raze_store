import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/barcode/barcode.dart' as store_barcode;
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/presentation/product_quick_view.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _scannerController;
  late final TextEditingController _manualController;
  late final FocusNode _manualFocusNode;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scannerController = MobileScannerController(
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
    );
    _manualController = TextEditingController();
    _manualFocusNode = FocusNode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scannerController.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_handling) unawaited(_scannerController.start());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_scannerController.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Scan a barcode',
      padBody: false,
      body: ListView(
        padding: AppSpacing.pageInsetsFor(MediaQuery.sizeOf(context).width),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Card(
                color: Colors.black,
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        tapToFocus: true,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) => _CameraError(
                          onManualEntry: () => _focusManualField(context),
                        ),
                        overlayBuilder: (_, _) =>
                            const IgnorePointer(child: _ScannerOverlay()),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: ValueListenableBuilder<MobileScannerState>(
                              valueListenable: _scannerController,
                              builder: (context, state, _) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _CameraAction(
                                    tooltip: state.torchState == TorchState.on
                                        ? 'Turn flash off'
                                        : 'Turn flash on',
                                    icon: state.torchState == TorchState.on
                                        ? Icons.flash_on_rounded
                                        : Icons.flash_off_rounded,
                                    enabled:
                                        state.torchState !=
                                        TorchState.unavailable,
                                    onPressed: _scannerController.toggleTorch,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  _CameraAction(
                                    tooltip: 'Switch camera',
                                    icon: Icons.cameraswitch_outlined,
                                    enabled: (state.availableCameras ?? 2) > 1,
                                    onPressed: _scannerController.switchCamera,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_handling)
                        const ColoredBox(
                          color: Color(0x66000000),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeader(
                    title: 'Enter a barcode manually',
                    subtitle:
                        'Useful when the label is damaged or hard to scan.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const ValueKey('manual-barcode-field'),
                    controller: _manualController,
                    focusNode: _manualFocusNode,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _handleBarcode,
                    decoration: InputDecoration(
                      labelText: 'Barcode number',
                      prefixIcon: const Icon(Icons.keyboard_outlined),
                      suffixIcon: IconButton(
                        onPressed: () => _handleBarcode(_manualController.text),
                        tooltip: 'Look up barcode',
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: () => context.push('/products/quick-add'),
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Add a product without a barcode'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value != null) unawaited(_handleBarcode(value));
  }

  Future<void> _handleBarcode(String rawValue) async {
    final barcode = store_barcode.Barcode.tryParse(rawValue);
    if (_handling || barcode == null) {
      if (barcode == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a barcode to look it up.')),
        );
      }
      return;
    }

    setState(() => _handling = true);
    await _scannerController.stop();
    try {
      final product = await ref
          .read(catalogRepositoryProvider)
          .findByBarcode(barcode.value);
      if (!mounted) return;

      if (product != null) {
        final added = await showProductQuickView(
          context,
          product: product,
          allowEdit: false,
        );
        if (added == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${product.name} added to cart.')),
          );
        }
      } else {
        final shouldCreate = await _showUnknownBarcode(barcode.value);
        if (shouldCreate == true && mounted) {
          await context.push(
            Uri(
              path: '/products/quick-add',
              queryParameters: {'barcode': barcode.value},
            ).toString(),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not look up this barcode.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _handling = false);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted) unawaited(_scannerController.start());
      }
    }
  }

  Future<bool?> _showUnknownBarcode(String barcode) {
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.help_outline_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Product not found',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              barcode,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add this product'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Scan another'),
            ),
          ],
        ),
      ),
    );
  }

  void _focusManualField(BuildContext context) {
    _manualFocusNode.requestFocus();
  }
}

class _CameraAction extends StatelessWidget {
  const _CameraAction({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB315211F),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: enabled ? () => unawaited(onPressed()) : null,
        tooltip: tooltip,
        color: Colors.white,
        disabledColor: Colors.white38,
        icon: Icon(icon),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black.withValues(alpha: 0.08)),
        Align(
          child: FractionallySizedBox(
            widthFactor: 0.78,
            child: AspectRatio(
              aspectRatio: 2.25,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2.5),
                  borderRadius: AppRadius.card,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x73000000),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCC15211F),
                borderRadius: AppRadius.control,
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Text(
                  'Center one barcode inside the frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.onManualEntry});

  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: AppEmptyState(
        icon: Icons.no_photography_outlined,
        title: 'Camera unavailable',
        message:
            'Allow camera access in system settings, or enter the barcode below.',
        actionLabel: 'Enter manually',
        onAction: onManualEntry,
      ),
    );
  }
}
