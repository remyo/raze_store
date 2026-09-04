import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/catalog/application/bulk_product_deletion_providers.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/settings/application/app_storage_providers.dart';

class BulkProductDeletionScreen extends ConsumerStatefulWidget {
  const BulkProductDeletionScreen({super.key});

  @override
  ConsumerState<BulkProductDeletionScreen> createState() =>
      _BulkProductDeletionScreenState();
}

class _BulkProductDeletionScreenState
    extends ConsumerState<BulkProductDeletionScreen> {
  static const _searchDebounce = Duration(milliseconds: 250);
  static const _pageSize = 40;

  final _selectedIds = <String>{};
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _scrollController;
  Timer? _debounceTimer;
  String _query = '';
  int _visibleLimit = _pageSize;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController()..addListener(_loadNearBottom);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController
      ..removeListener(_loadNearBottom)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        _visibleLimit = _pageSize;
      });
    });
  }

  void _loadNearBottom() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 320) {
      return;
    }
    final products = ref.read(bulkDeletionProductsProvider(_query)).value;
    if (products == null || _visibleLimit >= products.length) return;
    setState(() => _visibleLimit += _pageSize);
  }

  void _toggleProduct(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleAllMatching(List<StoreProduct> products) {
    final matchingIds = products.map((product) => product.id).toSet();
    final allSelected =
        matchingIds.isNotEmpty && matchingIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(matchingIds);
      } else {
        _selectedIds.addAll(matchingIds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(bulkDeletionProductsProvider(_query));

    return AppPageScaffold(
      title: 'Delete multiple products',
      leading: BackButton(
        onPressed: () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            context.go('/settings');
          }
        },
      ),
      padBody: false,
      body: _buildBody(products),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: FilledButton.icon(
            key: const ValueKey('delete-selected-products'),
            onPressed: _selectedIds.isEmpty || _deleting
                ? null
                : _confirmAndDelete,
            icon: _deleting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded),
            label: Text(
              _deleting
                  ? 'Deleting…'
                  : 'Delete ${_selectedIds.length} selected',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<StoreProduct>> products) {
    final items = products.value ?? const <StoreProduct>[];
    final visibleCount = math.min(_visibleLimit, items.length);
    final hasMore = visibleCount < items.length;
    final allMatchingSelected =
        items.isNotEmpty &&
        items.every((product) => _selectedIds.contains(product.id));
    final someMatchingSelected = items.any(
      (product) => _selectedIds.contains(product.id),
    );

    return ListView.builder(
      key: const ValueKey('bulk-product-list'),
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount:
          1 +
          (products.hasError || (products.hasValue && items.isEmpty) ? 1 : 0) +
          visibleCount +
          (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _BulkDeletionHeader(
            queryController: _searchController,
            queryFocusNode: _searchFocusNode,
            isLoading: products.isLoading,
            matchingCount: items.length,
            selectedCount: _selectedIds.length,
            allMatchingSelected: allMatchingSelected,
            someMatchingSelected: someMatchingSelected,
            onSearch: _onSearchChanged,
            onToggleAll: items.isEmpty ? null : () => _toggleAllMatching(items),
            onClearSelection: _selectedIds.isEmpty
                ? null
                : () => setState(_selectedIds.clear),
          );
        }

        if (products.hasError) {
          return _BoundedItem(
            child: SizedBox(
              height: 280,
              child: AppErrorState(
                message: 'Products could not be loaded.',
                onRetry: () =>
                    ref.invalidate(bulkDeletionProductsProvider(_query)),
              ),
            ),
          );
        }

        if (products.hasValue && items.isEmpty) {
          return _BoundedItem(
            child: SizedBox(
              height: 280,
              child: AppEmptyState(
                icon: _query.isEmpty
                    ? Icons.inventory_2_outlined
                    : Icons.search_off_rounded,
                title: _query.isEmpty
                    ? 'No products to manage'
                    : 'No matching products',
                message: _query.isEmpty
                    ? 'Products you add or import will appear here.'
                    : 'Try a different name, brand, barcode, or category.',
              ),
            ),
          );
        }

        final productIndex = index - 1;
        if (productIndex < visibleCount) {
          final product = items[productIndex];
          return _BoundedItem(
            child: _SelectableProductRow(
              key: ValueKey('bulk-product-row-${product.id}'),
              product: product,
              selected: _selectedIds.contains(product.id),
              enabled: !_deleting,
              onChanged: (selected) => _toggleProduct(product.id, selected),
            ),
          );
        }

        return const _BoundedItem(child: _PageLoader());
      },
    );
  }

  Future<void> _confirmAndDelete() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete $count selected ${count == 1 ? 'product' : 'products'}?',
        ),
        content: const Text(
          'The selected products will disappear from search and scanning. '
          'Their unfinished cart items will also be removed. Completed sales '
          'and receipt details will stay unchanged. This also clears the '
          'available Undo last import checkpoint because it would no longer '
          'be safe to restore. Restore a backup if you need to recover '
          'products after deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-selected-products'),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete $count'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final selected = Set<String>.of(_selectedIds);
    setState(() => _deleting = true);
    try {
      final result = await ref
          .read(bulkProductDeletionServiceProvider)
          .deleteProducts(selected);
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _selectedIds.removeAll(selected);
      });
      ref
        ..invalidate(bulkDeletionProductsProvider)
        ..invalidate(catalogProductsProvider)
        ..invalidate(catalogStoredCategoriesProvider)
        ..invalidate(catalogProductProvider)
        ..invalidate(cartDraftProvider)
        ..invalidate(catalogPackUndoSummaryProvider)
        ..invalidate(appStorageUsageProvider);

      final productLabel = result.deletedProductCount == 1
          ? 'product'
          : 'products';
      final cartMessage = result.removedCartRowCount == 0
          ? ''
          : ' Removed ${result.removedCartRowCount} unfinished cart ${result.removedCartRowCount == 1 ? 'item' : 'items'}.';
      final imageWarning = result.imageCleanupFailureCount == 0
          ? ''
          : ' Some unused images could not be cleaned up.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Deleted ${result.deletedProductCount} $productLabel.'
              '$cartMessage$imageWarning',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No products were deleted. Please try again.'),
          ),
        );
    }
  }
}

class _BulkDeletionHeader extends StatelessWidget {
  const _BulkDeletionHeader({
    required this.queryController,
    required this.queryFocusNode,
    required this.isLoading,
    required this.matchingCount,
    required this.selectedCount,
    required this.allMatchingSelected,
    required this.someMatchingSelected,
    required this.onSearch,
    required this.onToggleAll,
    required this.onClearSelection,
  });

  final TextEditingController queryController;
  final FocusNode queryFocusNode;
  final bool isLoading;
  final int matchingCount;
  final int selectedCount;
  final bool allMatchingSelected;
  final bool someMatchingSelected;
  final ValueChanged<String> onSearch;
  final VoidCallback? onToggleAll;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _BoundedItem(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: scheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Review products before deleting them. Completed sales '
                      'and their receipt details are always protected.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppSearchField(
            controller: queryController,
            focusNode: queryFocusNode,
            hintText: 'Search name, barcode, brand, or category',
            semanticLabel: 'Search products to delete',
            onChanged: onSearch,
            enabled: true,
          ),
          SizedBox(
            height: 2,
            child: isLoading
                ? const LinearProgressIndicator(
                    key: ValueKey('bulk-product-search-progress'),
                    minHeight: 2,
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Checkbox(
                  key: const ValueKey('select-all-matching-products'),
                  tristate: true,
                  value: allMatchingSelected
                      ? true
                      : someMatchingSelected
                      ? null
                      : false,
                  onChanged: onToggleAll == null ? null : (_) => onToggleAll!(),
                ),
                Expanded(
                  child: InkWell(
                    onTap: onToggleAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'Select all $matchingCount matching ${matchingCount == 1 ? 'product' : 'products'}',
                        maxLines: 2,
                      ),
                    ),
                  ),
                ),
                if (selectedCount > 0)
                  TextButton(
                    key: const ValueKey('clear-product-selection'),
                    onPressed: onClearSelection,
                    child: Text('Clear ($selectedCount)'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _SelectableProductRow extends StatelessWidget {
  const _SelectableProductRow({
    super.key,
    required this.product,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final StoreProduct product;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final barcode = product.barcode?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.42) : null,
      child: InkWell(
        onTap: enabled ? () => onChanged(!selected) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSize.comfortableRow,
            ),
            child: Row(
              children: [
                ProductImage(
                  key: ValueKey('bulk-product-image-${product.id}'),
                  product: product,
                  width: AppSize.smallThumbnail,
                  height: AppSize.smallThumbnail,
                  borderRadius: AppRadius.control,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              barcode == null || barcode.isEmpty
                                  ? 'No barcode'
                                  : barcode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          PriceText(
                            centavos: product.priceCentavos,
                            size: PriceTextSize.small,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox.square(
                  dimension: AppSize.minimumTouchTarget,
                  child: Tooltip(
                    message: selected
                        ? 'Do not delete this product'
                        : 'Select product to delete',
                    child: Checkbox(
                      key: ValueKey('bulk-product-checkbox-${product.id}'),
                      value: selected,
                      visualDensity: VisualDensity.compact,
                      onChanged: enabled
                          ? (value) => onChanged(value ?? false)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoundedItem extends StatelessWidget {
  const _BoundedItem({required this.child});

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

class _PageLoader extends StatelessWidget {
  const _PageLoader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: ValueKey('bulk-product-page-loader'),
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
