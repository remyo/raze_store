import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Keeps product photos inside app-owned storage after the picker session ends.
class LocalProductImageStore {
  LocalProductImageStore({Uuid uuid = const Uuid(), Directory? root})
    : _uuid = uuid,
      _rootOverride = root;

  static const directoryName = 'product_images';

  final Uuid _uuid;
  final Directory? _rootOverride;
  Future<Directory>? _rootFuture;

  Future<String> persist({required XFile source}) async {
    final root = await _root();
    final extension = _safeExtension(source.path);
    final destination = p.join(root.path, '${_uuid.v4()}$extension');
    final partial = '$destination.part';

    try {
      await File(source.path).copy(partial);
      await File(partial).rename(destination);
      return destination;
    } catch (_) {
      final incomplete = File(partial);
      if (await incomplete.exists()) {
        await incomplete.delete();
      }
      rethrow;
    }
  }

  Future<void> deleteIfManaged(String? filePath) async {
    final trimmed = filePath?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    final root = await _root();
    final normalizedRoot = p.normalize(root.absolute.path);
    final normalizedFile = p.normalize(File(trimmed).absolute.path);
    if (!p.isWithin(normalizedRoot, normalizedFile)) return;

    final file = File(normalizedFile);
    if (await file.exists()) await file.delete();
  }

  Future<Directory> _root() {
    return _rootFuture ??= _loadRoot();
  }

  Future<Directory> _loadRoot() async {
    final base = _rootOverride ?? await getApplicationSupportDirectory();
    final directory = Directory(p.join(base.path, directoryName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static String _safeExtension(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    const supported = {'.jpg', '.jpeg', '.png', '.heic', '.webp'};
    return supported.contains(extension) ? extension : '.jpg';
  }
}
