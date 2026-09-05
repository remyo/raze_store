import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef ReceiptTemporaryDirectoryProvider = Future<Directory> Function();
typedef ReceiptFileSaveCallback =
    Future<String?> Function(String sourcePath, String suggestedName);
typedef ReceiptFileShareCallback =
    Future<void> Function(
      String sourcePath,
      String fileName,
      String storeName,
      Rect? sharePositionOrigin,
    );

enum ReceiptSaveResult { saved, cancelled }

/// Writes receipt bytes to a real PNG before handing them to platform UI.
///
/// A concrete file is important on iOS: both the document picker and share
/// sheet can outlive the Flutter method call that opened them. The file stays
/// available until the platform operation completes and is then removed.
class ReceiptExportService {
  ReceiptExportService({
    required ReceiptTemporaryDirectoryProvider temporaryDirectoryProvider,
    required ReceiptFileSaveCallback saveFile,
    required ReceiptFileShareCallback shareFile,
  }) : _temporaryDirectoryProvider = temporaryDirectoryProvider,
       _saveFile = saveFile,
       _shareFile = shareFile;

  factory ReceiptExportService.device() {
    return ReceiptExportService(
      temporaryDirectoryProvider: getTemporaryDirectory,
      saveFile: _saveWithSystemDialog,
      shareFile: _shareWithSystemSheet,
    );
  }

  final ReceiptTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final ReceiptFileSaveCallback _saveFile;
  final ReceiptFileShareCallback _shareFile;

  Future<ReceiptSaveResult> savePng({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeFileName = _safePngFileName(fileName);
    final temporaryFile = await _writeTemporaryPng(bytes, safeFileName);
    try {
      final savedPath = await _saveFile(temporaryFile.path, safeFileName);
      return savedPath == null
          ? ReceiptSaveResult.cancelled
          : ReceiptSaveResult.saved;
    } finally {
      await _deleteBestEffort(temporaryFile);
    }
  }

  Future<void> sharePng({
    required Uint8List bytes,
    required String fileName,
    required String storeName,
    Rect? sharePositionOrigin,
  }) async {
    final safeFileName = _safePngFileName(fileName);
    final temporaryFile = await _writeTemporaryPng(bytes, safeFileName);
    try {
      await _shareFile(
        temporaryFile.path,
        safeFileName,
        storeName,
        sharePositionOrigin,
      );
    } finally {
      await _deleteBestEffort(temporaryFile);
    }
  }

  Future<File> _writeTemporaryPng(
    Uint8List bytes,
    String requestedFileName,
  ) async {
    if (!_hasPngSignature(bytes)) {
      throw const FormatException('Receipt export is not a valid PNG.');
    }

    final directory = await _temporaryDirectoryProvider();
    final receiptDirectory = Directory(
      p.join(directory.path, 'raze_store_receipts'),
    );
    await receiptDirectory.create(recursive: true);

    final uniqueName =
        '${DateTime.now().microsecondsSinceEpoch}-${requestedFileName.toLowerCase()}';
    final file = File(p.join(receiptDirectory.path, uniqueName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

Future<String?> _saveWithSystemDialog(String sourcePath, String suggestedName) {
  if (Platform.isIOS) {
    return _saveWithIosDocumentPicker(sourcePath, suggestedName);
  }
  return FlutterFileDialog.saveFile(
    params: SaveFileDialogParams(
      sourceFilePath: sourcePath,
      fileName: _safePngFileName(suggestedName),
      mimeTypesFilter: const ['image/png'],
    ),
  );
}

const _iosReceiptExportChannel = MethodChannel(
  'com.remyo.raze_store/receipt_export',
);

Future<String?> _saveWithIosDocumentPicker(
  String sourcePath,
  String suggestedName,
) {
  return _iosReceiptExportChannel.invokeMethod<String>('saveReceipt', {
    'sourcePath': sourcePath,
    'fileName': _safePngFileName(suggestedName),
  });
}

Future<void> _shareWithSystemSheet(
  String sourcePath,
  String fileName,
  String storeName,
  Rect? sharePositionOrigin,
) async {
  await SharePlus.instance.share(
    ShareParams(
      title: 'Receipt from $storeName',
      subject: 'Receipt from $storeName',
      files: [XFile(sourcePath, mimeType: 'image/png', name: fileName)],
      fileNameOverrides: [_safePngFileName(fileName)],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

bool _hasPngSignature(Uint8List bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

String _safePngFileName(String requestedFileName) {
  final baseName = p.basename(requestedFileName.trim());
  final withoutExtension = baseName.toLowerCase().endsWith('.png')
      ? baseName.substring(0, baseName.length - 4)
      : baseName;
  final safeStem = withoutExtension
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return '${safeStem.isEmpty ? 'raze-store-receipt' : safeStem}.png';
}

Future<void> _deleteBestEffort(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Temporary receipt files are safe to leave for the OS cache cleaner.
  }
}
