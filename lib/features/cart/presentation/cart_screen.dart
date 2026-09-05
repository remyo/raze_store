import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/core/widgets/bounded_network_image.dart';
import 'package:raze_store/features/cart/application/cart_providers.dart';
import 'package:raze_store/features/cart/domain/cart.dart';
import 'package:raze_store/features/receipt/receipt.dart';
import 'package:raze_store/features/sales/application/sales_providers.dart';
import 'package:raze_store/features/sales/domain/sales_repository.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  late final TextEditingController _cashController;
  final Set<String> _busyLines = {};
  bool _clearing = false;
  bool _preparingReceipt = false;
  bool _completingSale = false;
  bool _checkoutExpanded = true;

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

  void _setCheckoutExpanded(bool expanded) {
    if (_checkoutExpanded == expanded) return;
    setState(() => _checkoutExpanded = expanded);
  }

  void _collapseCheckoutForScroll() {
    if (!_checkoutExpanded) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _setCheckoutExpanded(false);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartDraftProvider);
    final draft = cart.asData?.value;

    return AppPageScaffold(
      title: 'Cart',
      actions: [
        if (draft?.isNotEmpty == true)
          IconButton(
            key: const ValueKey('new-customer'),
            onPressed: _clearing || _completingSale || _busyLines.isNotEmpty
                ? null
                : _confirmClear,
            tooltip: 'Start a new customer',
            icon: const Icon(Icons.restart_alt_rounded),
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
                busyLines: _busyLines,
                clearing: _clearing,
                completingSale: _completingSale,
                onQuantityChanged: _changeQuantity,
                onRemove: _remove,
                onScrollDown: _collapseCheckoutForScroll,
              ),
      ),
      bottomNavigationBar: draft?.isNotEmpty == true
          ? _CartCheckoutPanel(
              draft: draft!,
              cashController: _cashController,
              expanded: _checkoutExpanded,
              clearing: _clearing,
              preparingReceipt: _preparingReceipt,
              completingSale: _completingSale,
              cartWriteInProgress: _busyLines.isNotEmpty,
              onExpandedChanged: _setCheckoutExpanded,
              onPreviewReceipt: () => _previewReceipt(draft),
              onCompleteSale: _completeSale,
            )
          : null,
    );
  }

  Future<void> _changeQuantity(CartItem item, int quantity) async {
    if (_busyLines.contains(item.lineId) || _clearing || _completingSale) {
      return;
    }
    setState(() => _busyLines.add(item.lineId));
    try {
      await ref
          .read(cartRepositoryProvider)
          .updateQuantity(item.lineId, quantity);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not change the quantity.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLines.remove(item.lineId));
    }
  }

  Future<void> _remove(CartItem item) async {
    if (_busyLines.contains(item.lineId) || _clearing || _completingSale) {
      return;
    }
    setState(() => _busyLines.add(item.lineId));
    try {
      await ref.read(cartRepositoryProvider).removeProduct(item.lineId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove this product.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyLines.remove(item.lineId));
    }
  }

  Future<void> _confirmClear() async {
    if (_busyLines.isNotEmpty || _clearing || _completingSale) return;
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
      if (!mounted) return;
      _checkoutExpanded = true;
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

  Future<void> _previewReceipt(CartDraft cart) async {
    if (_busyLines.isNotEmpty ||
        _clearing ||
        _preparingReceipt ||
        _completingSale) {
      return;
    }
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
    setState(() => _preparingReceipt = true);
    try {
      final profile = await ref
          .read(settingsRepositoryProvider)
          .getStoreProfile();
      if (!mounted) return;
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
              unitLabel: item.unitLabelSnapshot,
              barcode: item.barcode,
              quantity: item.quantity,
              unitPriceCentavos: item.unitPriceCentavos,
            ),
        ],
      );
      await context.push<void>('/receipt', extra: draft);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load the store details for this receipt.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _preparingReceipt = false);
    }
  }

  Future<void> _completeSale() async {
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
    if (_completingSale ||
        _clearing ||
        _preparingReceipt ||
        _busyLines.isNotEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _completingSale = true);
    try {
      final sale = await ref
          .read(salesRepositoryProvider)
          .completeCurrentCart(cashReceivedCentavos: cashReceived);
      if (!mounted) return;
      _checkoutExpanded = true;
      _cashController.clear();
      try {
        await context.push<void>('/receipt', extra: sale.toReceiptDraft());
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sale saved, but the receipt could not be opened. You can reopen it from Sales.',
              ),
            ),
          );
        }
      }
    } on EmptyCartSaleException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The cart is already empty.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not complete the sale. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _completingSale = false);
    }
  }
}

class _CartBody extends StatelessWidget {
  const _CartBody({
    required this.draft,
    required this.busyLines,
    required this.clearing,
    required this.completingSale,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onScrollDown,
  });

  final CartDraft draft;
  final Set<String> busyLines;
  final bool clearing;
  final bool completingSale;
  final void Function(CartItem item, int quantity) onQuantityChanged;
  final Future<void> Function(CartItem item) onRemove;
  final VoidCallback onScrollDown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final itemCount = draft.items.length;

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (notification.direction == ScrollDirection.reverse) {
          onScrollDown();
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('cart-items-scroll-view'),
        padding: AppSpacing.pageInsetsFor(MediaQuery.sizeOf(context).width),
        itemCount: itemCount + 3,
        itemBuilder: (context, index) {
          Widget child;
          if (index == 0) {
            child = Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppSectionHeader(
                title:
                    '${draft.totalQuantity} ${draft.totalQuantity == 1 ? 'item' : 'items'}',
                subtitle:
                    '${draft.distinctProductCount} different ${draft.distinctProductCount == 1 ? 'product' : 'products'}',
              ),
            );
          } else if (index <= itemCount) {
            final item = draft.items[index - 1];
            child = Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: _CartLineTile(
                  item: item,
                  busy:
                      busyLines.contains(item.lineId) ||
                      clearing ||
                      completingSale,
                  onQuantityChanged: (quantity) =>
                      onQuantityChanged(item, quantity),
                  onRemove: () => onRemove(item),
                ),
              ),
            );
          } else if (index == itemCount + 1) {
            child = Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Card(
                margin: EdgeInsets.zero,
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
            );
          } else {
            child = const SizedBox(height: AppSpacing.sm);
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _CartCheckoutPanel extends StatelessWidget {
  const _CartCheckoutPanel({
    required this.draft,
    required this.cashController,
    required this.expanded,
    required this.clearing,
    required this.preparingReceipt,
    required this.completingSale,
    required this.cartWriteInProgress,
    required this.onExpandedChanged,
    required this.onPreviewReceipt,
    required this.onCompleteSale,
  });

  static const _cashBills = [50, 100, 200, 500, 1000];

  final CartDraft draft;
  final TextEditingController cashController;
  final bool expanded;
  final bool clearing;
  final bool preparingReceipt;
  final bool completingSale;
  final bool cartWriteInProgress;
  final ValueChanged<bool> onExpandedChanged;
  final VoidCallback onPreviewReceipt;
  final VoidCallback onCompleteSale;

  bool get _actionsDisabled =>
      clearing || preparingReceipt || completingSale || cartWriteInProgress;

  void _selectCashBill(int pesos) {
    final text = pesos.toString();
    cashController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final cashText = cashController.text.trim();
    final cash = cashText.isEmpty ? null : tryParsePesoCentavos(cashText);
    final change = cash == null ? null : cash - draft.totalCentavos;
    final availableHeight = MediaQuery.sizeOf(context).height - keyboardInset;
    final contentMaxHeight = (availableHeight * 0.56).clamp(180.0, 390.0);

    // Scaffold resizes its body for the keyboard, but persistent bottom bars
    // remain anchored to the bottom of the window. Lift this panel explicitly
    // so the cash field and checkout actions stay above the keyboard.
    return AnimatedPadding(
      key: const ValueKey('cash-panel-keyboard-lift'),
      duration: AppDurations.quick,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Material(
          color: scheme.surface,
          elevation: 12,
          shadowColor: scheme.shadow.withValues(alpha: 0.2),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GestureDetector(
                    key: const ValueKey('cash-panel-handle'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onExpandedChanged(!expanded),
                    onVerticalDragUpdate: (details) {
                      if (details.delta.dy < -2) {
                        onExpandedChanged(true);
                      } else if (details.delta.dy > 2) {
                        onExpandedChanged(false);
                      }
                    },
                    child: Semantics(
                      button: true,
                      label: expanded
                          ? 'Collapse cash and change'
                          : 'Expand cash and change',
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                color: scheme.outlineVariant,
                                borderRadius: AppRadius.control,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                AnimatedRotation(
                                  turns: expanded ? 0.5 : 0,
                                  duration: AppDurations.quick,
                                  child: const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Cash and change',
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      if (!expanded)
                                        Text(
                                          'Tap or swipe up to open',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Total ',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                PriceText(
                                  centavos: draft.totalCentavos,
                                  size: PriceTextSize.regular,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ClipRect(
                    child: AnimatedSize(
                      duration: AppDurations.standard,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: expanded
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: contentMaxHeight,
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  0,
                                  AppSpacing.md,
                                  AppSpacing.md,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Divider(height: 1),
                                    const SizedBox(height: AppSpacing.sm),
                                    TextField(
                                      key: const ValueKey(
                                        'cash-received-field',
                                      ),
                                      controller: cashController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9.,]'),
                                        ),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Cash received',
                                        prefixText: '₱ ',
                                        prefixIcon: const Icon(
                                          Icons.payments_outlined,
                                        ),
                                        errorText:
                                            cashText.isNotEmpty && cash == null
                                            ? 'Enter a valid amount.'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Row(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < _cashBills.length;
                                          index++
                                        ) ...[
                                          if (index > 0)
                                            const SizedBox(
                                              width: AppSpacing.xxs,
                                            ),
                                          Expanded(
                                            child: _CashBillButton(
                                              pesos: _cashBills[index],
                                              selected:
                                                  cash ==
                                                  _cashBills[index] * 100,
                                              onPressed: () => _selectCashBill(
                                                _cashBills[index],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (change != null) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: change >= 0
                                              ? scheme.secondaryContainer
                                              : scheme.errorContainer,
                                          borderRadius: AppRadius.control,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.sm,
                                            vertical: AppSpacing.xs,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  change >= 0
                                                      ? 'Change'
                                                      : 'Still due',
                                                  style: theme
                                                      .textTheme
                                                      .titleSmall,
                                                ),
                                              ),
                                              PriceText(
                                                centavos: change.abs(),
                                                color: change >= 0
                                                    ? scheme
                                                          .onSecondaryContainer
                                                    : scheme.onErrorContainer,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: AppSpacing.sm),
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: OutlinedButton(
                                            key: const ValueKey(
                                              'preview-receipt',
                                            ),
                                            onPressed: _actionsDisabled
                                                ? null
                                                : onPreviewReceipt,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                preparingReceipt
                                                    ? 'Preparing…'
                                                    : 'Preview receipt',
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        Expanded(
                                          flex: 3,
                                          child: FilledButton(
                                            key: const ValueKey(
                                              'complete-sale',
                                            ),
                                            onPressed: _actionsDisabled
                                                ? null
                                                : onCompleteSale,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                completingSale
                                                    ? 'Completing sale…'
                                                    : 'Complete sale',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      'Completing saves this sale and opens its receipt.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CashBillButton extends StatelessWidget {
  const _CashBillButton({
    required this.pesos,
    required this.selected,
    required this.onPressed,
  });

  final int pesos;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = FittedBox(fit: BoxFit.scaleDown, child: Text('₱$pesos'));
    if (selected) {
      return FilledButton.tonal(
        key: ValueKey('cash-bill-$pesos'),
        style: AppButtonStyles.compactFilled(context).copyWith(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          ),
        ),
        onPressed: onPressed,
        child: child,
      );
    }
    return OutlinedButton(
      key: ValueKey('cash-bill-$pesos'),
      style: AppButtonStyles.compactOutlined(context).copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        ),
      ),
      onPressed: onPressed,
      child: child,
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
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = [
      item.brandSnapshot,
      if (item.unitLabelSnapshot case final unit?) 'Sold as $unit',
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    final imagePath = item.imagePathSnapshot?.trim();
    final imageUri = imagePath == null ? null : Uri.tryParse(imagePath);
    final isRemoteImage = imageUri != null && imageUri.hasScheme;
    const imageFallback = ProductImagePlaceholder(width: 64, height: 64);

    return Dismissible(
      key: ValueKey('cart-line-${item.lineId}'),
      direction: busy ? DismissDirection.none : DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.35},
      confirmDismiss: busy
          ? null
          : (_) async {
              // The repository stream owns removal from the widget tree. Always
              // cancel Dismissible's local removal so a failed write restores
              // the row instead of leaving the cart visually out of sync.
              await onRemove();
              return false;
            },
      background: Container(
        key: ValueKey('cart-line-delete-background-${item.lineId}'),
        alignment: AlignmentDirectional.centerEnd,
        color: scheme.errorContainer,
        padding: const EdgeInsetsDirectional.only(end: AppSpacing.lg),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Remove',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: scheme.onErrorContainer),
            ),
          ],
        ),
      ),
      child: Padding(
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
                      ? BoundedNetworkImage(
                          url: imagePath,
                          fallback: imageFallback,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          cacheWidth: 192,
                        )
                      : Image.file(
                          File(imagePath),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          cacheWidth: 192,
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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
                  onPressed: busy
                      ? null
                      : () async {
                          await onRemove();
                        },
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
      ),
    );
  }
}
