import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/core/widgets/bounded_network_image.dart';
import 'package:raze_store/features/catalog/application/catalog_api_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/remote_catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_quick_view.dart';

class RemoteCatalogScreen extends ConsumerStatefulWidget {
  const RemoteCatalogScreen({super.key});

  @override
  ConsumerState<RemoteCatalogScreen> createState() =>
      _RemoteCatalogScreenState();
}

class _RemoteCatalogScreenState extends ConsumerState<RemoteCatalogScreen> {
  late final TextEditingController _searchController;
  Timer? _searchDebounce;
  List<RemoteCatalogProduct> _products = const [];
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNextPage = false;
  int _page = 1;
  int _requestGeneration = 0;
  String? _selectingProductId;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(remoteCatalogRepositoryProvider);
    return AppPageScaffold(
      title: 'Philippine catalog',
      leading: const BackButton(),
      padBody: false,
      body: !repository.isConfigured
          ? AppEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Shared catalog is not configured',
              message:
                  repository.configurationError ??
                  'Add the catalog API URL when building the app. Your saved store products still work offline.',
            )
          : Column(
              children: [
                Padding(
                  padding: AppSpacing.pageInsetsFor(
                    MediaQuery.sizeOf(context).width,
                  ).copyWith(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            'Choose shared product details, then set your store’s own selling price. API reference prices never replace your local price.',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppSearchField(
                        controller: _searchController,
                        hintText: 'Search name, brand, barcode, or category',
                        onChanged: _onSearchChanged,
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildResults()),
              ],
            ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const AppLoadingState(message: 'Loading shared products…');
    }
    if (_error != null && _products.isEmpty) {
      return AppErrorState(
        message:
            'The shared catalog could not be reached. Your saved products are still available offline.',
        onRetry: () => _load(reset: true),
      );
    }
    if (_products.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No shared products found',
        message: 'Try another product name, brand, barcode, or category.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        key: const ValueKey('remote-catalog-results'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: _products.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
        itemBuilder: (context, index) {
          if (index == _products.length) {
            if (!_hasNextPage && _error == null) {
              return const SizedBox(height: AppSpacing.md);
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: _error != null
                  ? OutlinedButton.icon(
                      onPressed: _loadingMore ? null : _loadNextPage,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry loading more'),
                    )
                  : OutlinedButton.icon(
                      key: const ValueKey('remote-catalog-load-more'),
                      onPressed: _loadingMore ? null : _loadNextPage,
                      icon: _loadingMore
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: Text(
                        _loadingMore ? 'Loading…' : 'Load more products',
                      ),
                    ),
            );
          }
          final product = _products[index];
          final selecting = _selectingProductId == product.catalogProductId;
          final selectionLocked = _selectingProductId != null;
          return Card(
            child: ListTile(
              key: ValueKey('remote-product-${product.catalogProductId}'),
              onTap: selectionLocked ? null : () => _chooseProduct(product),
              leading: _RemoteProductImage(url: product.remoteImageUrl),
              title: Text(product.name),
              subtitle: Text(
                [
                  product.brand,
                  product.unitLabel,
                  product.category,
                  product.barcode,
                  if (product.metadata.suggestedPriceCentavos case final price?)
                    'SRP/ref ${Money.fromCentavos(price).format()}',
                ].whereType<String>().join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: FilledButton.tonalIcon(
                key: ValueKey(
                  'remote-product-select-${product.catalogProductId}',
                ),
                onPressed: selectionLocked
                    ? null
                    : () => _chooseProduct(product),
                icon: selecting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
                label: Text(selecting ? 'Opening…' : 'Select'),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
  }

  Future<void> _loadNextPage() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    final repository = ref.read(remoteCatalogRepositoryProvider);
    if (!repository.isConfigured || (!reset && !_hasNextPage)) return;
    final generation = reset ? ++_requestGeneration : _requestGeneration;
    final requestedPage = reset ? 1 : _page + 1;
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = true;
          _products = const [];
        } else {
          _loadingMore = true;
        }
        _error = null;
      });
    }
    try {
      final result = await repository.searchProducts(
        query: _searchController.text,
        page: requestedPage,
      );
      if (!mounted || generation != _requestGeneration) return;
      final seen = <String>{};
      final combined = reset
          ? result.products
          : [..._products, ...result.products];
      setState(() {
        _products = [
          for (final product in combined)
            if (seen.add(product.catalogProductId)) product,
        ];
        _page = result.page;
        _hasNextPage = result.hasNextPage;
        _loading = false;
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _chooseProduct(RemoteCatalogProduct remoteProduct) async {
    if (_selectingProductId != null) return;
    setState(() => _selectingProductId = remoteProduct.catalogProductId);
    try {
      await _completeProductSelection(remoteProduct);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This product could not be opened. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _selectingProductId = null);
      }
    }
  }

  Future<void> _completeProductSelection(
    RemoteCatalogProduct remoteProduct,
  ) async {
    final localRepository = ref.read(catalogRepositoryProvider);
    var local = await localRepository.findByBarcode(remoteProduct.barcode);
    final source = remoteProduct.metadata.source;
    final sourceProductId = remoteProduct.metadata.sourceProductId;
    if (local == null && source != null && sourceProductId != null) {
      local = await localRepository.findBySource(source, sourceProductId);
    }
    if (!mounted) return;
    if (local != null) {
      await showProductQuickView(context, product: local);
      return;
    }

    final routeResult = await context.push<Object?>(
      '/products/quick-add',
      extra: remoteProduct.metadata,
    );
    final created = routeResult is StoreProduct ? routeResult : null;
    if (!mounted || created == null) return;
    final added = await showProductQuickView(context, product: created);
    if (added == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${created.name} added to cart.')));
    }
  }
}

class _RemoteProductImage extends StatelessWidget {
  const _RemoteProductImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.inventory_2_outlined),
    );
    final value = url;
    return ClipRRect(
      borderRadius: AppRadius.control,
      child: SizedBox.square(
        dimension: 52,
        child: value == null
            ? placeholder
            : BoundedNetworkImage(
                url: value,
                fallback: placeholder,
                fit: BoxFit.cover,
                cacheWidth: 192,
                cacheHeight: 192,
              ),
      ),
    );
  }
}
