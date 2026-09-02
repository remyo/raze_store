import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:raze_store/core/storage/local_product_image_store.dart';

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

final localProductImageStoreProvider = Provider<LocalProductImageStore>((ref) {
  return LocalProductImageStore();
});
