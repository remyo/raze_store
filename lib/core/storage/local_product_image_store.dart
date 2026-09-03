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
    return persistFile(File(source.path));
  }

  /// Copies a file into storage owned by Raze Store and returns its durable
  /// path. Backup restore uses this after validating an archive in staging.
  Future<String> persistFile(File source) async {
    final root = await _root();
    final extension = _safeExtension(source.path);
    final destination = p.join(root.path, '${_uuid.v4()}$extension');
    final partial = '$destination.part';

    try {
      await source.copy(partial);
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

  /// The directory containing app-managed product images.
  Future<Directory> managedDirectory() => _root();

  /// Returns an absolute managed path, or `null` when [filePath] points
  /// outside the app-owned product-image directory.
  Future<String?> resolveManagedPath(String? filePath) async {
    final trimmed = filePath?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final root = await _root();
    final normalizedRoot = p.normalize(root.absolute.path);
    final normalizedFile = p.normalize(File(trimmed).absolute.path);
    if (p.isWithin(normalizedRoot, normalizedFile)) return normalizedFile;

    // iOS can move an app's data into a container with a new UUID after an
    // update or restore. The stored absolute prefix then becomes stale even
    // though the managed image still exists. Only rebase the flat, generated
    // filename used by this store; never follow an arbitrary outside path.
    if (p.basename(p.dirname(normalizedFile)) != directoryName) return null;
    final fileName = p.basename(normalizedFile);
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\.(?:jpg|jpeg|png|heic|webp)$',
    ).hasMatch(fileName)) {
      return null;
    }
    final rebased = p.normalize(p.join(normalizedRoot, fileName));
    if (!p.isWithin(normalizedRoot, rebased)) return null;
    final stat = await File(rebased).stat();
    return stat.type == FileSystemEntityType.file ? rebased : null;
  }

  Future<void> deleteIfManaged(String? filePath) async {
    final trimmed = filePath?.trim();
    if (trimmed == null || trimmed.isEmpty) return;

    final normalizedFile = await resolveManagedPath(trimmed);
    if (normalizedFile == null) return;

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
