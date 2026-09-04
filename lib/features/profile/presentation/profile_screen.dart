import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog_transfer/presentation/backup_reminder_card.dart';

/// Store-management shortcuts that do not belong in the selling workflow.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.onOpenSales, this.onOpenSettings});

  /// Optional navigation seams used by embedders and widget tests.
  final VoidCallback? onOpenSales;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Profile',
      padBody: false,
      body: ListView(
        padding: AppSpacing.pageInsetsFor(MediaQuery.sizeOf(context).width),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.readingMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeader(
                    title: 'Store management',
                    subtitle:
                        'Review completed sales and manage your store setup.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const BackupReminderCard(),
                  _ProfileDestinationCard(
                    key: const ValueKey('profile-open-sales'),
                    icon: Icons.receipt_long_outlined,
                    title: 'Sales',
                    subtitle: 'View sales history, totals, and receipts.',
                    onTap: () => _openSales(context),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ProfileDestinationCard(
                    key: const ValueKey('profile-open-settings'),
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Manage store details, categories, and storage.',
                    onTap: () => _openSettings(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSales(BuildContext context) {
    final callback = onOpenSales;
    if (callback != null) {
      callback();
      return;
    }
    context.push('/sales');
  }

  void _openSettings(BuildContext context) {
    final callback = onOpenSettings;
    if (callback != null) {
      callback();
      return;
    }
    context.push('/settings');
  }
}

class _ProfileDestinationCard extends StatelessWidget {
  const _ProfileDestinationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: AppRadius.control,
                ),
                child: SizedBox.square(
                  dimension: AppSize.iconBadgeLarge,
                  child: Icon(icon, color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
