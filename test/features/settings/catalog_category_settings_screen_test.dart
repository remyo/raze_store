import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/settings/presentation/catalog_category_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('adds a normalized custom category and persists it', (
    tester,
  ) async {
    await _pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('add-custom-category')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-category-name-field')),
      '  Mobile   Load  ',
    );
    await tester.tap(find.byKey(const ValueKey('save-custom-category')));
    await tester.pumpAndSettle();

    expect(find.text('Mobile Load'), findsOneWidget);
    expect(find.text('1 of $maxCustomCatalogCategories added'), findsOneWidget);
    expect(find.text('Mobile Load added.'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(customCatalogCategoriesPreferenceKey), [
      'Mobile Load',
    ]);
  });

  testWidgets('confirms and deletes an unused custom category', (tester) async {
    SharedPreferences.setMockInitialValues({
      customCatalogCategoriesPreferenceKey: ['Mobile Load'],
    });
    await _pumpScreen(tester);

    final deleteButton = find.byKey(
      const ValueKey('delete-category-Mobile Load'),
    );
    await tester.scrollUntilVisible(
      deleteButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete Mobile Load?'), findsOneWidget);
    expect(
      find.text(
        'This removes it from future category choices. Products are not deleted.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Mobile Load deleted.'), findsOneWidget);
    expect(
      find.text(
        'No custom categories yet. Add one for groups such as Mobile Load or Frozen Treats.',
      ),
      findsOneWidget,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getStringList(customCatalogCategoriesPreferenceKey),
      isEmpty,
    );
  });

  testWidgets('keeps an in-use category and explains how to delete it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      customCatalogCategoriesPreferenceKey: ['Mobile Load'],
    });
    await _pumpScreen(tester, storedCategories: const ['MOBILE LOAD']);

    expect(find.text('Used by a saved product'), findsOneWidget);
    final deleteButton = find.byKey(
      const ValueKey('delete-category-Mobile Load'),
    );
    await tester.scrollUntilVisible(
      deleteButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete Mobile Load?'), findsNothing);
    expect(
      find.text('Move saved products out of Mobile Load before deleting it.'),
      findsOneWidget,
    );
    expect(find.text('Mobile Load'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList(customCatalogCategoriesPreferenceKey), [
      'Mobile Load',
    ]);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  List<String> storedCategories = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogStoredCategoriesProvider.overrideWithValue(
          AsyncValue.data(storedCategories),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const CatalogCategorySettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
