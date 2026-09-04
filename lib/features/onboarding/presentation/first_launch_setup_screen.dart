import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_coordinator.dart';
import 'package:raze_store/features/catalog_transfer/application/catalog_transfer_providers.dart';
import 'package:raze_store/features/catalog_transfer/domain/catalog_transfer_result.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_pack_review_screen.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

import '../application/onboarding_providers.dart';

class FirstLaunchSetupScreen extends ConsumerStatefulWidget {
  const FirstLaunchSetupScreen({super.key});

  @override
  ConsumerState<FirstLaunchSetupScreen> createState() =>
      _FirstLaunchSetupScreenState();
}

class _FirstLaunchSetupScreenState
    extends ConsumerState<FirstLaunchSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _storeNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _contactController;
  StoreProfile _existingProfile = StoreProfile.defaults;
  bool _loadingProfile = true;
  bool _savingProfile = false;
  bool _profileSaved = false;
  bool _transferringCatalog = false;

  @override
  void initState() {
    super.initState();
    _storeNameController = TextEditingController();
    _addressController = TextEditingController();
    _contactController = TextEditingController();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completing = ref.watch(onboardingControllerProvider).isLoading;
    final width = MediaQuery.sizeOf(context).width;

    return AppPageScaffold(
      padBody: false,
      body: _loadingProfile
          ? const AppLoadingState(message: 'Preparing store setup…')
          : ListView(
              padding: AppSpacing.pageInsetsFor(width),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppBreakpoints.readingMaxWidth,
                    ),
                    child: AnimatedSwitcher(
                      duration: AppDurations.standard,
                      child: _profileSaved
                          ? _SetupReady(
                              key: const ValueKey('setup-ready'),
                              storeName: _storeNameController.text.trim(),
                              busy: completing || _transferringCatalog,
                              onCatalogPack: _handleCatalogPackImport,
                              onQuickAdd: () => _finishSetup(
                                '/products/quick-add?fromSetup=true',
                              ),
                              onImportOrRestore: _handleImportOrRestore,
                              onContinue: () => _finishSetup('/products'),
                              onEdit: () {
                                setState(() => _profileSaved = false);
                              },
                            )
                          : _StoreDetailsForm(
                              key: const ValueKey('store-details'),
                              formKey: _formKey,
                              storeNameController: _storeNameController,
                              addressController: _addressController,
                              contactController: _contactController,
                              busy: _savingProfile,
                              onSave: _saveProfile,
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ref
          .read(settingsRepositoryProvider)
          .getStoreProfile();
      if (!mounted) return;
      _existingProfile = profile;
      final hasSavedIdentity =
          profile.storeName != StoreProfile.defaults.storeName ||
          profile.address.trim().isNotEmpty ||
          profile.contact.trim().isNotEmpty;
      if (hasSavedIdentity) {
        _storeNameController.text = profile.storeName;
        _addressController.text = profile.address;
        _contactController.text = profile.contact;
      }
    } catch (_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Existing store details could not be loaded.'),
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _savingProfile = true);

    final profile = _existingProfile.copyWith(
      storeName: _storeNameController.text.trim(),
      address: _addressController.text.trim(),
      contact: _contactController.text.trim(),
    );
    try {
      await ref.read(settingsRepositoryProvider).saveStoreProfile(profile);
      if (!mounted) return;
      setState(() {
        _existingProfile = profile;
        _savingProfile = false;
        _profileSaved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your store details.')),
      );
    }
  }

  Future<void> _finishSetup(String destination) async {
    final complete = await ref
        .read(onboardingControllerProvider.notifier)
        .completeStoreSetup();
    if (!mounted) return;
    if (complete) {
      context.go(destination);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store setup could not be completed. Try again.'),
        ),
      );
    }
  }

  Future<void> _handleImportOrRestore() async {
    final action = await showModalBottomSheet<_SetupCatalogAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('setup-import-restore-sheet-scroll'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.restore_rounded),
                title: const Text('Restore complete backup'),
                subtitle: const Text(
                  'Replace this setup with products, photos, and store details from a .razestore file.',
                ),
                onTap: () =>
                    Navigator.pop(context, _SetupCatalogAction.restoreBackup),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Import product CSV'),
                subtitle: const Text(
                  'Add or update product details and prices from a spreadsheet.',
                ),
                onTap: () =>
                    Navigator.pop(context, _SetupCatalogAction.importCsv),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == _SetupCatalogAction.restoreBackup) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: const Text(
            'The backup will replace the store details you just entered, along with all local products and photos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choose backup'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    await _runSetupCatalogAction(action);
  }

  Future<void> _handleCatalogPackImport() async {
    setState(() => _transferringCatalog = true);
    final operations = ref.read(catalogPackReviewCoordinatorProvider);
    final choice = await operations.chooseCatalogPackForReview();
    if (!mounted) return;
    setState(() => _transferringCatalog = false);
    if (choice case CatalogPackReviewNotReady(:final result)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
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
    await _finishAfterTransfer(result);
  }

  Future<void> _runSetupCatalogAction(_SetupCatalogAction action) async {
    setState(() => _transferringCatalog = true);
    final operations = ref.read(catalogTransferCoordinatorProvider);
    final result = switch (action) {
      _SetupCatalogAction.restoreBackup =>
        await operations.restoreBackupReplacing(),
      _SetupCatalogAction.importCsv => await operations.importCsvMerging(),
    };
    if (!mounted) return;
    setState(() => _transferringCatalog = false);
    await _finishAfterTransfer(result);
  }

  Future<void> _finishAfterTransfer(CatalogTransferResult result) async {
    if (result is! CatalogTransferSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }

    final complete = await ref
        .read(onboardingControllerProvider.notifier)
        .completeStoreSetup();
    if (!mounted) return;
    if (complete) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      context.go('/products');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Store setup could not be completed. Try again.'),
        ),
      );
    }
  }
}

enum _SetupCatalogAction { restoreBackup, importCsv }

class _StoreDetailsForm extends StatelessWidget {
  const _StoreDetailsForm({
    super.key,
    required this.formKey,
    required this.storeNameController,
    required this.addressController,
    required this.contactController,
    required this.busy,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController storeNameController;
  final TextEditingController addressController;
  final TextEditingController contactController;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Align(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.storefront_rounded,
              size: 40,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Set up your sari-sari store',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'These details appear on receipts. Everything stays on this phone and works offline.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const ValueKey('setup-store-name'),
                    controller: storeNameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Store name',
                      hintText: 'Aling Nena Sari-sari Store',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Enter your store name.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const ValueKey('setup-address'),
                    controller: addressController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const ValueKey('setup-contact'),
                    controller: contactController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => busy ? null : onSave(),
                    decoration: const InputDecoration(
                      labelText: 'Contact number (optional)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    key: const ValueKey('save-store-setup'),
                    onPressed: busy ? null : onSave,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(busy ? 'Saving…' : 'Save and continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SetupReady extends StatelessWidget {
  const _SetupReady({
    super.key,
    required this.storeName,
    required this.busy,
    required this.onCatalogPack,
    required this.onQuickAdd,
    required this.onImportOrRestore,
    required this.onContinue,
    required this.onEdit,
  });

  final String storeName;
  final bool busy;
  final VoidCallback onCatalogPack;
  final VoidCallback onQuickAdd;
  final VoidCallback onImportOrRestore;
  final VoidCallback onContinue;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Align(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.check_rounded,
              size: 44,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '$storeName is ready',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'How would you like to build the product list?',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          key: const ValueKey('setup-import-catalog-pack'),
          onPressed: busy ? null : onCatalogPack,
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('Import offline catalog pack'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Recommended: add ready-made Filipino products and bundled images from a trusted .razepack file.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          key: const ValueKey('setup-quick-add'),
          onPressed: busy ? null : onQuickAdd,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Add first product'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const ValueKey('setup-import-restore'),
          onPressed: busy ? null : onImportOrRestore,
          icon: const Icon(Icons.settings_backup_restore_rounded),
          label: const Text('Restore backup or import CSV'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          key: const ValueKey('setup-continue'),
          onPressed: busy ? null : onContinue,
          child: const Text('Continue to product list'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton.icon(
          onPressed: busy ? null : onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit store details'),
        ),
      ],
    );
  }
}
