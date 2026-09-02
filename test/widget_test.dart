import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/products_screen.dart';

void main() {
  testWidgets('opens the empty offline product catalog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProductsProvider.overrideWith(
            (ref) => Stream<List<StoreProduct>>.value(const []),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProductsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Products'), findsWidgets);
    expect(find.text('Your store list is empty'), findsOneWidget);
    expect(find.text('Add first product'), findsOneWidget);
  });
}
