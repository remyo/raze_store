import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bounds decoded pixels before background removal', () async {
    final source = await _solidPng(width: 200, height: 100);

    final prepared = await prepareProductPhotoBytesForBackgroundRemoval(
      source,
      targetLongestSide: 80,
    );
    final dimensions = await _dimensions(prepared);

    expect(dimensions, (80, 40));
  });

  test('uses a phone-safe default working size', () async {
    final source = await _solidPng(width: 900, height: 450);

    final prepared = await prepareProductPhotoBytesForBackgroundRemoval(source);

    expect(await _dimensions(prepared), (768, 384));
  });

  test('rejects a source above the configured pixel safety limit', () async {
    final source = await _solidPng(width: 20, height: 10);

    expect(
      () => prepareProductPhotoBytesForBackgroundRemoval(
        source,
        maximumSourcePixels: 199,
      ),
      throwsA(isA<ProductBackgroundRemovalException>()),
    );
  });

  test(
    'centers and enlarges a background-removed subject on a square canvas',
    () async {
      final source = await _subjectPng(
        width: 240,
        height: 120,
        // Deliberately off-center so this verifies both cropping and
        // re-centering instead of only the scale calculation.
        subject: const ui.Rect.fromLTWH(8, 5, 30, 40),
      );

      final normalized = await normalizeBackgroundRemovedProductBytes(
        source,
        paddingFraction: 0.1,
      );

      expect(await _dimensions(normalized), (240, 240));
      final (left, top, right, bottom) = (await _alphaBounds(normalized))!;
      final visibleWidth = right - left + 1;
      final visibleHeight = bottom - top + 1;
      expect(visibleHeight, closeTo(192, 2));
      expect(visibleWidth / visibleHeight, closeTo(0.75, 0.02));
      expect((left + right) / 2, closeTo(119.5, 1));
      expect((top + bottom) / 2, closeTo(119.5, 1));
    },
  );

  test('preserves an opaque background-removal result', () async {
    final source = await _solidPng(width: 200, height: 100);

    final normalized = await normalizeBackgroundRemovedProductBytes(source);

    expect(await _dimensions(normalized), (200, 100));
  });

  test(
    'only deletes UUID-named output files in its temporary directory',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'raze_store_background_cleanup_',
      );
      addTearDown(() => root.delete(recursive: true));
      final outputDirectory = Directory(
        '${root.path}/${OnDeviceProductBackgroundRemover.directoryName}',
      );
      await outputDirectory.create(recursive: true);
      final owned = File(
        '${outputDirectory.path}/123e4567-e89b-12d3-a456-426614174000.png',
      );
      final source = File('${root.path}/source.png');
      await owned.writeAsBytes([1]);
      await source.writeAsBytes([2]);
      final remover = OnDeviceProductBackgroundRemover(temporaryRoot: root);

      await remover.deleteTemporary(XFile(owned.path));
      await remover.deleteTemporary(XFile(source.path));

      expect(await owned.exists(), isFalse);
      expect(await source.exists(), isTrue);
    },
  );
}

Future<Uint8List> _solidPng({required int width, required int height}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF1565C0),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _subjectPng({
  required int width,
  required int height,
  required ui.Rect subject,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    subject,
    ui.Paint()
      ..color = const ui.Color(0xFF1565C0)
      ..isAntiAlias = false,
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<(int, int, int, int)?> _alphaBounds(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var minX = image.width;
      var minY = image.height;
      var maxX = -1;
      var maxY = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (rgba.getUint8(((y * image.width) + x) * 4 + 3) <= 12) continue;
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
      return maxX < minX ? null : (minX, minY, maxX, maxY);
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<(int, int)> _dimensions(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      return (descriptor.width, descriptor.height);
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}
