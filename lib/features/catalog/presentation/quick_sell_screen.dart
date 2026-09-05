import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/database/cart_line_id.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/cart/domain/cart_repository.dart';
import 'package:raze_store/features/catalog/application/quick_sell_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/app_preferences.dart';

/// Fast cart controls for products sold in more than one unit.
///
/// This is deliberately separate from the full catalog: the seller can find
/// common tingi items and punch a pack, piece, stick, or sachet into the cart
/// without opening a product details sheet first.
class QuickSellScreen extends ConsumerStatefulWidget {
  const QuickSellScreen({super.key});

  @override
  ConsumerState<QuickSellScreen> createState() => _QuickSellScreenState();
}

class _QuickSellScreenState extends ConsumerState<QuickSellScreen> {
  final Map<String, int> _optimisticQuantities = {};
  final Map<String, Future<void>> _lineQueues = {};
  late final TextEditingController _searchController;
  String _query = '';
  bool _openingCart = false;

  bool get _canOpenCart => !_openingCart && _lineQueues.isEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _changeLayout(CatalogViewLayout layout) async {
    final current =
        ref.read(appPreferencesProvider).value?.quickUnitsViewLayout ??
        CatalogViewLayout.grid;
    if (current == layout) return;
    try {
      await ref
          .read(appPreferencesProvider.notifier)
          .setQuickUnitsViewLayout(layout);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the Quick units view.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(quickSellProductsProvider);
    final cart = ref.watch(cartDraftProvider);
    final currentCart = cart.asData?.value;
    final appPreferences = ref.watch(appPreferencesProvider);
    final layout =
        appPreferences.value?.quickUnitsViewLayout ?? CatalogViewLayout.grid;

    return AppPageScaffold(
      title: 'Quick units',
      actions: [
        IconButton(
          key: const ValueKey('quick-sell-open-cart'),
          onPressed: _canOpenCart ? _openCart : null,
          tooltip: 'Open cart',
          icon: Badge(
            isLabelVisible: (currentCart?.totalQuantity ?? 0) > 0,
            label: Text(_badgeQuantity(currentCart?.totalQuantity ?? 0)),
            child: const Icon(Icons.shopping_basket_outlined),
          ),
        ),
      ],
      padBody: false,
      body: appPreferences.isLoading && !appPreferences.hasValue
          ? const AppLoadingState(message: 'Loading your Quick units view…')
          : products.when(
              loading: () => const AppLoadingState(
                message: 'Loading products with unit prices…',
              ),
              error: (_, _) => AppErrorState(
                message: 'Products with unit prices could not be loaded.',
                onRetry: () => ref.invalidate(quickSellProductsProvider),
              ),
              data: (items) => cart.when(
                loading: () => const AppLoadingState(message: 'Loading cart…'),
                error: (_, _) => AppErrorState(
                  message: 'Your unfinished cart could not be loaded.',
                  onRetry: () => ref.invalidate(cartDraftProvider),
                ),
                data: (draft) => _buildBody(context, items, draft, layout),
              ),
            ),
      bottomNavigationBar: currentCart?.isNotEmpty == true
          ? _CartSummaryBar(
              cart: currentCart!,
              onOpenCart: _canOpenCart ? _openCart : null,
            )
          : null,
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<StoreProduct> products,
    CartDraft cart,
    CatalogViewLayout layout,
  ) {
    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? products
        : products
              .where((product) {
                final searchable = [
                  product.name,
                  product.brand,
                  product.category,
                  product.barcode,
                  ...product.saleOptions.map((option) => option.label),
                ].whereType<String>().join(' ').toLowerCase();
                return searchable.contains(query);
              })
              .toList(growable: false);

    if (products.isEmpty) {
      return AppEmptyState(
        icon: Icons.widgets_outlined,
        title: 'No unit prices yet',
        message:
            'Edit a product and add a piece, stick, sachet, strip, tray, or other unit price.',
        actionLabel: 'Open products',
        onAction: () => context.go('/products'),
      );
    }

    Widget buildListCard(StoreProduct product) => _UnitProductCard(
      product: product,
      cart: cart,
      quantityChangesEnabled: !_openingCart,
      quantityFor: (option) =>
          _displayQuantity(cart, product.id, option.sellingUnitId),
      onQuantityChanged: (option, quantity) =>
          _setQuantity(product, option, cart, quantity),
      onEdit: () =>
          context.push('/products/${Uri.encodeComponent(product.id)}/edit'),
    );

    Widget buildGridCard(StoreProduct product) => _CompactUnitProductCard(
      key: ValueKey('quick-sell-grid-item-${product.id}'),
      product: product,
      cart: cart,
      quantityChangesEnabled: !_openingCart,
      quantityFor: (option) =>
          _displayQuantity(cart, product.id, option.sellingUnitId),
      onQuantityChanged: (option, quantity) =>
          _setQuantity(product, option, cart, quantity),
      onEdit: () =>
          context.push('/products/${Uri.encodeComponent(product.id)}/edit'),
    );

    return CustomScrollView(
      key: ValueKey('quick-sell-${layout.name}'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveContent(
            maxWidth: AppBreakpoints.readingMaxWidth,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSearchField(
                  controller: _searchController,
                  hintText: 'Search product or unit',
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${visible.length} ${visible.length == 1 ? 'product' : 'products'}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(
                            'Tap + to add to cart',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _QuickSellLayoutToggle(
                      value: layout,
                      onChanged: _changeLayout,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching unit product',
              message: 'Try another product name, barcode, or unit.',
            ),
          )
        else if (layout == CatalogViewLayout.list)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.xs,
              AppSpacing.xl,
            ),
            sliver: SliverList.separated(
              key: const ValueKey('quick-sell-results-list'),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, index) {
                final product = visible[index];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppBreakpoints.readingMaxWidth,
                    ),
                    child: buildListCard(product),
                  ),
                );
              },
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding =
                  ((constraints.crossAxisExtent -
                              AppBreakpoints.readingMaxWidth) /
                          2)
                      .clamp(AppSpacing.xs, double.infinity)
                      .toDouble();
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  AppSpacing.xl,
                ),
                // Each product follows the shortest column, so a product
                // with more selling units cannot leave gaps in other columns.
                sliver: SliverMasonryGrid.count(
                  key: const ValueKey('quick-sell-results-grid'),
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpacing.xs,
                  crossAxisSpacing: AppSpacing.xs,
                  childCount: visible.length,
                  itemBuilder: (context, index) =>
                      buildGridCard(visible[index]),
                ),
              );
            },
          ),
      ],
    );
  }

  int _displayQuantity(
    CartDraft cart,
    String productId,
    String? sellingUnitId,
  ) {
    final lineKey = buildCartLineId(productId, sellingUnitId);
    final savedQuantity =
        _cartItem(cart, productId, sellingUnitId)?.quantity ?? 0;
    final optimistic = _optimisticQuantities[lineKey];
    if (optimistic == null) return savedQuantity;

    // Once Drift publishes the saved quantity, stop overriding it so future
    // changes made from the Cart screen remain visible here.
    if (!_lineQueues.containsKey(lineKey) && optimistic == savedQuantity) {
      _optimisticQuantities.remove(lineKey);
      return savedQuantity;
    }
    return optimistic;
  }

  void _setQuantity(
    StoreProduct product,
    ProductSaleOption option,
    CartDraft cart,
    int requestedQuantity,
  ) {
    if (_openingCart) return;

    final lineKey = buildCartLineId(product.id, option.sellingUnitId);
    final item = _cartItem(cart, product.id, option.sellingUnitId);
    final currentQuantity = _displayQuantity(
      cart,
      product.id,
      option.sellingUnitId,
    );
    if (requestedQuantity == currentQuantity) return;

    final repository = ref.read(cartRepositoryProvider);
    final previousWrite = _lineQueues[lineKey] ?? Future<void>.value();
    final write = _writeAfter(
      previousWrite,
      repository: repository,
      product: product,
      option: option,
      lineId: item?.lineId ?? lineKey,
      currentQuantity: currentQuantity,
      requestedQuantity: requestedQuantity,
    );
    setState(() {
      _optimisticQuantities[lineKey] = requestedQuantity;
      _lineQueues[lineKey] = write;
    });
    unawaited(
      _settleWrite(
        lineKey,
        write,
        repository: repository,
        product: product,
        option: option,
      ),
    );
  }

  Future<void> _openCart() async {
    if (_openingCart) return;

    setState(() => _openingCart = true);

    // A stale callback can still reach this method during the frame in which
    // the cart button becomes disabled. Waiting for the writes captured after
    // the guard is set keeps them from completing after checkout starts.
    final pendingWrites = _lineQueues.values.toSet().toList(growable: false);
    await Future.wait(
      pendingWrites.map((write) async {
        try {
          await write;
        } on Object {
          // The matching settlement callback reports the write failure. It is
          // still safe to open the cart once the failed write has completed.
        }
      }),
    );

    if (!mounted) return;
    context.go('/cart');
  }

  Future<void> _writeAfter(
    Future<void> previousWrite, {
    required CartRepository repository,
    required StoreProduct product,
    required ProductSaleOption option,
    required String lineId,
    required int currentQuantity,
    required int requestedQuantity,
  }) async {
    try {
      await previousWrite;
    } on Object {
      // A failed earlier tap is reported by its own settlement callback. Later
      // taps still run so a temporary write failure does not freeze this line.
    }

    if (requestedQuantity > currentQuantity) {
      await repository.addProduct(
        product,
        saleOption: option,
        quantity: requestedQuantity - currentQuantity,
      );
    } else {
      await repository.updateQuantity(lineId, requestedQuantity);
    }
  }

  Future<void> _settleWrite(
    String lineKey,
    Future<void> write, {
    required CartRepository repository,
    required StoreProduct product,
    required ProductSaleOption option,
  }) async {
    Object? writeError;
    try {
      await write;
    } on Object catch (error) {
      writeError = error;
    }

    // A newer tap owns reconciliation for this line. This callback only needs
    // to report its own error and leave the optimistic value in place.
    if (_lineQueues[lineKey] != write) {
      if (writeError != null) _showWriteError(product, option);
      return;
    }

    int? savedQuantity;
    try {
      final latest = await repository.getDraft();
      savedQuantity =
          _cartItem(latest, product.id, option.sellingUnitId)?.quantity ?? 0;
    } on Object {
      // The cart stream normally publishes the result. If this defensive read
      // fails, falling back to that stream is safer than showing a stale count.
    }

    if (!mounted) return;
    setState(() {
      _lineQueues.remove(lineKey);
      if (savedQuantity == null) {
        _optimisticQuantities.remove(lineKey);
      } else {
        _optimisticQuantities[lineKey] = savedQuantity;
      }
    });
    if (writeError != null) _showWriteError(product, option);
  }

  void _showWriteError(StoreProduct product, ProductSaleOption option) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not update ${product.name} (${option.label}).'),
      ),
    );
  }
}

class _QuickSellLayoutToggle extends StatelessWidget {
  const _QuickSellLayoutToggle({required this.value, required this.onChanged});

  final CatalogViewLayout value;
  final ValueChanged<CatalogViewLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Quick units layout',
      child: SegmentedButton<CatalogViewLayout>(
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
            value: CatalogViewLayout.grid,
            icon: SizedBox.square(
              key: ValueKey('quick-sell-layout-grid'),
              dimension: AppSize.compactControl,
              child: Icon(Icons.grid_view_rounded, size: AppSize.icon),
            ),
            tooltip: 'Show quick units as a grid',
          ),
          ButtonSegment(
            value: CatalogViewLayout.list,
            icon: SizedBox.square(
              key: ValueKey('quick-sell-layout-list'),
              dimension: AppSize.compactControl,
              child: Icon(Icons.view_list_rounded, size: AppSize.icon),
            ),
            tooltip: 'Show quick units as a list',
          ),
        ],
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.first);
        },
      ),
    );
  }
}

class _CompactUnitProductCard extends StatelessWidget {
  const _CompactUnitProductCard({
    super.key,
    required this.product,
    required this.cart,
    required this.quantityChangesEnabled,
    required this.quantityFor,
    required this.onQuantityChanged,
    required this.onEdit,
  });

  final StoreProduct product;
  final CartDraft cart;
  final bool quantityChangesEnabled;
  final int Function(ProductSaleOption option) quantityFor;
  final void Function(ProductSaleOption option, int quantity) onQuantityChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nameStyle = Theme.of(
      context,
    ).textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w700, height: 1.3);
    final nameHeight =
        MediaQuery.textScalerOf(context).scale(nameStyle.fontSize!) * 2.6;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 68,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => ProductImage(
                    product: product,
                    width: constraints.maxWidth,
                    height: 68,
                    fit: BoxFit.cover,
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: onEdit,
                    tooltip: 'Edit ${product.name}',
                    constraints: const BoxConstraints.tightFor(
                      width: AppSize.minimumTouchTarget,
                      height: AppSize.minimumTouchTarget,
                    ),
                    padding: EdgeInsets.zero,
                    icon: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest.withValues(
                          alpha: 0.94,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.edit_outlined, size: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: SizedBox(
              height: nameHeight,
              child: Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ),
          for (var index = 0; index < product.saleOptions.length; index++) ...[
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Builder(
              builder: (context) {
                final option = product.saleOptions[index];
                final cartItem = _cartItem(
                  cart,
                  product.id,
                  option.sellingUnitId,
                );
                return _CompactUnitOption(
                  product: product,
                  option: option,
                  cartItem: cartItem,
                  quantity: quantityFor(option),
                  enabled: quantityChangesEnabled,
                  onChanged: (quantity) => onQuantityChanged(option, quantity),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactUnitOption extends StatelessWidget {
  const _CompactUnitOption({
    required this.product,
    required this.option,
    required this.cartItem,
    required this.quantity,
    required this.enabled,
    required this.onChanged,
  });

  final StoreProduct product;
  final ProductSaleOption option;
  final CartItem? cartItem;
  final int quantity;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayedLabel =
        cartItem?.unitLabelSnapshot?.trim().isNotEmpty == true
        ? cartItem!.unitLabelSnapshot!.trim()
        : option.label;
    final displayedPrice = cartItem?.unitPriceCentavos ?? option.priceCentavos;
    final usesSavedCartPrice =
        cartItem != null &&
        (displayedPrice != option.priceCentavos ||
            displayedLabel != option.label);
    return ColoredBox(
      color: quantity > 0
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: PriceText(
                    centavos: displayedPrice,
                    size: PriceTextSize.small,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (usesSavedCartPrice)
                  Tooltip(
                    message: 'Using the price already in cart',
                    child: Text(
                      'Using the price already in cart',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _UnitQuantityControls(
            product: product,
            option: option,
            label: displayedLabel,
            priceCentavos: displayedPrice,
            quantity: quantity,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _UnitQuantityControls extends StatelessWidget {
  const _UnitQuantityControls({
    required this.product,
    required this.option,
    required this.label,
    required this.priceCentavos,
    required this.quantity,
    required this.enabled,
    required this.onChanged,
  });

  final StoreProduct product;
  final ProductSaleOption option;
  final String label;
  final int priceCentavos;
  final int quantity;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canAdd =
        enabled && priceCentavos > 0 && quantity < maximumCartQuantity;
    final canRemove = enabled && quantity > 0;

    Widget button({required bool add}) {
      final active = add ? canAdd : canRemove;
      return IconButton(
        key: ValueKey(
          'quick-sell-${add ? 'add' : 'remove'}-${product.id}-${option.sellingUnitId ?? 'main'}',
        ),
        onPressed: active ? () => onChanged(quantity + (add ? 1 : -1)) : null,
        tooltip: add
            ? (priceCentavos <= 0 ? 'Set a price for $label' : 'Add one $label')
            : 'Remove one $label',
        constraints: const BoxConstraints.expand(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        alignment: add ? Alignment.centerRight : Alignment.centerLeft,
        icon: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: add && active ? scheme.primary : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Icon(
            add ? Icons.add_rounded : Icons.remove_rounded,
            size: 18,
            color: add && active
                ? scheme.onPrimary
                : scheme.onSurfaceVariant.withValues(alpha: active ? 1 : 0.35),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: '${product.name}, $label quantity',
      value: '$quantity',
      child: SizedBox(
        height: AppSize.minimumTouchTarget,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                Expanded(child: button(add: false)),
                Expanded(child: button(add: true)),
              ],
            ),
            // The count is informational; tapping it must not change the cart.
            AbsorbPointer(
              child: SizedBox(
                width: 28,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$quantity',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: quantity > 0
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitProductCard extends StatelessWidget {
  const _UnitProductCard({
    required this.product,
    required this.cart,
    required this.quantityChangesEnabled,
    required this.quantityFor,
    required this.onQuantityChanged,
    required this.onEdit,
  });

  final StoreProduct product;
  final CartDraft cart;
  final bool quantityChangesEnabled;
  final int Function(ProductSaleOption option) quantityFor;
  final void Function(ProductSaleOption option, int quantity) onQuantityChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      product.brand,
      product.category,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Row(
              children: [
                ProductImage(
                  product: product,
                  width: AppSize.thumbnail,
                  height: AppSize.thumbnail,
                  fit: BoxFit.cover,
                  borderRadius: AppRadius.control,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit ${product.name}',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ],
            ),
          ),
          for (var index = 0; index < product.saleOptions.length; index++) ...[
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Builder(
              builder: (context) {
                final option = product.saleOptions[index];
                final cartItem = _cartItem(
                  cart,
                  product.id,
                  option.sellingUnitId,
                );
                return _UnitOptionRow(
                  product: product,
                  option: option,
                  cartItem: cartItem,
                  quantity: quantityFor(option),
                  enabled: quantityChangesEnabled,
                  onChanged: (quantity) => onQuantityChanged(option, quantity),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _UnitOptionRow extends StatelessWidget {
  const _UnitOptionRow({
    required this.product,
    required this.option,
    required this.cartItem,
    required this.quantity,
    required this.enabled,
    required this.onChanged,
  });

  final StoreProduct product;
  final ProductSaleOption option;
  final CartItem? cartItem;
  final int quantity;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayedLabel =
        cartItem?.unitLabelSnapshot?.trim().isNotEmpty == true
        ? cartItem!.unitLabelSnapshot!.trim()
        : option.label;
    final displayedPrice = cartItem?.unitPriceCentavos ?? option.priceCentavos;
    final usesSavedCartPrice =
        cartItem != null &&
        (displayedPrice != option.priceCentavos ||
            displayedLabel != option.label);
    return Container(
      color: quantity > 0
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerLowest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                PriceText(centavos: displayedPrice, size: PriceTextSize.small),
                if (usesSavedCartPrice)
                  Text(
                    'Using the price already in cart',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 112,
            child: _UnitQuantityControls(
              product: product,
              option: option,
              label: displayedLabel,
              priceCentavos: displayedPrice,
              quantity: quantity,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.cart, required this.onOpenCart});

  final CartDraft cart;
  final VoidCallback? onOpenCart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cart.totalQuantity} ${cart.totalQuantity == 1 ? 'item' : 'items'} in cart',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    PriceText(
                      centavos: cart.totalCentavos,
                      size: PriceTextSize.small,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('quick-sell-view-cart'),
                onPressed: onOpenCart,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                iconAlignment: IconAlignment.end,
                label: const Text('View cart'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

CartItem? _cartItem(CartDraft cart, String productId, String? sellingUnitId) {
  for (final item in cart.items) {
    if (item.productId == productId && item.sellingUnitId == sellingUnitId) {
      return item;
    }
  }
  return null;
}

String _badgeQuantity(int quantity) => quantity > 99 ? '99+' : '$quantity';
