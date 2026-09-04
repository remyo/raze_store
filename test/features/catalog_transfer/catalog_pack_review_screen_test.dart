import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_pack_review.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_pack_review_screen.dart';

void main() {
  testWidgets(
    'starts with no products selected, debounces search, and applies exact choices',
    (tester) async {
      CatalogPackApplySelection? appliedSelection;
      var discardCalls = 0;
      final review = _review(
        products: [
          _product(
            id: 'new-mango',
            name: 'Mango Juice',
            brand: 'Sample Brand',
            category: 'Drinks',
          ),
          _product(
            id: 'new-crackers',
            name: 'Salty Crackers',
            brand: 'Another Brand',
            category: 'Biscuits',
          ),
          _product(
            id: 'existing-coffee',
            name: 'Coffee Twin Pack',
            existing: _details(
              name: 'Coffee Sachet',
              brand: 'Local Brand',
              category: 'Coffee',
              priceCentavos: 800,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        _ReviewHarness(
          review: review,
          onApply: (selection) async {
            appliedSelection = selection;
            return const CatalogTransferSuccess(
              action: CatalogTransferAction.catalogPackImport,
              message: 'One product imported.',
              productCount: 1,
            );
          },
          onDiscard: () async => discardCalls++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-review')));
      await tester.pumpAndSettle();

      expect(find.text('New products'), findsOneWidget);
      expect(find.text('Existing products'), findsOneWidget);
      expect(
        find.textContaining('Author and details unverified'),
        findsOneWidget,
      );
      expect(
        find.text('0 of 2 new products selected. Showing 2 of 2.'),
        findsOneWidget,
      );
      expect(
        find
            .byKey(const ValueKey('catalog-review-product-new-mango'))
            .hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Drinks'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('catalog-review-product-compare-new-mango')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Drinks'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(
                const ValueKey('catalog-review-product-check-new-mango'),
              ),
            )
            .value,
        isFalse,
      );
      await tester.tap(
        find.byKey(const ValueKey('catalog-review-product-compare-new-mango')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('catalog-review-apply')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const ValueKey('catalog-review-new-search')),
        'mango',
      );
      await tester.pump(const Duration(milliseconds: 249));
      expect(
        find.text('0 of 2 new products selected. Showing 2 of 2.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.text('0 of 2 new products selected. Showing 1 of 1 matches.'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('catalog-review-new-select-shown')),
      );
      await tester.pump();
      expect(
        find.text('1 of 2 new products selected. Showing 1 of 1 matches.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('catalog-review-apply')),
            )
            .onPressed,
        isNotNull,
      );

      tester.testTextInput.hide();
      final fields = find.byKey(const ValueKey('catalog-review-new-fields'));
      final brandField = find.byKey(
        const ValueKey('catalog-review-new-field-brand'),
      );
      expect(brandField, findsNothing);
      await tester.ensureVisible(fields);
      await tester.tap(fields);
      await tester.pumpAndSettle();
      expect(brandField, findsOneWidget);
      await tester.tap(brandField);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(brandField).value, isFalse);

      await tester.tap(find.byKey(const ValueKey('catalog-review-apply')));
      await tester.pumpAndSettle();
      expect(find.text('Apply selected products?'), findsOneWidget);
      expect(
        find.textContaining('This will add 1 product and update 0 products.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog-review-confirm-apply')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('catalog-review-confirm-apply')),
      );
      await tester.pumpAndSettle();

      expect(appliedSelection, isNotNull);
      expect(appliedSelection!.selectedProductIds, {'new-mango'});
      expect(
        appliedSelection!.fields.contains(CatalogPackImportField.brand),
        isFalse,
      );
      expect(
        appliedSelection!.fields.contains(CatalogPackImportField.barcode),
        isTrue,
      );
      expect(discardCalls, 0);
      expect(find.text('One product imported.'), findsOneWidget);
    },
  );

  testWidgets('shows current to incoming details and reports apply failures', (
    tester,
  ) async {
    var discardCalls = 0;
    final review = _review(
      products: [
        _product(
          id: 'existing-chips',
          name: 'Pack Chips',
          brand: 'Pack Brand',
          category: 'Snacks',
          priceCentavos: 1500,
          existing: _details(
            name: 'Old Chips',
            brand: 'Store Brand',
            category: 'Other',
            priceCentavos: 1200,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _ReviewHarness(
        review: review,
        onApply: (_) async => const CatalogTransferFailure(
          code: CatalogTransferFailureCode.validationFailed,
          message: 'The catalog changed. Review it again.',
        ),
        onDiscard: () async => discardCalls++,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Existing products'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('catalog-review-existing-search')),
      'store brand',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.text('0 of 1 existing products selected. Showing 1 of 1 matches.'),
      findsOneWidget,
    );
    tester.testTextInput.hide();

    final existingList = find.byKey(
      const ValueKey('catalog-review-existing-list'),
    );
    await tester.ensureVisible(existingList);
    await tester.pumpAndSettle();
    final comparison = find.byKey(
      const ValueKey('catalog-review-product-compare-existing-chips'),
    );
    expect(find.text('Old Chips'), findsOneWidget);
    expect(find.text('Pack Chips'), findsNothing);
    expect(find.text('4800000000000'), findsOneWidget);
    expect(find.text('₱12.00'), findsOneWidget);
    final image = find.byKey(
      const ValueKey('catalog-review-product-image-existing-chips'),
    );
    final checkbox = find.byKey(
      const ValueKey('catalog-review-product-check-existing-chips'),
    );
    expect(image, findsOneWidget);
    expect(checkbox, findsOneWidget);
    expect(tester.getCenter(image).dx, lessThan(tester.getCenter(checkbox).dx));
    final name = tester.widget<Text>(
      find.byKey(const ValueKey('catalog-review-product-name-existing-chips')),
    );
    expect(name.maxLines, 2);
    expect(name.overflow, TextOverflow.ellipsis);

    expect(comparison, findsOneWidget);
    await tester.tap(comparison);
    await tester.pumpAndSettle();
    expect(
      find.text('Current phone value → incoming pack value'),
      findsOneWidget,
    );
    expect(find.text('Current price is protected'), findsOneWidget);
    expect(find.textContaining('Old Chips', findRichText: true), findsWidgets);
    expect(find.textContaining('Pack Chips', findRichText: true), findsWidgets);

    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    expect(
      find.text('Current phone value → incoming pack value'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('catalog-review-apply')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('catalog-review-confirm-apply')),
    );
    await tester.pumpAndSettle();

    expect(find.text('The catalog changed. Review it again.'), findsOneWidget);
    expect(find.byType(CatalogPackReviewScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('catalog-review-close')));
    await tester.pumpAndSettle();
    expect(discardCalls, 1);
  });

  testWidgets('loads review products in 50-item pages', (tester) async {
    var discardCalls = 0;
    final review = _review(
      products: [
        for (var index = 0; index < 55; index++)
          _product(
            id: 'new-$index',
            name: 'Product $index',
            category: 'Snacks',
          ),
      ],
    );
    await tester.pumpWidget(
      _ReviewHarness(
        review: review,
        onApply: (_) async =>
            const CatalogTransferCancelled(message: 'Cancelled.'),
        onDiscard: () async => discardCalls++,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-review')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(
      find.byKey(const ValueKey('catalog-review-new-field-brand')),
      findsNothing,
    );
    final viewport = find.byKey(const ValueKey('catalog-review-new-viewport'));
    expect(viewport, findsOneWidget);
    expect(tester.getSize(viewport).height, inInclusiveRange(160, 360));
    final list = find.byKey(const ValueKey('catalog-review-new-list'));
    await tester.ensureVisible(list);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('catalog-review-new-loader')),
      list,
      const Offset(0, -500),
      maxIteration: 100,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('catalog-review-new-loader')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 181));
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('catalog-review-product-new-54')),
      list,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('catalog-review-product-new-54')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('catalog-review-close')));
    await tester.pumpAndSettle();
    expect(discardCalls, 1);
  });

  testWidgets('remains usable with large text on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var discardCalls = 0;
    await tester.pumpWidget(
      _ReviewHarness(
        review: _review(
          products: [_product(id: 'new-one', name: 'One product')],
        ),
        textScale: 2,
        onApply: (_) async =>
            const CatalogTransferCancelled(message: 'Cancelled.'),
        onDiscard: () async => discardCalls++,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-review')));
    await tester.pumpAndSettle();

    expect(find.text('New products'), findsOneWidget);
    expect(find.text('Existing products'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(discardCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

CatalogPackReview _review({required List<CatalogPackReviewProduct> products}) =>
    CatalogPackReview(
      reviewId: 'review-1',
      packId: 'starter-ph',
      revision: 3,
      createdAt: DateTime.utc(2026, 9, 4),
      products: products,
    );

CatalogPackReviewProduct _product({
  required String id,
  required String name,
  String? brand,
  String? category,
  int priceCentavos = 1000,
  CatalogPackProductDetails? existing,
}) => CatalogPackReviewProduct(
  targetId: id,
  catalogProductId: 'catalog-$id',
  incoming: _details(
    name: name,
    brand: brand,
    category: category,
    priceCentavos: priceCentavos,
  ),
  existing: existing,
  hasBundledImage: true,
);

CatalogPackProductDetails _details({
  required String name,
  String? brand,
  String? category,
  int priceCentavos = 1000,
}) => CatalogPackProductDetails(
  barcode: '4800000000000',
  name: name,
  brand: brand,
  unitLabel: 'piece',
  category: category,
  priceCentavos: priceCentavos,
  hasImage: true,
);

final class _ReviewHarness extends StatefulWidget {
  const _ReviewHarness({
    required this.review,
    required this.onApply,
    required this.onDiscard,
    this.textScale = 1,
  });

  final CatalogPackReview review;
  final Future<CatalogTransferResult> Function(CatalogPackApplySelection)
  onApply;
  final Future<void> Function() onDiscard;
  final double textScale;

  @override
  State<_ReviewHarness> createState() => _ReviewHarnessState();
}

final class _ReviewHarnessState extends State<_ReviewHarness> {
  CatalogTransferResult? _result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (pageContext) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  key: const ValueKey('open-review'),
                  onPressed: () => _openReview(pageContext),
                  child: const Text('Open review'),
                ),
                if (_result case final result?)
                  Text(result.message, key: const ValueKey('review-result')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openReview(BuildContext pageContext) async {
    final result = await Navigator.of(pageContext).push<CatalogTransferResult>(
      MaterialPageRoute<CatalogTransferResult>(
        builder: (context) => CatalogPackReviewScreen(
          review: widget.review,
          onApply: widget.onApply,
          onDiscard: widget.onDiscard,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _result = result);
  }
}
