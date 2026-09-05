import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/camera_scan_frame.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';
import 'package:raze_store/features/gcash/gcash_theme.dart';

void main() {
  test('receipt source crop reverses the centered cover preview', () {
    for (final viewport in const [
      Size(300, 400),
      Size(700, 300),
      Size(1200, 900),
    ]) {
      final geometry = GcashReceiptFrameGeometry(viewport);
      expect(geometry.frame.width / geometry.frame.height, 1);
      expect(geometry.frame.width, lessThanOrEqualTo(600));
      expect((Offset.zero & viewport).contains(geometry.frame.topLeft), isTrue);
      expect(
        (Offset.zero & viewport).contains(geometry.frame.bottomRight),
        isTrue,
      );
      for (final source in const [Size(1200, 1600), Size(1600, 1200)]) {
        final crop = geometry.sourceRect(source);
        final fit = applyBoxFit(BoxFit.cover, source, viewport);
        final visibleSource = Alignment.center.inscribe(
          fit.source,
          Offset.zero & source,
        );
        final sourceScale = fit.destination.width / fit.source.width;
        final roundTrip = Rect.fromLTWH(
          (crop.left - visibleSource.left) * sourceScale,
          (crop.top - visibleSource.top) * sourceScale,
          crop.width * sourceScale,
          crop.height * sourceScale,
        );
        expect(roundTrip.left, closeTo(geometry.frame.left, 0.0001));
        expect(roundTrip.top, closeTo(geometry.frame.top, 0.0001));
        expect(roundTrip.width, closeTo(geometry.frame.width, 0.0001));
        expect(roundTrip.height, closeTo(geometry.frame.height, 0.0001));
        expect(crop.left, greaterThanOrEqualTo(0));
        expect(crop.top, greaterThanOrEqualTo(0));
        expect(crop.right, lessThanOrEqualTo(source.width));
        expect(crop.bottom, lessThanOrEqualTo(source.height));
      }
    }
    final geometry = GcashReceiptFrameGeometry(const Size(300, 300));
    expect(
      geometry.sourceRect(
        const Size(4000, 3000),
        previewSize: const Size(1600, 900),
      ),
      rectMoreOrLessEquals(const Rect.fromLTWH(987.5, 487.5, 2025, 2025)),
    );
  });

  for (final viewport in const [
    Size(320, 568),
    Size(390, 844),
    Size(844, 390),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'GCash information frame, guidance and controls fit $viewport at text scale $textScale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = viewport;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final session = _SanitizedReceiptCameraSession();
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('receipt-qa-boundary'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: GcashTheme(
                  builder: (_) => ProductCaptureScreen(
                    purpose: ProductCapturePurpose.gcashReceipt,
                    sessionFactory: () async => session,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Read GCash receipt'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('gcash-receipt-guide-frame')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(
            find.text('Skip blank space and the green footer. Avoid glare.'),
            findsOneWidget,
          );
          final previewFinder = find.byKey(
            const ValueKey('gcash-receipt-preview'),
          );
          final frameFinder = find.byKey(
            const ValueKey('gcash-receipt-guide-window'),
          );
          final preview = tester.getRect(previewFinder);
          final geometry = GcashReceiptFrameGeometry(preview.size);
          expect(
            tester.getRect(frameFinder),
            rectMoreOrLessEquals(geometry.frame.shift(preview.topLeft)),
          );
          expect(geometry.frame.width, greaterThanOrEqualTo(160));
          final instructions = tester.getRect(
            find.byKey(const ValueKey('gcash-receipt-instruction')),
          );
          expect(instructions.overlaps(tester.getRect(frameFinder)), isFalse);
          final footerFinder = find.byKey(
            const ValueKey('gcash-receipt-support-note'),
          );
          final shutterFinder = find.byKey(
            const ValueKey('product-capture-shutter-button'),
          );
          if (textScale == 1) {
            expect(footerFinder.hitTestable(), findsOneWidget);
            expect(shutterFinder.hitTestable(), findsOneWidget);
          }

          session
            ..emitLuminance(0.1)
            ..emitLuminance(0.1)
            ..emitLuminance(0.1);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('product-capture-low-light-warning')),
            findsOneWidget,
          );
          await tester.ensureVisible(footerFinder);
          await tester.pumpAndSettle();
          expect(footerFinder.hitTestable(), findsOneWidget);
          await tester.ensureVisible(shutterFinder);
          expect(shutterFinder.hitTestable(), findsOneWidget);
          final torchFinder = find.byKey(
            const ValueKey('product-capture-torch-button'),
          );
          await tester.ensureVisible(torchFinder);
          await tester.tap(torchFinder);
          await tester.pumpAndSettle();
          expect(session.torchValues, [true]);
          expect(
            find.text('Still too dark? Move somewhere brighter.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'receipt capture saves the displayed window at native resolution',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gcash-crop-test-'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => temporary.delete(recursive: true)),
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => temporary.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(2);
      const _SanitizedReceiptPainter().paint(canvas, const Size(1200, 1600));
      final picture = recorder.endRecording();
      final source = await tester.runAsync(() => picture.toImage(2400, 3200));
      picture.dispose();
      final bytes = await tester.runAsync(
        () => source!.toByteData(format: ui.ImageByteFormat.png),
      );
      source!.dispose();
      final session = _FakeProductCameraSession(
        picture: XFile.fromData(
          bytes!.buffer.asUint8List(),
          mimeType: 'image/png',
        ),
      );
      final returned = Completer<XFile?>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async => returned.complete(
                  await Navigator.of(context).push<XFile>(
                    MaterialPageRoute(
                      builder: (_) => ProductCaptureScreen(
                        purpose: ProductCapturePurpose.gcashReceipt,
                        sessionFactory: () async => session,
                      ),
                    ),
                  ),
                ),
                child: const Text('Open receipt camera'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open receipt camera'));
      await tester.pumpAndSettle();
      final viewport = tester.getSize(
        find.byKey(const ValueKey('gcash-receipt-preview')),
      );
      final crop = GcashReceiptFrameGeometry(
        viewport,
      ).sourceRect(const Size(2400, 3200));
      await tester.tap(
        find.byKey(const ValueKey('product-capture-shutter-button')),
      );
      for (var attempt = 0; attempt < 100 && !returned.isCompleted; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(returned.isCompleted, isTrue);
      final captured = await returned.future;
      expect(captured, isNotNull);
      final codec = await tester.runAsync(
        () async => ui.instantiateImageCodec(await captured!.readAsBytes()),
      );
      final output = (await tester.runAsync(
        () => codec!.getNextFrame(),
      ))!.image;
      codec!.dispose();
      expect(output.width, crop.width.round());
      expect(output.height, crop.height.round());
      expect(output.width, greaterThan(1100));
      output.dispose();
      expect(
        session.events,
        containsAllInOrder(['stopLuminanceSampling', 'takePicture', 'dispose']),
      );
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

class _SanitizedReceiptCameraSession extends _FakeProductCameraSession
    implements ProductCameraPreviewGeometry {
  @override
  Size get orientedPreviewSize => const Size(1200, 1600);

  @override
  Widget buildPreview() =>
      const CustomPaint(painter: _SanitizedReceiptPainter());
}

class _SanitizedReceiptPainter extends CustomPainter {
  const _SanitizedReceiptPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFCCCCCC),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(70, 100, 1060, 1460),
        const Radius.circular(30),
      ),
      Paint()..color = Colors.white,
    );
    void text(
      String value,
      double y,
      double fontSize, {
      Color color = Colors.black,
      bool bold = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: fontSize,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 920);
      painter.paint(canvas, Offset((1200 - painter.width) / 2, y));
      painter.dispose();
    }

    text('GCash', 165, 64, color: const Color(0xFF005CE5), bold: true);
    text('DEMO R***', 390, 50, color: const Color(0xFF005CE5), bold: true);
    text('09XX XXX 1234', 470, 40);
    text('Sent via GCash', 550, 36);
    text('Amount                       500.00', 710, 40);
    canvas.drawLine(
      const Offset(150, 805),
      const Offset(1050, 805),
      Paint()
        ..color = const Color(0xFFCCCCCC)
        ..strokeWidth = 2,
    );
    text('Total Amount Sent       ₱500.00', 845, 42, bold: true);
    text('Ref. No. 0000 000 123456', 1030, 34);
    text('Sep 05, 2026 4:00 PM', 1110, 34);
    canvas.drawRect(
      const Rect.fromLTWH(70, 1400, 1060, 160),
      Paint()..color = const Color(0xFFC1EBB1),
    );
    text('Promotional footer', 1450, 38);
  }

  @override
  bool shouldRepaint(_SanitizedReceiptPainter oldDelegate) => false;
}
