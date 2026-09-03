abstract interface class OnboardingRepository {
  Future<bool> isStoreSetupComplete();

  Future<void> markStoreSetupComplete();
}
