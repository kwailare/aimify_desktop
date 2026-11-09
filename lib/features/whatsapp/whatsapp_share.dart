import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/utils/formatters.dart';
import '../purchases/domain/purchase.dart';
import '../sales/domain/sale.dart';

// "Send on WhatsApp": opens WhatsApp (the app, or WhatsApp Web) on this
// computer with the message already written, to the customer's or
// supplier's number. The person reads it and presses Send themselves, from
// their own WhatsApp, so it needs no setup and no consent tick (automatic
// messages, which do, are set up on the website).

/// A phone number as WhatsApp wants it: digits with the country code.
/// Nigerian numbers written locally (0803 123 4567) get 234. Null when it
/// can't be a phone number. The same rule as the server's.
String? toWhatsAppNumber(String? phone, {String countryCode = '234'}) {
  if (phone == null) return null;
  final trimmed = phone.trim();
  var digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (trimmed.startsWith('+')) {
    // Already international.
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = '$countryCode${digits.substring(1)}';
  } else if (!digits.startsWith(countryCode) && digits.length <= 10) {
    digits = '$countryCode$digits';
  }
  return digits.length >= 10 && digits.length <= 15 ? digits : null;
}

/// The link that opens a WhatsApp chat with [text] written; without a
/// usable number WhatsApp asks who to send it to.
Uri whatsAppUri(String? phone, String text) {
  final number = toWhatsAppNumber(phone);
  return Uri.parse('https://wa.me/${number ?? ''}?text=${Uri.encodeComponent(text)}');
}

/// Opens a link outside the app. Overridden in tests.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// A button that opens WhatsApp with [text] for [phone].
class SendOnWhatsAppButton extends ConsumerWidget {
  const SendOnWhatsAppButton({super.key, required this.phone, required this.text, this.label = 'Send on WhatsApp'});

  final String? phone;
  final String Function() text;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNumber = toWhatsAppNumber(phone) != null;
    return Tooltip(
      message: hasNumber ? 'Opens WhatsApp with the message ready to send' : 'No phone number: WhatsApp will ask who to send it to',
      child: OutlinedButton.icon(
        onPressed: () => openWhatsApp(context, ref, phone: phone, text: text()),
        icon: const Icon(Icons.chat_outlined, size: 18),
        label: Text(label),
      ),
    );
  }
}

// ---------------------------------------------------------------- words

String _money(double v) => currencyFormat.format(v);

/// The invoice for a sale, to the customer.
String invoiceWhatsAppText(Sale sale, {required String business}) {
  final balance = (sale.total - sale.amountPaid).clamp(0, double.infinity).toDouble();
  final lines = [for (final l in sale.lines) '• ${l.quantity} ${l.unit} ${l.productName} @ ${_money(l.unitPrice)}'];
  return [
    'Hello ${sale.customerName},',
    'Thank you for buying from $business. Invoice ${sale.reference} (${dateFormat.format(sale.saleDate)}):',
    ...lines,
    if (sale.discount > 0) 'Discount: ${_money(sale.discount)}',
    if (sale.tax > 0) 'Tax: ${_money(sale.tax)}',
    'Total: ${_money(sale.total)}',
    'Paid: ${_money(sale.amountPaid)}',
    if (balance > 0) 'Balance: ${_money(balance)}${sale.dueDate == null ? '' : ', due ${dateFormat.format(sale.dueDate!)}'}',
  ].join('\n');
}

/// A receipt for a payment, to the customer.
String receiptWhatsAppText({
  required String customer,
  required String business,
  required double amount,
  required String reference,
  required double balance,
}) =>
    'Hello $customer,\n$business received your payment of ${_money(amount)} ($reference). '
    'Your balance is now ${_money(balance < 0 ? 0 : balance)}. Thank you.';

/// A reminder of what is overdue, to the customer.
String reminderWhatsAppText({required String customer, required String business, required double overdue, required double balance}) =>
    'Hello $customer,\nThis is a friendly reminder from $business: ${_money(overdue)} is overdue on your account '
    '(your balance is ${_money(balance)}). Please get in touch to arrange payment. Thank you.';

/// A purchase order, to the supplier.
String purchaseOrderWhatsAppText(Purchase purchase, {required String business}) => [
      'Hello ${purchase.supplierName},',
      '$business would like to order (purchase order ${purchase.reference}):',
      for (final l in purchase.lines) '• ${l.quantity} ${l.unit} ${l.productName} @ ${_money(l.unitCost)}',
      'Total: ${_money(purchase.total)}',
      'Deliver to: ${purchase.warehouseName}${purchase.expectedDate == null ? '' : ', by ${dateFormat.format(purchase.expectedDate!)}'}',
      'Please confirm. Thank you.',
    ].join('\n');

/// Opens WhatsApp with [text] for [phone], from an icon or menu.
Future<void> openWhatsApp(BuildContext context, WidgetRef ref, {required String? phone, required String text}) async {
  final messenger = ScaffoldMessenger.of(context);
  final opened = await ref.read(urlOpenerProvider)(whatsAppUri(phone, text));
  if (!opened) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text("Couldn't open WhatsApp. Is it installed, or WhatsApp Web open?")));
  }
}
