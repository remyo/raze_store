import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/features/onboarding/data/local_onboarding_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('store setup starts incomplete', () async {
    const repository = LocalOnboardingRepository();

    expect(await repository.isStoreSetupComplete(), isFalse);
  });

  test('completed store setup stays completed', () async {
    const repository = LocalOnboardingRepository();

    await repository.markStoreSetupComplete();

    expect(await repository.isStoreSetupComplete(), isTrue);
  });
}
