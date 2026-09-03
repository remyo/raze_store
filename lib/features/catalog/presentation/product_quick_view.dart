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
  int _selectedOptionIndex = 0;
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final saleOptions = product.saleOptions;
    final selectedOption = saleOptions[_selectedOptionIndex];
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
                          centavos: selectedOption.priceCentavos,
                          size: PriceTextSize.large,
                        ),
                        if (product.sellingUnits.isNotEmpty)
                          Text(
                            'per ${selectedOption.label}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
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
              if (product.sellingUnits.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Choose how it is sold',
                  subtitle:
                      'The barcode belongs to the main product. Pick the pack or a loose unit before adding.',
                ),
                const SizedBox(height: AppSpacing.sm),
                for (var index = 0; index < saleOptions.length; index++) ...[
                  _SaleOptionTile(
                    option: saleOptions[index],
                    selected: _selectedOptionIndex == index,
                    onTap: _adding
                        ? null
                        : () => setState(() => _selectedOptionIndex = index),
                  ),
                  if (index < saleOptions.length - 1)
                    const SizedBox(height: AppSpacing.xs),
                ],
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
                      onPressed: _adding || selectedOption.priceCentavos <= 0
                          ? null
                          : _add,
                      icon: _adding
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_shopping_cart_rounded),
                      label: Text(
                        selectedOption.priceCentavos <= 0
                            ? 'Set a price first'
                            : product.sellingUnits.isEmpty
                            ? 'Add $_quantity to cart'
                            : 'Add $_quantity ${selectedOption.label}',
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
          .addProduct(
            widget.product,
            saleOption: widget.product.saleOptions[_selectedOptionIndex],
            quantity: _quantity,
          );
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

class _SaleOptionTile extends StatelessWidget {
  const _SaleOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ProductSaleOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: AppRadius.control,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (option.isDefault)
                      Text(
                        'Main barcode unit',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              PriceText(centavos: option.priceCentavos),
            ],
          ),
        ),
      ),
    );
  }
}
