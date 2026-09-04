import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/product_image_placeholder.dart';
import 'package:raze_store/core/widgets/responsive_page.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_pack_review.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';

/// Lets an owner inspect a validated catalog pack before any local data is
/// changed.
///
/// Product rows start unchecked. Field choices are shared by both tabs so the
/// final [CatalogPackApplySelection] describes one deliberate, atomic import.
final class CatalogPackReviewScreen extends StatefulWidget {
  const CatalogPackReviewScreen({
    super.key,
    required this.review,
    required this.onApply,
    required this.onDiscard,
  });

  final CatalogPackReview review;
  final Future<CatalogTransferResult> Function(
    CatalogPackApplySelection selection,
  )
  onApply;
  final Future<void> Function() onDiscard;

  @override
  State<CatalogPackReviewScreen> createState() =>
      _CatalogPackReviewScreenState();
}

final class _CatalogPackReviewScreenState
    extends State<CatalogPackReviewScreen> {
  final Set<String> _selectedProductIds = <String>{};
  final Set<CatalogPackImportField> _selectedFields = CatalogPackImportField
      .values
      .toSet();

  bool _busy = false;
  bool _leaving = false;
  bool _allowPop = false;
  bool _successfullyApplied = false;
  bool _discardStarted = false;

  late final List<CatalogPackReviewProduct> _newProducts;
  late final List<CatalogPackReviewProduct> _existingProducts;
  late final Set<String> _newProductIds;
  late final Set<String> _existingProductIds;

  int get _selectedNewCount =>
      _selectedProductIds.where(_newProductIds.contains).length;

  int get _selectedExistingCount =>
      _selectedProductIds.where(_existingProductIds.contains).length;

  @override
  void initState() {
    super.initState();
    _newProducts = widget.review.newProducts;
    _existingProducts = widget.review.existingProducts;
    _newProductIds = _newProducts.map((product) => product.targetId).toSet();
    _existingProductIds = _existingProducts
        .map((product) => product.targetId)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _busy || _leaving;
    final selectedCount = _selectedProductIds.length;

    return DefaultTabController(
      length: 2,
      child: PopScope<CatalogTransferResult>(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !blocked) {
            unawaited(_discardAndLeave());
          }
        },
        child: AppPageScaffold(
          appBar: AppBar(
            title: const Text('Review catalog pack'),
            leading: IconButton(
              key: const ValueKey('catalog-review-close'),
              onPressed: blocked ? null : _discardAndLeave,
              tooltip: 'Cancel catalog import',
              icon: const Icon(Icons.close_rounded),
            ),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'New products'),
                Tab(text: 'Existing products'),
              ],
            ),
          ),
          padBody: false,
          body: TabBarView(
            children: [
              _ReviewProductTab(
                key: const PageStorageKey<String>('catalog-review-new-tab'),
                kind: _ReviewKind.newProducts,
                packId: widget.review.packId,
                revision: widget.review.revision,
                products: _newProducts,
                selectedCount: _selectedNewCount,
                selectedProductIds: _selectedProductIds,
                selectedFields: _selectedFields,
                blocked: blocked,
                onProductChanged: _setProductSelected,
                onProductsChanged: _setProductsSelected,
                onFieldChanged: _setFieldSelected,
              ),
              _ReviewProductTab(
                key: const PageStorageKey<String>(
                  'catalog-review-existing-tab',
                ),
                kind: _ReviewKind.existingProducts,
                packId: widget.review.packId,
                revision: widget.review.revision,
                products: _existingProducts,
                selectedCount: _selectedExistingCount,
                selectedProductIds: _selectedProductIds,
                selectedFields: _selectedFields,
                blocked: blocked,
                onProductChanged: _setProductSelected,
                onProductsChanged: _setProductsSelected,
                onFieldChanged: _setFieldSelected,
              ),
            ],
          ),
          bottomNavigationBar: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: FilledButton.icon(
                  key: const ValueKey('catalog-review-apply'),
                  onPressed: selectedCount == 0 || blocked
                      ? null
                      : _confirmAndApply,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.playlist_add_check_rounded),
                  label: Text(
                    _busy
                        ? 'Applying selected products…'
                        : 'Apply ${_productCountLabel(selectedCount)}',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setProductSelected(String productId, bool selected) {
    setState(() {
      if (selected) {
        _selectedProductIds.add(productId);
      } else {
        _selectedProductIds.remove(productId);
      }
    });
  }

  void _setProductsSelected(Iterable<String> productIds, bool selected) {
    setState(() {
      if (selected) {
        _selectedProductIds.addAll(productIds);
      } else {
        _selectedProductIds.removeAll(productIds);
      }
    });
  }

  void _setFieldSelected(CatalogPackImportField field, bool selected) {
    setState(() {
      if (selected) {
        _selectedFields.add(field);
      } else {
        _selectedFields.remove(field);
      }
    });
  }

  Future<void> _confirmAndApply() async {
    final selectedCount = _selectedProductIds.length;
    if (selectedCount == 0 || _busy || _leaving) return;

    final selectedNewCount = _selectedNewCount;
    final selectedExistingCount = _selectedExistingCount;
    final fields = CatalogPackImportField.values
        .where(_selectedFields.contains)
        .map((field) => field.label)
        .toList(growable: false);
    final fieldSummary = fields.isEmpty
        ? 'no optional details'
        : fields.join(', ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Apply selected products?'),
        content: Text(
          'This will add ${_productCountLabel(selectedNewCount)} and update '
          '${_productCountLabel(selectedExistingCount)}. The allowed details '
          'are: $fieldSummary. No unselected product will change. New products '
          'always keep their required product name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            key: const ValueKey('catalog-review-confirm-apply'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Apply ${_productCountLabel(selectedCount)}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    CatalogTransferResult result;
    try {
      result = await widget.onApply(
        CatalogPackApplySelection(
          selectedProductIds: _selectedProductIds,
          fields: _selectedFields,
        ),
      );
    } catch (error) {
      result = CatalogTransferFailure(
        code: CatalogTransferFailureCode.ioFailure,
        message: 'The selected products could not be applied.',
        cause: error,
      );
    }
    if (!mounted) return;

    if (result is CatalogTransferSuccess) {
      _successfullyApplied = true;
      setState(() {
        _busy = false;
        _allowPop = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(result);
      });
      return;
    }

    setState(() => _busy = false);
    final isFailure = result is CatalogTransferFailure;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: isFailure
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
  }

  Future<void> _discardAndLeave() async {
    if (_busy || _leaving || _successfullyApplied) return;
    setState(() => _leaving = true);
    await _discardOnce();
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _discardOnce() async {
    if (_discardStarted || _successfullyApplied) return;
    _discardStarted = true;
    try {
      await widget.onDiscard();
    } catch (_) {
      // The route must remain escapable even if best-effort staging cleanup
      // fails. The coordinator can remove abandoned temporary files later.
    }
  }
}

enum _ReviewKind { newProducts, existingProducts }

extension on _ReviewKind {
  String get noun => switch (this) {
    _ReviewKind.newProducts => 'new',
    _ReviewKind.existingProducts => 'existing',
  };

  String get emptyTitle => switch (this) {
    _ReviewKind.newProducts => 'No new products found',
    _ReviewKind.existingProducts => 'No existing matches found',
  };
}

final class _ReviewProductTab extends StatefulWidget {
  const _ReviewProductTab({
    super.key,
    required this.kind,
    required this.packId,
    required this.revision,
    required this.products,
    required this.selectedCount,
    required this.selectedProductIds,
    required this.selectedFields,
    required this.blocked,
    required this.onProductChanged,
    required this.onProductsChanged,
    required this.onFieldChanged,
  });

  final _ReviewKind kind;
  final String packId;
  final int revision;
  final List<CatalogPackReviewProduct> products;
  final int selectedCount;
  final Set<String> selectedProductIds;
  final Set<CatalogPackImportField> selectedFields;
  final bool blocked;
  final void Function(String productId, bool selected) onProductChanged;
  final void Function(Iterable<String> productIds, bool selected)
  onProductsChanged;
  final void Function(CatalogPackImportField field, bool selected)
  onFieldChanged;

  @override
  State<_ReviewProductTab> createState() => _ReviewProductTabState();
}

final class _ReviewProductTabState extends State<_ReviewProductTab>
    with AutomaticKeepAliveClientMixin {
  static const int _pageSize = 50;
  static const Duration _paginationDelay = Duration(milliseconds: 180);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  int _visibleCount = _pageSize;
  int _filterRevision = 0;
  bool _loadingMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filteredProducts = _filteredProducts;
    final shownCount = math.min(_visibleCount, filteredProducts.length);
    final shownProducts = filteredProducts
        .take(shownCount)
        .toList(growable: false);
    final hasMore = shownCount < filteredProducts.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final listHeight = _reviewProductListHeight(
          context: context,
          availableHeight: constraints.maxHeight,
          itemCount: shownProducts.length,
          hasLoader: hasMore,
        );
        return SingleChildScrollView(
          key: ValueKey<String>('catalog-review-${widget.kind.noun}-page'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReviewHeader(
                kind: widget.kind,
                packId: widget.packId,
                revision: widget.revision,
                searchController: _searchController,
                query: _query,
                totalCount: widget.products.length,
                selectedCount: widget.selectedCount,
                filteredCount: filteredProducts.length,
                shownProducts: shownProducts,
                selectedProductIds: widget.selectedProductIds,
                selectedFields: widget.selectedFields,
                blocked: widget.blocked,
                onSearchChanged: _scheduleSearch,
                onProductsChanged: widget.onProductsChanged,
                onFieldChanged: widget.onFieldChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (filteredProducts.isEmpty)
                _EmptyReviewResults(
                  title: widget.kind.emptyTitle,
                  hasQuery: _query.isNotEmpty,
                )
              else
                SizedBox(
                  key: ValueKey<String>(
                    'catalog-review-${widget.kind.noun}-viewport',
                  ),
                  height: listHeight,
                  child: Scrollbar(
                    controller: _scrollController,
                    interactive: true,
                    child: ListView.builder(
                      key: ValueKey<String>(
                        'catalog-review-${widget.kind.noun}-list',
                      ),
                      controller: _scrollController,
                      primary: false,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      cacheExtent: 360,
                      addAutomaticKeepAlives: false,
                      itemCount: shownProducts.length + (hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index < shownProducts.length) {
                          final product = shownProducts[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: _ReviewProductCard(
                              product: product,
                              selected: widget.selectedProductIds.contains(
                                product.targetId,
                              ),
                              selectedFields: widget.selectedFields,
                              blocked: widget.blocked,
                              onChanged: (selected) => widget.onProductChanged(
                                product.targetId,
                                selected,
                              ),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Semantics(
                            liveRegion: true,
                            label: 'Loading more ${widget.kind.noun} products',
                            child: Center(
                              child: SizedBox.square(
                                key: ValueKey<String>(
                                  'catalog-review-${widget.kind.noun}-loader',
                                ),
                                dimension: 24,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _reviewProductListHeight({
    required BuildContext context,
    required double availableHeight,
    required int itemCount,
    required bool hasLoader,
  }) {
    final media = MediaQuery.of(context);
    final usableScreenHeight =
        media.size.height - media.padding.vertical - media.viewInsets.bottom;
    final boundedAvailable = availableHeight.isFinite
        ? availableHeight
        : usableScreenHeight;
    final upperBound = math
        .min(720, math.min(usableScreenHeight * 0.6, boundedAvailable))
        .clamp(1.0, 720.0)
        .toDouble();
    final lowerBound = math.min(160, upperBound).toDouble();
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final estimatedRowHeight = 72 + ((textScale - 1) * 36);
    final estimatedHeight =
        (itemCount * (estimatedRowHeight + AppSpacing.xs)) +
        (hasLoader ? 64 : 0);
    return estimatedHeight.clamp(lowerBound, upperBound).toDouble();
  }

  Iterable<String?> _searchValues(CatalogPackProductDetails details) sync* {
    yield details.name;
    yield details.brand;
    yield details.barcode;
    yield details.category;
    yield details.unitLabel;
  }

  String _searchText(CatalogPackReviewProduct product) => [
    ..._searchValues(product.incoming),
    if (product.existing case final existing?) ..._searchValues(existing),
  ].whereType<String>().join('\n').toLowerCase();

  void _resetProductScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  List<CatalogPackReviewProduct> get _filteredProducts {
    if (_query.isEmpty) return widget.products;
    return widget.products
        .where((product) => _searchText(product).contains(_query))
        .toList(growable: false);
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim().toLowerCase();
        _visibleCount = _pageSize;
        _loadingMore = false;
        _filterRevision++;
      });
      _resetProductScroll();
    });
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 240) {
      return;
    }
    final filteredLength = _filteredProducts.length;
    if (_visibleCount >= filteredLength || _loadingMore) return;
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    final revision = _filterRevision;
    setState(() => _loadingMore = true);
    await Future<void>.delayed(_paginationDelay);
    if (!mounted || revision != _filterRevision) return;
    setState(() {
      _visibleCount += _pageSize;
      _loadingMore = false;
    });
  }
}

final class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.kind,
    required this.packId,
    required this.revision,
    required this.searchController,
    required this.query,
    required this.totalCount,
    required this.selectedCount,
    required this.filteredCount,
    required this.shownProducts,
    required this.selectedProductIds,
    required this.selectedFields,
    required this.blocked,
    required this.onSearchChanged,
    required this.onProductsChanged,
    required this.onFieldChanged,
  });

  final _ReviewKind kind;
  final String packId;
  final int revision;
  final TextEditingController searchController;
  final String query;
  final int totalCount;
  final int selectedCount;
  final int filteredCount;
  final List<CatalogPackReviewProduct> shownProducts;
  final Set<String> selectedProductIds;
  final Set<CatalogPackImportField> selectedFields;
  final bool blocked;
  final ValueChanged<String> onSearchChanged;
  final void Function(Iterable<String> productIds, bool selected)
  onProductsChanged;
  final void Function(CatalogPackImportField field, bool selected)
  onFieldChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shownIds = shownProducts
        .map((product) => product.targetId)
        .toList(growable: false);
    final selectedShownCount = shownIds
        .where(selectedProductIds.contains)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: AppRadius.control,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.policy_outlined,
                  size: 20,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Nothing imported yet · File checked · Author and details '
                    'unverified\n$packId · revision $revision',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: ValueKey<String>('catalog-review-${kind.noun}-search'),
            controller: searchController,
            enabled: !blocked,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search ${kind.noun} products',
              hintText: 'Name, barcode, brand, category, or unit',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: blocked
                          ? null
                          : () {
                              searchController.clear();
                              onSearchChanged('');
                            },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              '$selectedCount of $totalCount ${kind.noun} products selected. '
              'Showing ${shownProducts.length} of $filteredCount'
              '${query.isEmpty ? '' : ' matches'}.',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                key: ValueKey<String>(
                  'catalog-review-${kind.noun}-select-shown',
                ),
                onPressed:
                    blocked ||
                        shownIds.isEmpty ||
                        selectedShownCount == shownIds.length
                    ? null
                    : () => onProductsChanged(shownIds, true),
                icon: const Icon(Icons.select_all_rounded),
                label: const Text('Select shown'),
              ),
              TextButton.icon(
                key: ValueKey<String>(
                  'catalog-review-${kind.noun}-clear-shown',
                ),
                onPressed: blocked || selectedShownCount == 0
                    ? null
                    : () => onProductsChanged(shownIds, false),
                icon: const Icon(Icons.deselect_rounded),
                label: const Text('Clear shown'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _ImportFieldSelector(
            kind: kind,
            selectedFields: selectedFields,
            blocked: blocked,
            onFieldChanged: onFieldChanged,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap a product to view all details.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

final class _ImportFieldSelector extends StatelessWidget {
  const _ImportFieldSelector({
    required this.kind,
    required this.selectedFields,
    required this.blocked,
    required this.onFieldChanged,
  });

  final _ReviewKind kind;
  final Set<CatalogPackImportField> selectedFields;
  final bool blocked;
  final void Function(CatalogPackImportField field, bool selected)
  onFieldChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey<String>('catalog-review-${kind.noun}-fields'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>('catalog-review-${kind.noun}-fields-state'),
        initiallyExpanded: false,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: const Icon(Icons.tune_rounded),
        title: const Text('Choose details to import'),
        subtitle: Text(
          '${selectedFields.length}/${CatalogPackImportField.values.length} allowed · both tabs',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 620 ? 2 : 1;
                final width = constraints.maxWidth / columns;
                return Wrap(
                  children: [
                    for (final field in CatalogPackImportField.values)
                      SizedBox(
                        width: width,
                        child: CheckboxListTile(
                          key: ValueKey<String>(
                            'catalog-review-${kind.noun}-field-${field.name}',
                          ),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          value: selectedFields.contains(field),
                          onChanged: blocked
                              ? null
                              : (value) =>
                                    onFieldChanged(field, value ?? false),
                          title: Text(field.label),
                          subtitle: field == CatalogPackImportField.name
                              ? const Text('New products always need a name')
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _ReviewProductCard extends StatelessWidget {
  const _ReviewProductCard({
    required this.product,
    required this.selected,
    required this.selectedFields,
    required this.blocked,
    required this.onChanged,
  });

  final CatalogPackReviewProduct product;
  final bool selected;
  final Set<CatalogPackImportField> selectedFields;
  final bool blocked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final incoming = product.incoming;
    final existing = product.existing;
    final primary = existing ?? incoming;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey<String>('catalog-review-product-${product.targetId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.42) : null,
      child: ExpansionTile(
        key: PageStorageKey<String>(
          'catalog-review-product-expansion-${product.targetId}',
        ),
        initiallyExpanded: false,
        maintainState: false,
        minTileHeight: 72,
        tilePadding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xxs,
          AppSpacing.xs,
          AppSpacing.xxs,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        leading: _ReviewProductThumbnail(
          key: ValueKey<String>(
            'catalog-review-product-image-${product.targetId}',
          ),
          imagePath: product.primaryImagePath,
          productName: primary.name,
        ),
        title: KeyedSubtree(
          key: ValueKey<String>(
            'catalog-review-product-compare-${product.targetId}',
          ),
          child: Text(
            primary.name,
            key: ValueKey<String>(
              'catalog-review-product-name-${product.targetId}',
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        subtitle: _CompactProductSummary(
          barcode: primary.barcode,
          priceCentavos: primary.priceCentavos,
        ),
        trailing: SizedBox.square(
          dimension: AppSize.minimumTouchTarget,
          child: Tooltip(
            message: selected ? 'Do not import this product' : 'Import product',
            child: Checkbox(
              key: ValueKey<String>(
                'catalog-review-product-check-${product.targetId}',
              ),
              value: selected,
              visualDensity: VisualDensity.compact,
              onChanged: blocked ? null : (value) => onChanged(value ?? false),
            ),
          ),
        ),
        children: [
          const Divider(height: 1),
          if (existing != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Current phone value → incoming pack value',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _ComparisonRow(
              label: 'Product name',
              current: existing.name,
              incoming: incoming.name,
              note: _fieldChoice(CatalogPackImportField.name),
            ),
            _ComparisonRow(
              label: 'Barcode',
              current: _displayValue(existing.barcode),
              incoming: _displayValue(incoming.barcode),
              note: _fieldChoice(CatalogPackImportField.barcode),
            ),
            _ComparisonRow(
              label: 'Brand',
              current: _displayValue(existing.brand),
              incoming: _displayValue(incoming.brand),
              note: _fieldChoice(CatalogPackImportField.brand),
            ),
            _ComparisonRow(
              label: 'Category',
              current: _displayValue(existing.category),
              incoming: _displayValue(incoming.category),
              note: _fieldChoice(CatalogPackImportField.category),
            ),
            _ComparisonRow(
              label: 'Size / unit',
              current: _displayValue(existing.unitLabel),
              incoming: _displayValue(incoming.unitLabel),
              note: _fieldChoice(CatalogPackImportField.unitLabel),
            ),
            _ComparisonRow(
              label: 'Suggested price',
              current: _formatPrice(existing.priceCentavos),
              incoming: _formatPrice(incoming.priceCentavos),
              note:
                  !selectedFields.contains(
                    CatalogPackImportField.suggestedPrice,
                  )
                  ? 'Not selected'
                  : existing.priceCentavos > 0
                  ? 'Current price is protected'
                  : 'Fills the zero price',
            ),
            _ComparisonRow(
              label: 'Image',
              current: existing.hasImage ? 'Available' : 'None',
              incoming: product.hasBundledImage
                  ? 'Bundled in pack'
                  : incoming.hasImage
                  ? 'Image reference'
                  : 'None',
              note: _fieldChoice(CatalogPackImportField.image),
            ),
            if (existing.hasImage || incoming.hasImage)
              _ReviewImageComparison(
                currentPath: product.existingImagePath,
                incomingPath: product.incomingImagePath,
                currentHasReference: existing.hasImage,
                incomingHasReference: incoming.hasImage,
                productName: primary.name,
              ),
          ] else ...[
            _PackDetailRow(
              label: 'Product name',
              value: incoming.name,
              note: 'Required for a new product',
            ),
            _PackDetailRow(
              label: 'Barcode',
              value: _displayValue(incoming.barcode),
              note: _fieldChoice(CatalogPackImportField.barcode),
            ),
            _PackDetailRow(
              label: 'Brand',
              value: _displayValue(incoming.brand),
              note: _fieldChoice(CatalogPackImportField.brand),
            ),
            _PackDetailRow(
              label: 'Category',
              value: _displayValue(incoming.category),
              note: _fieldChoice(CatalogPackImportField.category),
            ),
            _PackDetailRow(
              label: 'Size / unit',
              value: _displayValue(incoming.unitLabel),
              note: _fieldChoice(CatalogPackImportField.unitLabel),
            ),
            _PackDetailRow(
              label: 'Suggested price',
              value: _formatPrice(incoming.priceCentavos),
              note: _fieldChoice(CatalogPackImportField.suggestedPrice),
            ),
            _PackDetailRow(
              label: 'Image',
              value: product.hasBundledImage
                  ? 'Bundled in pack'
                  : incoming.hasImage
                  ? 'Image reference only'
                  : 'None',
              note: _fieldChoice(CatalogPackImportField.image),
            ),
          ],
        ],
      ),
    );
  }

  String _fieldChoice(CatalogPackImportField field) =>
      selectedFields.contains(field) ? 'Selected to import' : 'Not selected';
}

final class _CompactProductSummary extends StatelessWidget {
  const _CompactProductSummary({
    required this.barcode,
    required this.priceCentavos,
  });

  final String? barcode;
  final int priceCentavos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final barcodeWidget = Text(
      _displayBarcode(barcode),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
    final priceWidget = Text(
      _formatPrice(priceCentavos),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 168 || textScale > 1.4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [barcodeWidget, priceWidget],
          );
        }
        return Row(
          children: [
            Expanded(child: barcodeWidget),
            const SizedBox(width: AppSpacing.xs),
            Flexible(child: priceWidget),
          ],
        );
      },
    );
  }
}

final class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.current,
    required this.incoming,
    required this.note,
  });

  final String label;
  final String current;
  final String incoming;
  final String note;

  @override
  Widget build(BuildContext context) {
    final changed = current != incoming;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: current),
                      const TextSpan(text: '  →  '),
                      TextSpan(
                        text: incoming,
                        style: changed
                            ? TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              )
                            : TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: note == 'Not selected'
                        ? scheme.outline
                        : scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _PackDetailRow extends StatelessWidget {
  const _PackDetailRow({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: note == 'Not selected'
                        ? scheme.outline
                        : scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _ReviewProductThumbnail extends StatelessWidget {
  const _ReviewProductThumbnail({
    super.key,
    required this.imagePath,
    required this.productName,
    this.size = 48,
  });

  final String? imagePath;
  final String productName;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ProductImagePlaceholder(
      width: size,
      height: size,
      semanticLabel: 'No local preview for $productName',
      borderRadius: BorderRadius.circular(10),
    );
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) return fallback;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, 512);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        filterQuality: FilterQuality.low,
        semanticLabel: 'Product image for $productName',
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

final class _ReviewImageComparison extends StatelessWidget {
  const _ReviewImageComparison({
    required this.currentPath,
    required this.incomingPath,
    required this.currentHasReference,
    required this.incomingHasReference,
    required this.productName,
  });

  final String? currentPath;
  final String? incomingPath;
  final bool currentHasReference;
  final bool incomingHasReference;
  final String productName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _LabeledReviewImage(
              label: 'Current image',
              imagePath: currentPath,
              hasReference: currentHasReference,
              productName: productName,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _LabeledReviewImage(
              label: 'Incoming image',
              imagePath: incomingPath,
              hasReference: incomingHasReference,
              productName: productName,
            ),
          ),
        ],
      ),
    );
  }
}

final class _LabeledReviewImage extends StatelessWidget {
  const _LabeledReviewImage({
    required this.label,
    required this.imagePath,
    required this.hasReference,
    required this.productName,
  });

  final String label;
  final String? imagePath;
  final bool hasReference;
  final String productName;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ReviewProductThumbnail(
          imagePath: imagePath,
          productName: productName,
          size: 72,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        if (hasReference && imagePath == null)
          Text(
            'Reference only',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

final class _EmptyReviewResults extends StatelessWidget {
  const _EmptyReviewResults({required this.title, required this.hasQuery});

  final String title;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 42),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (hasQuery) ...[
            const SizedBox(height: AppSpacing.xxs),
            const Text('Try a different name, barcode, or category.'),
          ],
        ],
      ),
    );
  }
}

extension on CatalogPackImportField {
  String get label => switch (this) {
    CatalogPackImportField.barcode => 'Barcode',
    CatalogPackImportField.name => 'Product name',
    CatalogPackImportField.brand => 'Brand',
    CatalogPackImportField.category => 'Category',
    CatalogPackImportField.unitLabel => 'Size / unit',
    CatalogPackImportField.suggestedPrice => 'Suggested price',
    CatalogPackImportField.image => 'Catalog image',
  };
}

final NumberFormat _pesoFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
);

String _formatPrice(int centavos) => _pesoFormat.format(centavos / 100);

String _displayValue(String? value) {
  final clean = value?.trim();
  return clean == null || clean.isEmpty ? 'None' : clean;
}

String _displayBarcode(String? value) {
  final clean = value?.trim();
  return clean == null || clean.isEmpty ? 'No barcode' : clean;
}

String _productCountLabel(int count) =>
    '$count ${count == 1 ? 'product' : 'products'}';
