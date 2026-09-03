import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/app/theme_mode_controller.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog/application/custom_catalog_categories_controller.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_data_section.dart';
import 'package:raze_store/features/settings/application/app_storage_providers.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';
import 'package:raze_store/features/settings/presentation/storage_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(storeProfileProvider)
        .when(
          loading: () => const AppPageScaffold(
            title: 'Store settings',
            leading: _SettingsBackButton(),
            body: AppLoadingState(message: 'Loading store details…'),
          ),
          error: (error, _) => AppPageScaffold(
            title: 'Store settings',
            leading: const _SettingsBackButton(),
            body: AppErrorState(
              message: 'The store details could not be loaded.',
              onRetry: () => ref.invalidate(storeProfileProvider),
            ),
          ),
          data: (profile) => _SettingsEditor(
            key: ValueKey(
              '${profile.storeName}|${profile.address}|${profile.contact}|${profile.receiptFooter}',
            ),
            profile: profile,
          ),
        );
  }
}

class _SettingsEditor extends ConsumerStatefulWidget {
  const _SettingsEditor({super.key, required this.profile});

  final StoreProfile profile;

  @override
  ConsumerState<_SettingsEditor> createState() => _SettingsEditorState();
}

class _SettingsEditorState extends ConsumerState<_SettingsEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _contactController;
  late final TextEditingController _footerController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.storeName);
    _addressController = TextEditingController(text: widget.profile.address);
    _contactController = TextEditingController(text: widget.profile.contact);
    _footerController = TextEditingController(
      text: widget.profile.receiptFooter,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final customCategoryCount = ref
        .watch(customCatalogCategoriesProvider)
        .length;
    final storageUsage = ref.watch(appStorageUsageProvider);

    return AppPageScaffold(
      title: 'Store settings',
      leading: const _SettingsBackButton(),
      padBody: false,
      body: ListView(
        padding: AppSpacing.pageInsetsFor(MediaQuery.sizeOf(context).width),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.readingMaxWidth,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSectionHeader(
                      title: 'Receipt details',
                      subtitle:
                          'These details appear on receipt images you save or send.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Store name',
                                prefixIcon: Icon(Icons.storefront_outlined),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Enter the store name.'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _addressController,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Address (optional)',
                                prefixIcon: Icon(Icons.location_on_outlined),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _contactController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Contact (optional)',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _footerController,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Receipt message',
                                hintText: 'Salamat po!',
                                prefixIcon: Icon(
                                  Icons.favorite_outline_rounded,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.icon(
                              onPressed: _saving ? null : _saveProfile,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(
                                _saving ? 'Saving…' : 'Save receipt details',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Product categories',
                      subtitle:
                          'Choose broad shelf groups and add your own categories.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: const ValueKey('manage-product-categories'),
                        dense: true,
                        leading: const Icon(Icons.category_outlined),
                        title: const Text('Manage categories'),
                        subtitle: Text(
                          customCategoryCount == 0
                              ? 'Built-in categories only'
                              : '$customCategoryCount custom ${customCategoryCount == 1 ? 'category' : 'categories'}',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/settings/categories'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Storage',
                      subtitle:
                          'See what is using space and safely clear temporary files.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        key: const ValueKey('manage-app-storage'),
                        dense: true,
                        leading: const Icon(Icons.storage_rounded),
                        title: const Text('Storage manager'),
                        subtitle: Text(
                          storageUsage.when(
                            data: (usage) =>
                                '${formatStorageBytes(usage.totalManagedBytes)} measured local data',
                            loading: () => 'Measuring local data…',
                            error: (error, stackTrace) =>
                                'View storage details',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _openStorageManager,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Appearance',
                      subtitle: 'Use the phone setting or choose a theme.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.settings_brightness_outlined),
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark'),
                            ),
                          ],
                          selected: {themeMode},
                          onSelectionChanged: (selection) {
                            ref
                                .read(themeModeProvider.notifier)
                                .setMode(selection.single);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Catalog files',
                      subtitle:
                          'Install offline products, protect local prices, or edit products in a spreadsheet.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const CatalogDataSection(),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveStoreProfile(
            StoreProfile(
              storeName: _nameController.text,
              address: _addressController.text,
              contact: _contactController.text,
              receiptFooter: _footerController.text,
            ),
          );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt details saved.')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the store details.')),
      );
    }
  }

  Future<void> _openStorageManager() async {
    ref.invalidate(appStorageUsageProvider);
    await context.push('/settings/storage');
    if (!mounted) return;
    ref.invalidate(appStorageUsageProvider);
  }
}

class _SettingsBackButton extends StatelessWidget {
  const _SettingsBackButton();

  @override
  Widget build(BuildContext context) {
    return BackButton(
      onPressed: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          context.go('/products');
        }
      },
    );
  }
}
