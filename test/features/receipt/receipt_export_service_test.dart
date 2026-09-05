import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/receipt/application/receipt_export_service.dart';

void main() {
  late Directory temporaryRoot;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp(
      'raze-store-receipt-export-test-',
    );
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  test(
    'download gives the platform a concrete PNG and cleans it afterward',
    () async {
      String? receivedSourcePath;
      String? receivedName;
      final service = ReceiptExportService(
        temporaryDirectoryProvider: () async => temporaryRoot,
        saveFile: (sourcePath, suggestedName) async {
          receivedSourcePath = sourcePath;
          receivedName = suggestedName;
          expect(await File(sourcePath).readAsBytes(), _pngBytes);
          return '/user/selected/$suggestedName';
        },
        shareFile: _unusedShare,
      );

      final result = await service.savePng(
        bytes: _pngBytes,
        fileName: '../Sari Sari Receipt.PNG',
      );

      expect(result, ReceiptSaveResult.saved);
      expect(receivedName, 'Sari-Sari-Receipt.png');
      expect(receivedSourcePath, isNotNull);
      expect(await File(receivedSourcePath!).exists(), isFalse);
    },
  );

  test(
    'download cancellation is reported and the temporary PNG is removed',
    () async {
      String? receivedSourcePath;
      final service = ReceiptExportService(
        temporaryDirectoryProvider: () async => temporaryRoot,
        saveFile: (sourcePath, _) async {
          receivedSourcePath = sourcePath;
          return null;
        },
        shareFile: _unusedShare,
      );

      final result = await service.savePng(
        bytes: _pngBytes,
        fileName: 'receipt.png',
      );

      expect(result, ReceiptSaveResult.cancelled);
      expect(await File(receivedSourcePath!).exists(), isFalse);
    },
  );

  test(
    'share keeps a concrete PNG alive until the share sheet completes',
    () async {
      String? sharedSourcePath;
      const origin = Rect.fromLTWH(12, 20, 140, 48);
      final service = ReceiptExportService(
        temporaryDirectoryProvider: () async => temporaryRoot,
        saveFile: _unusedSave,
        shareFile: (sourcePath, fileName, storeName, shareOrigin) async {
          sharedSourcePath = sourcePath;
          expect(await File(sourcePath).readAsBytes(), _pngBytes);
          expect(fileName, 'receipt.png');
          expect(storeName, 'Aling Nena Store');
          expect(shareOrigin, origin);
        },
      );

      await service.sharePng(
        bytes: _pngBytes,
        fileName: 'receipt.png',
        storeName: 'Aling Nena Store',
        sharePositionOrigin: origin,
      );

      expect(sharedSourcePath, isNotNull);
      expect(await File(sharedSourcePath!).exists(), isFalse);
    },
  );

  test(
    'plugin failures are rethrown after cleaning the temporary PNG',
    () async {
      String? receivedSourcePath;
      final service = ReceiptExportService(
        temporaryDirectoryProvider: () async => temporaryRoot,
        saveFile: (sourcePath, _) async {
          receivedSourcePath = sourcePath;
          throw StateError('file dialog failed');
        },
        shareFile: _unusedShare,
      );

      await expectLater(
        service.savePng(bytes: _pngBytes, fileName: 'receipt.png'),
        throwsStateError,
      );
      expect(await File(receivedSourcePath!).exists(), isFalse);
    },
  );

  test('rejects invalid image bytes before opening platform UI', () async {
    var saveCalls = 0;
    final service = ReceiptExportService(
      temporaryDirectoryProvider: () async => temporaryRoot,
      saveFile: (_, _) async {
        saveCalls += 1;
        return '/unused';
      },
      shareFile: _unusedShare,
    );

    await expectLater(
      service.savePng(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        fileName: 'receipt.png',
      ),
      throwsFormatException,
    );
    expect(saveCalls, 0);
  });
}

final _pngBytes = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  0,
]);

Future<String?> _unusedSave(String sourcePath, String suggestedName) async =>
    '/unused';

Future<void> _unusedShare(
  String sourcePath,
  String fileName,
  String storeName,
  Rect? sharePositionOrigin,
) async {}
