import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/friendly_error.dart';
import '../data/catalog_repository.dart';
import '../data/products_repository.dart';
import '../domain/product.dart';
import 'widgets/catalog_field.dart';

const _maxImageBytes = 2 * 1024 * 1024;

/// Create or edit a product against the real API. Pass [product] to edit.
///
/// Stock is deliberately not editable here: `currentStock` only changes
/// through stock movements (Inventory → Record movement), which is what
/// keeps the ledger trustworthy.
class ProductFormDialog extends ConsumerStatefulWidget {
  const ProductFormDialog({super.key, this.product});

  final Product? product;

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _sku = TextEditingController(text: widget.product?.sku);
  late final _name = TextEditingController(text: widget.product?.name);
  late final _barcode = TextEditingController(text: widget.product?.barcode);
  late final _brand = TextEditingController(text: widget.product?.brand);
  late final _description = TextEditingController(text: widget.product?.description);
  late final _category = TextEditingController(text: widget.product?.category);
  late final _unit = TextEditingController(text: widget.product?.unit ?? 'piece');
  late final _purchasePrice =
      TextEditingController(text: _num(widget.product?.purchasePrice));
  late final _sellingPrice = TextEditingController(text: _num(widget.product?.sellingPrice));
  late final _minStock = TextEditingController(text: '${widget.product?.minStock ?? 0}');
  late final _maxStock = TextEditingController(text: widget.product?.maxStock?.toString() ?? '');

  Uint8List? _pickedImage;
  String? _pickedImageName;
  bool _removeImage = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.product != null;

  static String _num(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _sku, _name, _barcode, _brand, _description, _category, _unit,
      _purchasePrice, _sellingPrice, _minStock, _maxStock,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    if (bytes.length > _maxImageBytes) {
      setState(() => _error = 'That picture is over 2 MB. Choose a smaller one.');
      return;
    }
    setState(() {
      _pickedImage = bytes;
      _pickedImageName = file.name;
      _removeImage = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final input = ProductInput(
      sku: _sku.text.trim(),
      name: _name.text.trim(),
      barcode: _optional(_barcode),
      description: _optional(_description),
      brand: _optional(_brand),
      category: _optional(_category),
      unit: _unit.text.trim(),
      purchasePrice: double.parse(_purchasePrice.text.trim()),
      sellingPrice: double.parse(_sellingPrice.text.trim()),
      minStock: int.parse(_minStock.text.trim()),
      maxStock: _maxStock.text.trim().isEmpty ? null : int.parse(_maxStock.text.trim()),
    );

    setState(() {
      _saving = true;
      _error = null;
    });

    final notifier = ref.read(productsProvider.notifier);
    try {
      final saved = _editing
          ? await notifier.edit(widget.product!.id, input)
          : await notifier.add(input);

      // The product itself is saved at this point. If only the picture
      // fails, keep the dialog open and say so — closing would hide it.
      try {
        if (_pickedImage != null) {
          await notifier.setImage(saved.id, bytes: _pickedImage!, filename: _pickedImageName ?? 'image');
        } else if (_removeImage && widget.product?.imageUrl != null) {
          await notifier.clearImage(saved.id);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = 'Product saved, but the picture could not be uploaded: ${friendlyError(e)}';
          });
        }
        ref.invalidate(catalogProvider);
        return;
      }

      ref.invalidate(catalogProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  String? _required(String? v, {int? max}) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (max != null && v.trim().length > max) return 'At most $max characters';
    return null;
  }

  String? _price(String? v) {
    final parsed = double.tryParse((v ?? '').trim());
    if (parsed == null || parsed < 0) return 'Enter 0 or more';
    return null;
  }

  String? _wholeNumber(String? v, {bool optional = false}) {
    final text = (v ?? '').trim();
    if (text.isEmpty) return optional ? null : 'Required';
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) return 'Whole number, 0 or more';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(catalogProvider(CatalogKind.category)).valueOrNull ?? const [];
    final units = ref.watch(catalogProvider(CatalogKind.unit)).valueOrNull ?? const [];
    final existingImage = _removeImage ? null : widget.product?.imageUrl;

    return AlertDialog(
      title: Text(_editing ? 'Edit product' : 'Add product'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ImageRow(
                  pickedBytes: _pickedImage,
                  existingUrl: existingImage,
                  onPick: _saving ? null : _pickImage,
                  onRemove: _saving || (_pickedImage == null && existingImage == null)
                      ? null
                      : () => setState(() {
                            _pickedImage = null;
                            _pickedImageName = null;
                            _removeImage = true;
                          }),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _sku,
                        decoration: const InputDecoration(labelText: 'SKU *'),
                        validator: (v) => _required(v, max: 64),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name *'),
                        validator: (v) => _required(v, max: 200),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _brand,
                        decoration: const InputDecoration(labelText: 'Brand'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _barcode,
                        decoration: const InputDecoration(labelText: 'Barcode'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: CatalogField(
                        controller: _category,
                        label: 'Category',
                        options: [for (final c in categories) c.name],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CatalogField(
                        controller: _unit,
                        label: 'Unit *',
                        options: [for (final u in units) u.name],
                        validator: (v) => _required(v, max: 60),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _purchasePrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Purchase price *'),
                        validator: _price,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sellingPrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Selling price *'),
                        validator: _price,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Reorder level *',
                          helperText: 'Alert when stock falls to this',
                        ),
                        validator: _wholeNumber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxStock,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Maximum stock',
                          helperText: 'Optional upper limit',
                        ),
                        validator: (v) {
                          final basic = _wholeNumber(v, optional: true);
                          if (basic != null) return basic;
                          final max = int.tryParse((v ?? '').trim());
                          final min = int.tryParse(_minStock.text.trim());
                          if (max != null && min != null && max < min) {
                            return "Can't be below the reorder level";
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                if (_editing) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Stock on hand (${widget.product!.currentStock}) changes only through '
                    'stock movements on the Inventory screen.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_editing ? 'Save changes' : 'Add product'),
        ),
      ],
    );
  }
}

class _ImageRow extends StatelessWidget {
  const _ImageRow({
    required this.pickedBytes,
    required this.existingUrl,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? pickedBytes;
  final String? existingUrl;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget preview;
    if (pickedBytes != null) {
      preview = Image.memory(pickedBytes!, fit: BoxFit.cover);
    } else if (existingUrl != null) {
      preview = Image.network(
        existingUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    } else {
      preview = Icon(
        Icons.image_outlined,
        size: 28,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
      );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 72,
            height: 72,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
            alignment: Alignment.center,
            child: preview,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(pickedBytes != null || existingUrl != null ? 'Replace picture' : 'Add picture'),
                  ),
                  if (onRemove != null)
                    TextButton(onPressed: onRemove, child: const Text('Remove')),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'PNG, JPEG or WebP, up to 2 MB',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
