import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/barcode/barcode.dart' as store_barcode;
import 'package:raze_store/core/widgets/app_widgets.dart';

/// Injectable entry point for reading a product barcode from the camera.
abstract interface class ProductBarcodeScannerLauncher {
  Future<String?> scan(BuildContext context);
}

/// Opens the guided on-device barcode reader.
class DeviceProductBarcodeScannerLauncher
    implements ProductBarcodeScannerLauncher {
  const DeviceProductBarcodeScannerLauncher();

  @override
  Future<String?> scan(BuildContext context) {
    return ProductBarcodeCaptureScreen.scan(context);
  }
}

final productBarcodeScannerLauncherProvider =
    Provider<ProductBarcodeScannerLauncher>(
      (ref) => const DeviceProductBarcodeScannerLauncher(),
    );

/// A focused barcode reader used by the add/edit product form.
class ProductBarcodeCaptureScreen extends StatefulWidget {
  const ProductBarcodeCaptureScreen({super.key});

  static Future<String?> scan(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => const ProductBarcodeCaptureScreen(),
      ),
    );
  }

  @override
  State<ProductBarcodeCaptureScreen> createState() =>
      _ProductBarcodeCaptureScreenState();
}

class _ProductBarcodeCaptureScreenState
    extends State<ProductBarcodeCaptureScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _appActive = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appActive = true;
        if (_controller.value.hasCameraPermission && !_finishing) {
          unawaited(_startScanner());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appActive = false;
        if (_controller.value.hasCameraPermission) {
          unawaited(_stopScanner());
        }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final cameraMaxHeight = (screenSize.height * 0.58).clamp(260.0, 560.0);
    return PopScope(
      canPop: !_finishing,
      child: AppPageScaffold(
        title: 'Scan product barcode',
        leading: IconButton(
          key: const ValueKey('close-product-barcode-scanner'),
          onPressed: _finishing ? null : () => Navigator.of(context).pop(),
          tooltip: 'Close barcode scanner',
          icon: const Icon(Icons.close_rounded),
        ),
        padBody: false,
        body: ListView(
          padding: AppSpacing.pageInsetsFor(screenSize.width),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Center the package barcode inside the frame.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: cameraMaxHeight),
                      child: Card(
                        color: Colors.black,
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              MobileScanner(
                                controller: _controller,
                                tapToFocus: true,
                                onDetect: _onDetect,
                                errorBuilder: (_, _) => _CameraError(
                                  onBack: () => Navigator.of(context).pop(),
                                ),
                                overlayBuilder: (_, _) => const IgnorePointer(
                                  child: _BarcodeOverlay(),
                                ),
                              ),
                              Align(
                                alignment: Alignment.topRight,
                                child: SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.sm,
                                    ),
                                    child:
                                        ValueListenableBuilder<
                                          MobileScannerState
                                        >(
                                          valueListenable: _controller,
                                          builder: (context, state, _) => Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _CameraAction(
                                                tooltip:
                                                    state.torchState ==
                                                        TorchState.on
                                                    ? 'Turn flash off'
                                                    : 'Turn flash on',
                                                icon:
                                                    state.torchState ==
                                                        TorchState.on
                                                    ? Icons.flash_on_rounded
                                                    : Icons.flash_off_rounded,
                                                enabled:
                                                    state.torchState !=
                                                    TorchState.unavailable,
                                                onPressed:
                                                    _controller.toggleTorch,
                                              ),
                                              const SizedBox(
                                                width: AppSpacing.xs,
                                              ),
                                              _CameraAction(
                                                tooltip: 'Switch camera',
                                                icon:
                                                    Icons.cameraswitch_outlined,
                                                enabled:
                                                    (state.availableCameras ??
                                                        2) >
                                                    1,
                                                onPressed:
                                                    _controller.switchCamera,
                                              ),
                                            ],
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                              if (_finishing)
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
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'The scanned code will replace the barcode currently entered in the product form.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_finishing) return;
    for (final detected in capture.barcodes) {
      final rawValue = detected.rawValue;
      if (rawValue == null) continue;
      final barcode = store_barcode.Barcode.tryParse(rawValue);
      if (barcode == null) continue;
      unawaited(_finish(barcode.value));
      return;
    }
  }

  Future<void> _finish(String barcode) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await _stopScanner();
    if (!mounted) return;
    Navigator.of(context).pop(barcode);
  }

  Future<void> _startScanner() async {
    if (!_appActive || _finishing) return;
    try {
      await _controller.start();
    } catch (_) {
      // MobileScanner presents camera startup failures through errorBuilder.
    }
  }

  Future<void> _stopScanner() async {
    try {
      await _controller.stop();
    } catch (_) {
      // The controller may already be stopped during route/lifecycle changes.
    }
  }
}

class _BarcodeOverlay extends StatelessWidget {
  const _BarcodeOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CameraScanFrame(widthFactor: 0.78, aspectRatio: 2.25),
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

class _CameraError extends StatelessWidget {
  const _CameraError({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: AppEmptyState(
        icon: Icons.no_photography_outlined,
        title: 'Camera unavailable',
        message:
            'Allow camera access in system settings, or return and type the barcode.',
        actionLabel: 'Enter manually',
        onAction: onBack,
      ),
    );
  }
}
