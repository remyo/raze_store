import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/features/settings/data/app_storage_service.dart';
import 'package:raze_store/features/settings/domain/app_storage_usage.dart';

final appStorageServiceProvider = Provider<AppStorageService>((ref) {
  return AppStorageService();
});

final appStorageUsageProvider = FutureProvider.autoDispose<AppStorageUsage>((
  ref,
) {
  return ref.watch(appStorageServiceProvider).loadUsage();
});
