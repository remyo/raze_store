import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/cart/presentation/cart_shortcut_button.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';
import 'package:raze_store/features/catalog/presentation/product_quick_view.dart';

enum _ProductBrowseLayout { grid, list }

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  static const _searchDebounceDuration = Duration(milliseconds: 250);
  static const _pageSize = 30;

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  Timer? _searchDebounce;
  String? _selectedCategory;
  int _visibleProductLimit = _pageSize;
  _ProductBrowseLayout _layout = _ProductBrowseLayout.grid;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(catalogSearchQueryProvider),
    );
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (_selectedCategory != null) {
      setState(() {
        _selectedCategory = null;
        _visibleProductLimit = _pageSize;
      });
    }
    _searchDebounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      setState(() => _visibleProductLimit = _pageSize);
      ref.read(catalogSearchQueryProvider.notifier).update(value);
    });
  }

  void _selectCategory(String? category) {
    setState(() {
      _selectedCategory = category;
      _visibleProductLimit = _pageSize;
    });
  }

  void _showNextPage() {
    if (!mounted) return;
    setState(() => _visibleProductLimit += _pageSize);
  }

  void _changeLayout(_ProductBrowseLayout layout) {
    if (_layout == layout) return;
    setState(() {
      _layout = layout;
      _visibleProductLimit = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(catalogProductsProvider);
    final query = ref.watch(catalogSearchQueryProvider).trim();

    return AppPageScaffold(
      title: 'Home',
      actions: [
        IconButton(
          onPressed: () => context.push('/products/quick-add'),
          tooltip: 'Add product',
          icon: const Icon(Icons.add_rounded),
        ),
        const CartShortcutButton(),
      ],
      padBody: false,
      body: products.when(
        // A search query rebuilds the stream provider. Keep the current
        // catalog on screen while the filtered stream starts so the search
        // field is not removed from the tree (which would dismiss its
        // keyboard after every character).
        skipLoadingOnReload: true,
        loading: () => const AppLoadingState(),
        error: (error, _) => AppErrorState(
          message: 'Your saved products could not be loaded.',
          onRetry: () => ref.invalidate(catalogProductsProvider),
        ),
        data: (items) => _ProductsBody(
          products: items,
          query: query,
          selectedCategory: _selectedCategory,
          searchController: _searchController,
          searchFocusNode: _searchFocusNode,
          isSearching: products.isLoading,
          visibleProductLimit: _visibleProductLimit,
          layout: _layout,
          onSearch: _onSearchChanged,
          onCategorySelected: _selectCategory,
          onLayoutChanged: _changeLayout,
          onLoadMore: _showNextPage,
          onOpen: (product) async {
            final added = await showProductQuickView(context, product: product);
            if (added == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${product.name} added to cart.')),
              );
            }
          },
          onAddFirst: () => context.push('/products/quick-add'),
          onScan: () => context.go('/scan'),
        ),
      ),
    );
  }
}

class _ProductsBody extends StatelessWidget {
  const _ProductsBody({
    required this.products,
    required this.query,
    required this.selectedCategory,
    required this.searchController,
    required this.searchFocusNode,
    required this.isSearching,
    required this.visibleProductLimit,
    required this.layout,
    required this.onSearch,
    required this.onCategorySelected,
    required this.onLayoutChanged,
    required this.onLoadMore,
    required this.onOpen,
    required this.onAddFirst,
    required this.onScan,
  });

  final List<StoreProduct> products;
  final String query;
  final String? selectedCategory;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearching;
  final int visibleProductLimit;
  final _ProductBrowseLayout layout;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<_ProductBrowseLayout> onLayoutChanged;
  final VoidCallback onLoadMore;
  final ValueChanged<StoreProduct> onOpen;
  final VoidCallback onAddFirst;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final categories = distinctCatalogCategories(
      products.map((product) => product.category),
    );
    final selectedKey = selectedCategory?.trim().toLowerCase();
    final activeCategory = selectedKey == null
        ? null
        : categories.cast<String?>().firstWhere(
            (category) => category?.toLowerCase() == selectedKey,
            orElse: () => null,
          );
    final visible = activeCategory == null
        ? products
        : products
              .where(
                (product) =>
                    product.category?.trim().toLowerCase() == selectedKey,
              )
              .toList(growable: false);
    final shownProducts = visible
        .take(visibleProductLimit)
        .toList(growable: false);
    final hasMore = shownProducts.length < visible.length;

    return CustomScrollView(
      key: ValueKey('products-${layout.name}'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverPadding(
            padding: EdgeInsets.fromLTRB(
              _contentInset(constraints.crossAxisExtent),
              AppSpacing.md,
              _contentInset(constraints.crossAxisExtent),
              AppSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: _ProductsHeader(
                categories: categories,
                selectedCategory: activeCategory,
                query: query,
                productCount: visible.length,
                searchController: searchController,
                searchFocusNode: searchFocusNode,
                isSearching: isSearching,
                layout: layout,
                onSearch: onSearch,
                onCategorySelected: onCategorySelected,
                onLayoutChanged: onLayoutChanged,
                onScan: onScan,
              ),
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverLayoutBuilder(
            builder: (context, constraints) => SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: _contentInset(constraints.crossAxisExtent),
              ),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 320,
                  child: AppEmptyState(
                    icon: products.isEmpty && query.isEmpty
                        ? Icons.shelves
                        : Icons.search_off_rounded,
                    title: products.isEmpty && query.isEmpty
                        ? 'Your store list is empty'
                        : 'No matching products',
                    message: products.isEmpty && query.isEmpty
                        ? 'Add the products your family sells. They stay available even when the phone is offline.'
                        : activeCategory != null
                        ? 'There are no products left in this category.'
                        : 'Try a different name, brand, barcode, or category.',
                    actionLabel: products.isEmpty && query.isEmpty
                        ? 'Add first product'
                        : null,
                    onAction: products.isEmpty && query.isEmpty
                        ? onAddFirst
                        : null,
                  ),
                ),
              ),
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final inset = _contentInset(constraints.crossAxisExtent);
              final contentWidth = constraints.crossAxisExtent - (inset * 2);
              final geometry = _productGridGeometry(context, contentWidth);
              return SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                sliver: switch (layout) {
                  _ProductBrowseLayout.grid => SliverGrid.builder(
                    key: const ValueKey('product-results-grid'),
                    itemCount: shownProducts.length + (hasMore ? 1 : 0),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: geometry.columnCount,
                      mainAxisSpacing: geometry.spacing,
                      crossAxisSpacing: geometry.spacing,
                      mainAxisExtent: geometry.mainAxisExtent,
                    ),
                    itemBuilder: (context, index) {
                      if (index == shownProducts.length) {
                        return _NextPageLoader(
                          key: ValueKey('product-page-${shownProducts.length}'),
                          onVisible: onLoadMore,
                        );
                      }
                      final product = shownProducts[index];
                      return _ProductGridCard(
                        key: ValueKey('product-grid-item-${product.id}'),
                        product: product,
                        imageExtent: geometry.imageExtent,
                        onTap: () => onOpen(product),
                      );
                    },
                  ),
                  _ProductBrowseLayout.list => SliverList.builder(
                    key: const ValueKey('product-results-list'),
                    itemCount: shownProducts.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == shownProducts.length) {
                        return _NextPageLoader(
                          key: ValueKey('product-page-${shownProducts.length}'),
                          onVisible: onLoadMore,
                        );
                      }
                      final product = shownProducts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _ProductCard(
                          key: ValueKey('product-list-item-${product.id}'),
                          product: product,
                          onTap: () => onOpen(product),
                        ),
                      );
                    },
                  ),
                },
              );
            },
          ),
        const SliverToBoxAdapter(
          child: SizedBox(height: AppSpacing.xxxl + AppSpacing.xl),
        ),
      ],
    );
  }

  static double _contentInset(double viewportWidth) => math.max(
    AppSpacing.md,
    (viewportWidth - AppBreakpoints.contentMaxWidth) / 2,
  );
}

class _ProductsHeader extends StatelessWidget {
  const _ProductsHeader({
    required this.categories,
    required this.selectedCategory,
    required this.query,
    required this.productCount,
    required this.searchController,
    required this.searchFocusNode,
    required this.isSearching,
    required this.layout,
    required this.onSearch,
    required this.onCategorySelected,
    required this.onLayoutChanged,
    required this.onScan,
  });

  final List<String> categories;
  final String? selectedCategory;
  final String query;
  final int productCount;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearching;
  final _ProductBrowseLayout layout;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<_ProductBrowseLayout> onLayoutChanged;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScanCallout(onScan: onScan),
        const SizedBox(height: AppSpacing.md),
        AppSearchField(
          controller: searchController,
          focusNode: searchFocusNode,
          hintText: 'Search products or barcode',
          onChanged: onSearch,
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 2,
          child: isSearching
              ? const LinearProgressIndicator(
                  key: ValueKey('product-search-progress'),
                  minHeight: 2,
                )
              : null,
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _ProductCategoryBrowser(
            categories: categories,
            selectedCategory: selectedCategory,
            onSelected: onCategorySelected,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppSectionHeader(
          title: query.isEmpty ? 'Store products' : 'Search results',
          subtitle:
              '$productCount ${productCount == 1 ? 'product' : 'products'}',
          action: _ProductLayoutToggle(
            value: layout,
            onChanged: onLayoutChanged,
          ),
        ),
      ],
    );
  }
}

/// A single horizontal viewport with two compact category rows.
///
/// Both rows live inside the same scroller, so dragging either row moves the
/// entire browser. Each chip keeps its natural width until a long label reaches
/// the width cap, where its fitted label scales down instead of overflowing.
class _ProductCategoryBrowser extends StatelessWidget {
  const _ProductCategoryBrowser({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final choices = <String?>[null, ...categories];
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledLabelHeight =
        textScaler.scale(AppButtonStyles.compactFontSize) *
        AppButtonStyles.compactLineHeight;
    const categoryGap = AppSpacing.xs;
    final rowHeight = math.max(
      AppSize.compactChip,
      scaledLabelHeight + (AppSpacing.xxs * 2),
    );
    final firstRow = <String?>[];
    final secondRow = <String?>[];
    for (var index = 0; index < choices.length; index++) {
      (index.isEven ? firstRow : secondRow).add(choices[index]);
    }

    return Semantics(
      container: true,
      label: 'Product categories',
      child: SizedBox(
        key: const ValueKey('product-category-browser'),
        height: rowHeight * 2 + categoryGap,
        child: SingleChildScrollView(
          key: const ValueKey('product-category-scroll'),
          scrollDirection: Axis.horizontal,
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductCategoryRow(
                key: const ValueKey('product-category-row-first'),
                categories: firstRow,
                selectedCategory: selectedCategory,
                height: rowHeight,
                onSelected: onSelected,
              ),
              const SizedBox(height: categoryGap),
              _ProductCategoryRow(
                key: const ValueKey('product-category-row-second'),
                categories: secondRow,
                selectedCategory: selectedCategory,
                height: rowHeight,
                onSelected: onSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCategoryRow extends StatelessWidget {
  const _ProductCategoryRow({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.height,
    required this.onSelected,
  });

  static const _maximumChipWidth = 152.0;

  final List<String?> categories;
  final String? selectedCategory;
  final double height;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < categories.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.xs),
          _buildChip(categories[index]),
        ],
      ],
    );
  }

  Widget _buildChip(String? category) {
    final label = category ?? 'All';
    return SizedBox(
      height: height,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maximumChipWidth),
        child: ChoiceChip(
          key: ValueKey(
            category == null
                ? 'product-category-all'
                : 'product-category-$category',
          ),
          padding: EdgeInsets.zero,
          labelPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          label: FittedBox(
            key: ValueKey('product-category-label-$label'),
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(label, maxLines: 1, softWrap: false),
            ),
          ),
          tooltip: label,
          selected: selectedCategory == category,
          onSelected: (_) => onSelected(category),
        ),
      ),
    );
  }
}

class _ProductLayoutToggle extends StatelessWidget {
  const _ProductLayoutToggle({required this.value, required this.onChanged});

  final _ProductBrowseLayout value;
  final ValueChanged<_ProductBrowseLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Product layout',
      child: SegmentedButton<_ProductBrowseLayout>(
        showSelectedIcon: false,
        selected: {value},
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          minimumSize: const WidgetStatePropertyAll(
            Size.square(AppSize.compactControl),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : scheme.surfaceContainerLow,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        segments: const [
          ButtonSegment(
            value: _ProductBrowseLayout.grid,
            icon: SizedBox.square(
              key: ValueKey('product-layout-grid'),
              dimension: AppSize.compactControl,
              child: Icon(Icons.grid_view_rounded, size: AppSize.icon),
            ),
            tooltip: 'Show products as a grid',
          ),
          ButtonSegment(
            value: _ProductBrowseLayout.list,
            icon: SizedBox.square(
              key: ValueKey('product-layout-list'),
              dimension: AppSize.compactControl,
              child: Icon(Icons.view_list_rounded, size: AppSize.icon),
            ),
            tooltip: 'Show products as a list',
          ),
        ],
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.first);
        },
      ),
    );
  }
}

({int columnCount, double spacing, double imageExtent, double mainAxisExtent})
_productGridGeometry(BuildContext context, double width) {
  final columnCount = switch (width) {
    < 188 => 1,
    < 520 => 2,
    < 760 => 3,
    < 1000 => 4,
    _ => 5,
  };
  final spacing = width < AppBreakpoints.compact
      ? AppSpacing.xs
      : AppSpacing.sm;
  final itemWidth = (width - (spacing * (columnCount - 1))) / columnCount;
  final imageExtent = (itemWidth - (AppSpacing.xs * 2))
      .clamp(80.0, 144.0)
      .toDouble();
  final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
  final compactCard = itemWidth < 150;
  final detailsExtent = compactCard ? 116.0 : 108.0;
  final scaledTextAllowance = (textScale - 1) * (compactCard ? 78.0 : 64.0);
  return (
    columnCount: columnCount,
    spacing: spacing,
    imageExtent: imageExtent,
    mainAxisExtent: imageExtent + detailsExtent + scaledTextAllowance,
  );
}

class _NextPageLoader extends StatefulWidget {
  const _NextPageLoader({super.key, required this.onVisible});

  final VoidCallback onVisible;

  @override
  State<_NextPageLoader> createState() => _NextPageLoaderState();
}

class _NextPageLoaderState extends State<_NextPageLoader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('product-page-loader'),
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: AppSpacing.xs),
            Text('Loading more products…'),
          ],
        ),
      ),
    );
  }
}

class _ScanCallout extends StatelessWidget {
  const _ScanCallout({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: AppRadius.control,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.barcode_reader,
                color: scheme.onPrimary,
                size: 28,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need the price?',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Scan the product barcode.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onScan,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('Scan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductGridCard extends StatelessWidget {
  const _ProductGridCard({
    super.key,
    required this.product,
    required this.imageExtent,
    required this.onTap,
  });

  final StoreProduct product;
  final double imageExtent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      product.brand,
      product.unitLabel,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ProductImage(
                  product: product,
                  width: double.infinity,
                  height: imageExtent,
                  fit: BoxFit.cover,
                  borderRadius: AppRadius.control,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (detail.isNotEmpty)
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              PriceText(
                centavos: product.priceCentavos,
                size: PriceTextSize.small,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (product.sellingUnits.isNotEmpty)
                Text(
                  '+${product.sellingUnits.length} other ${product.sellingUnits.length == 1 ? 'unit' : 'units'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({super.key, required this.product, required this.onTap});

  final StoreProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      product.brand,
      product.unitLabel,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ProductImage(
                product: product,
                width: AppSize.largeThumbnail,
                height: AppSize.largeThumbnail,
                borderRadius: AppRadius.control,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    PriceText(
                      centavos: product.priceCentavos,
                      size: PriceTextSize.regular,
                    ),
                    if (product.sellingUnits.isNotEmpty)
                      Text(
                        '+${product.sellingUnits.length} other ${product.sellingUnits.length == 1 ? 'unit price' : 'unit prices'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
