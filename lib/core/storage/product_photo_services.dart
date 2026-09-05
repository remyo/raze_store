import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_background_remover/image_background_remover.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProductPhotoPicker {
  Future<XFile?> pickFromGallery();

  Future<XFile?> takePhoto();
}

class DeviceProductPhotoPicker implements ProductPhotoPicker {
  DeviceProductPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<XFile?> pickFromGallery() => _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 88,
  );

  @override
  Future<XFile?> takePhoto() => _picker.pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: CameraDevice.rear,
    maxWidth: 1600,
    imageQuality: 88,
  );
}

final productPhotoPickerProvider = Provider<ProductPhotoPicker>((ref) {
  return DeviceProductPhotoPicker();
});

abstract interface class ProductBackgroundRemover {
  Future<XFile> removeBackground(XFile source);

  /// Deletes an output owned by this remover. Arbitrary source photos are
  /// ignored so form cleanup can never remove a user's gallery photo.
  Future<void> deleteTemporary(XFile output);
}

/// Runs the bundled ONNX model locally and returns a transparent PNG.
final class OnDeviceProductBackgroundRemover
    implements ProductBackgroundRemover {
  OnDeviceProductBackgroundRemover({
    Directory? temporaryRoot,
    Uuid uuid = const Uuid(),
    this.maximumInputBytes = 15 * 1024 * 1024,
    this.maximumOutputBytes = 30 * 1024 * 1024,
    this.maximumSourcePixels = 40 * 1000 * 1000,
    this.targetLongestSide = 768,
  }) : _temporaryRoot = temporaryRoot,
       _uuid = uuid;

  static const directoryName = 'background_removed_products';

  final Directory? _temporaryRoot;
  final Uuid _uuid;
  final int maximumInputBytes;
  final int maximumOutputBytes;
  final int maximumSourcePixels;
  final int targetLongestSide;
  Future<void>? _initialization;

  @override
  Future<XFile> removeBackground(XFile source) async {
    final length = await source.length();
    if (length <= 0 || length > maximumInputBytes) {
      throw const ProductBackgroundRemovalException(
        'Choose a product photo smaller than 15 MB.',
      );
    }

    try {
      final sourceBytes = await source.readAsBytes();
      final preparedBytes = await prepareProductPhotoBytesForBackgroundRemoval(
        sourceBytes,
        maximumSourcePixels: maximumSourcePixels,
        targetLongestSide: targetLongestSide,
      );
      await _ensureInitialized();
      // Edge enhancement creates another full-resolution nested mask in this
      // plugin. The model already produces a smooth mask, so retaining mask
      // smoothing while skipping that extra pass keeps memory bounded on
      // lower-end phones without changing the on-device/privacy behavior.
      final removedBytes = await BackgroundRemover.instance.removeBgBytes(
        preparedBytes,
        enhanceEdges: false,
      );
      if (removedBytes.isEmpty || removedBytes.length > maximumOutputBytes) {
        throw const ProductBackgroundRemovalException(
          'The processed product photo is too large.',
        );
      }
      final outputBytes = await normalizeBackgroundRemovedProductBytes(
        removedBytes,
      );
      if (outputBytes.isEmpty || outputBytes.length > maximumOutputBytes) {
        throw const ProductBackgroundRemovalException(
          'The processed product photo is too large.',
        );
      }

      final temporaryDirectory =
          _temporaryRoot ?? await getTemporaryDirectory();
      final outputDirectory = Directory(
        p.join(temporaryDirectory.path, directoryName),
      );
      if (!await outputDirectory.exists()) {
        await outputDirectory.create(recursive: true);
      }
      final output = File(p.join(outputDirectory.path, '${_uuid.v4()}.png'));
      await output.writeAsBytes(outputBytes, flush: true);
      return XFile(output.path, mimeType: 'image/png');
    } on ProductBackgroundRemovalException {
      rethrow;
    } catch (_) {
      // The dependency owns a process-wide ONNX session. Reset it after a
      // failed inference so a retry does not reuse a broken session or a
      // stale completed initialization future.
      _initialization = null;
      try {
        await BackgroundRemover.instance.dispose();
      } catch (_) {
        // Preserve the useful, user-facing background-removal error below.
      }
      throw const ProductBackgroundRemovalException(
        'The background could not be removed from this photo.',
      );
    }
  }

  @override
  Future<void> deleteTemporary(XFile output) async {
    final temporaryDirectory = _temporaryRoot ?? await getTemporaryDirectory();
    final ownedDirectory = p.normalize(
      Directory(p.join(temporaryDirectory.path, directoryName)).absolute.path,
    );
    final candidate = p.normalize(File(output.path).absolute.path);
    final filename = p.basename(candidate);
    if (!p.isWithin(ownedDirectory, candidate) ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.png$',
        ).hasMatch(filename)) {
      return;
    }

    final file = File(candidate);
    if (await file.exists()) await file.delete();
  }

  Future<void> _ensureInitialized() async {
    final initialization = _initialization ??= BackgroundRemover.instance
        .initializeOrt();
    try {
      await initialization;
    } catch (_) {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
      rethrow;
    }
  }

  Future<void> dispose() => BackgroundRemover.instance.dispose();
}

/// Reads image dimensions without decoding the full bitmap, rejects extreme
/// sources, then asks Flutter's native codec for a bounded image before ONNX
/// processing. Gallery/camera picks are capped before storage; background
/// removal uses a smaller default working copy to bound the plugin's nested
/// mask allocations on lower-memory phones.
Future<Uint8List> prepareProductPhotoBytesForBackgroundRemoval(
  Uint8List sourceBytes, {
  int maximumSourcePixels = 40 * 1000 * 1000,
  int targetLongestSide = 768,
}) async {
  if (sourceBytes.isEmpty ||
      maximumSourcePixels <= 0 ||
      targetLongestSide <= 0) {
    throw const ProductBackgroundRemovalException(
      'This product photo could not be read.',
    );
  }

  final buffer = await ui.ImmutableBuffer.fromUint8List(sourceBytes);
  late final int width;
  late final int height;
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      width = descriptor.width;
      height = descriptor.height;
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }

  if (width <= 0 || height <= 0 || width * height > maximumSourcePixels) {
    throw const ProductBackgroundRemovalException(
      'Choose a product photo smaller than 40 megapixels.',
    );
  }
  final longestSide = width > height ? width : height;
  if (longestSide <= targetLongestSide) return sourceBytes;

  final scale = targetLongestSide / longestSide;
  final targetWidth = (width * scale)
      .round()
      .clamp(1, targetLongestSide)
      .toInt();
  final targetHeight = (height * scale)
      .round()
      .clamp(1, targetLongestSide)
      .toInt();
  final codec = await ui.instantiateImageCodec(
    sourceBytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const ProductBackgroundRemovalException(
          'This product photo could not be resized.',
        );
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Makes a transparent background-removal result useful in square product
/// thumbnails.
///
/// Background-removal models preserve the source canvas, so a product that was
/// photographed from far away can remain tiny even after its background is
/// gone. This finds the visible alpha bounds, scales that subject to a square
/// canvas with a small safety margin, and centers it without changing its
/// aspect ratio. The remover already limits its longest input side to 768px,
/// keeping the extra RGBA buffer and canvas bounded on lower-memory phones.
Future<Uint8List> normalizeBackgroundRemovedProductBytes(
  Uint8List sourceBytes, {
  double paddingFraction = 0.06,
  int alphaThreshold = 12,
}) async {
  if (sourceBytes.isEmpty ||
      !paddingFraction.isFinite ||
      paddingFraction < 0 ||
      paddingFraction >= 0.5 ||
      alphaThreshold < 0 ||
      alphaThreshold > 255) {
    throw const ProductBackgroundRemovalException(
      'The processed product photo could not be read.',
    );
  }

  final codec = await ui.instantiateImageCodec(sourceBytes);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) return sourceBytes;

      var minX = image.width;
      var minY = image.height;
      var maxX = -1;
      var maxY = -1;
      for (var y = 0; y < image.height; y++) {
        final rowOffset = y * image.width * 4;
        for (var x = 0; x < image.width; x++) {
          final alpha = rgba.getUint8(rowOffset + (x * 4) + 3);
          if (alpha <= alphaThreshold) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }

      // An entirely transparent or fully edge-to-edge result has no safe
      // transparent margin to crop. Preserve it instead of guessing.
      if (maxX < minX || maxY < minY) return sourceBytes;
      if (minX == 0 &&
          minY == 0 &&
          maxX == image.width - 1 &&
          maxY == image.height - 1) {
        return sourceBytes;
      }

      final subjectWidth = maxX - minX + 1;
      final subjectHeight = maxY - minY + 1;
      final subjectExtent = math.max(subjectWidth, subjectHeight).toDouble();
      final canvasSide = math.max(image.width, image.height);
      final usableExtent = canvasSide * (1 - (paddingFraction * 2));
      final scale = usableExtent / subjectExtent;
      final renderedWidth = subjectWidth * scale;
      final renderedHeight = subjectHeight * scale;
      final destination = ui.Rect.fromLTWH(
        (canvasSide - renderedWidth) / 2,
        (canvasSide - renderedHeight) / 2,
        renderedWidth,
        renderedHeight,
      );
      final source = ui.Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        (maxX + 1).toDouble(),
        (maxY + 1).toDouble(),
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        source,
        destination,
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final normalized = await picture.toImage(canvasSide, canvasSide);
        try {
          final png = await normalized.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null) return sourceBytes;
          return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
        } finally {
          normalized.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      image.dispose();
    }
  } catch (_) {
    throw const ProductBackgroundRemovalException(
      'The processed product photo could not be read.',
    );
  } finally {
    codec.dispose();
  }
}

final class ProductBackgroundRemovalException implements Exception {
  const ProductBackgroundRemovalException(this.message);

  final String message;

  @override
  String toString() => message;
}

final productBackgroundRemoverProvider = Provider<ProductBackgroundRemover>((
  ref,
) {
  final remover = OnDeviceProductBackgroundRemover();
  ref.onDispose(() => unawaited(remover.dispose()));
  return remover;
});

final localProductImageStoreProvider = Provider<LocalProductImageStore>((ref) {
  return LocalProductImageStore();
});
