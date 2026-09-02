import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';
import 'package:raze_store/features/catalog/presentation/product_quick_view.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  late final TextEditingController _searchController;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(catalogSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(catalogProductsProvider);
    final query = ref.watch(catalogSearchQueryProvider).trim();

    return AppPageScaffold(
      title: 'Products',
      actions: [
        IconButton(
          onPressed: () => context.push('/products/new'),
          tooltip: 'Add product',
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton(
          onPressed: () => context.push('/settings'),
          tooltip: 'Store settings',
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      padBody: false,
      body: products.when(
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
          onSearch: ref.read(catalogSearchQueryProvider.notifier).update,
          onCategorySelected: (category) {
            setState(() => _selectedCategory = category);
          },
          onOpen: (product) async {
            final added = await showProductQuickView(context, product: product);
            if (added == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${product.name} added to cart.')),
              );
            }
          },
          onAddFirst: () => context.push('/products/new'),
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
    required this.onSearch,
    required this.onCategorySelected,
    required this.onOpen,
    required this.onAddFirst,
    required this.onScan,
  });

  final List<StoreProduct> products;
  final String query;
  final String? selectedCategory;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<StoreProduct> onOpen;
  final VoidCallback onAddFirst;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final categories =
        products
            .map((product) => product.category?.trim())
            .whereType<String>()
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final visible = selectedCategory == null
        ? products
        : products
              .where((product) => product.category == selectedCategory)
              .toList(growable: false);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScanCallout(onScan: onScan),
                const SizedBox(height: AppSpacing.md),
                AppSearchField(
                  controller: searchController,
                  hintText: 'Search products or barcode',
                  onChanged: onSearch,
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: selectedCategory == null,
                          onSelected: (_) => onCategorySelected(null),
                        ),
                        for (final category in categories) ...[
                          const SizedBox(width: AppSpacing.xs),
                          ChoiceChip(
                            label: Text(category),
                            selected: selectedCategory == category,
                            onSelected: (_) => onCategorySelected(category),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                AppSectionHeader(
                  title: query.isEmpty ? 'Store products' : 'Search results',
                  subtitle:
                      '${visible.length} ${visible.length == 1 ? 'product' : 'products'}',
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: query.isEmpty ? Icons.shelves : Icons.search_off_rounded,
              title: query.isEmpty
                  ? 'Your store list is empty'
                  : 'No matching products',
              message: query.isEmpty
                  ? 'Add the products your family sells. They stay available even when the phone is offline.'
                  : 'Try a different name, brand, barcode, or category.',
              actionLabel: query.isEmpty ? 'Add first product' : null,
              onAction: query.isEmpty ? onAddFirst : null,
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xxxl + AppSpacing.xl,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final columns = switch (width) {
                  < 520 => 2,
                  < 820 => 3,
                  < 1120 => 4,
                  _ => 5,
                };
                return SliverGrid.builder(
                  itemCount: visible.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: width < 520 ? 0.67 : 0.72,
                  ),
                  itemBuilder: (context, index) => _ProductCard(
                    product: visible[index],
                    onTap: () => onOpen(visible[index]),
                  ),
                );
              },
            ),
          ),
      ],
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
  const _ProductCard({required this.product, required this.onTap});

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ProductImage(
                product: product,
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
