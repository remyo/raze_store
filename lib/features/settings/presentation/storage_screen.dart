import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/settings/application/app_storage_providers.dart';
import 'package:raze_store/features/settings/domain/app_storage_usage.dart';

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  bool _clearingTemporaryFiles = false;

  @override
  Widget build(BuildContext context) {
    final usage = ref.watch(appStorageUsageProvider);

    return AppPageScaffold(
      title: 'Storage',
      leading: BackButton(
        onPressed: _clearingTemporaryFiles
            ? null
            : () => Navigator.of(context).maybePop(),
      ),
      actions: [
        IconButton(
          key: const ValueKey('storage-refresh'),
          tooltip: 'Refresh storage usage',
          onPressed: _clearingTemporaryFiles
              ? null
              : () => ref.invalidate(appStorageUsageProvider),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      padBody: false,
      body: usage.when(
        data: _buildContent,
        loading: () =>
            const AppLoadingState(message: 'Measuring Raze Store data…'),
        error: (error, stackTrace) => AppErrorState(
          title: 'Storage could not be measured',
          message: 'Your local data is safe. Try measuring it again.',
          onRetry: () => ref.invalidate(appStorageUsageProvider),
        ),
      ),
    );
  }

  Widget _buildContent(AppStorageUsage usage) {
    return ListView(
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
                _ManagedStorageCard(usage: usage),
                if (usage.unreadableEntryCount > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _StorageNotice(
                    key: const ValueKey('storage-best-effort-notice'),
                    icon: Icons.info_outline_rounded,
                    title: 'Best-effort total',
                    message:
                        '${usage.unreadableEntryCount} ${usage.unreadableEntryCount == 1 ? 'entry was' : 'entries were'} changing or unavailable while storage was measured. Refresh to try again.',
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Safe cleanup',
                  subtitle:
                      'Temporary files can be rebuilt. Your products and sales data cannot.',
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  key: const ValueKey('storage-clear-temporary-card'),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StorageCleanupRow(
                          subtitle:
                              '${formatStorageBytes(usage.temporaryBytes)} · ${_fileCountLabel(usage.temporaryFileCount)}',
                          clearing: _clearingTemporaryFiles,
                          onClear: _confirmClearTemporaryFiles,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'This removes only other cache, background-removal working files, and temporary receipt copies. It never deletes the database, product images, or exported files.',
                          key: const ValueKey('storage-cleanup-scope'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Deleting sales or products may not reduce the database file immediately. SQLite can reuse that free space, and its temporary WAL file may grow or shrink later.',
                          key: const ValueKey('storage-database-reuse-note'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Outside this total',
                  subtitle:
                      'Some storage cannot be measured from inside the app.',
                ),
                const SizedBox(height: AppSpacing.sm),
                const _StorageNotice(
                  key: ValueKey('storage-installed-app-notice'),
                  icon: Icons.apps_outlined,
                  title: 'Installed app size is separate',
                  message:
                      'The Raze Store app binary, bundled background-removal model, operating-system support files, and native library data are not included. Your phone’s system Storage settings show the complete installed size.',
                ),
                const SizedBox(height: AppSpacing.sm),
                const _StorageNotice(
                  key: ValueKey('storage-external-files-notice'),
                  icon: Icons.photo_library_outlined,
                  title: 'Saved copies are outside this total',
                  message:
                      'Receipt PNGs, backups, and CSV files saved through Files are stored outside Raze Store. Copies kept by apps you share with are external too. Only temporary receipt working copies still in this app’s cache are counted above.',
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearTemporaryFiles() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear temporary files?'),
        content: const Text(
          'Raze Store will remove rebuildable cache, background-removal working files, and temporary receipt copies. Products, sales, product images, the database, and exported files will stay untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('storage-confirm-clear-temporary'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear temporary files'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingTemporaryFiles = true);
    try {
      final result = await ref
          .read(appStorageServiceProvider)
          .clearTemporaryFiles();
      if (!mounted) return;
      ref.invalidate(appStorageUsageProvider);
      final message = switch ((result.clearedBytes, result.failureCount)) {
        (0, 0) => 'Temporary storage is already clear.',
        (final bytes, 0) =>
          'Cleared ${formatStorageBytes(bytes)} from temporary storage.',
        (final bytes, final failures) =>
          'Cleared ${formatStorageBytes(bytes)}. $failures ${failures == 1 ? 'entry could' : 'entries could'} not be fully cleared.',
      };
      _showMessage(message);
    } catch (_) {
      if (mounted) {
        _showMessage('Could not clear temporary files. Try again.');
      }
    } finally {
      if (mounted) setState(() => _clearingTemporaryFiles = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ManagedStorageCard extends StatelessWidget {
  const _ManagedStorageCard({required this.usage});

  final AppStorageUsage usage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('storage-managed-summary'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: AppSize.iconBadgeLarge,
                  height: AppSize.iconBadgeLarge,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: AppRadius.control,
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.storage_rounded, color: scheme.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatStorageBytes(usage.totalManagedBytes),
                        key: const ValueKey('storage-managed-total'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Raze Store data · ${_fileCountLabel(usage.totalFileCount)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.xs),
            _StorageBreakdownRow(
              key: const ValueKey('storage-database'),
              icon: Icons.storage_outlined,
              label: 'Store database',
              value: formatStorageBytes(usage.databaseBytes),
              fileCount: usage.databaseFileCount,
            ),
            _StorageBreakdownRow(
              key: const ValueKey('storage-product-images'),
              icon: Icons.inventory_2_outlined,
              label: 'Managed product images',
              value: formatStorageBytes(usage.productImageBytes),
              fileCount: usage.productImageFileCount,
            ),
            _StorageBreakdownRow(
              key: const ValueKey('storage-temporary-receipts'),
              icon: Icons.receipt_long_outlined,
              label: 'Temporary receipt copies',
              value: formatStorageBytes(usage.temporaryReceiptBytes),
              fileCount: usage.temporaryReceiptFileCount,
            ),
            _StorageBreakdownRow(
              key: const ValueKey('storage-background-removal'),
              icon: Icons.auto_fix_high_outlined,
              label: 'Background-removal files',
              value: formatStorageBytes(usage.backgroundRemovalBytes),
              fileCount: usage.backgroundRemovalFileCount,
            ),
            _StorageBreakdownRow(
              key: const ValueKey('storage-cache'),
              icon: Icons.cached_rounded,
              label: 'Other temporary cache',
              value: formatStorageBytes(usage.cacheBytes),
              fileCount: usage.cacheFileCount,
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageBreakdownRow extends StatelessWidget {
  const _StorageBreakdownRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.fileCount,
  });

  final IconData icon;
  final String label;
  final String value;
  final int fileCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label, $value, ${_fileCountLabel(fileCount)}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.regularRow),
          child: Row(
            children: [
              Icon(icon, size: AppSize.icon, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    _fileCountLabel(fileCount),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageCleanupRow extends StatelessWidget {
  const _StorageCleanupRow({
    required this.subtitle,
    required this.clearing,
    required this.onClear,
  });

  final String subtitle;
  final bool clearing;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cleaning_services_outlined, color: scheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Temporary storage',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    final button = OutlinedButton(
      key: const ValueKey('storage-clear-temporary'),
      onPressed: clearing ? null : onClear,
      child: Text(clearing ? 'Clearing…' : 'Clear'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 340 || textScale >= 1.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: AppSpacing.sm),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: AppSpacing.sm),
            button,
          ],
        );
      },
    );
  }
}

class _StorageNotice extends StatelessWidget {
  const _StorageNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.onSecondaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatStorageBytes(int bytes) {
  final safeBytes = bytes < 0 ? 0 : bytes;
  const unit = 1024;
  if (safeBytes < unit) return '$safeBytes B';

  const labels = ['KB', 'MB', 'GB', 'TB'];
  var value = safeBytes.toDouble();
  var labelIndex = -1;
  while (value >= unit && labelIndex < labels.length - 1) {
    value /= unit;
    labelIndex += 1;
  }
  final decimals = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${labels[labelIndex]}';
}

String _fileCountLabel(int count) => '$count ${count == 1 ? 'file' : 'files'}';
