import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/application/custom_catalog_categories_controller.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';

class CatalogCategorySettingsScreen extends ConsumerWidget {
  const CatalogCategorySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customCategories = ref.watch(customCatalogCategoriesProvider);
    final usedCategories = ref
        .watch(catalogStoredCategoriesProvider)
        .when(
          data: (categories) => categories,
          error: (_, _) => null,
          loading: () => null,
        );
    final atLimit = customCategories.length >= maxCustomCatalogCategories;

    return AppPageScaffold(
      title: 'Product categories',
      leading: BackButton(
        onPressed: () {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          } else {
            context.go('/settings');
          }
        },
      ),
      actions: [
        IconButton(
          key: const ValueKey('add-custom-category'),
          tooltip: atLimit ? 'Custom category limit reached' : 'Add category',
          onPressed: atLimit ? null : () => _addCategory(context, ref),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
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
                  Text(
                    'Use broad shelf groups so products stay easy to find. '
                    'You can also type a one-time category while editing a product.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const AppSectionHeader(
                    title: 'Built-in categories',
                    subtitle: 'Available offline and cannot be deleted.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final category in starterCatalogCategories)
                        Chip(
                          avatar: const Icon(Icons.category_outlined, size: 16),
                          label: Text(category),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppSectionHeader(
                    title: 'Custom categories',
                    subtitle:
                        '${customCategories.length} of $maxCustomCatalogCategories added',
                    action: FilledButton.tonalIcon(
                      onPressed: atLimit
                          ? null
                          : () => _addCategory(context, ref),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (customCategories.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'No custom categories yet. Add one for groups such as Mobile Load or Frozen Treats.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: customCategories.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final category = customCategories[index];
                          final usageKnown = usedCategories != null;
                          final isUsed =
                              usedCategories?.any(
                                (value) =>
                                    value.toLowerCase() ==
                                    category.toLowerCase(),
                              ) ??
                              false;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.label_outline_rounded),
                            title: Text(category),
                            subtitle: isUsed
                                ? const Text('Used by a saved product')
                                : null,
                            trailing: IconButton(
                              key: ValueKey('delete-category-$category'),
                              tooltip: !usageKnown
                                  ? 'Checking saved products'
                                  : isUsed
                                  ? 'Move products first'
                                  : 'Delete category',
                              onPressed: usageKnown
                                  ? () => _deleteCategory(
                                      context,
                                      ref,
                                      category,
                                      isUsed: isUsed,
                                    )
                                  : null,
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final category = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCategoryDialog(),
    );
    if (category == null || !context.mounted) return;

    try {
      await ref
          .read(customCatalogCategoriesProvider.notifier)
          .addCategory(category);
      if (!context.mounted) return;
      _showMessage(context, '${normalizeCatalogCategoryName(category)} added.');
    } on CatalogCategoryException catch (error) {
      if (context.mounted) _showMessage(context, error.message);
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'Could not save the category. Try again.');
      }
    }
  }

  Future<void> _deleteCategory(
    BuildContext context,
    WidgetRef ref,
    String category, {
    required bool isUsed,
  }) async {
    if (isUsed) {
      _showMessage(
        context,
        'Move saved products out of $category before deleting it.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $category?'),
        content: const Text(
          'This removes it from future category choices. Products are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(customCatalogCategoriesProvider.notifier)
          .deleteCategory(category);
      if (context.mounted) _showMessage(context, '$category deleted.');
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, 'Could not delete the category. Try again.');
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add custom category'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('custom-category-name-field'),
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: maxCatalogCategoryNameLength,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'e.g. Mobile Load',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Enter a category name.'
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save-custom-category'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_nameController.text);
    }
  }
}
