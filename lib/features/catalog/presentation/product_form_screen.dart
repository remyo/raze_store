import 'dart:async';
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
import 'package:raze_store/features/catalog/application/product_text_recognizer.dart';
import 'package:raze_store/features/catalog/domain/catalog_categories.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';
import 'package:raze_store/features/catalog/presentation/duplicate_barcode_resolution.dart';
import 'package:raze_store/features/catalog/presentation/product_capture_screen.dart';

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
  XFile? _temporaryBackgroundPhoto;
  ProductBackgroundRemover? _temporaryBackgroundOwner;
  bool _removeExistingPhoto = false;
  bool _busy = false;
  bool _removingBackground = false;
  bool _readingText = false;
  bool _backgroundRemoved = false;

  bool get _editing => widget.product != null;
  bool get _blocked => _busy || _removingBackground || _readingText;

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
    final suggestedPrice = widget.initialMetadata?.suggestedPriceCentavos;
    _priceController = TextEditingController(
      text: product == null
          ? widget.initialPrice ??
                (suggestedPrice == null ? '' : formatPesoInput(suggestedPrice))
          : (product.priceCentavos / 100).toStringAsFixed(2),
    );
    _sellingUnits = [
      for (final unit in product?.sellingUnits ?? const <SellingUnit>[])
        _SellingUnitFields.fromUnit(unit),
    ];
  }

  @override
  void dispose() {
    unawaited(_discardTemporaryBackgroundPhoto());
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
      canPop: !_blocked && !widget.goToProductsAfterSave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.goToProductsAfterSave && !_blocked) {
          context.go('/products');
        }
      },
      child: AppPageScaffold(
        title: _editing ? 'Edit product' : 'Add product',
        leading: widget.goToProductsAfterSave
            ? IconButton(
                onPressed: _blocked ? null : () => context.go('/products'),
                tooltip: 'Close product form',
                icon: const Icon(Icons.close_rounded),
              )
            : IconButton(
                onPressed: _blocked ? null : () => context.pop(),
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
              onPressed: _blocked ? null : _save,
              icon: _blocked
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _removingBackground
                    ? 'Removing background…'
                    : _busy
                    ? 'Saving…'
                    : 'Save product',
              ),
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
                                'Product details came from an offline Raze catalog pack. Your selling price, photo, and selling units remain yours.',
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
                    busy: _blocked,
                    removingBackground: _removingBackground,
                    readingText: _readingText,
                    backgroundRemoved: _backgroundRemoved,
                    onChoose: _choosePhotoSource,
                    onRemoveBackground: _removePhotoBackground,
                    onReadText: _readCurrentPhotoText,
                    onRemove: _removePhoto,
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
                          decoration:
                              const InputDecoration(
                                labelText: 'Category',
                                hintText: 'Choose or type your own',
                                prefixIcon: Icon(Icons.category_outlined),
                              ).copyWith(
                                suffixIcon: IconButton(
                                  key: const ValueKey(
                                    'choose-product-category',
                                  ),
                                  tooltip: 'Choose category',
                                  onPressed: _blocked
                                      ? null
                                      : () => _showCategoryPicker(
                                          categorySuggestions,
                                        ),
                                  icon: const Icon(
                                    Icons.arrow_drop_down_rounded,
                                  ),
                                ),
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
                    'Add reusable custom categories from Store settings.',
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
                      enabled: !_blocked,
                      isDuplicateLabel: _isDuplicateSellingUnitLabel,
                      onRemove: () => _removeSellingUnit(index),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  OutlinedButton.icon(
                    onPressed: _blocked ? null : _addSellingUnit,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add another selling unit'),
                  ),
                  if (_editing) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const Divider(),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _blocked ? null : _delete,
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

  Future<void> _showCategoryPicker(List<String> categories) async {
    _categoryFocusNode.unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                'Choose category',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('product-category-options'),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final selected =
                      _categoryController.text.trim().toLowerCase() ==
                      category.toLowerCase();
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.category_outlined,
                    ),
                    title: Text(category),
                    onTap: () => Navigator.of(context).pop(category),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _categoryController.value = TextEditingValue(
      text: selected,
      selection: TextSelection.collapsed(offset: selected.length),
    );
  }

  Future<void> _choosePhotoSource() async {
    final action = await showModalBottomSheet<_ProductPhotoAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Use the product frame and lighting guide.'),
              onTap: () =>
                  Navigator.pop(context, _ProductPhotoAction.takeProductPhoto),
            ),
            ListTile(
              key: const ValueKey('scan-product-label-action'),
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Read product label'),
              subtitle: const Text(
                'Take one photo and suggest the name, brand, size, and price.',
              ),
              onTap: () =>
                  Navigator.pop(context, _ProductPhotoAction.readProductLabel),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () =>
                  Navigator.pop(context, _ProductPhotoAction.chooseFromGallery),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    try {
      final XFile? picked;
      switch (action) {
        case _ProductPhotoAction.takeProductPhoto:
          picked = await ref
              .read(productCaptureLauncherProvider)
              .capture(context, purpose: ProductCapturePurpose.productPhoto);
        case _ProductPhotoAction.readProductLabel:
          picked = await ref
              .read(productCaptureLauncherProvider)
              .capture(context, purpose: ProductCapturePurpose.productLabel);
        case _ProductPhotoAction.chooseFromGallery:
          picked = await ref.read(productPhotoPickerProvider).pickFromGallery();
      }
      if (!mounted || picked == null) return;
      await _setPendingPhoto(picked);
      if (!mounted) return;
      if (action == _ProductPhotoAction.readProductLabel) {
        await _readPhotoText(picked);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the product photo.')),
      );
    }
  }

  Future<void> _setPendingPhoto(XFile photo) async {
    await _discardTemporaryBackgroundPhoto();
    if (!mounted) return;
    setState(() {
      _pendingPhoto = photo;
      _removeExistingPhoto = false;
      _backgroundRemoved = false;
    });
  }

  Future<void> _readCurrentPhotoText() async {
    final existingPath = _removeExistingPhoto
        ? null
        : widget.product?.localImagePath;
    final source =
        _pendingPhoto ?? (existingPath == null ? null : XFile(existingPath));
    if (source == null || _blocked) return;
    await _readPhotoText(source);
  }

  Future<void> _readPhotoText(XFile source) async {
    if (_blocked) return;
    setState(() => _readingText = true);
    late final ProductTextRecognitionResult recognition;
    try {
      recognition = await ref
          .read(productTextRecognizerProvider)
          .recognizeImagePath(source.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not read the label. Try a brighter, sharper photo.',
          ),
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _readingText = false);
    }
    if (!mounted) return;

    if (recognition.rawLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No text was found. Move closer and keep the label inside the frame.',
          ),
        ),
      );
      return;
    }

    final selection = await showModalBottomSheet<_RecognizedProductSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _RecognizedProductReview(
        recognition: recognition,
        currentName: _nameController.text,
        currentBrand: _brandController.text,
        currentUnit: _unitController.text,
        currentPrice: _priceController.text,
      ),
    );
    if (selection == null || !mounted) return;

    if (selection.productName != null) {
      _replaceControllerText(_nameController, selection.productName!);
    }
    if (selection.brand != null) {
      _replaceControllerText(_brandController, selection.brand!);
    }
    if (selection.sizeOrUnit != null) {
      _replaceControllerText(_unitController, selection.sizeOrUnit!);
    }
    if (selection.priceCentavos != null) {
      _replaceControllerText(
        _priceController,
        formatPesoInput(selection.priceCentavos!),
      );
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Details filled from the photo. Please review before saving.',
          ),
        ),
      );
  }

  void _replaceControllerText(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _removePhotoBackground() async {
    final existingPath = _removeExistingPhoto
        ? null
        : widget.product?.localImagePath;
    final source =
        _pendingPhoto ?? (existingPath == null ? null : XFile(existingPath));
    if (source == null || _blocked || _backgroundRemoved) return;

    setState(() => _removingBackground = true);
    final remover = ref.read(productBackgroundRemoverProvider);
    try {
      final processed = await remover.removeBackground(source);
      if (!mounted) {
        try {
          await remover.deleteTemporary(processed);
        } catch (_) {
          // Best-effort cleanup after the form closes during processing.
        }
        return;
      }
      setState(() {
        _pendingPhoto = processed;
        _temporaryBackgroundPhoto = processed;
        _temporaryBackgroundOwner = remover;
        _removeExistingPhoto = false;
        _backgroundRemoved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The photo background was removed on this device.'),
        ),
      );
    } on ProductBackgroundRemovalException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove the photo background.')),
      );
    } finally {
      if (mounted) setState(() => _removingBackground = false);
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
      await _discardTemporaryBackgroundPhoto();
      if (!mounted) return;
      if (widget.goToProductsAfterSave) {
        context.go('/products');
      } else {
        context.pop(savedProduct);
      }
    } on DuplicateBarcodeException catch (error) {
      await _deleteManagedPhotoBestEffort(savedPhotoPath);
      if (!mounted) return;
      setState(() => _busy = false);
      StoreProduct? existingProduct;
      try {
        existingProduct = await ref
            .read(catalogRepositoryProvider)
            .findByBarcode(error.barcode);
      } catch (_) {
        // The uniqueness error remains useful even if the follow-up lookup
        // cannot load the existing row.
      }
      if (!mounted) return;
      if (existingProduct == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Barcode ${error.barcode} is already in your store. No duplicate was created.',
            ),
          ),
        );
        return;
      }
      final useExisting = await showDuplicateBarcodeResolution(
        context,
        existingProduct: existingProduct,
      );
      if (useExisting != true || !mounted) return;
      if (widget.goToProductsAfterSave) {
        context.go('/products');
      } else {
        context.pop(existingProduct);
      }
    } on DuplicateCatalogProductException {
      await _deleteManagedPhotoBestEffort(savedPhotoPath);
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
      await _deleteManagedPhotoBestEffort(savedPhotoPath);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this product.')),
      );
    }
  }

  Future<void> _deleteManagedPhotoBestEffort(String? path) async {
    if (path == null) return;
    try {
      await ref.read(localProductImageStoreProvider).deleteIfManaged(path);
    } catch (_) {
      // Keep the original save error visible and re-enable the form even if
      // cleanup itself fails.
    }
  }

  Future<void> _removePhoto() async {
    final cleanup = _discardTemporaryBackgroundPhoto();
    if (mounted) {
      setState(() {
        _pendingPhoto = null;
        _removeExistingPhoto = true;
        _backgroundRemoved = false;
      });
    }
    await cleanup;
  }

  Future<void> _discardTemporaryBackgroundPhoto() async {
    final photo = _temporaryBackgroundPhoto;
    final owner = _temporaryBackgroundOwner;
    _temporaryBackgroundPhoto = null;
    _temporaryBackgroundOwner = null;
    if (photo == null || owner == null) return;
    try {
      await owner.deleteTemporary(photo);
    } catch (_) {
      // Temporary media cleanup is best effort and must not block the form.
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
        final imageStore = ref.read(localProductImageStoreProvider);
        for (final imagePath in {
          product.localImagePath,
          product.catalogImagePath,
        }) {
          await imageStore.deleteIfManaged(imagePath);
        }
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

enum _ProductPhotoAction {
  takeProductPhoto,
  readProductLabel,
  chooseFromGallery,
}

final class _RecognizedProductSelection {
  const _RecognizedProductSelection({
    this.productName,
    this.brand,
    this.sizeOrUnit,
    this.priceCentavos,
  });

  final String? productName;
  final String? brand;
  final String? sizeOrUnit;
  final int? priceCentavos;
}

class _RecognizedProductReview extends StatefulWidget {
  const _RecognizedProductReview({
    required this.recognition,
    required this.currentName,
    required this.currentBrand,
    required this.currentUnit,
    required this.currentPrice,
  });

  final ProductTextRecognitionResult recognition;
  final String currentName;
  final String currentBrand;
  final String currentUnit;
  final String currentPrice;

  @override
  State<_RecognizedProductReview> createState() =>
      _RecognizedProductReviewState();
}

class _RecognizedProductReviewState extends State<_RecognizedProductReview> {
  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _unitController;
  late final TextEditingController _priceController;
  late bool _useName;
  late bool _useBrand;
  late bool _useUnit;
  late bool _usePrice;
  String? _priceError;

  ProductTextSuggestions get _suggestions => widget.recognition.suggestions;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _suggestions.productName ?? '',
    );
    _brandController = TextEditingController(text: _suggestions.brand ?? '');
    _unitController = TextEditingController(
      text: _suggestions.sizeOrUnit ?? '',
    );
    _priceController = TextEditingController(
      text: _suggestions.priceCentavos == null
          ? ''
          : formatPesoInput(_suggestions.priceCentavos!),
    );
    _useName = _selectedByDefault(widget.currentName, _suggestions.productName);
    _useBrand = _selectedByDefault(widget.currentBrand, _suggestions.brand);
    _useUnit = _selectedByDefault(widget.currentUnit, _suggestions.sizeOrUnit);
    final currentPrice = tryParsePesoCentavos(widget.currentPrice);
    _usePrice =
        _suggestions.priceCentavos != null &&
        (currentPrice == null || currentPrice == _suggestions.priceCentavos);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSuggestion =
        _suggestions.productName != null ||
        _suggestions.brand != null ||
        _suggestions.sizeOrUnit != null ||
        _suggestions.priceCentavos != null;
    final hasSelectedSuggestion =
        (_useName && _nameController.text.trim().isNotEmpty) ||
        (_useBrand && _brandController.text.trim().isNotEmpty) ||
        (_useUnit && _unitController.text.trim().isNotEmpty) ||
        (_usePrice && _priceController.text.trim().isNotEmpty);
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Review label details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              hasSuggestion
                  ? 'Select only the details you want to use. Existing values stay unchanged unless you select a replacement.'
                  : 'Text was found, but no safe field suggestions could be made. Review the detected text below.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_suggestions.productName != null)
                      _detectedField(
                        checkboxKey: const ValueKey(
                          'detected-product-name-checkbox',
                        ),
                        label: 'Product name',
                        controller: _nameController,
                        selected: _useName,
                        currentValue: widget.currentName,
                        onSelected: (value) => setState(() => _useName = value),
                      ),
                    if (_suggestions.brand != null)
                      _detectedField(
                        checkboxKey: const ValueKey('detected-brand-checkbox'),
                        label: 'Brand',
                        controller: _brandController,
                        selected: _useBrand,
                        currentValue: widget.currentBrand,
                        onSelected: (value) =>
                            setState(() => _useBrand = value),
                      ),
                    if (_suggestions.sizeOrUnit != null)
                      _detectedField(
                        checkboxKey: const ValueKey('detected-unit-checkbox'),
                        label: 'Size / unit',
                        controller: _unitController,
                        selected: _useUnit,
                        currentValue: widget.currentUnit,
                        onSelected: (value) => setState(() => _useUnit = value),
                      ),
                    if (_suggestions.priceCentavos != null)
                      _detectedField(
                        checkboxKey: const ValueKey('detected-price-checkbox'),
                        label: 'Printed price',
                        controller: _priceController,
                        selected: _usePrice,
                        currentValue: widget.currentPrice.isEmpty
                            ? ''
                            : '₱${widget.currentPrice}',
                        prefixText: '₱ ',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        errorText: _priceError,
                        onSelected: (value) =>
                            setState(() => _usePrice = value),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    Card(
                      color: scheme.surfaceContainerLow,
                      child: ExpansionTile(
                        key: const ValueKey('recognized-label-text'),
                        initiallyExpanded: !hasSuggestion,
                        leading: const Icon(Icons.text_snippet_outlined),
                        title: const Text('Detected text'),
                        subtitle: Text(
                          '${widget.recognition.rawLines.length} line${widget.recognition.rawLines.length == 1 ? '' : 's'} found',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              0,
                              AppSpacing.md,
                              AppSpacing.md,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                widget.recognition.rawLines.join('\n'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('apply-detected-product-details'),
                  onPressed: hasSelectedSuggestion ? _submit : null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Use selected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detectedField({
    required ValueKey<String> checkboxKey,
    required String label,
    required TextEditingController controller,
    required bool selected,
    required String currentValue,
    required ValueChanged<bool> onSelected,
    TextInputType? keyboardType,
    String? prefixText,
    String? errorText,
  }) {
    final current = currentValue.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Checkbox(
              key: checkboxKey,
              value: selected,
              onChanged: (value) => onSelected(value ?? false),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: selected,
              onChanged: (_) => setState(() => _priceError = null),
              keyboardType: keyboardType,
              decoration: InputDecoration(
                labelText: label,
                prefixText: prefixText,
                errorText: errorText,
                helperText: current.isEmpty
                    ? 'New suggestion'
                    : selected
                    ? 'Will replace: $current'
                    : 'Keeping: $current',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final price = _usePrice
        ? tryParsePesoCentavos(_priceController.text)
        : null;
    if (_usePrice && (price == null || price <= 0)) {
      setState(() => _priceError = 'Enter a valid price.');
      return;
    }
    Navigator.of(context).pop(
      _RecognizedProductSelection(
        productName: _selectedText(_useName, _nameController),
        brand: _selectedText(_useBrand, _brandController),
        sizeOrUnit: _selectedText(_useUnit, _unitController),
        priceCentavos: price,
      ),
    );
  }

  static bool _selectedByDefault(String current, String? suggestion) {
    if (suggestion == null || suggestion.trim().isEmpty) return false;
    final normalizedCurrent = current.trim().toLowerCase();
    return normalizedCurrent.isEmpty ||
        normalizedCurrent == suggestion.trim().toLowerCase();
  }

  static String? _selectedText(
    bool selected,
    TextEditingController controller,
  ) {
    final value = controller.text.trim();
    return selected && value.isNotEmpty ? value : null;
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
    required this.removingBackground,
    required this.readingText,
    required this.backgroundRemoved,
    required this.onChoose,
    required this.onRemoveBackground,
    required this.onReadText,
    required this.onRemove,
  });

  final StoreProduct? product;
  final XFile? pendingPhoto;
  final bool removeExisting;
  final bool busy;
  final bool removingBackground;
  final bool readingText;
  final bool backgroundRemoved;
  final VoidCallback onChoose;
  final VoidCallback onRemoveBackground;
  final VoidCallback onReadText;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final existingPath = removeExisting ? null : product?.localImagePath;
    final hasPhoto = pendingPhoto != null || existingPath != null;
    final scheme = Theme.of(context).colorScheme;
    final previewCacheSize = (104 * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(104, 512);

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
                      cacheWidth: previewCacheSize,
                      cacheHeight: previewCacheSize,
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
                      cacheWidth: previewCacheSize,
                      cacheHeight: previewCacheSize,
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
                  if (hasPhoto) ...[
                    const SizedBox(height: AppSpacing.xs),
                    OutlinedButton.icon(
                      key: const ValueKey('remove-photo-background'),
                      onPressed: busy || backgroundRemoved
                          ? null
                          : onRemoveBackground,
                      icon: removingBackground
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              backgroundRemoved
                                  ? Icons.check_rounded
                                  : Icons.auto_fix_high_rounded,
                            ),
                      label: Text(
                        removingBackground
                            ? 'Removing…'
                            : backgroundRemoved
                            ? 'Background removed'
                            : 'Remove background',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    OutlinedButton.icon(
                      key: const ValueKey('read-product-photo-text'),
                      onPressed: busy ? null : onReadText,
                      icon: readingText
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.document_scanner_outlined),
                      label: Text(
                        readingText ? 'Reading label…' : 'Read label text',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: busy ? null : onRemove,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
