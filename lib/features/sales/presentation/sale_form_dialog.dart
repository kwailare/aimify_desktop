import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/formatters.dart';
import '../../../shared/utils/friendly_error.dart';
import '../../auth/domain/permissions.dart';
import '../../auth/presentation/permissions_provider.dart';
import '../../parties/data/parties_repository.dart';
import '../../parties/domain/party.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product.dart';
import '../../warehouses/data/warehouses_repository.dart';
import '../../whatsapp/whatsapp_auto.dart';
import '../data/sales_repository.dart';
import '../domain/sale.dart';

String _plain(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

class _LineDraft {
  _LineDraft({required this.product, required int quantity})
      : quantity = TextEditingController(text: '$quantity'),
        price = TextEditingController(text: _plain(product.sellingPrice));

  final Product product;
  final TextEditingController quantity;
  final TextEditingController price;

  int get quantityValue => int.tryParse(quantity.text.trim()) ?? 0;
  double get priceValue => double.tryParse(price.text.trim()) ?? product.sellingPrice;

  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}

/// What the form returns: the recorded sale (null when it was saved
/// offline) and any stock alerts it caused.
/// The sale, and who to send its invoice to on WhatsApp ([whatsAppPhone],
/// and whether they agreed to automatic messages).
typedef SaleFormResult = ({SaleOutcome? outcome, bool queued, String? whatsAppPhone, bool whatsAppAgreed});

/// Records a sale: who it's for (a customer, or a walk-in who pays in
/// full), which warehouse it leaves from, products at their selling price
/// (other prices and discounts need sales.discount), tax, and what is paid
/// now and how. Stock leaves the warehouse as soon as it's completed.
class SaleFormDialog extends ConsumerStatefulWidget {
  const SaleFormDialog({super.key, this.initialCustomerId});

  final String? initialCustomerId;

  @override
  ConsumerState<SaleFormDialog> createState() => _SaleFormDialogState();
}

class _SaleFormDialogState extends ConsumerState<SaleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late String? _customerId = widget.initialCustomerId;
  String? _warehouseId;
  final List<_LineDraft> _lines = [];
  final _discount = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');
  final _paid = TextEditingController();
  final _notes = TextEditingController();
  SalePaymentMethod _method = SalePaymentMethod.cash;

  /// The customer's WhatsApp number: a walk-in's (kept on the sale), or the
  /// chosen customer's (a change is saved to the customer).
  final _phone = TextEditingController();
  final _newCustomerName = TextEditingController();
  bool _saveAsCustomer = false;

  /// The customer the phone box was filled for (and whether they had loaded).
  (String?, bool)? _phoneFilledFor;

  /// Until someone types in "Paid now", it follows the total (a cash sale).
  bool _paidTouched = false;
  bool _allowOverLimit = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_discount, _tax, _paid, _notes, _phone, _newCustomerName]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double _money(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  double get _subtotal => _lines.fold(0.0, (s, l) => s + l.quantityValue * l.priceValue);
  double get _total => _subtotal - _money(_discount) + _money(_tax);
  double get _paidNow => _paidTouched ? _money(_paid) : _total;

  void _syncPaid() {
    if (!_paidTouched) _paid.text = _plain(_total < 0 ? 0 : _total);
  }

  void _add(Product product) {
    setState(() {
      final existing = _lines.where((l) => l.product.id == product.id).firstOrNull;
      if (existing != null) {
        existing.quantity.text = '${existing.quantityValue + 1}';
      } else {
        _lines.add(_LineDraft(product: product, quantity: 1));
      }
      _error = null;
      _syncPaid();
    });
  }

  Future<void> _save({required Party? customer, required int Function(Product) held}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      setState(() => _error = 'Add at least one product.');
      return;
    }
    for (final l in _lines) {
      if (l.quantityValue > held(l.product)) {
        setState(() => _error = 'Only ${held(l.product)} of ${l.product.name} in this warehouse.');
        return;
      }
    }
    final total = _total;
    final paid = _paidNow;
    if (total < 0) {
      setState(() => _error = "The discount can't be more than the sale is worth.");
      return;
    }
    if (paid > total + 0.004) {
      setState(() => _error = "Paid now can't be more than the total.");
      return;
    }
    final phone = _phone.text.trim().isEmpty ? null : _phone.text.trim();
    final walkIn = _customerId == null && !_saveAsCustomer;
    if (walkIn && paid < total - 0.004) {
      setState(() => _error = 'A walk-in sale must be paid in full. Choose the customer to sell on credit.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    var customerId = _customerId;
    // Whether they agreed to automatic WhatsApp messages: a walk-in or a new
    // customer giving their number did; a customer, as their tick says (a
    // number added where there was none ticks it).
    var agreed = customer?.whatsappOptIn ?? true;
    try {
      final parties = ref.read(partiesProvider(PartyType.customer).notifier);
      if (_customerId == null && _saveAsCustomer) {
        final created = await parties.add(
          PartyInput(type: PartyType.customer, name: _newCustomerName.text.trim(), phone: phone),
        );
        customerId = created.value!.id;
      } else if (customer != null && phone != (customer.phone?.trim().isEmpty ?? true ? null : customer.phone!.trim())) {
        if ((customer.phone ?? '').trim().isEmpty && phone != null) agreed = true;
        await parties.edit(
          customer.id,
          PartyInput(
            type: PartyType.customer,
            name: customer.name,
            phone: phone,
            email: customer.email,
            address: customer.address,
            notes: customer.notes,
            creditLimit: customer.creditLimit,
            customerTypeId: customer.customerTypeId,
            paymentTermsDays: customer.paymentTermsDays,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e);
      });
      return;
    }

    final input = SaleInput(
      customerId: customerId,
      customerPhone: walkIn ? phone : null,
      warehouseId: _warehouseId!,
      lines: [
        for (final l in _lines) SaleLineInput(productId: l.product.id, quantity: l.quantityValue, unitPrice: l.priceValue),
      ],
      discount: _money(_discount),
      tax: _money(_tax),
      amountPaid: paid,
      paymentMethod: _method,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      allowOverLimit: _allowOverLimit,
    );

    try {
      final result = await ref.read(salesProvider.notifier).add(input);
      if (!mounted) return;
      Navigator.of(context).pop<SaleFormResult>(
        (outcome: result.value, queued: result.queued, whatsAppPhone: phone, whatsAppAgreed: agreed),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final canDiscount = hasPermission(ref, Permissions.salesDiscount);
    final canOverride = hasPermission(ref, Permissions.salesOverride);
    final canSeeCustomers = hasPermission(ref, Permissions.customersView);
    final customers = canSeeCustomers
        ? ref.watch(partyListProvider(PartyType.customer)).where((c) => c.isActive || c.id == _customerId).toList()
        : const <Party>[];
    final warehouses = ref.watch(activeWarehousesProvider);
    if (_warehouseId == null && warehouses.isNotEmpty) _warehouseId = warehouses.first.id;
    final warehouseId = _warehouseId;
    final products = ref.watch(productListProvider).where((p) => !p.isArchived && !p.isPending).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    int held(Product p) => warehouseId == null ? 0 : p.stockIn(warehouseId);

    final customer = customers.where((c) => c.id == _customerId).firstOrNull;
    // The phone box shows the chosen customer's number (once they've loaded);
    // a walk-in starts empty.
    if (_phoneFilledFor != (_customerId, customer != null)) {
      final before = _phoneFilledFor;
      _phoneFilledFor = (_customerId, customer != null);
      if (_customerId != null || before?.$1 != null) _phone.text = customer?.phone ?? '';
    }
    final canCreateCustomer = hasPermission(ref, Permissions.customersCreate);
    final canEditCustomer = hasPermission(ref, Permissions.customersEdit);
    final hasPhone = _phone.text.trim().isNotEmpty;
    final autoOpen = ref.watch(whatsAppAutoOpenProvider).valueOrNull ?? true;
    final unpaid = _total - _paidNow;
    final creditLeft = customer == null || customer.creditLimit <= 0 ? null : customer.creditLimit - customer.balanceOwed;
    final overLimit = creditLeft != null && unpaid > 0.004 && unpaid > creditLeft + 0.004;

    return AlertDialog(
      title: const Text('New sale'),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        key: const Key('sale-customer'),
                        initialValue: _customerId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Customer'),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Walk-in customer (pays now)')),
                          for (final c in customers)
                            DropdownMenuItem<String?>(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                          // Opened for a customer the list hasn't loaded yet.
                          if (_customerId != null && customer == null)
                            DropdownMenuItem<String?>(value: _customerId, child: const Text('Customer')),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) => setState(() {
                                  _customerId = v;
                                  _allowOverLimit = false;
                                }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('sale-warehouse'),
                        initialValue: _warehouseId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Sell from'),
                        items: [
                          for (final w in warehouses)
                            DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: _saving ? null : (v) => setState(() => _warehouseId = v),
                        validator: (v) => v == null ? 'Choose a warehouse' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_customerId == null) ...[
                  TextFormField(
                    key: const Key('sale-walkin-phone'),
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: "Customer's WhatsApp number (optional)",
                      helperText: 'For their invoice on WhatsApp',
                      prefixIcon: Icon(Icons.chat_outlined, size: 18),
                    ),
                  ),
                  if (canCreateCustomer)
                    CheckboxListTile(
                      key: const Key('sale-save-customer'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _saveAsCustomer,
                      onChanged: _saving ? null : (v) => setState(() => _saveAsCustomer = v ?? false),
                      title: const Text('Save them as a new customer'),
                      subtitle: const Text('So their name and number are there next time.'),
                    ),
                  if (_saveAsCustomer)
                    TextFormField(
                      key: const Key('sale-new-customer-name'),
                      controller: _newCustomerName,
                      enabled: !_saving,
                      decoration: const InputDecoration(labelText: 'Customer name'),
                      validator: (v) => _saveAsCustomer && (v ?? '').trim().isEmpty ? 'Enter their name' : null,
                    ),
                ] else
                  TextFormField(
                    key: const Key('sale-customer-phone'),
                    controller: _phone,
                    enabled: !_saving && canEditCustomer,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: "Customer's phone (WhatsApp)",
                      helperText: canEditCustomer ? 'A change is saved to the customer' : null,
                      prefixIcon: const Icon(Icons.chat_outlined, size: 18),
                    ),
                  ),
                if (hasPhone)
                  CheckboxListTile(
                    key: const Key('sale-send-whatsapp'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: autoOpen,
                    onChanged: _saving ? null : (v) => ref.read(whatsAppAutoOpenProvider.notifier).set(v ?? true),
                    title: const Text('Send the invoice on WhatsApp'),
                    subtitle: const Text('WhatsApp opens with it ready; you press Send. Remembered on this computer.'),
                  ),
                if (customer != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      'Owes ${currencyFormat.format(customer.balanceOwed)}',
                      if (creditLeft != null) 'credit left ${currencyFormat.format(creditLeft < 0 ? 0 : creditLeft)}',
                    ].join(' · '),
                    key: const Key('sale-customer-credit'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                const SizedBox(height: 16),
                DropdownMenu<String>(
                  key: ValueKey('sale-add-product-${_lines.length}-$_warehouseId'),
                  width: 712,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  enabled: !_saving && warehouseId != null,
                  hintText: products.isEmpty ? 'No products yet' : 'Add a product — type to search',
                  leadingIcon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                  dropdownMenuEntries: [
                    for (final p in products)
                      DropdownMenuEntry(
                        value: p.id,
                        label: '${p.name} · ${p.sku}',
                        trailingIcon: Text('${held(p)} ${p.unit}', style: theme.textTheme.bodySmall),
                        enabled: held(p) > 0,
                      ),
                  ],
                  onSelected: (id) {
                    final product = products.where((p) => p.id == id).firstOrNull;
                    if (product != null) _add(product);
                  },
                ),
                const SizedBox(height: 8),
                if (_lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No products added yet.', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  )
                else
                  for (final line in _lines)
                    Padding(
                      key: ValueKey('sale-line-${line.product.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.product.name, overflow: TextOverflow.ellipsis),
                                  Text('${held(line.product)} ${line.product.unit} in stock here',
                                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: TextFormField(
                              key: ValueKey('sale-qty-${line.product.id}'),
                              controller: line.quantity,
                              enabled: !_saving,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: InputDecoration(labelText: 'Qty', isDense: true, suffixText: line.product.unit),
                              onChanged: (_) => setState(_syncPaid),
                              validator: (v) {
                                final q = int.tryParse((v ?? '').trim()) ?? 0;
                                if (q <= 0) return 'Above 0';
                                if (q > held(line.product)) return 'Only ${held(line.product)}';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              key: ValueKey('sale-price-${line.product.id}'),
                              controller: line.price,
                              enabled: !_saving && canDiscount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Price',
                                isDense: true,
                                helperText: canDiscount ? null : 'Selling price',
                              ),
                              onChanged: (_) => setState(_syncPaid),
                              validator: (v) {
                                final p = double.tryParse((v ?? '').trim());
                                return p == null || p < 0 ? '0 or more' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(
                                currencyFormat.format(line.quantityValue * line.priceValue),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                      _lines.remove(line);
                                      line.dispose();
                                      _syncPaid();
                                    }),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                const Divider(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (canDiscount) ...[
                      Expanded(
                        child: TextFormField(
                          key: const Key('sale-discount'),
                          controller: _discount,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Discount'),
                          onChanged: (_) => setState(_syncPaid),
                          validator: (v) {
                            final d = double.tryParse((v ?? '').trim());
                            return d == null || d < 0 ? '0 or more' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: TextFormField(
                        key: const Key('sale-tax'),
                        controller: _tax,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: orgTaxRate > 0 ? orgTaxName : 'Tax',
                          suffixIcon: orgTaxRate > 0
                              ? IconButton(
                                  key: const Key('sale-apply-tax'),
                                  tooltip: 'Apply ${_plain(orgTaxRate)}% after discount',
                                  icon: const Icon(Icons.percent, size: 18),
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() {
                                            final base = (_subtotal - _money(_discount)).clamp(0, double.infinity);
                                            _tax.text = (base * orgTaxRate / 100).toStringAsFixed(2);
                                            _syncPaid();
                                          }),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(_syncPaid),
                        validator: (v) {
                          final t = double.tryParse((v ?? '').trim());
                          return t == null || t < 0 ? '0 or more' : null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('sale-paid'),
                        controller: _paid,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Paid now',
                          helperText: _customerId == null ? 'Walk-ins pay in full' : 'Less than the total = on credit',
                        ),
                        onChanged: (_) => setState(() => _paidTouched = true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<SalePaymentMethod>(
                        key: const Key('sale-method'),
                        initialValue: _method,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Paid by'),
                        items: [
                          for (final m in SalePaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label)),
                        ],
                        onChanged: _saving ? null : (v) => setState(() => _method = v ?? SalePaymentMethod.cash),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Goods ${currencyFormat.format(_subtotal)}', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                      Text(
                        'Total ${currencyFormat.format(_total)}',
                        key: const Key('sale-total'),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if (unpaid > 0.004)
                        Text(
                          [
                            'On credit ${currencyFormat.format(unpaid)}',
                            if (customer != null)
                              'due ${dateFormat.format(DateTime.now().add(Duration(days: customer.paymentTermsDays)))}',
                          ].join(' · '),
                          key: const Key('sale-on-credit'),
                          style: theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                if (overLimit) ...[
                  const SizedBox(height: 10),
                  Container(
                    key: const Key('sale-over-limit'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This would take ${customer!.name} over their credit limit: only '
                          '${currencyFormat.format(creditLeft < 0 ? 0 : creditLeft)} of credit is left.',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        if (canOverride)
                          CheckboxListTile(
                            key: const Key('sale-allow-over-limit'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _allowOverLimit,
                            onChanged: _saving ? null : (v) => setState(() => _allowOverLimit = v ?? false),
                            title: const Text('Allow over the limit (recorded in the activity trail)'),
                          )
                        else
                          Text('Take more payment now, or ask an Owner or Administrator.',
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  enabled: !_saving,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, key: const Key('sale-error'), style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton.icon(
          key: const Key('sale-complete'),
          onPressed: _saving || (overLimit && !_allowOverLimit)
              ? null
              : () => _save(customer: customer, held: held),
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check, size: 18),
          label: Text('Complete sale · ${currencyFormat.format(_total)}'),
        ),
      ],
    );
  }
}
