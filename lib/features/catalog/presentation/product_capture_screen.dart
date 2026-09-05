import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';

/// The kind of product detail the guided camera should frame.
enum ProductCapturePurpose { productPhoto, productLabel, gcashReceipt }

/// Injectable entry point for opening the guided product camera.
abstract interface class ProductCaptureLauncher {
  Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  });
}

/// Opens the on-device guided camera.
class DeviceProductCaptureLauncher implements ProductCaptureLauncher {
  const DeviceProductCaptureLauncher();

  @override
  Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  }) {
    return ProductCaptureScreen.capture(context, purpose: purpose);
  }
}

final productCaptureLauncherProvider = Provider<ProductCaptureLauncher>(
  (ref) => const DeviceProductCaptureLauncher(),
);

typedef ProductCameraSessionFactory = Future<ProductCameraSession> Function();

/// Small camera boundary that keeps [ProductCaptureScreen] hardware-testable.
abstract interface class ProductCameraSession {
  Future<void> initialize();

  Widget buildPreview();

  Future<void> startLuminanceSampling(ValueChanged<double> onSample);

  Future<void> stopLuminanceSampling();

  Future<void> setTorchEnabled(bool enabled);

  Future<XFile> takePicture();

  Future<void> dispose();
}

/// Optional camera capability used by the label reader's camera switch action.
///
/// Keeping this separate from [ProductCameraSession] means test and alternate
/// sessions that only support one camera do not need to implement switching.
abstract interface class ProductCameraSwitchingSession {
  bool get canSwitchCamera;

  Future<void> switchCamera();
}

/// Optional preview geometry used to crop a camera feed like the barcode
/// scanner without stretching it.
abstract interface class _ProductCameraPreviewGeometry {
  Size? get orientedPreviewSize;
}

/// Creates a session using the rear camera, falling back to the first camera.
Future<ProductCameraSession> defaultProductCameraSessionFactory() async {
  final cameras = await availableCameras();
  if (cameras.isEmpty) {
    throw const ProductCameraUnavailableException();
  }

  final selectedCamera = selectProductCamera(cameras);
  return _PluginProductCameraSession(cameras, cameras.indexOf(selectedCamera));
}

/// Selects a rear camera when one is available.
@visibleForTesting
CameraDescription selectProductCamera(List<CameraDescription> cameras) {
  assert(cameras.isNotEmpty);
  for (final camera in cameras) {
    if (camera.lensDirection == CameraLensDirection.back) {
      return camera;
    }
  }
  return cameras.first;
}

/// Uses each mobile camera implementation's reliable streaming format.
@visibleForTesting
ImageFormatGroup productCameraImageFormat(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.iOS => ImageFormatGroup.bgra8888,
    TargetPlatform.android => ImageFormatGroup.yuv420,
    _ => ImageFormatGroup.unknown,
  };
}

class ProductCameraUnavailableException implements Exception {
  const ProductCameraUnavailableException();
}

/// Applies hysteresis so a single noisy frame cannot flash the warning.
@visibleForTesting
class ProductLowLightMonitor {
  ProductLowLightMonitor({
    this.lowThreshold = 0.22,
    this.adequateThreshold = 0.30,
    this.lowSamplesRequired = 3,
    this.adequateSamplesRequired = 2,
  }) : assert(lowThreshold >= 0 && lowThreshold < adequateThreshold),
       assert(adequateThreshold <= 1),
       assert(lowSamplesRequired > 0),
       assert(adequateSamplesRequired > 0);

  final double lowThreshold;
  final double adequateThreshold;
  final int lowSamplesRequired;
  final int adequateSamplesRequired;

  int _lowSamples = 0;
  int _adequateSamples = 0;
  bool _isLowLight = false;

  bool get isLowLight => _isLowLight;

  /// Returns whether the visible low-light state changed.
  bool addSample(double normalizedLuminance) {
    if (!normalizedLuminance.isFinite) {
      return false;
    }

    final previous = _isLowLight;
    if (normalizedLuminance < lowThreshold) {
      _lowSamples += 1;
      _adequateSamples = 0;
      if (_lowSamples >= lowSamplesRequired) {
        _isLowLight = true;
      }
    } else if (normalizedLuminance > adequateThreshold) {
      _adequateSamples += 1;
      _lowSamples = 0;
      if (_adequateSamples >= adequateSamplesRequired) {
        _isLowLight = false;
      }
    } else {
      _lowSamples = 0;
      _adequateSamples = 0;
    }

    return previous != _isLowLight;
  }

  void reset() {
    _lowSamples = 0;
    _adequateSamples = 0;
    _isLowLight = false;
  }
}

/// A full-screen, guided camera that pops with the captured [XFile].
class ProductCaptureScreen extends StatefulWidget {
  const ProductCaptureScreen({
    super.key,
    this.purpose = ProductCapturePurpose.productPhoto,
    this.sessionFactory = defaultProductCameraSessionFactory,
  });

  final ProductCapturePurpose purpose;
  final ProductCameraSessionFactory sessionFactory;

  static Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  }) {
    return Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(
        fullscreenDialog: true,
        builder: (context) => ProductCaptureScreen(purpose: purpose),
      ),
    );
  }

  @override
  State<ProductCaptureScreen> createState() => _ProductCaptureScreenState();
}

class _ProductCaptureScreenState extends State<ProductCaptureScreen>
    with WidgetsBindingObserver {
  final ProductLowLightMonitor _lightMonitor = ProductLowLightMonitor();
  Size? _receiptViewport;

  Future<XFile> _cropReceipt(XFile photo) async {
    final viewport = _receiptViewport;
    if (viewport == null) return photo;
    final codec = await ui.instantiateImageCodec(await photo.readAsBytes());
    final source = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final scale = math.max(
        viewport.width / source.width,
        viewport.height / source.height,
      );
      final width =
          math.min(viewport.width * 0.82, viewport.height * 0.60 * 0.62) /
          scale;
      final height = width / 0.62;
      final rect = Rect.fromCenter(
        center: Offset(source.width / 2, source.height / 2),
        width: width,
        height: height,
      );
      final outputWidth = math.min(1100, width.round());
      final outputHeight = (outputWidth / 0.62).round();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        source,
        rect,
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(outputWidth, outputHeight);
      picture.dispose();
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      final directory = await getTemporaryDirectory();
      final captureDirectory = Directory(
        '${directory.path}/raze_store_gcash_capture',
      );
      await captureDirectory.create(recursive: true);
      final file = File(
        '${captureDirectory.path}/${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      return XFile(file.path);
    } finally {
      source.dispose();
    }
  }

  ProductCameraSession? _session;
  int _sessionGeneration = 0;
  bool _lifecycleSuspended = false;
  bool _starting = true;
  bool _capturing = false;
  bool _changingTorch = false;
  bool _switchingCamera = false;
  bool _torchEnabled = false;
  bool _isLowLight = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_openCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_lifecycleSuspended) {
          _lifecycleSuspended = false;
          unawaited(_openCamera());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _lifecycleSuspended = true;
        unawaited(_releaseCamera(updateUi: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionGeneration += 1;
    final session = _session;
    _session = null;
    if (session != null) {
      unawaited(session.dispose());
    }
    super.dispose();
  }

  Future<void> _openCamera() async {
    final generation = ++_sessionGeneration;
    final staleSession = _session;
    _session = null;
    if (staleSession != null) {
      await staleSession.dispose();
    }
    if (!mounted || generation != _sessionGeneration || _lifecycleSuspended) {
      return;
    }

    setState(() {
      _starting = true;
      _errorMessage = null;
      _torchEnabled = false;
      _switchingCamera = false;
      _isLowLight = false;
      _lightMonitor.reset();
    });

    ProductCameraSession? candidate;
    try {
      candidate = await widget.sessionFactory();
      await candidate.initialize();
      if (!mounted || generation != _sessionGeneration || _lifecycleSuspended) {
        await candidate.dispose();
        return;
      }

      _session = candidate;
      setState(() => _starting = false);

      try {
        await candidate.startLuminanceSampling((luminance) {
          if (!mounted || !identical(_session, candidate)) {
            return;
          }
          if (_lightMonitor.addSample(luminance)) {
            setState(() => _isLowLight = _lightMonitor.isLowLight);
          }
        });
      } catch (_) {
        // The preview and capture remain useful if a device cannot stream
        // frames for the optional light meter.
      }
    } catch (error) {
      if (candidate != null && !identical(candidate, _session)) {
        await candidate.dispose();
      }
      if (!mounted || generation != _sessionGeneration) {
        return;
      }
      _session = null;
      setState(() {
        _starting = false;
        _errorMessage = _cameraErrorMessage(error);
      });
    }
  }

  Future<void> _releaseCamera({required bool updateUi}) async {
    _sessionGeneration += 1;
    final session = _session;
    _session = null;
    _lightMonitor.reset();
    if (updateUi && mounted) {
      setState(() {
        _starting = true;
        _capturing = false;
        _changingTorch = false;
        _switchingCamera = false;
        _torchEnabled = false;
        _isLowLight = false;
      });
    }
    if (session != null) {
      await session.dispose();
    }
  }

  Future<void> _capture() async {
    final session = _session;
    if (session == null || _capturing || _changingTorch || _switchingCamera) {
      return;
    }

    setState(() => _capturing = true);
    try {
      await session.stopLuminanceSampling();
      var photo = await session.takePicture();
      if (widget.purpose == ProductCapturePurpose.gcashReceipt && mounted) {
        photo = await _cropReceipt(photo);
      }
      if (!mounted || !identical(_session, session)) {
        return;
      }
      Navigator.of(context).pop<XFile>(photo);
    } catch (_) {
      if (!mounted || !identical(_session, session)) {
        return;
      }
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not take the photo. Please try again.'),
        ),
      );
      try {
        await session.startLuminanceSampling((luminance) {
          if (!mounted || !identical(_session, session)) {
            return;
          }
          if (_lightMonitor.addSample(luminance)) {
            setState(() => _isLowLight = _lightMonitor.isLowLight);
          }
        });
      } catch (_) {
        // Capture can still be retried without light sampling.
      }
    }
  }

  Future<void> _toggleTorch() => _setTorchEnabled(!_torchEnabled);

  Future<void> _setTorchEnabled(bool enabled) async {
    final session = _session;
    if (session == null || _changingTorch || _capturing || _switchingCamera) {
      return;
    }

    setState(() => _changingTorch = true);
    try {
      await session.setTorchEnabled(enabled);
      if (!mounted || !identical(_session, session)) {
        return;
      }
      setState(() {
        _torchEnabled = enabled;
        _changingTorch = false;
      });
    } catch (_) {
      if (!mounted || !identical(_session, session)) {
        return;
      }
      setState(() => _changingTorch = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The camera light is not available on this device.'),
        ),
      );
    }
  }

  Future<void> _switchCamera() async {
    final session = _session;
    if (session == null ||
        session is! ProductCameraSwitchingSession ||
        _switchingCamera ||
        _changingTorch ||
        _capturing) {
      return;
    }
    final switchingSession = session as ProductCameraSwitchingSession;
    if (!switchingSession.canSwitchCamera) {
      return;
    }

    setState(() => _switchingCamera = true);
    try {
      await session.stopLuminanceSampling();
      await switchingSession.switchCamera();
      if (!mounted || !identical(_session, session)) {
        return;
      }

      _lightMonitor.reset();
      setState(() {
        _switchingCamera = false;
        _torchEnabled = false;
        _isLowLight = false;
      });

      try {
        await session.startLuminanceSampling((luminance) {
          if (!mounted || !identical(_session, session)) {
            return;
          }
          if (_lightMonitor.addSample(luminance)) {
            setState(() => _isLowLight = _lightMonitor.isLowLight);
          }
        });
      } catch (_) {
        // Camera switching still succeeds when light sampling is unavailable.
      }
    } catch (_) {
      if (!mounted || !identical(_session, session)) {
        return;
      }
      setState(() => _switchingCamera = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not switch cameras. Please try again.'),
        ),
      );
      await _openCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    final readsLabel = widget.purpose == ProductCapturePurpose.productLabel;
    return PopScope(
      canPop: !_capturing,
      child: Scaffold(
        backgroundColor: readsLabel
            ? Theme.of(context).scaffoldBackgroundColor
            : Colors.black,
        appBar: AppBar(
          backgroundColor: readsLabel ? null : Colors.black,
          foregroundColor: readsLabel ? null : Colors.white,
          title: Text(widget.purpose.title),
          leading: IconButton(
            onPressed: _capturing ? null : () => Navigator.of(context).pop(),
            tooltip: 'Close camera',
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.purpose == ProductCapturePurpose.productLabel) {
      return _buildLabelBody();
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return _CameraUnavailableView(
        message: errorMessage,
        onRetry: _openCamera,
      );
    }

    final session = _session;
    if (_starting || session == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: AppSpacing.md),
            Text('Starting camera…', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: widget.purpose == ProductCapturePurpose.gcashReceipt
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    _receiptViewport = constraints.biggest;
                    return _CoverCameraPreview(session: session);
                  },
                )
              : Center(child: session.buildPreview()),
        ),
        Semantics(
          key: widget.purpose == ProductCapturePurpose.productLabel
              ? const ValueKey('product-label-guide-frame')
              : null,
          container: true,
          label: widget.purpose.guideSemanticsLabel,
          child: IgnorePointer(
            child: widget.purpose == ProductCapturePurpose.gcashReceipt
                ? LayoutBuilder(
                    builder: (context, constraints) => CameraScanFrame(
                      widthFactor: math.min(
                        0.82,
                        constraints.maxHeight *
                            0.60 *
                            0.62 /
                            constraints.maxWidth,
                      ),
                      aspectRatio: 0.62,
                    ),
                  )
                : widget.purpose == ProductCapturePurpose.productLabel
                ? const CameraScanFrame(
                    key: ValueKey('product-capture-guide-frame'),
                    frameKey: ValueKey('product-label-guide-window'),
                    widthFactor: 0.78,
                    maximumWidth: 530.4,
                    aspectRatio: 2.25,
                  )
                : CustomPaint(
                    key: const ValueKey('product-capture-guide-frame'),
                    painter: _ProductGuidePainter(widget.purpose),
                  ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.73),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: AppRadius.control,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.purpose.instruction,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.purpose.secondaryInstruction
                        case final hint?) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isLowLight)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.md,
            child: _LowLightWarning(
              torchEnabled: _torchEnabled,
              changingTorch: _changingTorch,
              onTurnOnTorch: () => _setTorchEnabled(true),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.66),
                borderRadius: AppRadius.panel,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton.filledTonal(
                          key: const ValueKey('product-capture-torch-button'),
                          onPressed: _changingTorch || _capturing
                              ? null
                              : _toggleTorch,
                          tooltip: _torchEnabled
                              ? 'Turn off camera light'
                              : 'Turn on camera light',
                          icon: _changingTorch
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _torchEnabled
                                      ? Icons.flashlight_on_rounded
                                      : Icons.flashlight_off_rounded,
                                ),
                        ),
                      ),
                      SizedBox.square(
                        dimension: 72,
                        child: IconButton.filled(
                          key: const ValueKey('product-capture-shutter-button'),
                          onPressed: _capturing || _changingTorch
                              ? null
                              : _capture,
                          tooltip: 'Take photo',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: Colors.white54,
                          ),
                          icon: _capturing
                              ? const SizedBox.square(
                                  dimension: 28,
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_rounded, size: 32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelBody() {
    final session = _session;
    final ProductCameraSwitchingSession? switchableSession =
        session is ProductCameraSwitchingSession
        ? session as ProductCameraSwitchingSession
        : null;
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const pageInset = AppSpacing.sm;
          const controlGap = AppSpacing.md;
          final landscape = constraints.maxWidth > constraints.maxHeight;
          final shutterSize = constraints.maxHeight < 360 ? 64.0 : 72.0;
          final contentWidth = math.max(
            1.0,
            constraints.maxWidth - (pageInset * 2),
          );
          final contentHeight = math.max(
            1.0,
            constraints.maxHeight - (pageInset * 2),
          );
          final widthForCamera = landscape
              ? contentWidth - controlGap - shutterSize
              : contentWidth;
          final heightForCamera = landscape
              ? contentHeight
              : contentHeight - controlGap - shutterSize;
          final cameraWidth = math.max(
            1.0,
            math.min(
              720.0,
              math.min(widthForCamera, heightForCamera * (4 / 3)),
            ),
          );

          final cameraCard = _buildLabelCameraCard(
            session: session,
            switchableSession: switchableSession,
            width: cameraWidth,
          );
          final shutter = _buildLabelShutter(
            session: session,
            dimension: shutterSize,
          );

          return SingleChildScrollView(
            key: const ValueKey('product-label-camera-scroll-view'),
            padding: const EdgeInsets.all(pageInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: contentHeight),
              child: landscape
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        cameraCard,
                        const SizedBox(width: controlGap),
                        shutter,
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        cameraCard,
                        const SizedBox(height: controlGap),
                        shutter,
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLabelCameraCard({
    required ProductCameraSession? session,
    required ProductCameraSwitchingSession? switchableSession,
    required double width,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: SizedBox(
        width: width,
        child: Card(
          margin: EdgeInsets.zero,
          color: Colors.black,
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_errorMessage case final message?)
                  _CameraUnavailableView(message: message, onRetry: _openCamera)
                else if (_starting || session == null)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: AppSpacing.md),
                        Text(
                          'Starting camera…',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  )
                else ...[
                  ColoredBox(
                    color: Colors.black,
                    child: _CoverCameraPreview(
                      key: const ValueKey('product-capture-preview-cover'),
                      session: session,
                    ),
                  ),
                  Semantics(
                    key: const ValueKey('product-label-guide-frame'),
                    container: true,
                    label: 'Product name guide frame',
                    child: const IgnorePointer(
                      child: CameraScanFrame(
                        key: ValueKey('product-capture-guide-frame'),
                        frameKey: ValueKey('product-label-guide-window'),
                        widthFactor: 0.84,
                        aspectRatio: 2.25,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LabelCameraAction(
                            buttonKey: const ValueKey(
                              'product-capture-torch-button',
                            ),
                            tooltip: _torchEnabled
                                ? 'Turn flash off'
                                : 'Turn flash on',
                            icon: _torchEnabled
                                ? Icons.flash_on_rounded
                                : Icons.flash_off_rounded,
                            enabled:
                                !_changingTorch &&
                                !_switchingCamera &&
                                !_capturing,
                            progress: _changingTorch,
                            onPressed: _toggleTorch,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _LabelCameraAction(
                            buttonKey: const ValueKey(
                              'product-capture-switch-camera-button',
                            ),
                            tooltip: 'Switch camera',
                            icon: Icons.cameraswitch_outlined,
                            enabled:
                                switchableSession?.canSwitchCamera == true &&
                                !_changingTorch &&
                                !_switchingCamera &&
                                !_capturing,
                            progress: _switchingCamera,
                            onPressed: _switchCamera,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: _isLowLight
                          ? _LowLightWarning(
                              torchEnabled: _torchEnabled,
                              changingTorch: _changingTorch,
                              onTurnOnTorch: () => _setTorchEnabled(true),
                            )
                          : DecoratedBox(
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
                                  'Center the product name inside the frame',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (_capturing)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabelShutter({
    required ProductCameraSession? session,
    required double dimension,
  }) {
    if (session == null || _errorMessage != null) {
      return const SizedBox.shrink();
    }
    return SizedBox.square(
      dimension: dimension,
      child: IconButton.filled(
        key: const ValueKey('product-capture-shutter-button'),
        onPressed: _capturing || _changingTorch || _switchingCamera
            ? null
            : _capture,
        tooltip: 'Read label',
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
        icon: _capturing
            ? const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const Icon(Icons.camera_alt_rounded, size: 32),
      ),
    );
  }
}

class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({super.key, required this.session});

  final ProductCameraSession session;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetSize = constraints.biggest;
        final reportedSize = session is _ProductCameraPreviewGeometry
            ? (session as _ProductCameraPreviewGeometry).orientedPreviewSize
            : null;
        final sourceSize =
            reportedSize == null ||
                !reportedSize.width.isFinite ||
                !reportedSize.height.isFinite ||
                reportedSize.width <= 0 ||
                reportedSize.height <= 0
            ? targetSize
            : reportedSize;
        return ClipRect(
          child: SizedBox.fromSize(
            size: targetSize,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox.fromSize(
                size: sourceSize,
                child: session.buildPreview(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LabelCameraAction extends StatelessWidget {
  const _LabelCameraAction({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.progress,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final bool progress;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB315211F),
      shape: const CircleBorder(),
      child: IconButton(
        key: buttonKey,
        onPressed: enabled ? () => unawaited(onPressed()) : null,
        tooltip: tooltip,
        color: Colors.white,
        disabledColor: Colors.white38,
        icon: progress
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon),
      ),
    );
  }
}

class _PluginProductCameraSession
    implements
        ProductCameraSession,
        ProductCameraSwitchingSession,
        _ProductCameraPreviewGeometry {
  _PluginProductCameraSession(
    List<CameraDescription> cameras,
    this._cameraIndex,
  ) : _cameras = List.unmodifiable(cameras) {
    _controller = _createController(_cameras[_cameraIndex]);
  }

  static const _sampleInterval = Duration(milliseconds: 650);

  final List<CameraDescription> _cameras;
  int _cameraIndex;
  late CameraController _controller;
  DateTime? _lastSampleAt;
  bool _disposed = false;

  CameraController _createController(CameraDescription camera) {
    return CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: productCameraImageFormat(defaultTargetPlatform),
    );
  }

  @override
  bool get canSwitchCamera => !_disposed && _cameras.length > 1;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Size? get orientedPreviewSize {
    final previewSize = _controller.value.previewSize;
    if (previewSize == null) {
      return null;
    }
    final value = _controller.value;
    final orientation = value.isRecordingVideo
        ? value.recordingOrientation ?? value.deviceOrientation
        : value.previewPauseOrientation ??
              value.lockedCaptureOrientation ??
              value.deviceOrientation;
    final landscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    return landscape
        ? previewSize
        : Size(previewSize.height, previewSize.width);
  }

  @override
  Future<void> startLuminanceSampling(ValueChanged<double> onSample) async {
    if (_disposed ||
        _controller.value.isStreamingImages ||
        !_controller.supportsImageStreaming()) {
      return;
    }
    _lastSampleAt = null;
    await _controller.startImageStream((image) {
      if (_disposed) {
        return;
      }
      final now = DateTime.now();
      final lastSampleAt = _lastSampleAt;
      if (lastSampleAt != null &&
          now.difference(lastSampleAt) < _sampleInterval) {
        return;
      }
      _lastSampleAt = now;
      final luminance = estimateProductImageLuminance(image);
      if (luminance != null) {
        onSample(luminance);
      }
    });
  }

  @override
  Future<void> stopLuminanceSampling() async {
    if (_disposed || !_controller.value.isStreamingImages) {
      return;
    }
    await _controller.stopImageStream();
  }

  @override
  Future<void> setTorchEnabled(bool enabled) {
    if (_disposed) {
      return Future<void>.value();
    }
    return _controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
  }

  @override
  Future<void> switchCamera() async {
    if (!canSwitchCamera) {
      return;
    }

    final previousController = _controller;
    if (previousController.value.isStreamingImages) {
      await previousController.stopImageStream();
    }
    if (previousController.value.isInitialized &&
        previousController.value.flashMode == FlashMode.torch) {
      await previousController.setFlashMode(FlashMode.off);
    }
    await previousController.dispose();

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _lastSampleAt = null;
    _controller = _createController(_cameras[_cameraIndex]);
    await _controller.initialize();
  }

  @override
  Future<XFile> takePicture() => _controller.takePicture();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_controller.value.isStreamingImages) {
      try {
        await _controller.stopImageStream();
      } catch (_) {
        // Disposal must continue even if the platform already ended the stream.
      }
    }
    if (_controller.value.isInitialized &&
        _controller.value.flashMode == FlashMode.torch) {
      try {
        await _controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // Releasing the controller also releases the torch on supported devices.
      }
    }
    await _controller.dispose();
  }
}

/// Estimates brightness from a small, evenly distributed set of frame pixels.
@visibleForTesting
double? estimateProductImageLuminance(CameraImage image) {
  if (image.planes.isEmpty || image.width <= 0 || image.height <= 0) {
    return null;
  }

  return switch (image.format.group) {
    ImageFormatGroup.yuv420 ||
    ImageFormatGroup.nv21 => _estimateSingleChannelLuminance(image),
    ImageFormatGroup.bgra8888 => _estimateBgraLuminance(image),
    ImageFormatGroup.unknown || ImageFormatGroup.jpeg => null,
  };
}

double? _estimateSingleChannelLuminance(CameraImage image) {
  final plane = image.planes.first;
  final width = math.min(image.width, plane.width ?? image.width);
  final height = math.min(image.height, plane.height ?? image.height);
  final pixelStride = plane.bytesPerPixel ?? 1;
  final sampleStride = _luminanceSampleStride(width, height);
  var total = 0;
  var count = 0;

  for (var y = 0; y < height; y += sampleStride) {
    final rowStart = y * plane.bytesPerRow;
    for (var x = 0; x < width; x += sampleStride) {
      final index = rowStart + (x * pixelStride);
      if (index >= plane.bytes.length) {
        break;
      }
      total += plane.bytes[index];
      count += 1;
    }
  }

  return count == 0 ? null : total / (count * 255);
}

double? _estimateBgraLuminance(CameraImage image) {
  final plane = image.planes.first;
  final width = math.min(image.width, plane.width ?? image.width);
  final height = math.min(image.height, plane.height ?? image.height);
  final pixelStride = plane.bytesPerPixel ?? 4;
  final sampleStride = _luminanceSampleStride(width, height);
  var total = 0.0;
  var count = 0;

  for (var y = 0; y < height; y += sampleStride) {
    final rowStart = y * plane.bytesPerRow;
    for (var x = 0; x < width; x += sampleStride) {
      final index = rowStart + (x * pixelStride);
      if (index + 2 >= plane.bytes.length) {
        break;
      }
      final blue = plane.bytes[index];
      final green = plane.bytes[index + 1];
      final red = plane.bytes[index + 2];
      total += (0.0722 * blue) + (0.7152 * green) + (0.2126 * red);
      count += 1;
    }
  }

  return count == 0 ? null : total / (count * 255);
}

int _luminanceSampleStride(int width, int height) {
  const targetSamples = 4096;
  return math.max(1, math.sqrt((width * height) / targetSamples).ceil());
}

class _LowLightWarning extends StatelessWidget {
  const _LowLightWarning({
    required this.torchEnabled,
    required this.changingTorch,
    required this.onTurnOnTorch,
  });

  final bool torchEnabled;
  final bool changingTorch;
  final VoidCallback onTurnOnTorch;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('product-capture-low-light-warning'),
      color: const Color(0xFFFFE2AD),
      borderRadius: AppRadius.panel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.brightness_low_rounded, color: Color(0xFF3D2500)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                torchEnabled
                    ? 'Still too dark? Move somewhere brighter.'
                    : 'It’s too dark. Turn on the flashlight or move somewhere brighter.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF3D2500),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!torchEnabled)
              TextButton(
                key: const ValueKey('product-capture-warning-torch-action'),
                onPressed: changingTorch ? null : onTurnOnTorch,
                child: const Text('Use flashlight'),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraUnavailableView extends StatelessWidget {
  const _CameraUnavailableView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductGuidePainter extends CustomPainter {
  const _ProductGuidePainter(this.purpose);

  final ProductCapturePurpose purpose;

  @override
  void paint(Canvas canvas, Size size) {
    final guideRect = _productGuideRect(size, purpose.guideAspectRatio);
    final guide = RRect.fromRectAndRadius(
      guideRect,
      const Radius.circular(AppRadius.large),
    );
    final shadePath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(guide),
    );
    canvas.drawPath(shadePath, Paint()..color = Colors.black45);
    canvas.drawRRect(
      guide,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final accentPaint = Paint()
      ..color = const Color(0xFFFFC567)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    const cornerLength = 26.0;
    final left = guideRect.left;
    final right = guideRect.right;
    final top = guideRect.top;
    final bottom = guideRect.bottom;
    canvas
      ..drawLine(
        Offset(left, top + cornerLength),
        Offset(left, top),
        accentPaint,
      )
      ..drawLine(
        Offset(left, top),
        Offset(left + cornerLength, top),
        accentPaint,
      )
      ..drawLine(
        Offset(right - cornerLength, top),
        Offset(right, top),
        accentPaint,
      )
      ..drawLine(
        Offset(right, top),
        Offset(right, top + cornerLength),
        accentPaint,
      )
      ..drawLine(
        Offset(left, bottom - cornerLength),
        Offset(left, bottom),
        accentPaint,
      )
      ..drawLine(
        Offset(left, bottom),
        Offset(left + cornerLength, bottom),
        accentPaint,
      )
      ..drawLine(
        Offset(right - cornerLength, bottom),
        Offset(right, bottom),
        accentPaint,
      )
      ..drawLine(
        Offset(right, bottom),
        Offset(right, bottom - cornerLength),
        accentPaint,
      );
  }

  @override
  bool shouldRepaint(_ProductGuidePainter oldDelegate) =>
      oldDelegate.purpose != purpose;
}

Rect _productGuideRect(Size size, double aspectRatio) {
  final maxWidth = math.max(0.0, size.width - (AppSpacing.xxl * 2));
  final maxHeight = math.max(0.0, size.height * 0.56);
  var width = math.min(maxWidth, 430.0);
  var height = width / aspectRatio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * aspectRatio;
  }
  return Rect.fromCenter(
    center: Offset(size.width / 2, (size.height * 0.47)),
    width: width,
    height: height,
  );
}

extension on ProductCapturePurpose {
  String get title => switch (this) {
    ProductCapturePurpose.productPhoto => 'Take product photo',
    ProductCapturePurpose.productLabel => 'Read label',
    ProductCapturePurpose.gcashReceipt => 'Read GCash receipt',
  };

  String get instruction => switch (this) {
    ProductCapturePurpose.productPhoto =>
      'Fit the whole product inside the frame',
    ProductCapturePurpose.gcashReceipt => 'Fit the receipt inside the frame',
    ProductCapturePurpose.productLabel =>
      'Center the product name inside the frame',
  };

  String? get secondaryInstruction => switch (this) {
    ProductCapturePurpose.productPhoto => null,
    ProductCapturePurpose.gcashReceipt =>
      'Include the amount, reference number and date. Avoid screen glare.',
    ProductCapturePurpose.productLabel =>
      'Keep other words outside the frame, avoid glare, and hold steady.',
  };

  String get guideSemanticsLabel => switch (this) {
    ProductCapturePurpose.productPhoto => 'Product photo guide frame',
    ProductCapturePurpose.gcashReceipt => 'GCash receipt guide frame',
    ProductCapturePurpose.productLabel => 'Product name guide frame',
  };

  double get guideAspectRatio => switch (this) {
    ProductCapturePurpose.productPhoto => 0.78,
    ProductCapturePurpose.gcashReceipt => 0.62,
    ProductCapturePurpose.productLabel => 2.25,
  };
}

String _cameraErrorMessage(Object error) {
  if (error is ProductCameraUnavailableException) {
    return 'No camera is available on this device.';
  }
  if (error is CameraException) {
    return switch (error.code) {
      'CameraAccessDenied' =>
        'Camera access was denied. Allow camera access to take a product photo.',
      'CameraAccessDeniedWithoutPrompt' =>
        'Camera access is off. Enable it in Settings, then try again.',
      'CameraAccessRestricted' => 'Camera access is restricted on this device.',
      _ => 'The camera could not be started. Please try again.',
    };
  }
  return 'The camera could not be started. Please try again.';
}
