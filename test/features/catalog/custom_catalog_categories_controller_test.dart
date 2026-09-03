import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme_mode_controller.dart';
import 'package:raze_store/features/catalog/application/custom_catalog_categories_controller.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists normalized additions and case-insensitive deletion', () async {
    final writer = ProviderContainer();
    final reader = ProviderContainer();
    addTearDown(writer.dispose);
    addTearDown(reader.dispose);

    final controller = writer.read(customCatalogCategoriesProvider.notifier);
    await controller.addCategory('  Mobile   Load  ');
    await controller.addCategory('Frozen Treats');
    await controller.deleteCategory(' mobile LOAD ');

    expect(writer.read(customCatalogCategoriesProvider), ['Frozen Treats']);
    final preferences = await writer.read(sharedPreferencesProvider.future);
    expect(preferences.getStringList(customCatalogCategoriesPreferenceKey), [
      'Frozen Treats',
    ]);
    expect(await _waitForCategories(reader, length: 1), ['Frozen Treats']);
  });

  test(
    'rejects custom and starter duplicates without changing storage',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        customCatalogCategoriesProvider.notifier,
      );

      await controller.addCategory('Mobile Load');

      await expectLater(
        controller.addCategory('  mobile   LOAD '),
        throwsA(
          isA<CatalogCategoryException>().having(
            (error) => error.message,
            'message',
            'A category with this name already exists.',
          ),
        ),
      );
      await expectLater(
        controller.addCategory(' snacks '),
        throwsA(isA<CatalogCategoryException>()),
      );

      expect(container.read(customCatalogCategoriesProvider), ['Mobile Load']);
      final preferences = await container.read(
        sharedPreferencesProvider.future,
      );
      expect(preferences.getStringList(customCatalogCategoriesPreferenceKey), [
        'Mobile Load',
      ]);
    },
  );

  test(
    'accepts the maximum name length and rejects one character more',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        customCatalogCategoriesProvider.notifier,
      );
      final maximumLengthName = List.filled(
        maxCatalogCategoryNameLength,
        'A',
      ).join();

      await controller.addCategory(maximumLengthName);
      await expectLater(
        controller.addCategory('${maximumLengthName}A'),
        throwsA(
          isA<CatalogCategoryException>().having(
            (error) => error.message,
            'message',
            'The category name is too long.',
          ),
        ),
      );

      expect(container.read(customCatalogCategoriesProvider), [
        maximumLengthName,
      ]);
    },
  );

  test(
    'loads at most the configured count and rejects another category',
    () async {
      final stored = List.generate(
        maxCustomCatalogCategories,
        (index) => 'Custom Category $index',
      );
      SharedPreferences.setMockInitialValues({
        customCatalogCategoriesPreferenceKey: stored,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final categories = await _waitForCategories(
        container,
        length: maxCustomCatalogCategories,
      );
      expect(categories, hasLength(maxCustomCatalogCategories));

      await expectLater(
        container
            .read(customCatalogCategoriesProvider.notifier)
            .addCategory('Overflow Category'),
        throwsA(
          isA<CatalogCategoryException>().having(
            (error) => error.message,
            'message',
            'The custom category limit has been reached.',
          ),
        ),
      );
      expect(
        container.read(customCatalogCategoriesProvider),
        hasLength(maxCustomCatalogCategories),
      );
    },
  );
}

Future<List<String>> _waitForCategories(
  ProviderContainer container, {
  required int length,
}) async {
  final completer = Completer<List<String>>();
  final subscription = container.listen<List<String>>(
    customCatalogCategoriesProvider,
    (_, categories) {
      if (categories.length == length && !completer.isCompleted) {
        completer.complete(categories);
      }
    },
    fireImmediately: true,
  );
  try {
    return await completer.future.timeout(const Duration(seconds: 2));
  } finally {
    subscription.close();
  }
}
