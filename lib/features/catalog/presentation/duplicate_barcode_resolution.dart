import 'package:flutter/material.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';

/// Explains the one-barcode/one-product rule and lets a caller reuse the
/// product that already owns the barcode.
Future<bool?> showDuplicateBarcodeResolution(
  BuildContext context, {
  required StoreProduct existingProduct,
}) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.info_outline_rounded, size: 40, color: scheme.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Barcode already saved',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${existingProduct.barcode} belongs to ${existingProduct.name}. '
              'One barcode can identify only one product, so no duplicate was created.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('use-existing-barcode-product'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Use existing product'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
          ],
        ),
      );
    },
  );
}
