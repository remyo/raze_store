import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/receipt/receipt.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  late final TextEditingController _cashController;
  final Set<String> _busyProducts = {};
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _cashController = TextEditingController()..addListener(_cashChanged);
  }

  @override
  void dispose() {
    _cashController
      ..removeListener(_cashChanged)
      ..dispose();
    super.dispose();
  }

  void _cashChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartDraftProvider);
    final profile =
        ref.watch(storeProfileProvider).value ?? StoreProfile.defaults;

    return AppPageScaffold(
      title: 'Cart',
      actions: [
        if (cart.value?.isNotEmpty == true)
          IconButton(
            onPressed: _clearing ? null : _confirmClear,
            tooltip: 'Clear cart',
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
      ],
      padBody: false,
      body: cart.when(
        loading: () => const AppLoadingState(message: 'Loading cart…'),
        error: (error, _) => AppErrorState(
          message: 'Your unfinished cart could not be loaded.',
          onRetry: () => ref.invalidate(cartDraftProvider),
        ),
        data: (draft) => draft.isEmpty
            ? AppEmptyState(
                icon: Icons.shopping_basket_outlined,
                title: 'The cart is empty',
                message:
                    'Scan a barcode or choose a product to start calculating.',
                actionLabel: 'Scan a product',
                onAction: () => context.go('/scan'),
              )
            : _CartBody(
                draft: draft,
                cashController: _cashController,
                busyProducts: _busyProducts,
                clearing: _clearing,
                onQuantityChanged: _changeQuantity,
                onRemove: _remove,
                onPreviewReceipt: () => _previewReceipt(draft, profile),
                onClear: _confirmClear,
              ),
      ),
    );
  }

  Future<void> _changeQuantity(CartItem item, int quantity) async {
    if (_busyProducts.contains(item.productId)) return;
    setState(() => _busyProducts.add(item.productId));
    try {
      await ref
          .read(cartRepositoryProvider)
          .updateQuantity(item.productId, quantity);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change the quantity.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyProducts.remove(item.productId));
    }
  }

  Future<void> _remove(CartItem item) async {
    if (_busyProducts.contains(item.productId)) return;
    setState(() => _busyProducts.add(item.productId));
    try {
      await ref.read(cartRepositoryProvider).removeProduct(item.productId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove this product.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyProducts.remove(item.productId));
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new customer?'),
        content: const Text(
          'This clears the current cart. No sold item or sales record will be created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep cart'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear cart'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await ref.read(cartRepositoryProvider).clear();
      _cashController.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not clear the cart.')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _previewReceipt(CartDraft cart, StoreProfile profile) async {
    final cashText = _cashController.text.trim();
    final cashReceived = cashText.isEmpty
        ? null
        : tryParsePesoCentavos(cashText);
    if (cashText.isNotEmpty && cashReceived == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid cash amount first.')),
      );
      return;
    }

    final draft = ReceiptDraft(
      storeName: profile.storeName,
      storeAddress: profile.address,
      storeContact: profile.contact,
      footerMessage: profile.receiptFooter,
      createdAt: DateTime.now(),
      cashReceivedCentavos: cashReceived,
      lines: [
        for (final item in cart.items)
          ReceiptLine(
            productName: item.nameSnapshot,
            barcode: item.barcode,
            quantity: item.quantity,
            unitPriceCentavos: item.unitPriceCentavos,
          ),
      ],
    );
    await context.push<void>('/receipt', extra: draft);
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({
    required this.draft,
    required this.cashController,
    required this.busyProducts,
    required this.clearing,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onPreviewReceipt,
    required this.onClear,
  });

  final CartDraft draft;
  final TextEditingController cashController;
  final Set<String> busyProducts;
  final bool clearing;
  final void Function(CartItem item, int quantity) onQuantityChanged;
  final ValueChanged<CartItem> onRemove;
  final VoidCallback onPreviewReceipt;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cashText = cashController.text.trim();
    final cash = cashText.isEmpty ? null : tryParsePesoCentavos(cashText);
    final change = cash == null ? null : cash - draft.totalCentavos;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: AppSpacing.pageInsetsFor(MediaQuery.sizeOf(context).width),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSectionHeader(
                  title:
                      '${draft.totalQuantity} ${draft.totalQuantity == 1 ? 'item' : 'items'}',
                  subtitle:
                      '${draft.distinctProductCount} different ${draft.distinctProductCount == 1 ? 'product' : 'products'}',
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < draft.items.length;
                        index++
                      ) ...[
                        _CartLineTile(
                          item: draft.items[index],
                          busy: busyProducts.contains(
                            draft.items[index].productId,
                          ),
                          onQuantityChanged: (quantity) =>
                              onQuantityChanged(draft.items[index], quantity),
                          onRemove: () => onRemove(draft.items[index]),
                        ),
                        if (index < draft.items.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        PriceText(
                          centavos: draft.totalCentavos,
                          size: PriceTextSize.large,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Cash and change',
                  subtitle:
                      'Optional calculator only. The amount is not saved as a sale.',
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: cashController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Cash received',
                    prefixText: '₱ ',
                    prefixIcon: const Icon(Icons.payments_outlined),
                    errorText: cashText.isNotEmpty && cash == null
                        ? 'Enter a valid amount.'
                        : null,
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    color: change >= 0
                        ? scheme.secondaryContainer
                        : scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              change >= 0 ? 'Change' : 'Still due',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          PriceText(
                            centavos: change.abs(),
                            color: change >= 0
                                ? scheme.onSecondaryContainer
                                : scheme.onErrorContainer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onPreviewReceipt,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Preview receipt'),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'You can save the receipt as an image or send it using your phone’s share menu.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: clearing ? null : onClear,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(clearing ? 'Clearing…' : 'New customer'),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.item,
    required this.busy,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final CartItem item;
  final bool busy;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      item.brandSnapshot,
      item.unitLabelSnapshot,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    final imagePath = item.imagePathSnapshot?.trim();
    final imageUri = imagePath == null ? null : Uri.tryParse(imagePath);
    final isRemoteImage =
        imageUri != null &&
        (imageUri.scheme == 'https' || imageUri.scheme == 'http');
    const imageFallback = ProductImagePlaceholder(width: 64, height: 64);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.control,
                child: imagePath == null || imagePath.isEmpty
                    ? imageFallback
                    : isRemoteImage
                    ? Image.network(
                        imagePath,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => imageFallback,
                      )
                    : Image.file(
                        File(imagePath),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => imageFallback,
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${PriceText.format(item.unitPriceCentavos)} each',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: busy ? null : onRemove,
                tooltip: 'Remove ${item.name}',
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IgnorePointer(
                ignoring: busy,
                child: Opacity(
                  opacity: busy ? 0.55 : 1,
                  child: QuantityStepper(
                    value: item.quantity,
                    maximum: maximumCartQuantity,
                    onChanged: onQuantityChanged,
                    semanticLabel: 'Quantity for ${item.name}',
                  ),
                ),
              ),
              const Spacer(),
              PriceText(
                centavos: item.lineTotalCentavos,
                size: PriceTextSize.regular,
                semanticLabel: 'Subtotal for ${item.name}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
