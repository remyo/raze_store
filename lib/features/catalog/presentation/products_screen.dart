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

enum _ProductSortOrder {
  defaultOrder('Default order', 'default'),
  priceHighToLow('Price: highest first', 'price-high-low'),
  priceLowToHigh('Price: lowest first', 'price-low-high'),
  nameAToZ('Name: A–Z', 'name-a-z'),
  nameZToA('Name: Z–A', 'name-z-a'),
  newest('Newest added', 'newest');

  const _ProductSortOrder(this.label, this.keySuffix);

  final String label;
  final String keySuffix;
}

enum _ProductBrowseFilter {
  all('All products', 'all'),
  withPhoto('With photo', 'with-photo'),
  withoutPhoto('Without photo', 'without-photo'),
  withAdditionalUnits('With additional units', 'additional-units'),
  priced('With a price', 'priced'),
  missingPrice('Price missing', 'missing-price');

  const _ProductBrowseFilter(this.label, this.keySuffix);

  final String label;
  final String keySuffix;
}

enum _ProductBrowseMenuAction { reset }

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
  _ProductSortOrder _sortOrder = _ProductSortOrder.defaultOrder;
  _ProductBrowseFilter _productFilter = _ProductBrowseFilter.all;

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

  void _changeSortOrder(_ProductSortOrder sortOrder) {
    if (_sortOrder == sortOrder) return;
    setState(() {
      _sortOrder = sortOrder;
      _visibleProductLimit = _pageSize;
    });
  }

  void _changeProductFilter(_ProductBrowseFilter productFilter) {
    if (_productFilter == productFilter) return;
    setState(() {
      _productFilter = productFilter;
      _visibleProductLimit = _pageSize;
    });
  }

  void _resetBrowseOptions() {
    if (_sortOrder == _ProductSortOrder.defaultOrder &&
        _productFilter == _ProductBrowseFilter.all) {
      return;
    }
    setState(() {
      _sortOrder = _ProductSortOrder.defaultOrder;
      _productFilter = _ProductBrowseFilter.all;
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
          sortOrder: _sortOrder,
          productFilter: _productFilter,
          onSearch: _onSearchChanged,
          onCategorySelected: _selectCategory,
          onLayoutChanged: _changeLayout,
          onSortOrderChanged: _changeSortOrder,
          onProductFilterChanged: _changeProductFilter,
          onBrowseOptionsReset: _resetBrowseOptions,
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
          onQuickUnits: () => context.push('/quick-sell'),
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
    required this.sortOrder,
    required this.productFilter,
    required this.onSearch,
    required this.onCategorySelected,
    required this.onLayoutChanged,
    required this.onSortOrderChanged,
    required this.onProductFilterChanged,
    required this.onBrowseOptionsReset,
    required this.onLoadMore,
    required this.onOpen,
    required this.onAddFirst,
    required this.onScan,
    required this.onQuickUnits,
  });

  final List<StoreProduct> products;
  final String query;
  final String? selectedCategory;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearching;
  final int visibleProductLimit;
  final _ProductBrowseLayout layout;
  final _ProductSortOrder sortOrder;
  final _ProductBrowseFilter productFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<_ProductBrowseLayout> onLayoutChanged;
  final ValueChanged<_ProductSortOrder> onSortOrderChanged;
  final ValueChanged<_ProductBrowseFilter> onProductFilterChanged;
  final VoidCallback onBrowseOptionsReset;
  final VoidCallback onLoadMore;
  final ValueChanged<StoreProduct> onOpen;
  final VoidCallback onAddFirst;
  final VoidCallback onScan;
  final VoidCallback onQuickUnits;

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
    final categoryProducts = activeCategory == null
        ? products
        : products
              .where(
                (product) =>
                    product.category?.trim().toLowerCase() == selectedKey,
              )
              .toList(growable: false);
    final visible = categoryProducts
        .where((product) => _matchesProductFilter(product, productFilter))
        .toList(growable: true);
    _sortProducts(visible, sortOrder);
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
                sortOrder: sortOrder,
                productFilter: productFilter,
                onSearch: onSearch,
                onCategorySelected: onCategorySelected,
                onLayoutChanged: onLayoutChanged,
                onSortOrderChanged: onSortOrderChanged,
                onProductFilterChanged: onProductFilterChanged,
                onBrowseOptionsReset: onBrowseOptionsReset,
                onScan: onScan,
                onQuickUnits: onQuickUnits,
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
                        : productFilter != _ProductBrowseFilter.all
                        ? 'No products match the selected filter.'
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

bool _matchesProductFilter(StoreProduct product, _ProductBrowseFilter filter) =>
    switch (filter) {
      _ProductBrowseFilter.all => true,
      _ProductBrowseFilter.withPhoto => _hasProductPhoto(product),
      _ProductBrowseFilter.withoutPhoto => !_hasProductPhoto(product),
      _ProductBrowseFilter.withAdditionalUnits =>
        product.sellingUnits.isNotEmpty,
      _ProductBrowseFilter.priced => product.priceCentavos > 0,
      _ProductBrowseFilter.missingPrice => product.priceCentavos == 0,
    };

bool _hasProductPhoto(StoreProduct product) =>
    _hasText(product.localImagePath) ||
    _hasText(product.catalogImagePath) ||
    _hasText(product.remoteImageUrl);

bool _hasText(String? value) => value?.trim().isNotEmpty == true;

void _sortProducts(List<StoreProduct> products, _ProductSortOrder sortOrder) {
  if (sortOrder == _ProductSortOrder.defaultOrder) return;

  products.sort((left, right) {
    final primary = switch (sortOrder) {
      _ProductSortOrder.defaultOrder => 0,
      _ProductSortOrder.priceHighToLow => right.priceCentavos.compareTo(
        left.priceCentavos,
      ),
      _ProductSortOrder.priceLowToHigh => left.priceCentavos.compareTo(
        right.priceCentavos,
      ),
      _ProductSortOrder.nameAToZ => _compareProductNames(left, right),
      _ProductSortOrder.nameZToA => _compareProductNames(right, left),
      _ProductSortOrder.newest => right.createdAt.compareTo(left.createdAt),
    };
    if (primary != 0) return primary;

    final nameTieBreak = _compareProductNames(left, right);
    if (nameTieBreak != 0) return nameTieBreak;
    return left.id.compareTo(right.id);
  });
}

int _compareProductNames(StoreProduct left, StoreProduct right) {
  final normalized = left.name.toLowerCase().compareTo(
    right.name.toLowerCase(),
  );
  if (normalized != 0) return normalized;
  return left.name.compareTo(right.name);
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
    required this.sortOrder,
    required this.productFilter,
    required this.onSearch,
    required this.onCategorySelected,
    required this.onLayoutChanged,
    required this.onSortOrderChanged,
    required this.onProductFilterChanged,
    required this.onBrowseOptionsReset,
    required this.onScan,
    required this.onQuickUnits,
  });

  final List<String> categories;
  final String? selectedCategory;
  final String query;
  final int productCount;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool isSearching;
  final _ProductBrowseLayout layout;
  final _ProductSortOrder sortOrder;
  final _ProductBrowseFilter productFilter;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<_ProductBrowseLayout> onLayoutChanged;
  final ValueChanged<_ProductSortOrder> onSortOrderChanged;
  final ValueChanged<_ProductBrowseFilter> onProductFilterChanged;
  final VoidCallback onBrowseOptionsReset;
  final VoidCallback onScan;
  final VoidCallback onQuickUnits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ScanCallout(onScan: onScan),
        const SizedBox(height: AppSpacing.xs),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: [
                InkWell(
                  onTap: () => context.push('/gcash'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 20),
                        SizedBox(width: 8),
                        Expanded(child: Text('GCash Services')),
                        Flexible(
                          child: Text(
                            'History',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.push('/gcash/new?kind=cashIn'),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Cash In'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            context.push('/gcash/new?kind=cashOut'),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Cash Out'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        _QuickUnitsShortcut(onPressed: onQuickUnits),
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
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ProductSortFilterMenu(
                sortOrder: sortOrder,
                productFilter: productFilter,
                onSortOrderChanged: onSortOrderChanged,
                onProductFilterChanged: onProductFilterChanged,
                onReset: onBrowseOptionsReset,
              ),
              const SizedBox(width: AppSpacing.xs),
              _ProductLayoutToggle(value: layout, onChanged: onLayoutChanged),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickUnitsShortcut extends StatelessWidget {
  const _QuickUnitsShortcut({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: const ValueKey('home-quick-units'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.format_list_numbered_rounded, size: AppSize.icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick units',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Punch pieces, sticks, sachets, and packs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
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

class _ProductSortFilterMenu extends StatelessWidget {
  const _ProductSortFilterMenu({
    required this.sortOrder,
    required this.productFilter,
    required this.onSortOrderChanged,
    required this.onProductFilterChanged,
    required this.onReset,
  });

  final _ProductSortOrder sortOrder;
  final _ProductBrowseFilter productFilter;
  final ValueChanged<_ProductSortOrder> onSortOrderChanged;
  final ValueChanged<_ProductBrowseFilter> onProductFilterChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeCount =
        (sortOrder == _ProductSortOrder.defaultOrder ? 0 : 1) +
        (productFilter == _ProductBrowseFilter.all ? 0 : 1);
    final status = [
      if (sortOrder != _ProductSortOrder.defaultOrder) sortOrder.label,
      if (productFilter != _ProductBrowseFilter.all) productFilter.label,
    ].join(', ');

    return Semantics(
      label:
          'Sort and filter products${status.isEmpty ? '' : '. Active: $status'}',
      button: true,
      child: PopupMenuButton<Object>(
        key: const ValueKey('product-sort-filter-menu'),
        tooltip: 'Sort and filter products',
        constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          if (activeCount > 0) ...[
            const PopupMenuItem<Object>(
              key: ValueKey('product-filter-reset'),
              value: _ProductBrowseMenuAction.reset,
              height: AppSize.minimumTouchTarget,
              child: Row(
                children: [
                  Icon(Icons.restart_alt_rounded, size: AppSize.icon),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Reset sort & filters')),
                ],
              ),
            ),
            const PopupMenuDivider(),
          ],
          PopupMenuItem<Object>(
            enabled: false,
            height: AppSize.compactControl,
            child: Text(
              'Sort by',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final option in _ProductSortOrder.values)
            CheckedPopupMenuItem<Object>(
              key: ValueKey('product-sort-${option.keySuffix}'),
              value: option,
              checked: sortOrder == option,
              height: AppSize.compactControl,
              child: Text(option.label),
            ),
          const PopupMenuDivider(),
          PopupMenuItem<Object>(
            enabled: false,
            height: AppSize.compactControl,
            child: Text(
              'Show',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final option in _ProductBrowseFilter.values)
            CheckedPopupMenuItem<Object>(
              key: ValueKey('product-filter-${option.keySuffix}'),
              value: option,
              checked: productFilter == option,
              height: AppSize.compactControl,
              child: Text(option.label),
            ),
        ],
        onSelected: (selection) {
          switch (selection) {
            case final _ProductSortOrder sortOrder:
              onSortOrderChanged(sortOrder);
              break;
            case final _ProductBrowseFilter productFilter:
              onProductFilterChanged(productFilter);
              break;
            case _ProductBrowseMenuAction.reset:
              onReset();
              break;
            default:
              break;
          }
        },
        child: SizedBox(
          width: 92,
          height: AppSize.minimumTouchTarget,
          child: Center(
            child: Container(
              height: AppSize.compactControl,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                color: activeCount == 0
                    ? scheme.surfaceContainerLow
                    : scheme.secondaryContainer,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: AppRadius.control,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: AppSize.icon,
                    color: activeCount == 0
                        ? scheme.onSurfaceVariant
                        : scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Filter',
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: activeCount == 0
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  if (activeCount > 0) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    Container(
                      key: const ValueKey('product-filter-active-count'),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: scheme.secondary,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        child: Text(
                          '$activeCount',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
