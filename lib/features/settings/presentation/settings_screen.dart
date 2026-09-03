import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/app/theme_mode_controller.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog/application/catalog_api_providers.dart';
import 'package:raze_store/features/catalog_transfer/presentation/catalog_data_section.dart';
import 'package:raze_store/features/settings/application/settings_providers.dart';
import 'package:raze_store/features/settings/domain/store_profile.dart';

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
                          'Protect your local prices or edit products in a spreadsheet.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const CatalogDataSection(),
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Catalog connection',
                      subtitle:
                          'Shared product details from raze_store_api; your prices stay on this phone.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _CatalogConnectionCard(),
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
}

class _CatalogConnectionCard extends ConsumerStatefulWidget {
  const _CatalogConnectionCard();

  @override
  ConsumerState<_CatalogConnectionCard> createState() =>
      _CatalogConnectionCardState();
}

class _CatalogConnectionCardState
    extends ConsumerState<_CatalogConnectionCard> {
  bool _checking = false;
  bool? _connected;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(remoteCatalogRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final configured = repository.isConfigured;
    final connected = _connected;
    final icon = connected == true
        ? Icons.cloud_done_outlined
        : configured
        ? Icons.cloud_outlined
        : Icons.cloud_off_outlined;
    final message = !configured
        ? repository.configurationError ??
              'No catalog endpoint was included in this release build.'
        : connected == true
        ? 'Connected to the shared Philippine product catalog.'
        : connected == false
        ? 'The endpoint could not be reached. Saved products remain available offline.'
        : 'Ready to look up shared products at ${repository.baseUri}';

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.onSecondaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (configured) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                key: const ValueKey('test-catalog-connection'),
                onPressed: _checking ? null : _testConnection,
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: Text(_checking ? 'Checking…' : 'Test connection'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() => _checking = true);
    try {
      await ref.read(remoteCatalogRepositoryProvider).checkHealth();
      if (mounted) setState(() => _connected = true);
    } on Object {
      if (mounted) setState(() => _connected = false);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
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
