import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/barcode/barcode.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/core/storage/product_photo_services.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';

class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({super.key, this.productId, this.initialBarcode});

  final String? productId;
  final String? initialBarcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = productId;
    if (id == null) {
      return _ProductEditor(initialBarcode: initialBarcode);
    }

    return ref
        .watch(catalogProductProvider(id))
        .when(
          loading: () => const AppPageScaffold(
            title: 'Edit product',
            body: AppLoadingState(message: 'Loading product…'),
          ),
          error: (error, _) => AppPageScaffold(
            title: 'Edit product',
            body: AppErrorState(
              message: 'This product could not be loaded.',
              onRetry: () => ref.invalidate(catalogProductProvider(id)),
            ),
          ),
          data: (product) => product == null
              ? const AppPageScaffold(
                  title: 'Edit product',
                  body: AppEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Product not found',
                    message: 'It may already have been deleted.',
                  ),
                )
              : _ProductEditor(key: ValueKey(product.id), product: product),
        );
  }
}

class _ProductEditor extends ConsumerStatefulWidget {
  const _ProductEditor({super.key, this.product, this.initialBarcode});

  final StoreProduct? product;
  final String? initialBarcode;

  @override
  ConsumerState<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<_ProductEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _unitController;
  late final TextEditingController _categoryController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _priceController;
  XFile? _pendingPhoto;
  bool _removeExistingPhoto = false;
  bool _busy = false;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(text: product?.name ?? '');
    _brandController = TextEditingController(text: product?.brand ?? '');
    _unitController = TextEditingController(text: product?.unitLabel ?? '');
    _categoryController = TextEditingController(text: product?.category ?? '');
    _barcodeController = TextEditingController(
      text: product?.barcode ?? widget.initialBarcode ?? '',
    );
    _priceController = TextEditingController(
      text: product == null
          ? ''
          : (product.priceCentavos / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _unitController.dispose();
    _categoryController.dispose();
    _barcodeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AppPageScaffold(
      title: _editing ? 'Edit product' : 'Add product',
      leading: const BackButton(),
      padBody: false,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_busy ? 'Saving…' : 'Save product'),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ResponsiveContent(
          maxWidth: AppBreakpoints.readingMaxWidth,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSectionHeader(
                  title: 'Product photo',
                  subtitle: 'Optional, but helpful for family members.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _PhotoEditor(
                  product: widget.product,
                  pendingPhoto: _pendingPhoto,
                  removeExisting: _removeExistingPhoto,
                  busy: _busy,
                  onChoose: _choosePhotoSource,
                  onRemove: () {
                    setState(() {
                      _pendingPhoto = null;
                      _removeExistingPhoto = true;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(
                  title: 'Product details',
                  subtitle: 'Only the name and selling price are required.',
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Product name',
                    hintText: 'e.g. Instant noodles',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the product name.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _brandController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Brand'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _unitController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Size / unit',
                          hintText: '55 g, 1 L, piece',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _categoryController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    hintText: 'Snacks, Drinks, Household…',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppSectionHeader(
                  title: 'Price and barcode',
                  subtitle:
                      'The selling price belongs to this store and stays on this device.',
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Selling price',
                    prefixText: '₱ ',
                    prefixIcon: Icon(Icons.sell_outlined),
                  ),
                  validator: (value) {
                    final centavos = tryParsePesoCentavos(value ?? '');
                    if (centavos == null || centavos <= 0) {
                      return 'Enter a selling price greater than zero.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _barcodeController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                    hintText: 'Scan or type the code',
                    prefixIcon: Icon(Icons.barcode_reader),
                    helperText: 'Leave blank for loose or repacked products.',
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) return null;
                    return Barcode.tryParse(trimmed) == null
                        ? 'Enter a valid barcode.'
                        : null;
                  },
                ),
                if (_editing) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete product'),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ref.read(productPhotoPickerProvider);
      final picked = source == ImageSource.camera
          ? await picker.takePhoto()
          : await picker.pickFromGallery();
      if (!mounted || picked == null) return;
      setState(() {
        _pendingPhoto = picked;
        _removeExistingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the product photo.')),
      );
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    String? savedPhotoPath;
    try {
      final oldPhotoPath = widget.product?.localImagePath;
      if (_pendingPhoto != null) {
        savedPhotoPath = await ref
            .read(localProductImageStoreProvider)
            .persist(source: _pendingPhoto!);
      }
      final localImagePath =
          savedPhotoPath ?? (_removeExistingPhoto ? null : oldPhotoPath);
      final existing = widget.product;
      final draft = ProductDraft(
        id: existing?.id,
        barcode: _barcodeController.text,
        name: _nameController.text,
        brand: _brandController.text,
        unitLabel: _unitController.text,
        category: _categoryController.text,
        remoteImageUrl: existing?.remoteImageUrl,
        source: existing?.metadata.source,
        sourceProductId: existing?.metadata.sourceProductId,
        localImagePath: localImagePath,
        priceCentavos: tryParsePesoCentavos(_priceController.text)!,
      );
      final repository = ref.read(catalogRepositoryProvider);
      if (existing == null) {
        await repository.createProduct(draft);
      } else {
        await repository.updateProduct(existing.id, draft);
      }
      if ((savedPhotoPath != null || _removeExistingPhoto) &&
          oldPhotoPath != null &&
          oldPhotoPath != localImagePath) {
        try {
          await ref
              .read(localProductImageStoreProvider)
              .deleteIfManaged(oldPhotoPath);
        } catch (_) {
          // The database save is already complete. A stale local photo is
          // preferable to reporting that the product failed to save.
        }
      }
      if (!mounted) return;
      context.pop(true);
    } on DuplicateBarcodeException catch (error) {
      if (savedPhotoPath != null) {
        await ref
            .read(localProductImageStoreProvider)
            .deleteIfManaged(savedPhotoPath);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barcode ${error.barcode} is already in your store.'),
        ),
      );
    } catch (_) {
      if (savedPhotoPath != null) {
        await ref
            .read(localProductImageStoreProvider)
            .deleteIfManaged(savedPhotoPath);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this product.')),
      );
    }
  }

  Future<void> _delete() async {
    final product = widget.product!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this product?'),
        content: Text(
          '${product.name} will disappear from search and scanning. An existing cart keeps its current receipt snapshot until you remove or clear it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(catalogRepositoryProvider).deleteProduct(product.id);
      try {
        await ref
            .read(localProductImageStoreProvider)
            .deleteIfManaged(product.localImagePath);
      } catch (_) {
        // Product deletion succeeded; media cleanup is best effort.
      }
      if (!mounted) return;
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this product.')),
      );
    }
  }
}

class _PhotoEditor extends StatelessWidget {
  const _PhotoEditor({
    required this.product,
    required this.pendingPhoto,
    required this.removeExisting,
    required this.busy,
    required this.onChoose,
    required this.onRemove,
  });

  final StoreProduct? product;
  final XFile? pendingPhoto;
  final bool removeExisting;
  final bool busy;
  final VoidCallback onChoose;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final existingPath = removeExisting ? null : product?.localImagePath;
    final hasPhoto = pendingPhoto != null || existingPath != null;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadius.card,
              child: pendingPhoto != null
                  ? Image.file(
                      File(pendingPhoto!.path),
                      width: 104,
                      height: 104,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ProductImagePlaceholder(
                        width: 104,
                        height: 104,
                      ),
                    )
                  : existingPath != null
                  ? Image.file(
                      File(existingPath),
                      width: 104,
                      height: 104,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ProductImagePlaceholder(
                        width: 104,
                        height: 104,
                      ),
                    )
                  : const ProductImagePlaceholder(width: 104, height: 104),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : onChoose,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(hasPhoto ? 'Change photo' : 'Add photo'),
                  ),
                  if (hasPhoto)
                    TextButton.icon(
                      onPressed: busy ? null : onRemove,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove'),
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
