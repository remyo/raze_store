import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/camera_scan_frame.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';

void main() {
  testWidgets(
    'GCash receipt frame fits portrait and landscape without overflow',
    (tester) async {
      final session = _FakeSwitchableProductCameraSession();
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductCaptureScreen(
            purpose: ProductCapturePurpose.gcashReceipt,
            sessionFactory: () async => session,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Read GCash receipt'), findsOneWidget);
      expect(find.byType(CameraScanFrame), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test('rear camera is preferred and the first camera is the fallback', () {
    const front = CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 90,
    );
    const rear = CameraDescription(
      name: 'rear',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    );

    expect(selectProductCamera([front, rear]), rear);
    expect(selectProductCamera([front]), front);
  });

  test('uses a native luminance-friendly image format on iOS and Android', () {
    expect(
      productCameraImageFormat(TargetPlatform.iOS),
      ImageFormatGroup.bgra8888,
    );
    expect(
      productCameraImageFormat(TargetPlatform.android),
      ImageFormatGroup.yuv420,
    );
  });

  test(
    'low-light monitor waits for consecutive samples and uses hysteresis',
    () {
      final monitor = ProductLowLightMonitor();

      expect(monitor.addSample(0.10), isFalse);
      expect(monitor.addSample(0.10), isFalse);
      expect(monitor.isLowLight, isFalse);
      expect(monitor.addSample(0.10), isTrue);
      expect(monitor.isLowLight, isTrue);

      expect(monitor.addSample(0.50), isFalse);
      expect(monitor.isLowLight, isTrue);
      expect(monitor.addSample(0.50), isTrue);
      expect(monitor.isLowLight, isFalse);

      monitor.addSample(0.10);
      monitor.addSample(0.25);
      monitor.addSample(0.10);
      monitor.addSample(0.10);
      expect(monitor.isLowLight, isFalse);
    },
  );

  testWidgets(
    'label reader mirrors the barcode camera card and keeps low-light help',
    (tester) async {
      final session = _FakeSwitchableProductCameraSession();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProductCaptureScreen(
            purpose: ProductCapturePurpose.productLabel,
            sessionFactory: () async => session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final previewFinder = find.byKey(const ValueKey('fake-camera-preview'));
      final cameraCardFinder = find.ancestor(
        of: previewFinder,
        matching: find.byType(Card),
      );
      expect(cameraCardFinder, findsOneWidget);

      final cameraCard = tester.widget<Card>(cameraCardFinder);
      expect(cameraCard.color, Colors.black);
      expect(cameraCard.clipBehavior, Clip.antiAlias);

      final cameraCardElement = tester.element(cameraCardFinder);
      final widthConstraint = cameraCardElement
          .findAncestorWidgetOfExactType<ConstrainedBox>();
      expect(widthConstraint, isNotNull);
      expect(widthConstraint!.constraints.maxWidth, 720);

      final cameraAspectRatioFinder = find.descendant(
        of: cameraCardFinder,
        matching: find.byType(AspectRatio),
      );
      expect(cameraAspectRatioFinder, findsOneWidget);
      expect(
        tester.widget<AspectRatio>(cameraAspectRatioFinder).aspectRatio,
        4 / 3,
      );
      final previewCoverFinder = find.descendant(
        of: find.byKey(const ValueKey('product-capture-preview-cover')),
        matching: find.byType(FittedBox),
        matchRoot: true,
      );
      expect(previewCoverFinder, findsOneWidget);
      expect(tester.widget<FittedBox>(previewCoverFinder).fit, BoxFit.cover);

      expect(find.text('Read label'), findsOneWidget);
      expect(
        find.text('Center the product name inside the frame'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('product-label-guide-frame')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('product-capture-guide-frame')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Product name guide frame'), findsOneWidget);
      final sharedScanFrame = tester.widget<CameraScanFrame>(
        find.byType(CameraScanFrame),
      );
      // Keep the established barcode scanner treatment while giving longer
      // product names a little more horizontal room.
      expect(sharedScanFrame.widthFactor, 0.84);
      expect(sharedScanFrame.aspectRatio, 2.25);
      expect(sharedScanFrame.center, const Offset(0.5, 0.5));
      expect(sharedScanFrame.overlayOpacity, 0.08);
      final guideWindowFinder = find.byKey(
        const ValueKey('product-label-guide-window'),
      );
      expect(guideWindowFinder, findsOneWidget);
      final guideWindow = tester.widget<DecoratedBox>(guideWindowFinder);
      final decoration = guideWindow.decoration as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.color, Colors.white);
      expect(border.top.width, 2.5);
      expect(border.right, border.top);
      expect(border.bottom, border.top);
      expect(border.left, border.top);
      expect(decoration.borderRadius, AppRadius.card);
      expect(decoration.boxShadow, hasLength(1));
      final shadow = decoration.boxShadow!.single;
      expect(shadow.color, const Color(0x73000000));
      expect(shadow.blurRadius, 14);
      expect(shadow.spreadRadius, 2);
      expect(
        find.byKey(const ValueKey('product-label-guide-caption')),
        findsNothing,
      );

      final torchButtonFinder = find.byKey(
        const ValueKey('product-capture-torch-button'),
      );
      final switchButtonFinder = find.byKey(
        const ValueKey('product-capture-switch-camera-button'),
      );
      expect(torchButtonFinder, findsOneWidget);
      expect(switchButtonFinder, findsOneWidget);
      expect(
        tester.widget<IconButton>(torchButtonFinder).tooltip,
        'Turn flash on',
      );
      expect(
        tester.widget<IconButton>(switchButtonFinder).tooltip,
        'Switch camera',
      );
      expect(tester.widget<IconButton>(torchButtonFinder).onPressed, isNotNull);
      expect(
        tester.widget<IconButton>(switchButtonFinder).onPressed,
        isNotNull,
      );

      for (final controlFinder in [torchButtonFinder, switchButtonFinder]) {
        final controlElement = tester.element(controlFinder);
        final material = controlElement
            .findAncestorWidgetOfExactType<Material>();
        expect(material, isNotNull);
        expect(material!.shape, isA<CircleBorder>());
      }

      final controlsAlignmentFinder = find.ancestor(
        of: torchButtonFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is Align && widget.alignment == Alignment.topRight,
        ),
      );
      expect(controlsAlignmentFinder, findsOneWidget);
      expect(
        find.descendant(
          of: controlsAlignmentFinder,
          matching: switchButtonFinder,
        ),
        findsOneWidget,
      );
      var cameraCardRect = tester.getRect(cameraCardFinder);
      final torchCenter = tester.getCenter(torchButtonFinder);
      final switchCenter = tester.getCenter(switchButtonFinder);
      expect(cameraCardRect.contains(torchCenter), isTrue);
      expect(cameraCardRect.contains(switchCenter), isTrue);
      expect(torchCenter.dx, greaterThan(cameraCardRect.center.dx));
      expect(switchCenter.dx, greaterThan(torchCenter.dx));
      expect(torchCenter.dy, lessThan(cameraCardRect.center.dy));
      expect(switchCenter.dy, lessThan(cameraCardRect.center.dy));

      expect(
        find.byKey(const ValueKey('product-capture-low-light-warning')),
        findsNothing,
      );

      session
        ..emitLuminance(0.10)
        ..emitLuminance(0.10)
        ..emitLuminance(0.10);
      await tester.pump();

      expect(
        find.text(
          'It’s too dark. Turn on the flashlight or move somewhere brighter.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('product-capture-warning-torch-action')),
      );
      await tester.tap(
        find.byKey(const ValueKey('product-capture-warning-torch-action')),
      );
      await tester.pumpAndSettle();

      expect(session.torchValues, [true]);
      expect(
        find.text('Still too dark? Move somewhere brighter.'),
        findsOneWidget,
      );

      final shutterFinder = find.byKey(
        const ValueKey('product-capture-shutter-button'),
      );
      expect(shutterFinder, findsOneWidget);
      expect(shutterFinder.hitTestable(), findsOneWidget);
      expect(tester.widget<IconButton>(shutterFinder).tooltip, 'Read label');
      cameraCardRect = tester.getRect(cameraCardFinder);
      expect(
        tester.getTopLeft(shutterFinder).dx,
        greaterThan(cameraCardRect.right),
      );
    },
  );

  for (final viewport in const <Size>[
    Size(320, 568),
    Size(390, 844),
    Size(844, 390),
  ]) {
    testWidgets(
      'label camera and shutter fit ${viewport.width.toInt()}x${viewport.height.toInt()} without scrolling',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = viewport;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final session = _FakeProductCameraSession();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ProductCaptureScreen(
              purpose: ProductCapturePurpose.productLabel,
              sessionFactory: () async => session,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final previewFinder = find.byKey(const ValueKey('fake-camera-preview'));
        final cameraCardFinder = find.ancestor(
          of: previewFinder,
          matching: find.byType(Card),
        );
        final shutterFinder = find.byKey(
          const ValueKey('product-capture-shutter-button'),
        );
        expect(cameraCardFinder, findsOneWidget);
        expect(shutterFinder, findsOneWidget);
        expect(cameraCardFinder.hitTestable(), findsOneWidget);
        expect(shutterFinder.hitTestable(), findsOneWidget);

        final screenRect = Offset.zero & viewport;
        final cameraCardRect = tester.getRect(cameraCardFinder);
        final shutterRect = tester.getRect(shutterFinder);
        expect(screenRect.contains(cameraCardRect.topLeft), isTrue);
        expect(screenRect.contains(cameraCardRect.bottomRight), isTrue);
        expect(screenRect.contains(shutterRect.topLeft), isTrue);
        expect(screenRect.contains(shutterRect.bottomRight), isTrue);
        expect(
          cameraCardRect.width / cameraCardRect.height,
          closeTo(4 / 3, 0.01),
        );
        if (viewport.width > viewport.height) {
          expect(shutterRect.left, greaterThan(cameraCardRect.right));
        } else {
          expect(shutterRect.top, greaterThan(cameraCardRect.bottom));
        }

        final previewCoverFinder = find.descendant(
          of: find.byKey(const ValueKey('product-capture-preview-cover')),
          matching: find.byType(FittedBox),
          matchRoot: true,
        );
        expect(previewCoverFinder, findsOneWidget);
        expect(tester.widget<FittedBox>(previewCoverFinder).fit, BoxFit.cover);

        for (final scrollable in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          expect(scrollable.position.pixels, 0);
        }

        final sharedScanFrame = tester.widget<CameraScanFrame>(
          find.byType(CameraScanFrame),
        );
        expect(sharedScanFrame.widthFactor, 0.84);
        expect(sharedScanFrame.aspectRatio, 2.25);
        final guideRect = tester.getRect(
          find.byKey(const ValueKey('product-label-guide-window')),
        );
        expect(guideRect.width / cameraCardRect.width, closeTo(0.84, 0.01));

        if (viewport == const Size(320, 568)) {
          session
            ..emitLuminance(0.10)
            ..emitLuminance(0.10)
            ..emitLuminance(0.10);
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find
                .byKey(const ValueKey('product-capture-low-light-warning'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find
                .byKey(const ValueKey('product-capture-warning-torch-action'))
                .hitTestable(),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets('product photo keeps its full-screen camera treatment', (
    tester,
  ) async {
    final session = _FakeProductCameraSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductCaptureScreen(sessionFactory: () async => session),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(CameraScanFrame), findsNothing);
    expect(
      find.byKey(const ValueKey('product-capture-guide-frame')),
      findsOneWidget,
    );
    expect(find.byType(CustomPaint), findsWidgets);

    final fullScreenStackFinder = find.ancestor(
      of: find.byKey(const ValueKey('fake-camera-preview')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Stack && widget.fit == StackFit.expand,
      ),
    );
    expect(fullScreenStackFinder, findsOneWidget);
    expect(
      tester.getSize(fullScreenStackFinder).width,
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    );
  });

  testWidgets('stops light sampling, captures, and returns the XFile', (
    tester,
  ) async {
    final session = _FakeProductCameraSession(
      picture: XFile('/tmp/guided-product-photo.jpg'),
    );
    XFile? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.of(context).push<XFile>(
                  MaterialPageRoute<XFile>(
                    builder: (context) => ProductCaptureScreen(
                      sessionFactory: () async => session,
                    ),
                  ),
                );
              },
              child: const Text('Open camera'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open camera'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('product-capture-shutter-button')),
    );
    await tester.pumpAndSettle();

    expect(result?.path, '/tmp/guided-product-photo.jpg');
    expect(
      session.events,
      containsAllInOrder([
        'initialize',
        'startLuminanceSampling',
        'stopLuminanceSampling',
        'takePicture',
        'dispose',
      ]),
    );
  });

  testWidgets('releases and recreates the camera across app lifecycle', (
    tester,
  ) async {
    final sessions = <_FakeProductCameraSession>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductCaptureScreen(
          sessionFactory: () async {
            final session = _FakeProductCameraSession();
            sessions.add(session);
            return session;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sessions, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(sessions.first.disposeCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(sessions, hasLength(2));
    expect(sessions.last.initializeCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test(
    'launcher provider can be overridden without opening camera hardware',
    () {
      final fake = _FakeProductCaptureLauncher();
      final container = ProviderContainer(
        overrides: [productCaptureLauncherProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(productCaptureLauncherProvider), same(fake));
    },
  );
}

class _FakeProductCameraSession implements ProductCameraSession {
  _FakeProductCameraSession({XFile? picture})
    : picture = picture ?? XFile('/tmp/fake-product-photo.jpg');

  final XFile picture;
  final List<String> events = [];
  final List<bool> torchValues = [];
  ValueChanged<double>? _onLuminance;
  int initializeCalls = 0;
  int disposeCalls = 0;
  bool _streaming = false;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    events.add('initialize');
  }

  @override
  Widget buildPreview() => const ColoredBox(
    key: ValueKey('fake-camera-preview'),
    color: Colors.blueGrey,
  );

  @override
  Future<void> startLuminanceSampling(ValueChanged<double> onSample) async {
    events.add('startLuminanceSampling');
    _streaming = true;
    _onLuminance = onSample;
  }

  @override
  Future<void> stopLuminanceSampling() async {
    events.add('stopLuminanceSampling');
    _streaming = false;
    _onLuminance = null;
  }

  @override
  Future<void> setTorchEnabled(bool enabled) async {
    events.add('setTorchEnabled:$enabled');
    torchValues.add(enabled);
  }

  @override
  Future<XFile> takePicture() async {
    if (_streaming) {
      throw StateError('Light sampling was not stopped before capture.');
    }
    events.add('takePicture');
    return picture;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    events.add('dispose');
    _streaming = false;
    _onLuminance = null;
  }

  void emitLuminance(double value) => _onLuminance?.call(value);
}

class _FakeSwitchableProductCameraSession extends _FakeProductCameraSession
    implements ProductCameraSwitchingSession {
  @override
  bool get canSwitchCamera => true;

  @override
  Future<void> switchCamera() async {
    events.add('switchCamera');
  }
}

class _FakeProductCaptureLauncher implements ProductCaptureLauncher {
  @override
  Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  }) async {
    return null;
  }
}
