import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_pack_review.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_pack_review_screen.dart';
import 'package:raze_store/features/settings/application/app_storage_providers.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';

enum _TransferAction {
  catalogPack,
  catalogPackUndo,
  backup,
  restore,
  exportCsv,
  importCsv,
}

final class CatalogDataSection extends ConsumerStatefulWidget {
  const CatalogDataSection({super.key});

  @override
  ConsumerState<CatalogDataSection> createState() => _CatalogDataSectionState();
}

final class _CatalogDataSectionState extends ConsumerState<CatalogDataSection> {
  _TransferAction? _busyAction;

  bool get _busy => _busyAction != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final undoSummary = ref.watch(catalogPackUndoSummaryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) ...[
          Semantics(
            liveRegion: true,
            label: 'Catalog file operation in progress',
            child: const LinearProgressIndicator(minHeight: 3),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        AppExpansionCard(
          key: const ValueKey('catalog-pack-expansion'),
          icon: Icons.inventory_2_outlined,
          title: 'Offline catalog pack',
          subtitle: 'Review trusted .razepack products before importing',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Open a .razepack, review New and Existing products separately, then check only the products and details you trust. Nothing is added while you review. Existing non-zero prices, your photos, sub-unit prices, receipt settings, and sales are protected.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Each official starter pack includes full attribution for its DTI, Open Food Facts, and dated retailer price sources.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.icon(
                key: const ValueKey('import-catalog-pack'),
                onPressed: _busy ? null : _confirmCatalogPackImport,
                icon: _actionIcon(
                  _TransferAction.catalogPack,
                  Icons.inventory_2_outlined,
                ),
                label: Text(
                  _busyAction == _TransferAction.catalogPack
                      ? 'Checking pack…'
                      : 'Choose and review catalog pack',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              undoSummary.when(
                loading: () => const SizedBox(
                  height: 38,
                  child: Center(child: LinearProgressIndicator()),
                ),
                error: (error, stackTrace) => Text(
                  'Undo status could not be checked.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
                data: (undo) {
                  if (undo == null) {
                    return Text(
                      'No reviewed catalog import is available to undo.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                  }
                  return OutlinedButton.icon(
                    key: const ValueKey('undo-catalog-pack-import'),
                    onPressed: _busy ? null : () => _confirmUndo(undo),
                    icon: _actionIcon(
                      _TransferAction.catalogPackUndo,
                      Icons.undo_rounded,
                    ),
                    label: Text(
                      _busyAction == _TransferAction.catalogPackUndo
                          ? 'Restoring…'
                          : 'Undo last import (${undo.changedProductCount})',
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppExpansionCard(
          key: const ValueKey('complete-backup-expansion'),
          icon: Icons.health_and_safety_outlined,
          title: 'Complete backup',
          subtitle: 'Save or restore products, photos, settings, and sales',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Includes products, main and sub-unit prices, photos, completed sales history, receipt details, categories, and appearance.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: AppRadius.control,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_open_rounded,
                      size: 19,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Backup files are not encrypted. They contain prices, completed transactions and payment amounts, store details, and copies of product photos, so keep them private.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ResponsiveButtons(
                primary: FilledButton.icon(
                  onPressed: _busy ? null : _createBackup,
                  icon: _actionIcon(
                    _TransferAction.backup,
                    Icons.file_download_outlined,
                  ),
                  label: Text(
                    _busyAction == _TransferAction.backup
                        ? 'Creating…'
                        : 'Create backup',
                  ),
                ),
                secondary: OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmRestore,
                  icon: _actionIcon(
                    _TransferAction.restore,
                    Icons.restore_rounded,
                  ),
                  label: Text(
                    _busyAction == _TransferAction.restore
                        ? 'Restoring…'
                        : 'Restore backup',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppExpansionCard(
          key: const ValueKey('csv-tools-expansion'),
          icon: Icons.table_view_outlined,
          title: 'CSV spreadsheet',
          subtitle: 'Edit catalog fields and prices in a spreadsheet',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CSV contains catalog fields and prices, not photos or settings. Import adds or updates rows and never deletes missing products.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ResponsiveButtons(
                primary: OutlinedButton.icon(
                  onPressed: _busy ? null : _exportCsv,
                  icon: _actionIcon(
                    _TransferAction.exportCsv,
                    Icons.table_view_outlined,
                  ),
                  label: Text(
                    _busyAction == _TransferAction.exportCsv
                        ? 'Exporting…'
                        : 'Export CSV',
                  ),
                ),
                secondary: OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmCsvImport,
                  icon: _actionIcon(
                    _TransferAction.importCsv,
                    Icons.upload_file_outlined,
                  ),
                  label: Text(
                    _busyAction == _TransferAction.importCsv
                        ? 'Importing…'
                        : 'Import CSV',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionIcon(_TransferAction action, IconData idleIcon) {
    if (_busyAction != action) return Icon(idleIcon);
    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Future<void> _createBackup() =>
      _run(_TransferAction.backup, (operations) => operations.createBackup());

  Future<void> _exportCsv() =>
      _run(_TransferAction.exportCsv, (operations) => operations.exportCsv());

  Future<void> _confirmCatalogPackImport() async {
    setState(() => _busyAction = _TransferAction.catalogPack);
    final operations = ref.read(catalogPackReviewCoordinatorProvider);
    final choice = await operations.chooseCatalogPackForReview();
    if (!mounted) return;
    setState(() => _busyAction = null);
    if (choice case CatalogPackReviewNotReady(:final result)) {
      _showResult(result);
      return;
    }
    final review = (choice as CatalogPackReviewReady).review;
    final result = await Navigator.of(context).push<CatalogTransferResult>(
      MaterialPageRoute(
        builder: (context) => CatalogPackReviewScreen(
          review: review,
          onApply: (selection) =>
              operations.applyCatalogPackReview(review, selection),
          onDiscard: () => operations.discardCatalogPackReview(review),
        ),
      ),
    );
    if (!mounted || result == null) return;
    ref.invalidate(appStorageUsageProvider);
    ref.invalidate(catalogPackUndoSummaryProvider);
    _showResult(result);
  }

  Future<void> _confirmUndo(CatalogPackUndoSummary undo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Undo last catalog import?'),
        content: Text(
          'This removes ${undo.createdCount} products added by the pack and restores ${undo.updatedCount} products to their earlier catalog details. Completed sales stay unchanged. If any affected product was edited after import, undo stops without changing anything.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Undo import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyAction = _TransferAction.catalogPackUndo);
    final result = await ref
        .read(catalogPackReviewCoordinatorProvider)
        .undoLastCatalogImport();
    if (!mounted) return;
    ref.invalidate(appStorageUsageProvider);
    ref.invalidate(catalogPackUndoSummaryProvider);
    setState(() => _busyAction = null);
    _showResult(result);
  }

  Future<void> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Replace local store data?'),
        content: const Text(
          'Restore replaces all products, prices, sub-units, product photos, completed sales history, and store receipt details on this phone. It also clears the unfinished cart. An older backup that has no sales will replace the current history with an empty history.\n\nCreate a current backup first if you may need to undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose backup and replace'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      _TransferAction.restore,
      (operations) => operations.restoreBackupReplacing(),
    );
  }

  Future<void> _confirmCsvImport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Import product CSV?'),
        content: const Text(
          'Products are matched by product ID, then barcode. Matching products and their sub-unit prices are updated; new products are added. Products missing from the CSV are kept.\n\nThe whole file is validated first, so an invalid row changes nothing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose CSV and import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      _TransferAction.importCsv,
      (operations) => operations.importCsvMerging(),
    );
  }

  Future<void> _run(
    _TransferAction action,
    Future<CatalogTransferResult> Function(CatalogTransferOperations) operation,
  ) async {
    setState(() => _busyAction = action);
    final result = await operation(
      ref.read(catalogTransferCoordinatorProvider),
    );
    if (result is CatalogTransferSuccess &&
        result.action == CatalogTransferAction.backupExport) {
      try {
        await ref.read(appPreferencesProvider.notifier).markBackupCompleted();
      } catch (_) {
        // The exported file is already safe. A reminder timestamp failure
        // should not replace the useful transfer result shown to the user.
      }
    }
    if (!mounted) return;
    ref.invalidate(appStorageUsageProvider);
    setState(() => _busyAction = null);
    _showResult(result);
  }

  void _showResult(CatalogTransferResult result) {
    final isFailure = result is CatalogTransferFailure;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: isFailure
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
  }
}

final class _ResponsiveButtons extends StatelessWidget {
  const _ResponsiveButtons({required this.primary, required this.secondary});

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: AppSpacing.xs),
              secondary,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: secondary),
          ],
        );
      },
    );
  }
}
