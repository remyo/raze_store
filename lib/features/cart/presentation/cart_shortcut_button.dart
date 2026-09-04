import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';

/// A consistent, badge-aware shortcut used outside the primary navigation.
class CartShortcutButton extends ConsumerWidget {
  const CartShortcutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(cartDraftProvider).value?.totalQuantity ?? 0;
    final itemLabel = quantity == 1 ? 'item' : 'items';
    return IconButton(
      key: const ValueKey('open-cart'),
      onPressed: () => context.push('/cart'),
      tooltip: quantity == 0 ? 'Open cart' : 'Open cart, $quantity $itemLabel',
      icon: Badge(
        isLabelVisible: quantity > 0,
        label: Text(quantity > 99 ? '99+' : '$quantity'),
        child: const Icon(Icons.shopping_basket_outlined),
      ),
    );
  }
}
