import 'package:shared_preferences/shared_preferences.dart';

import '../domain/onboarding_repository.dart';

final class LocalOnboardingRepository implements OnboardingRepository {
  const LocalOnboardingRepository();

  static const storeSetupCompleteKey =
      'raze_store.onboarding.store_setup_complete';

  @override
  Future<bool> isStoreSetupComplete() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(storeSetupCompleteKey) ?? false;
  }

  @override
  Future<void> markStoreSetupComplete() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setBool(storeSetupCompleteKey, true);
    if (!saved) {
      throw StateError('Could not save the store setup status.');
    }
  }
}
