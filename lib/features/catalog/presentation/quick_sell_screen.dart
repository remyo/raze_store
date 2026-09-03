import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(quickSellProductsProvider);
    final cart = ref.watch(cartDraftProvider);
    final currentCart = cart.asData?.value;

    return AppPageScaffold(
      title: 'Quick units',
      actions: [
        IconButton(
          onPressed: () => context.go('/cart'),
          tooltip: 'Open cart',
          icon: Badge(
            isLabelVisible: (currentCart?.totalQuantity ?? 0) > 0,
            label: Text(_badgeQuantity(currentCart?.totalQuantity ?? 0)),
            child: const Icon(Icons.shopping_basket_outlined),
          ),
        ),
      ],
      padBody: false,
      body: products.when(
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
          data: (draft) => _buildBody(context, items, draft),
        ),
      ),
      bottomNavigationBar: currentCart?.isNotEmpty == true
          ? _CartSummaryBar(
              cart: currentCart!,
              onOpenCart: () => context.go('/cart'),
            )
          : null,
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<StoreProduct> products,
    CartDraft cart,
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveContent(
            maxWidth: AppBreakpoints.readingMaxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'Add by unit',
                  subtitle:
                      'Use + and − to update the cart immediately. Each unit keeps its own price and quantity.',
                ),
                const SizedBox(height: AppSpacing.md),
                AppSearchField(
                  controller: _searchController,
                  hintText: 'Search product or unit',
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppSectionHeader(
                  title: query.isEmpty ? 'Unit products' : 'Search results',
                  subtitle:
                      '${visible.length} ${visible.length == 1 ? 'product' : 'products'}',
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
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final product = visible[index];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppBreakpoints.readingMaxWidth,
                    ),
                    child: _UnitProductCard(
                      product: product,
                      cart: cart,
                      quantityFor: (option) => _displayQuantity(
                        cart,
                        product.id,
                        option.sellingUnitId,
                      ),
                      onQuantityChanged: (option, quantity) =>
                          _setQuantity(product, option, cart, quantity),
                      onEdit: () => context.push(
                        '/products/${Uri.encodeComponent(product.id)}/edit',
                      ),
                    ),
                  ),
                );
              },
            ),
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

class _UnitProductCard extends StatelessWidget {
  const _UnitProductCard({
    required this.product,
    required this.cart,
    required this.quantityFor,
    required this.onQuantityChanged,
    required this.onEdit,
  });

  final StoreProduct product;
  final CartDraft cart;
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                ProductImage(
                  product: product,
                  width: AppSize.smallThumbnail,
                  height: AppSize.smallThumbnail,
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
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Edit ${product.name}',
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
          for (var index = 0; index < product.saleOptions.length; index++) ...[
            if (index > 0) const Divider(height: 1),
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
    required this.onChanged,
  });

  final StoreProduct product;
  final ProductSaleOption option;
  final CartItem? cartItem;
  final int quantity;
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
    final canAdd = displayedPrice > 0 && quantity < maximumCartQuantity;
    final canRemove = quantity > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (option.isDefault) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Tooltip(
                        message: 'Main barcode unit',
                        child: Icon(
                          Icons.barcode_reader,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
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
          Semantics(
            container: true,
            label: '${product.name}, $displayedLabel quantity',
            value: '$quantity',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: AppRadius.control,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey(
                      'quick-sell-remove-${product.id}-${option.sellingUnitId ?? 'main'}',
                    ),
                    onPressed: canRemove ? () => onChanged(quantity - 1) : null,
                    tooltip: 'Remove one $displayedLabel',
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'quick-sell-add-${product.id}-${option.sellingUnitId ?? 'main'}',
                    ),
                    onPressed: canAdd ? () => onChanged(quantity + 1) : null,
                    tooltip: displayedPrice <= 0
                        ? 'Set a price for $displayedLabel'
                        : 'Add one $displayedLabel',
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
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
  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cart.totalQuantity} ${cart.totalQuantity == 1 ? 'item' : 'items'} in cart',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    PriceText(
                      centavos: cart.totalCentavos,
                      size: PriceTextSize.small,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onOpenCart,
                icon: const Icon(Icons.shopping_basket_outlined),
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
