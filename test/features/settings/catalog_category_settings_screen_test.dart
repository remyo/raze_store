import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/catalog/domain/catalog_taxonomy.dart';
import 'package:raze_store/features/settings/presentation/catalog_category_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'shows all general categories collapsed and reveals their subcategories',
    (tester) async {
      await _pumpScreen(tester);

      expect(find.text('General categories'), findsOneWidget);
      expect(
        find.text(
          '${generalCatalogCategoryGroups.length} groups • '
          '${generalCatalogSubcategories.length} subcategories. '
          'Tap a group to browse.',
        ),
        findsOneWidget,
      );
      for (final group in generalCatalogCategoryGroups) {
        expect(
          find.byKey(ValueKey('general-category-${group.name}')),
          findsOneWidget,
        );
      }

      const foodGroup = 'Food & Beverages';
      const freshFood = 'Fresh Food';
      final foodTile = find.byKey(
        const ValueKey('general-category-Food & Beverages'),
      );
      final freshFoodChip = find.byKey(
        const ValueKey('general-subcategory-Food & Beverages-Fresh Food'),
      );
      expect(freshFoodChip, findsNothing);
      expect(tester.widget<ExpansionTile>(foodTile).initiallyExpanded, isFalse);

      await tester.tap(find.text(foodGroup));
      await tester.pumpAndSettle();

      expect(freshFoodChip, findsOneWidget);
      expect(find.text(freshFood), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'general-subcategory-Food & Beverages-Filipino Specialty Food',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(
            'general-subcategory-Grocery & Daily Essentials-Coffee & Tea',
          ),
        ),
        findsNothing,
      );

      await tester.tap(find.text(foodGroup));
      await tester.pumpAndSettle();
      expect(freshFoodChip, findsNothing);
    },
  );

  testWidgets(
    'general categories remain usable on a narrow large-text screen',
    (tester) async {
      await _pumpScreen(
        tester,
        size: const Size(320, 667),
        textScaler: const TextScaler.linear(3),
      );

      final group = find.byKey(
        const ValueKey('general-category-Food & Beverages'),
      );
      final groupTitle = find.text('Food & Beverages');
      await _scrollPageUntilVisible(tester, groupTitle);
      expect(group, findsOneWidget);
      await tester.tap(groupTitle);
      await tester.pumpAndSettle();

      final longSubcategory = find.byKey(
        const ValueKey(
          'general-subcategory-Food & Beverages-Snacks & Confectionery',
        ),
      );
      await _scrollPageUntilVisible(tester, longSubcategory);
      await tester.pumpAndSettle();

      final rect = tester.getRect(longSubcategory);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );

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
    await _scrollPageUntilVisible(tester, deleteButton);
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
    await _scrollPageUntilVisible(tester, deleteButton);
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
  Size size = const Size(800, 1000),
  TextScaler? textScaler,
}) async {
  tester.view.physicalSize = size;
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
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
        home: const CatalogCategorySettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollPageUntilVisible(WidgetTester tester, Finder target) async {
  final page = find.byKey(const ValueKey('category-settings-scroll'));
  final scrollable = find.descendant(
    of: page,
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  final viewportHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var attempt = 0; attempt < 4; attempt++) {
    final rect = tester.getRect(target);
    if (rect.top >= AppSize.appBar && rect.bottom <= viewportHeight) return;
    final nextOffset = (position.pixels + rect.top - AppSize.appBar)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    position.jumpTo(nextOffset);
    await tester.pump();
  }
  fail(
    'Could not bring ${target.describeMatch(Plurality.one)} into the category settings view.',
  );
}
