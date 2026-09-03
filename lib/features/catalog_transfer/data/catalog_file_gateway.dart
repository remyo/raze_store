import 'package:flutter_file_dialog/flutter_file_dialog.dart';

abstract interface class CatalogFileGateway {
  Future<String?> saveFile({
    required String sourcePath,
    required String suggestedName,
    required List<String> mimeTypes,
  });

  Future<String?> pickBackup();

  Future<String?> pickCsv();
}

class DeviceCatalogFileGateway implements CatalogFileGateway {
  const DeviceCatalogFileGateway();

  @override
  Future<String?> saveFile({
    required String sourcePath,
    required String suggestedName,
    required List<String> mimeTypes,
  }) {
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        sourceFilePath: sourcePath,
        fileName: suggestedName,
        mimeTypesFilter: mimeTypes,
      ),
    );
  }

  @override
  Future<String?> pickBackup() {
    return FlutterFileDialog.pickFile(
      params: const OpenFileDialogParams(
        dialogType: OpenFileDialogType.document,
        allowedUtiTypes: ['com.remyo.razestore.backup'],
        fileExtensionsFilter: ['razestore'],
        mimeTypesFilter: [
          'application/vnd.raze-store.backup',
          'application/octet-stream',
          'application/zip',
        ],
        copyFileToCacheDir: true,
      ),
    );
  }

  @override
  Future<String?> pickCsv() {
    return FlutterFileDialog.pickFile(
      params: const OpenFileDialogParams(
        dialogType: OpenFileDialogType.document,
        allowedUtiTypes: ['public.comma-separated-values-text'],
        fileExtensionsFilter: ['csv'],
        mimeTypesFilter: ['text/csv', 'text/comma-separated-values'],
        copyFileToCacheDir: true,
      ),
    );
  }
}
