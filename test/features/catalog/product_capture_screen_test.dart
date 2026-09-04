import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';

void main() {
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
    'shows purpose guide and offers torch when sampled light is low',
    (tester) async {
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

      expect(find.text('Capture product label'), findsOneWidget);
      expect(
        find.text('Fill the frame with the product label and keep text sharp'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('product-capture-guide-frame')),
        findsOneWidget,
      );
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
      await tester.tap(
        find.byKey(const ValueKey('product-capture-warning-torch-action')),
      );
      await tester.pumpAndSettle();

      expect(session.torchValues, [true]);
      expect(
        find.text('Still too dark? Move somewhere brighter.'),
        findsOneWidget,
      );
    },
  );

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

class _FakeProductCaptureLauncher implements ProductCaptureLauncher {
  @override
  Future<XFile?> capture(
    BuildContext context, {
    ProductCapturePurpose purpose = ProductCapturePurpose.productPhoto,
  }) async {
    return null;
  }
}
