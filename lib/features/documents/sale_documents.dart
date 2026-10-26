import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../parties/domain/party.dart';
import '../sales/domain/sale.dart';
import 'document_kit.dart';

/// Documents that come from sales, as PDF bytes.

List<String?> _customerLines(Sale s, Party? customer) => s.isWalkIn
    ? ['Walk-in customer']
    : [s.customerName, customer?.phone, customer?.email, customer?.address];

pw.Widget _boxes(pw.Widget left, pw.Widget right) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [pw.Expanded(child: left), pw.SizedBox(width: 12), pw.Expanded(child: right)],
      ),
    );

/// The invoice for a sale, with what was paid and what is still due. A
/// voided sale is stamped VOID.
Future<Uint8List> buildInvoice(DocumentKit kit, Sale s, {Party? customer}) {
  final doc = kit.document('Invoice ${s.reference}');
  final anyDiscount = s.lines.any((l) => l.discounted);
  doc.addPage(
    pw.MultiPage(
      pageTheme: kit.pageTheme(watermark: s.isVoided ? 'VOID' : null),
      header: (context) => context.pageNumber == 1
          ? kit.header('Invoice', [
              ('No.', s.reference),
              ('Date', kit.dateTime(s.saleDate)),
              if (s.createdByName != null) ('Served by', s.createdByName!),
            ])
          : pw.SizedBox(),
      footer: kit.footer,
      build: (context) => [
        _boxes(
          kit.infoBox('Bill to', _customerLines(s, customer)),
          kit.infoBox('From', [s.warehouseName, if (s.isVoided) 'VOIDED — ${s.voidReason ?? ''}']),
        ),
        kit.table(
          headers: ['#', 'Product', 'Qty', if (anyDiscount) 'List price', 'Unit price', 'Amount'],
          rows: [
            for (final (i, l) in s.lines.indexed)
              [
                '${i + 1}',
                '${l.productName}  ·  ${l.sku}',
                '${l.quantity} ${l.unit}',
                if (anyDiscount) kit.money(l.listPrice),
                kit.money(l.unitPrice),
                kit.money(l.lineTotal),
              ],
          ],
          numeric: anyDiscount ? {0, 2, 3, 4, 5} : {0, 2, 3, 4},
          widths: {
            0: const pw.FixedColumnWidth(22),
            1: const pw.FlexColumnWidth(3.4),
            2: const pw.FlexColumnWidth(1.2),
            if (anyDiscount) 3: const pw.FlexColumnWidth(1.3),
            (anyDiscount ? 4 : 3): const pw.FlexColumnWidth(1.3),
            (anyDiscount ? 5 : 4): const pw.FlexColumnWidth(1.5),
          },
        ),
        kit.totals([
          ('Subtotal', kit.money(s.subtotal)),
          if (s.discount > 0) ('Discount', '- ${kit.money(s.discount)}'),
          if (s.tax > 0) (kit.company.taxName ?? 'Tax', kit.money(s.tax)),
          ('Total', kit.money(s.total)),
          ('Paid', kit.money(s.amountPaid)),
          (s.isVoided ? 'Balance due (voided)' : 'Balance due', kit.money(s.balance)),
        ]),
        if (s.notes != null) ...[
          pw.SizedBox(height: 14),
          pw.Text('Notes', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: DocumentKit.muted)),
          pw.Text(s.notes!, style: const pw.TextStyle(fontSize: 9)),
        ],
        pw.SizedBox(height: 18),
        pw.Text(
          s.isPaid ? 'Paid in full. Thank you for your business.' : 'Thank you for your business.',
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        ),
        kit.signatures(['Issued by', 'Received by (customer)']),
      ],
    ),
  );
  return doc.save();
}

/// Where a sale stood after payment number [paymentIndex] (0-based, oldest
/// first).
({double paidToDate, double balanceAfter}) salePaymentStanding(Sale s, int paymentIndex) {
  final paid = s.payments.take(paymentIndex + 1).fold(0.0, (sum, p) => sum + p.amount);
  return (paidToDate: paid, balanceAfter: s.total - paid);
}

/// A receipt for one payment received on a sale: INV-0001-RCPT-1, -2, ...
Future<Uint8List> buildSaleReceipt(DocumentKit kit, Sale s, int paymentIndex, {Party? customer}) {
  final payment = s.payments[paymentIndex];
  final standing = salePaymentStanding(s, paymentIndex);
  final number = '${s.reference}-RCPT-${paymentIndex + 1}';
  final doc = kit.document('Receipt $number');
  doc.addPage(
    pw.Page(
      pageTheme: kit.pageTheme(),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          kit.header('Receipt', [
            ('No.', number),
            ('Date', kit.dateTime(payment.createdAt)),
            ('Invoice', s.reference),
          ]),
          _boxes(
            kit.infoBox('Received from', _customerLines(s, customer)),
            kit.infoBox('For', ['Invoice ${s.reference}', 'Dated ${kit.date(s.saleDate)}', 'Total ${kit.money(s.total)}']),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 16),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: DocumentKit.accent, width: 1.2),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              children: [
                pw.Text('AMOUNT RECEIVED',
                    style: pw.TextStyle(fontSize: 8, color: DocumentKit.muted, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(kit.money(payment.amount), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(
                  [payment.method.label, ?payment.note].join('  ·  '),
                  style: const pw.TextStyle(fontSize: 9, color: DocumentKit.muted),
                ),
              ],
            ),
          ),
          kit.totals([
            ('Invoice total', kit.money(s.total)),
            ('Paid to date', kit.money(standing.paidToDate)),
            ('Balance after this payment', kit.money(standing.balanceAfter)),
          ]),
          if (payment.userName != null) ...[
            pw.SizedBox(height: 10),
            pw.Text('Received by ${payment.userName}', style: const pw.TextStyle(fontSize: 8.5, color: DocumentKit.muted)),
          ],
          pw.Spacer(),
          kit.signatures(['Received by', 'Paid by (customer)']),
          kit.footer(context),
        ],
      ),
    ),
  );
  return doc.save();
}
