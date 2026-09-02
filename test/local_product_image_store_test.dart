import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:raze_store/core/storage/local_product_image_store.dart';

void main() {
  test('persists a picked image inside managed storage', () async {
    final temporary = await Directory.systemTemp.createTemp('raze-store-');
    addTearDown(() => temporary.delete(recursive: true));
    final source = File(p.join(temporary.path, 'source.png'));
    await source.writeAsBytes(<int>[1, 2, 3]);
    final managedRoot = Directory(p.join(temporary.path, 'managed'));
    final store = LocalProductImageStore(root: managedRoot);

    final savedPath = await store.persist(source: XFile(source.path));

    expect(p.isWithin(managedRoot.path, savedPath), isTrue);
    expect(await File(savedPath).readAsBytes(), <int>[1, 2, 3]);
  });

  test('only deletes files inside managed storage', () async {
    final temporary = await Directory.systemTemp.createTemp('raze-store-');
    addTearDown(() => temporary.delete(recursive: true));
    final external = File(p.join(temporary.path, 'external.jpg'));
    await external.writeAsBytes(<int>[4, 5, 6]);
    final managedRoot = Directory(p.join(temporary.path, 'managed'));
    final store = LocalProductImageStore(root: managedRoot);

    await store.deleteIfManaged(external.path);

    expect(await external.exists(), isTrue);
  });
}
