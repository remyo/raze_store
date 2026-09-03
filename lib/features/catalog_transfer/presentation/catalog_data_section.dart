import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';

enum _TransferAction { catalogPack, backup, restore, exportCsv, importCsv }

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: AppRadius.control,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.folder_copy_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Catalog, backup & spreadsheet tools',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Start from an offline product pack, keep a complete backup, or move prices with CSV.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: AppSpacing.md),
              Semantics(
                liveRegion: true,
                label: 'Catalog file operation in progress',
                child: const LinearProgressIndicator(minHeight: 3),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              'Offline catalog pack',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Import a .razepack file to add ready-made Filipino products and bundled images. Your product details, selling prices, selling units, store photos, receipt settings, and cart are preserved.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Raze starter-pack data is credited to Open Food Facts contributors (ODbL/DbCL; images CC BY-SA 3.0). Each official pack includes its full attribution and dated price sources.',
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
                    ? 'Importing…'
                    : 'Import catalog pack',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Complete backup',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Includes products, main and sub-unit prices, photos, receipt details, and appearance.',
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
                      'Backup files are not encrypted. They contain prices, store details, and copies of product photos, so keep them private.',
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
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            Text(
              'CSV spreadsheet',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Import offline catalog pack?'),
        content: const Text(
          'New products and their bundled images will be added to this phone. Matching products keep their details, selling prices, selling units, and store photos; a missing bundled catalog image may be installed. Store details and the unfinished cart are also kept.\n\nOnly import a .razepack from a source you trust.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose pack and import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      _TransferAction.catalogPack,
      (operations) => operations.importCatalogPackMerging(),
    );
  }

  Future<void> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Replace this catalog?'),
        content: const Text(
          'Restore replaces all products, prices, sub-units, product photos, and store receipt details on this phone. It also clears the unfinished cart.\n\nCreate a current backup first if you may need to undo this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose file and replace'),
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
    if (!mounted) return;
    setState(() => _busyAction = null);
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
