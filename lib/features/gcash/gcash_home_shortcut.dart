import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'gcash_price_list_sheet.dart';
import 'gcash_theme.dart';

class GcashHomeShortcut extends StatelessWidget {
  const GcashHomeShortcut({super.key});

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('home-gcash-services'),
    color: GcashTheme.blue,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push('/gcash'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'GCash Services',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('home-gcash-price-list'),
              onPressed: () => showGcashPriceListSheet(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
                textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
              label: const Text('Price list'),
            ),
          ],
        ),
      ),
    ),
  );
}
