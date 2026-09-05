import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:raze_store/features/catalog/presentation/product_barcode_capture_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MobileScannerPlatform originalPlatform;

  setUp(() {
    originalPlatform = MobileScannerPlatform.instance;
    MobileScannerController.resetPlatformSessionOwner();
  });

  tearDown(() {
    MobileScannerController.resetPlatformSessionOwner();
    MobileScannerPlatform.instance = originalPlatform;
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  testWidgets('returns the first valid barcode in canonical form', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await ProductBarcodeCaptureScreen.scan(context);
              },
              child: const Text('Open reader'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reader'));
    await tester.pumpAndSettle();
    expect(find.text('Scan product barcode'), findsOneWidget);

    platform.addBarcode(
      const BarcodeCapture(
        barcodes: [
          Barcode(rawValue: ''),
          Barcode(rawValue: '012345678905'),
        ],
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(result, '0012345678905');
    expect(find.text('Open reader'), findsOneWidget);
    expect(platform.stopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('pauses and resumes camera access with the app lifecycle', (
    tester,
  ) async {
    final platform = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = platform;

    await tester.pumpWidget(
      const MaterialApp(home: ProductBarcodeCaptureScreen()),
    );
    await tester.pumpAndSettle();
    expect(platform.startCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(platform.stopCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.startCalls, 2);
  });
}

final class _FakeMobileScannerPlatform extends MobileScannerPlatform {
  final _barcodeController = StreamController<BarcodeCapture?>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodeController.stream;

  @override
  Stream<TorchState> get torchStateStream =>
      Stream.value(TorchState.unavailable);

  @override
  Stream<double> get zoomScaleStateStream => Stream.value(1);

  @override
  Widget buildCameraView() => const SizedBox.square(dimension: 100);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    startCalls++;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(200, 200),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    await _barcodeController.close();
  }

  void addBarcode(BarcodeCapture capture) => _barcodeController.add(capture);
}
