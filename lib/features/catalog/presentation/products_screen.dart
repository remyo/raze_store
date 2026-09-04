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
          onSearch: _onSearchChanged,
          onCategorySelected: _selectCategory,
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
    required this.onSearch,
    required this.onCategorySelected,
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
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategorySelected;
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
    final resultItemCount = visible.isEmpty
        ? 1
        : shownProducts.length + (hasMore ? 1 : 0);

    return ListView.builder(
      key: const ValueKey('products-list'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxxl + AppSpacing.xl,
      ),
      itemCount: 1 + resultItemCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _BoundedListItem(
            child: Column(
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
                    selectedCategory: activeCategory,
                    onSelected: onCategorySelected,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppSectionHeader(
                  title: query.isEmpty ? 'Store products' : 'Search results',
                  subtitle:
                      '${visible.length} ${visible.length == 1 ? 'product' : 'products'}',
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          );
        }

        if (visible.isEmpty) {
          return _BoundedListItem(
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
                onAction: products.isEmpty && query.isEmpty ? onAddFirst : null,
              ),
            ),
          );
        }

        final productIndex = index - 1;
        if (productIndex < shownProducts.length) {
          final product = shownProducts[productIndex];
          return _BoundedListItem(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ProductCard(
                key: ValueKey('product-list-item-${product.id}'),
                product: product,
                onTap: () => onOpen(product),
              ),
            ),
          );
        }

        return _BoundedListItem(
          child: _NextPageLoader(
            key: ValueKey('product-page-${shownProducts.length}'),
            onVisible: onLoadMore,
          ),
        );
      },
    );
  }
}

/// A single horizontal viewport with two category rows.
///
/// The grid owns one scroll position, so dragging either row moves the entire
/// category browser instead of leaving the other row behind.
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
    final scaledLabelHeight = textScaler.scale(14);
    final textScale = scaledLabelHeight / 14;
    const categoryGap = AppSpacing.xs;
    // ChoiceChip labels stay on one line, but their row must follow the real
    // accessibility scale instead of clipping it at an arbitrary ceiling.
    final rowHeight = math.max(48.0, scaledLabelHeight + 30);
    final columnWidth = 152.0 + math.max(0.0, textScale - 1) * 32;

    return Semantics(
      container: true,
      label: 'Product categories',
      child: SizedBox(
        key: const ValueKey('product-category-browser'),
        height: rowHeight * 2 + categoryGap,
        child: GridView.builder(
          key: const ValueKey('product-category-grid'),
          scrollDirection: Axis.horizontal,
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: choices.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: columnWidth,
            mainAxisSpacing: categoryGap,
            crossAxisSpacing: categoryGap,
          ),
          itemBuilder: (context, index) {
            final category = choices[index];
            final label = category ?? 'All';
            return Align(
              alignment: Alignment.centerLeft,
              child: ChoiceChip(
                key: ValueKey(
                  category == null
                      ? 'product-category-all'
                      : 'product-category-$category',
                ),
                label: SizedBox(
                  width: columnWidth - 34,
                  child: FittedBox(
                    key: ValueKey('product-category-label-$label'),
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: Text(label, maxLines: 1, softWrap: false),
                    ),
                  ),
                ),
                tooltip: label,
                selected: selectedCategory == category,
                onSelected: (_) => onSelected(category),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BoundedListItem extends StatelessWidget {
  const _BoundedListItem({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppBreakpoints.contentMaxWidth,
        ),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
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
