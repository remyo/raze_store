import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/presentation/product_image.dart';

Future<bool?> showProductQuickView(
  BuildContext context, {
  required StoreProduct product,
  bool allowEdit = true,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ProductQuickView(product: product, allowEdit: allowEdit),
  );
}

class ProductQuickView extends ConsumerStatefulWidget {
  const ProductQuickView({
    super.key,
    required this.product,
    this.allowEdit = true,
  });

  final StoreProduct product;
  final bool allowEdit;

  @override
  ConsumerState<ProductQuickView> createState() => _ProductQuickViewState();
}

class _ProductQuickViewState extends ConsumerState<ProductQuickView> {
  int _quantity = 1;
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      product.brand,
      product.unitLabel,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductImage(
                    product: product,
                    width: 112,
                    height: 112,
                    borderRadius: AppRadius.card,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product.category case final category?)
                          Text(
                            category.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.primary,
                                  letterSpacing: 0.7,
                                ),
                          ),
                        Text(
                          product.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            details,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        PriceText(
                          centavos: product.priceCentavos,
                          size: PriceTextSize.large,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (product.barcode case final barcode?) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Icon(
                      Icons.barcode_reader,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        barcode,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  QuantityStepper(
                    value: _quantity,
                    maximum: maximumCartQuantity,
                    onChanged: (value) => setState(() => _quantity = value),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _adding || product.priceCentavos <= 0
                          ? null
                          : _add,
                      icon: _adding
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_shopping_cart_rounded),
                      label: Text(
                        product.priceCentavos <= 0
                            ? 'Set a price first'
                            : 'Add $_quantity to cart',
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.allowEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/products/${product.id}/edit');
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit product'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await ref
          .read(cartRepositoryProvider)
          .addProduct(widget.product, quantity: _quantity);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add this product to the cart.'),
        ),
      );
    }
  }
}
