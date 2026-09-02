import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('search field reports and clears its query', (tester) async {
    var query = '';
    var cleared = false;

    await tester.pumpWidget(
      _app(
        AppSearchField(
          onChanged: (value) => query = value,
          onClear: () => cleared = true,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'sardines');
    await tester.pump();
    expect(query, 'sardines');
    expect(find.byTooltip('Clear search'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(query, isEmpty);
    expect(cleared, isTrue);
    expect(find.text('sardines'), findsNothing);
  });

  testWidgets('quantity stepper respects its bounds', (tester) async {
    var quantity = 1;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return QuantityStepper(
                value: quantity,
                maximum: 2,
                onChanged: (value) => setState(() => quantity = value),
              );
            },
          ),
        ),
      ),
    );

    final removeButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.remove_rounded),
    );
    expect(removeButton.onPressed, isNull);

    await tester.tap(find.byTooltip('Increase quantity'));
    await tester.pump();
    expect(quantity, 2);

    final addButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add_rounded),
    );
    expect(addButton.onPressed, isNull);
  });

  testWidgets('price uses peso formatting from integer centavos', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const PriceText(centavos: 123456)));

    expect(find.text('₱1,234.56'), findsOneWidget);
    expect(PriceText.format(50), '₱0.50');
  });

  testWidgets('empty and error states expose their actions', (tester) async {
    var actionCount = 0;

    await tester.pumpWidget(
      _app(
        AppEmptyState(
          title: 'No products yet',
          message: 'Add the first product to this store.',
          actionLabel: 'Add product',
          onAction: () => actionCount++,
        ),
      ),
    );
    await tester.tap(find.text('Add product'));
    expect(actionCount, 1);

    await tester.pumpWidget(_app(AppErrorState(onRetry: () => actionCount++)));
    await tester.tap(find.text('Try again'));
    expect(actionCount, 2);
  });

  testWidgets('page scaffold supplies a title and responsive content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const AppPageScaffold(
          title: 'Products',
          body: Text('Catalog content'),
        ),
      ),
    );

    expect(find.text('Products'), findsOneWidget);
    expect(find.byType(ResponsiveContent), findsOneWidget);
    expect(find.text('Catalog content'), findsOneWidget);
  });

  testWidgets('section headers adapt at 200 percent text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: AppSectionHeader(
            title: 'Popular products',
            subtitle: 'Items your family reaches for most often',
            action: TextButton(onPressed: () {}, child: const Text('See all')),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Popular products'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });
}
