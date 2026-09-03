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
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';

class ProductFormScreen extends ConsumerWidget {
  const ProductFormScreen({
    super.key,
    this.productId,
    this.initialBarcode,
    this.initialName,
    this.initialPrice,
    this.initialMetadata,
    this.goToProductsAfterSave = false,
  });

  final String? productId;
  final String? initialBarcode;
  final String? initialName;
  final String? initialPrice;
  final CatalogMetadata? initialMetadata;
  final bool goToProductsAfterSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = productId;
    if (id == null) {
      return _ProductEditor(
        initialBarcode: initialBarcode,
        initialName: initialName,
        initialPrice: initialPrice,
        initialMetadata: initialMetadata,
        goToProductsAfterSave: goToProductsAfterSave,
      );
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
  const _ProductEditor({
    super.key,
    this.product,
    this.initialBarcode,
    this.initialName,
    this.initialPrice,
    this.initialMetadata,
    this.goToProductsAfterSave = false,
  });

  final StoreProduct? product;
  final String? initialBarcode;
  final String? initialName;
  final String? initialPrice;
  final CatalogMetadata? initialMetadata;
  final bool goToProductsAfterSave;

  @override
  ConsumerState<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<_ProductEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _unitController;
  late final TextEditingController _categoryController;
  late final FocusNode _categoryFocusNode;
  late final TextEditingController _barcodeController;
  late final TextEditingController _priceController;
  late final List<_SellingUnitFields> _sellingUnits;
  XFile? _pendingPhoto;
  bool _removeExistingPhoto = false;
  bool _busy = false;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _nameController = TextEditingController(
      text:
          product?.name ??
          widget.initialName ??
          widget.initialMetadata?.name ??
          '',
    );
    _brandController = TextEditingController(
      text: product?.brand ?? widget.initialMetadata?.brand ?? '',
    );
    _unitController = TextEditingController(
      text: product?.unitLabel ?? widget.initialMetadata?.unitLabel ?? '',
    );
    _categoryController = TextEditingController(
      text: product?.category ?? widget.initialMetadata?.category ?? '',
    );
    _categoryFocusNode = FocusNode();
    _barcodeController = TextEditingController(
      text:
          product?.barcode ??
          widget.initialBarcode ??
          widget.initialMetadata?.barcode ??
          '',
    );
    _priceController = TextEditingController(
      text: product == null
          ? widget.initialPrice ?? ''
          : (product.priceCentavos / 100).toStringAsFixed(2),
    );
    _sellingUnits = [
      for (final unit in product?.sellingUnits ?? const <SellingUnit>[])
        _SellingUnitFields.fromUnit(unit),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _unitController.dispose();
    _categoryController.dispose();
    _categoryFocusNode.dispose();
    _barcodeController.dispose();
    _priceController.dispose();
    for (final fields in _sellingUnits) {
      fields.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final categorySuggestions = ref.watch(catalogCategorySuggestionsProvider);
    return PopScope(
      canPop: !_busy && !widget.goToProductsAfterSave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.goToProductsAfterSave && !_busy) {
          context.go('/products');
        }
      },
      child: AppPageScaffold(
        title: _editing ? 'Edit product' : 'Add product',
        leading: widget.goToProductsAfterSave
            ? IconButton(
                onPressed: _busy ? null : () => context.go('/products'),
                tooltip: 'Close product form',
                icon: const Icon(Icons.close_rounded),
              )
            : IconButton(
                onPressed: _busy ? null : () => context.pop(),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
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
                  if (!_editing && widget.initialMetadata != null) ...[
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_done_outlined),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Product details were prefilled from the shared Raze catalog. Your selling price and selling units remain local.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
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
                    key: const ValueKey('product-name-field'),
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
                          key: const ValueKey('product-main-unit-field'),
                          controller: _unitController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Main size / unit',
                            hintText: 'pack, bottle, tray',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  RawAutocomplete<String>(
                    textEditingController: _categoryController,
                    focusNode: _categoryFocusNode,
                    optionsBuilder: (value) => matchingCatalogCategories(
                      value.text,
                      categories: categorySuggestions,
                    ),
                    onSelected: (category) {
                      _categoryController.text = category;
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) =>
                        TextFormField(
                          key: const ValueKey('product-category-field'),
                          controller: controller,
                          focusNode: focusNode,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            hintText: 'Choose a suggestion or type your own',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                        ),
                    optionsViewBuilder: (context, onSelected, options) {
                      final values = options.toList(growable: false);
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          borderRadius: AppRadius.control,
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 440,
                              maxHeight: 280,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: values.length,
                              itemBuilder: (context, index) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.category_outlined),
                                title: Text(values[index]),
                                onTap: () => onSelected(values[index]),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'You can type a new category. Future API categories can be added to these suggestions.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    key: const ValueKey('product-main-price-field'),
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Main selling price',
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
                    key: const ValueKey('product-barcode-field'),
                    controller: _barcodeController,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Main product barcode (optional)',
                      hintText: 'Scan or type the code',
                      prefixIcon: Icon(Icons.barcode_reader),
                      helperText:
                          'Scan this once, then choose the main or loose selling unit.',
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) {
                        return _sellingUnits.isEmpty
                            ? null
                            : 'Add a main barcode for sub-unit prices.';
                      }
                      return Barcode.tryParse(trimmed) == null
                          ? 'Enter a valid barcode.'
                          : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const AppSectionHeader(
                    title: 'Additional selling units',
                    subtitle:
                        'Optional prices under the main barcode—for example Stick, Piece, Sachet, or Tray.',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_sellingUnits.isEmpty)
                    Card(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'No extra unit prices yet. Scanning will use only the main price.',
                        ),
                      ),
                    ),
                  for (
                    var index = 0;
                    index < _sellingUnits.length;
                    index++
                  ) ...[
                    _SellingUnitEditor(
                      key: ObjectKey(_sellingUnits[index]),
                      index: index,
                      fields: _sellingUnits[index],
                      enabled: !_busy,
                      isDuplicateLabel: _isDuplicateSellingUnitLabel,
                      onRemove: () => _removeSellingUnit(index),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _addSellingUnit,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add another selling unit'),
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
      final initialMetadata = widget.initialMetadata;
      final draft = ProductDraft(
        id: existing?.id,
        barcode: _barcodeController.text,
        name: _nameController.text,
        brand: _brandController.text,
        unitLabel: _unitController.text,
        category: _categoryController.text,
        remoteImageUrl:
            existing?.remoteImageUrl ?? initialMetadata?.remoteImageUrl,
        source: existing?.metadata.source ?? initialMetadata?.source,
        sourceProductId:
            existing?.metadata.sourceProductId ??
            initialMetadata?.sourceProductId,
        localImagePath: localImagePath,
        priceCentavos: tryParsePesoCentavos(_priceController.text)!,
        sellingUnits: [
          for (final fields in _sellingUnits)
            SellingUnitDraft(
              id: fields.id,
              label: fields.labelController.text,
              priceCentavos: tryParsePesoCentavos(fields.priceController.text)!,
            ),
        ],
      );
      final repository = ref.read(catalogRepositoryProvider);
      final StoreProduct savedProduct;
      if (existing == null) {
        savedProduct = await repository.createProduct(draft);
      } else {
        savedProduct = await repository.updateProduct(existing.id, draft);
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
      if (widget.goToProductsAfterSave) {
        context.go('/products');
      } else {
        context.pop(savedProduct);
      }
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
    } on DuplicateCatalogProductException {
      if (savedPhotoPath != null) {
        await ref
            .read(localProductImageStoreProvider)
            .deleteIfManaged(savedPhotoPath);
      }
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This shared catalog product is already in your store.',
          ),
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

  void _addSellingUnit() {
    setState(() => _sellingUnits.add(_SellingUnitFields()));
  }

  void _removeSellingUnit(int index) {
    final fields = _sellingUnits.removeAt(index);
    fields.dispose();
    setState(() {});
  }

  bool _isDuplicateSellingUnitLabel(_SellingUnitFields current, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized ==
        effectiveMainSellingUnitLabel(_unitController.text).toLowerCase()) {
      return true;
    }
    return _sellingUnits.any(
      (fields) =>
          !identical(fields, current) &&
          fields.labelController.text.trim().toLowerCase() == normalized,
    );
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

class _SellingUnitFields {
  _SellingUnitFields({this.id, String label = '', String price = ''})
    : labelController = TextEditingController(text: label),
      priceController = TextEditingController(text: price);

  factory _SellingUnitFields.fromUnit(SellingUnit unit) => _SellingUnitFields(
    id: unit.id,
    label: unit.label,
    price: (unit.priceCentavos / 100).toStringAsFixed(2),
  );

  final String? id;
  final TextEditingController labelController;
  final TextEditingController priceController;

  void dispose() {
    labelController.dispose();
    priceController.dispose();
  }
}

class _SellingUnitEditor extends StatelessWidget {
  const _SellingUnitEditor({
    super.key,
    required this.index,
    required this.fields,
    required this.enabled,
    required this.isDuplicateLabel,
    required this.onRemove,
  });

  final int index;
  final _SellingUnitFields fields;
  final bool enabled;
  final bool Function(_SellingUnitFields current, String value)
  isDuplicateLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Selling unit ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: enabled ? onRemove : null,
                  tooltip: 'Remove selling unit ${index + 1}',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('selling-unit-label-$index'),
                    controller: fields.labelController,
                    enabled: enabled,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Unit name',
                      hintText: 'Stick, piece, sachet…',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Enter a unit name.';
                      if (isDuplicateLabel(fields, text)) {
                        return 'Use a unique name different from the main unit.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: fields.priceController,
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Unit price',
                      prefixText: '₱ ',
                    ),
                    validator: (value) {
                      final centavos = tryParsePesoCentavos(value ?? '');
                      return centavos == null || centavos <= 0
                          ? 'Enter a valid price.'
                          : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Uses the main product barcode; no separate barcode is needed.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
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
