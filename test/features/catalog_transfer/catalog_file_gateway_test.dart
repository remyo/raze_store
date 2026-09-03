import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/catalog_transfer/data/catalog_file_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_file_dialog');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'saveFile'
              ? '/Files/exported-file'
              : '/cache/selected-file';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'saves an existing source file through the device file dialog',
    () async {
      final path = await const DeviceCatalogFileGateway().saveFile(
        sourcePath: '/tmp/store.razestore',
        suggestedName: 'store.razestore',
        mimeTypes: const ['application/vnd.raze-store.backup'],
      );

      expect(path, '/Files/exported-file');
      expect(calls.single.method, 'saveFile');
      final arguments = (calls.single.arguments as Map).cast<String, Object?>();
      expect(arguments['sourceFilePath'], '/tmp/store.razestore');
      expect(arguments['fileName'], 'store.razestore');
      expect(arguments['data'], isNull);
    },
  );

  test('backup picker restricts selection to Raze Store archives', () async {
    final path = await const DeviceCatalogFileGateway().pickBackup();

    expect(path, '/cache/selected-file');
    final arguments = (calls.single.arguments as Map).cast<String, Object?>();
    expect(arguments['allowedUtiTypes'], ['com.remyo.razestore.backup']);
    expect(arguments['fileExtensionsFilter'], ['razestore']);
    expect(arguments['copyFileToCacheDir'], isTrue);
  });

  test('CSV picker accepts spreadsheet CSV documents', () async {
    final path = await const DeviceCatalogFileGateway().pickCsv();

    expect(path, '/cache/selected-file');
    final arguments = (calls.single.arguments as Map).cast<String, Object?>();
    expect(arguments['fileExtensionsFilter'], ['csv']);
    expect(arguments['mimeTypesFilter'], contains('text/csv'));
    expect(arguments['copyFileToCacheDir'], isTrue);
  });
}
