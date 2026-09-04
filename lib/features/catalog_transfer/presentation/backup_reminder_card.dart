import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/settings/application/app_storage_providers.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';

/// A device-local reminder shown only when the selected backup interval is due.
///
/// Creating a backup remains an explicit user action because the destination is
/// selected through the system file picker. No notification permission or
/// background service is needed.
class BackupReminderCard extends ConsumerStatefulWidget {
  const BackupReminderCard({super.key});

  @override
  ConsumerState<BackupReminderCard> createState() => _BackupReminderCardState();
}

class _BackupReminderCardState extends ConsumerState<BackupReminderCard> {
  bool _creating = false;
  bool _snoozing = false;

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesProvider).value;
    if (preferences == null ||
        !preferences.isBackupReminderDue(
          ref.watch(appPreferencesClockProvider)(),
        )) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        key: const ValueKey('backup-reminder-card'),
        color: scheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Time to back up your store',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: scheme.onTertiaryContainer),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Protect your products, prices, photos, settings, and sales in a .razestore file.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onTertiaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton(
                    key: const ValueKey('snooze-backup-reminder'),
                    onPressed: _creating || _snoozing ? null : _snooze,
                    child: Text(_snoozing ? 'Saving…' : 'Later'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('create-reminder-backup'),
                    onPressed: _creating || _snoozing ? null : _createBackup,
                    icon: _creating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined),
                    label: Text(_creating ? 'Creating…' : 'Back up now'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snooze() async {
    setState(() => _snoozing = true);
    try {
      await ref.read(appPreferencesProvider.notifier).snoozeBackupReminder();
      if (mounted) setState(() => _snoozing = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _snoozing = false);
      _showMessage('Could not postpone the backup reminder.', isFailure: true);
    }
  }

  Future<void> _createBackup() async {
    setState(() => _creating = true);
    final result = await ref
        .read(catalogTransferCoordinatorProvider)
        .createBackup();
    if (result is CatalogTransferSuccess &&
        result.action == CatalogTransferAction.backupExport) {
      try {
        await ref.read(appPreferencesProvider.notifier).markBackupCompleted();
      } catch (_) {
        // The file is already safe in the user's chosen location. A failed
        // timestamp write may make the reminder appear again, but must not
        // misreport a successful backup as a failed file operation.
      }
    }
    ref.invalidate(appStorageUsageProvider);
    if (!mounted) return;
    setState(() => _creating = false);
    _showMessage(result.message, isFailure: result is CatalogTransferFailure);
  }

  void _showMessage(String message, {required bool isFailure}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isFailure
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
  }
}
