import 'dart:async';
import 'dart:io';
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
    this.targetLongestSide = 1600,
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
      final outputBytes = await BackgroundRemover.instance.removeBgBytes(
        preparedBytes,
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
/// processing. Gallery/camera picks are already capped at 1600 px, while this
/// also protects restored or previously imported photos.
Future<Uint8List> prepareProductPhotoBytesForBackgroundRemoval(
  Uint8List sourceBytes, {
  int maximumSourcePixels = 40 * 1000 * 1000,
  int targetLongestSide = 1600,
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
