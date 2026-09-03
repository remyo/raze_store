import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:raze_store/app/theme/theme.dart';
import 'package:raze_store/core/barcode/barcode.dart';
import 'package:raze_store/core/money/money.dart';
import 'package:raze_store/core/widgets/app_widgets.dart';
import 'package:raze_store/features/catalog/application/catalog_providers.dart';
import 'package:raze_store/features/catalog/domain/catalog_product.dart';
import 'package:raze_store/features/catalog/domain/catalog_repository.dart';

class QuickAddProductScreen extends ConsumerStatefulWidget {
  const QuickAddProductScreen({
    super.key,
    this.initialBarcode,
    this.initialMetadata,
    this.goToProductsAfterSave = false,
  });

  final String? initialBarcode;
  final CatalogMetadata? initialMetadata;
  final bool goToProductsAfterSave;

  @override
  ConsumerState<QuickAddProductScreen> createState() =>
      _QuickAddProductScreenState();
}

class _QuickAddProductScreenState extends ConsumerState<QuickAddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _barcodeController = TextEditingController(
      text: widget.initialBarcode ?? widget.initialMetadata?.barcode,
    );
    _nameController = TextEditingController(text: widget.initialMetadata?.name);
    _priceController = TextEditingController();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving && !widget.goToProductsAfterSave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.goToProductsAfterSave && !_saving) {
          context.go('/products');
        }
      },
      child: AppPageScaffold(
        title: 'Quick add product',
        leading: IconButton(
          onPressed: _saving ? null : _close,
          tooltip: 'Close quick add',
          icon: const Icon(Icons.close_rounded),
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
              key: const ValueKey('quick-add-save'),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Saving…' : 'Save product'),
            ),
          ),
        ),
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
                      if (widget.initialMetadata != null) ...[
                        _ApiProductNotice(metadata: widget.initialMetadata!),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Text(
                        widget.initialMetadata == null
                            ? 'Only the essentials'
                            : 'Set your store price',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.initialMetadata == null
                            ? 'Enter a name and selling price. A barcode is optional for loose or repacked items.'
                            : 'Product details came from the shared catalog. Confirm the name and enter the price charged by this store.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextFormField(
                        key: const ValueKey('quick-add-barcode'),
                        controller: _barcodeController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Barcode (optional)',
                          hintText: 'Scan or type the main package barcode',
                          prefixIcon: Icon(Icons.barcode_reader),
                        ),
                        validator: (value) {
                          final input = value?.trim() ?? '';
                          if (input.isEmpty) return null;
                          return Barcode.tryParse(input) == null
                              ? 'Enter a valid barcode.'
                              : null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        key: const ValueKey('quick-add-name'),
                        controller: _nameController,
                        autofocus: widget.initialMetadata == null,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Product name',
                          hintText: 'Example: Kopiko Brown Coffee',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Enter the product name.'
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        key: const ValueKey('quick-add-price'),
                        controller: _priceController,
                        autofocus: false,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onFieldSubmitted: (_) => _saving ? null : _save(),
                        decoration: const InputDecoration(
                          labelText: 'Selling price',
                          prefixText: '₱ ',
                          prefixIcon: Icon(Icons.sell_outlined),
                        ),
                        validator: (value) {
                          final price = tryParsePesoCentavos(value ?? '');
                          return price == null || price <= 0
                              ? 'Enter a selling price greater than zero.'
                              : null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Card(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              const Expanded(
                                child: Text(
                                  'After saving, open the product to add details such as brand, photo, category, or piece and pack prices.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving ? null : _openDetailedForm,
                        child: const Text('Use the detailed product form'),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final product = await ref
          .read(catalogRepositoryProvider)
          .createProduct(
            ProductDraft(
              barcode: _barcodeController.text,
              name: _nameController.text,
              brand: widget.initialMetadata?.brand,
              unitLabel: widget.initialMetadata?.unitLabel,
              category: widget.initialMetadata?.category,
              remoteImageUrl: widget.initialMetadata?.remoteImageUrl,
              source: widget.initialMetadata?.source,
              sourceProductId: widget.initialMetadata?.sourceProductId,
              priceCentavos: tryParsePesoCentavos(_priceController.text)!,
            ),
          );
      if (!mounted) return;
      if (widget.goToProductsAfterSave) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${product.name} was added.')));
        context.go('/products');
      } else {
        Navigator.of(context).pop(product);
      }
    } on DuplicateBarcodeException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barcode ${error.barcode} is already in your store.'),
        ),
      );
    } on DuplicateCatalogProductException {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This shared catalog product is already in your store.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this product.')),
      );
    }
  }

  Future<void> _openDetailedForm() async {
    final barcode = _barcodeController.text.trim();
    final name = _nameController.text.trim();
    final price = _priceController.text.trim();
    final queryParameters = <String, String>{
      if (barcode.isNotEmpty) 'barcode': barcode,
      if (name.isNotEmpty) 'name': name,
      if (price.isNotEmpty) 'price': price,
      if (widget.goToProductsAfterSave) 'fromSetup': 'true',
    };
    final original = widget.initialMetadata;
    final handoffMetadata = original == null || name.isEmpty
        ? null
        : CatalogMetadata(
            barcode: barcode,
            name: name,
            brand: original.brand,
            unitLabel: original.unitLabel,
            category: original.category,
            remoteImageUrl: original.remoteImageUrl,
            source: original.source,
            sourceProductId: original.sourceProductId,
          );
    final result = await context.push<Object?>(
      Uri(
        path: '/products/new',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      ).toString(),
      extra: handoffMetadata,
    );
    if (!mounted || widget.goToProductsAfterSave) return;
    if (result is StoreProduct) Navigator.of(context).pop(result);
  }

  void _close() {
    if (widget.goToProductsAfterSave) {
      context.go('/products');
    } else {
      Navigator.of(context).pop();
    }
  }
}

class _ApiProductNotice extends StatelessWidget {
  const _ApiProductNotice({required this.metadata});

  final CatalogMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = [
      metadata.brand,
      metadata.unitLabel,
      metadata.category,
    ].whereType<String>().join(' · ');
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_done_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Found in the Raze catalog',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
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
