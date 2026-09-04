import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:raze_store/app/shell/app_shell.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/barcode/barcode.dart' as store_barcode;
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/presentation/cart_shortcut_button.dart';
import 'package:raze_store/features/catalog/application/catalog_lookup_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_lookup_service.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_quick_view.dart';
import 'package:raze_store/features/scanner/application/scan_feedback_service.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/app_preferences.dart';

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
  final Map<String, Timer> _cameraRepeatGuardTimers = {};
  bool _handling = false;
  bool? _branchVisible;
  bool? _routeForeground;
  bool _appActive = true;
  int _lookupGeneration = 0;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = AppShellBranchScope.of(context) == 1;
    final routeForeground = TickerMode.of(context);
    final wasVisible = _branchVisible;
    final wasRouteForeground = _routeForeground;
    _branchVisible = visible;
    _routeForeground = routeForeground;
    if (wasVisible == null || wasRouteForeground == null) {
      if (!visible || !routeForeground) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && (_branchVisible != true || _routeForeground != true)) {
            unawaited(_scannerController.stop());
          }
        });
      }
      return;
    }

    if (wasVisible && !visible) {
      _lookupGeneration++;
      _handling = false;
      unawaited(_scannerController.stop());
    } else if (!routeForeground) {
      unawaited(_scannerController.stop());
    } else if (visible && _appActive && !_handling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _branchVisible == true &&
            _routeForeground == true &&
            _appActive &&
            !_handling) {
          unawaited(_scannerController.start());
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appActive = true;
        if (_scannerController.value.hasCameraPermission &&
            _branchVisible != false &&
            _routeForeground != false &&
            !_handling) {
          unawaited(_scannerController.start());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appActive = false;
        if (_scannerController.value.hasCameraPermission) {
          unawaited(_scannerController.stop());
        }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _cameraRepeatGuardTimers.values) {
      timer.cancel();
    }
    _cameraRepeatGuardTimers.clear();
    _scannerController.dispose();
    _manualController.dispose();
    _manualFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Start loading scan preferences before the first camera detection. The
    // handler reads the latest value for every accepted barcode.
    ref.watch(appPreferencesProvider);
    return AppPageScaffold(
      title: 'Scan a barcode',
      actions: const [CartShortcutButton()],
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
    String? nextBarcode;
    final repeatGuardDuration = _currentRepeatGuardDuration();
    for (final detected in capture.barcodes) {
      final rawValue = detected.rawValue;
      if (rawValue == null) continue;
      final barcode = store_barcode.Barcode.tryParse(rawValue);
      if (barcode == null) continue;
      if (_cameraRepeatGuardTimers.containsKey(barcode.value)) {
        // Refresh every guarded barcode that is still visible. This preserves
        // leave-frame behavior even when several labels share one frame.
        _guardCameraRepeat(barcode.value, duration: repeatGuardDuration);
      } else {
        nextBarcode ??= rawValue;
      }
    }
    if (nextBarcode != null) {
      unawaited(_handleBarcode(nextBarcode, fromCamera: true));
    }
  }

  Future<void> _handleBarcode(
    String rawValue, {
    bool fromCamera = false,
  }) async {
    final barcode = store_barcode.Barcode.tryParse(rawValue);
    if (_branchVisible == false ||
        _routeForeground == false ||
        !_appActive ||
        _handling ||
        barcode == null) {
      if (barcode == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a barcode to look it up.')),
        );
      }
      return;
    }
    final preferences = await _loadPreferences();
    if (!mounted ||
        _branchVisible == false ||
        _routeForeground == false ||
        !_appActive ||
        _handling) {
      return;
    }
    if (fromCamera && _cameraRepeatGuardTimers.containsKey(barcode.value)) {
      // The camera reports the same label every few frames. Keep extending the
      // guard while it remains visible, then allow a deliberate re-scan after
      // it has left the frame.
      _guardCameraRepeat(
        barcode.value,
        duration: Duration(milliseconds: preferences.scannerRepeatCooldownMs),
      );
      return;
    }

    setState(() => _handling = true);
    final generation = ++_lookupGeneration;
    await _scannerController.stop();
    try {
      final result = await ref
          .read(catalogLookupServiceProvider)
          .findByBarcode(barcode.value);
      if (!mounted ||
          _branchVisible == false ||
          _routeForeground == false ||
          !_appActive ||
          generation != _lookupGeneration) {
        return;
      }

      if (result.kind == CatalogLookupKind.local) {
        final product = result.localProduct!;
        final hasPricedSubUnit = product.sellingUnits.any(
          (unit) => unit.priceCentavos > 0,
        );
        if (product.sellingUnits.isNotEmpty &&
            (!preferences.autoAddMainUnitOnScan ||
                (product.priceCentavos <= 0 && hasPricedSubUnit))) {
          final added = await showProductQuickView(context, product: product);
          if (!fromCamera) {
            _manualController.clear();
          }
          if (added == true &&
              mounted &&
              generation == _lookupGeneration &&
              _branchVisible == true &&
              _routeForeground == true &&
              _appActive) {
            await _playSuccessFeedback(
              fromCamera: fromCamera,
              preferences: preferences,
            );
            if (!_canPublishResult(generation)) return;
            _showAddedToCart(product.name);
          }
          return;
        }
        if (product.priceCentavos <= 0) {
          if (!fromCamera) {
            _manualController.clear();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Set a selling price for ${product.name} before adding it to the cart.',
              ),
              action: SnackBarAction(
                label: 'Set price',
                onPressed: () => context.push(
                  '/products/${Uri.encodeComponent(product.id)}/edit',
                ),
              ),
            ),
          );
          return;
        }
        try {
          await ref.read(cartRepositoryProvider).addProduct(product);
        } catch (_) {
          if (mounted &&
              generation == _lookupGeneration &&
              _branchVisible == true &&
              _routeForeground == true &&
              _appActive) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not add this product to the cart.'),
              ),
            );
          }
          return;
        }
        if (!fromCamera) {
          _manualController.clear();
        }
        if (mounted &&
            generation == _lookupGeneration &&
            _branchVisible == true &&
            _routeForeground == true &&
            _appActive) {
          await _playSuccessFeedback(
            fromCamera: fromCamera,
            preferences: preferences,
          );
          if (!_canPublishResult(generation)) return;
          _showAddedToCart(product.name);
        }
      } else if (result.kind == CatalogLookupKind.remote) {
        final remote = result.remoteProduct!;
        final routeResult = await context.push<Object?>(
          '/products/quick-add',
          extra: remote.metadata,
        );
        final created = routeResult is StoreProduct ? routeResult : null;
        if (created != null &&
            mounted &&
            generation == _lookupGeneration &&
            _branchVisible == true &&
            _routeForeground == true &&
            _appActive) {
          final added = await showProductQuickView(
            context,
            product: created,
            allowEdit: false,
          );
          if (added == true &&
              mounted &&
              generation == _lookupGeneration &&
              _branchVisible == true &&
              _routeForeground == true &&
              _appActive) {
            await _playSuccessFeedback(
              fromCamera: fromCamera,
              preferences: preferences,
            );
            if (!_canPublishResult(generation)) return;
            _showAddedToCart(created.name);
          }
        }
      } else {
        final shouldCreate = await _showUnknownBarcode(
          barcode.value,
          catalogUnavailable: result.kind == CatalogLookupKind.unavailable,
        );
        if (shouldCreate == true &&
            mounted &&
            generation == _lookupGeneration &&
            _branchVisible == true &&
            _routeForeground == true &&
            _appActive) {
          await context.push(
            Uri(
              path: '/products/quick-add',
              queryParameters: {'barcode': barcode.value},
            ).toString(),
          );
        }
      }
    } catch (_) {
      if (mounted &&
          generation == _lookupGeneration &&
          _branchVisible == true &&
          _routeForeground == true &&
          _appActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not look up this barcode.')),
        );
      }
    } finally {
      if (mounted && generation == _lookupGeneration) {
        if (fromCamera) {
          _guardCameraRepeat(
            barcode.value,
            duration: Duration(
              milliseconds: preferences.scannerRepeatCooldownMs,
            ),
          );
        }
        setState(() => _handling = false);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted &&
            _branchVisible == true &&
            _routeForeground == true &&
            _appActive) {
          unawaited(_scannerController.start());
        }
      }
    }
  }

  Future<AppPreferences> _loadPreferences() async {
    try {
      return await ref.read(appPreferencesProvider.future);
    } catch (_) {
      return AppPreferences.defaults(anchor: DateTime.now().toUtc());
    }
  }

  Duration _currentRepeatGuardDuration() => Duration(
    milliseconds:
        ref.read(appPreferencesProvider).value?.scannerRepeatCooldownMs ??
        defaultScannerRepeatCooldownMilliseconds,
  );

  void _guardCameraRepeat(String barcode, {required Duration duration}) {
    _cameraRepeatGuardTimers.remove(barcode)?.cancel();
    late final Timer timer;
    timer = Timer(duration, () {
      if (identical(_cameraRepeatGuardTimers[barcode], timer)) {
        _cameraRepeatGuardTimers.remove(barcode);
      }
    });
    _cameraRepeatGuardTimers[barcode] = timer;
  }

  Future<void> _playSuccessFeedback({
    required bool fromCamera,
    required AppPreferences preferences,
  }) async {
    if (!fromCamera ||
        (!preferences.scannerSoundEnabled &&
            !preferences.scannerVibrationEnabled)) {
      return;
    }
    try {
      await ref
          .read(scanFeedbackServiceProvider)
          .confirmProductAdded(
            soundEnabled: preferences.scannerSoundEnabled,
            vibrationEnabled: preferences.scannerVibrationEnabled,
          );
    } catch (_) {
      // Optional device feedback cannot change a successful cart result.
    }
  }

  bool _canPublishResult(int generation) =>
      mounted &&
      generation == _lookupGeneration &&
      _branchVisible == true &&
      _routeForeground == true &&
      _appActive;

  void _showAddedToCart(String productName) {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey('scan-added-feedback'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
        content: Semantics(
          liveRegion: true,
          label: '$productName added to cart',
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: scheme.onInverseSurface),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$productName added to cart.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showUnknownBarcode(
    String barcode, {
    bool catalogUnavailable = false,
  }) {
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
            if (catalogUnavailable) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The shared catalog is unavailable right now. You can still add the product manually and keep selling offline.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
