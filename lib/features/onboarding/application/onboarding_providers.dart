import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_onboarding_repository.dart';
import '../domain/onboarding_repository.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return const LocalOnboardingRepository();
});

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);

final class OnboardingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(onboardingRepositoryProvider).isStoreSetupComplete();
  }

  Future<bool> completeStoreSetup() async {
    state = const AsyncLoading();
    try {
      await ref.read(onboardingRepositoryProvider).markStoreSetupComplete();
      state = const AsyncData(true);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}
