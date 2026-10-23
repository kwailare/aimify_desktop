import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../parties/domain/party.dart';
import '../purchases/domain/purchase.dart';
import '../warehouses/domain/warehouse.dart';
import 'document_data.dart';
import 'document_kit.dart';

/// The four documents that come from purchases and suppliers, as PDF bytes.

List<String?> _supplierLines(Purchase p, Party? supplier) => [
      p.supplierName,
      if (supplier?.contactPerson != null) 'Attn: ${supplier!.contactPerson}',
      supplier?.phone,
      supplier?.email,
      supplier?.address,
    ];

List<String?> _warehouseLines(Purchase p, Warehouse? warehouse) => [
      p.warehouseName,
      warehouse?.address,
      if (warehouse?.managerName != null) 'Manager: ${warehouse!.managerName}',
      warehouse?.phone,
    ];

pw.Widget _boxes(DocumentKit kit, pw.Widget left, pw.Widget right) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 14),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [pw.Expanded(child: left), pw.SizedBox(width: 12), pw.Expanded(child: right)],
      ),
    );

/// The purchase as sent to the supplier.
Future<Uint8List> buildPurchaseOrder(
  DocumentKit kit,
  Purchase p, {
  Party? supplier,
  Warehouse? warehouse,
}) {
  final doc = kit.document('Purchase order ${p.reference}');
  final watermark = switch (p.status) {
    PurchaseStatus.draft => 'DRAFT',
    PurchaseStatus.cancelled => 'CANCELLED',
    _ => null,
  };
  doc.addPage(
    pw.MultiPage(
      pageTheme: kit.pageTheme(watermark: watermark),
      header: (context) => context.pageNumber == 1
          ? kit.header('Purchase order', [
              ('No.', p.reference),
              ('Date', kit.date(p.orderDate)),
              if (p.expectedDate != null) ('Expected', kit.date(p.expectedDate!)),
              ('Status', p.status.label),
            ])
          : pw.SizedBox(),
      footer: kit.footer,
      build: (context) => [
        _boxes(kit, kit.infoBox('Supplier', _supplierLines(p, supplier)),
            kit.infoBox('Deliver to', _warehouseLines(p, warehouse))),
        kit.table(
          headers: ['#', 'Product', 'SKU', 'Qty', 'Unit cost', 'Line total'],
          rows: [
            for (final (i, l) in p.lines.indexed)
              ['${i + 1}', l.productName, l.sku, '${l.quantity} ${l.unit}', kit.money(l.unitCost), kit.money(l.lineTotal)],
          ],
          numeric: {0, 3, 4, 5},
          widths: {
            0: const pw.FixedColumnWidth(22),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.4),
            5: const pw.FlexColumnWidth(1.5),
          },
        ),
        kit.totals(
          [
            ('Goods', kit.money(p.subtotal)),
            if (p.discount > 0) ('Discount', '- ${kit.money(p.discount)}'),
            if (p.tax > 0) (kit.company.taxName ?? 'Tax', kit.money(p.tax)),
            ('Total', kit.money(p.total)),
            if (p.amountPaid > 0) ...[
              ('Paid', kit.money(p.amountPaid)),
              ('Balance due', kit.money(p.balance)),
            ],
          ],
        ),
        if (p.notes != null) ...[
          pw.SizedBox(height: 14),
          pw.Text('Notes', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: DocumentKit.muted)),
          pw.Text(p.notes!, style: const pw.TextStyle(fontSize: 9)),
        ],
        kit.signatures(['Authorised by', 'Supplier acknowledgement']),
      ],
    ),
  );
  return doc.save();
}

/// One delivery received on a purchase ([receiptIndex] is 0-based, oldest
/// first): numbered PO-0001-GRN-1, -2, ...
Future<Uint8List> buildGoodsReceivedNote(
  DocumentKit kit,
  Purchase p,
  int receiptIndex, {
  Party? supplier,
  Warehouse? warehouse,
}) {
  final receipt = p.receipts[receiptIndex];
  final lines = goodsReceivedLines(p, receiptIndex);
  final number = '${p.reference}-GRN-${receiptIndex + 1}';
  final units = lines.fold(0, (s, l) => s + l.receivedNow);
  final doc = kit.document('Goods received note $number');
  doc.addPage(
    pw.MultiPage(
      pageTheme: kit.pageTheme(),
      header: (context) => context.pageNumber == 1
          ? kit.header('Goods received note', [
              ('No.', number),
              ('Received', kit.dateTime(receipt.createdAt)),
              ('Purchase', p.reference),
              if (receipt.userName != null) ('By', receipt.userName!),
            ])
          : pw.SizedBox(),
      footer: kit.footer,
      build: (context) => [
        _boxes(kit, kit.infoBox('Supplier', _supplierLines(p, supplier)),
            kit.infoBox('Received into', _warehouseLines(p, warehouse))),
        kit.table(
          headers: ['Product', 'SKU', 'Ordered', 'Received now', 'Received to date', 'Still to come'],
          rows: [
            for (final l in lines)
              [
                l.productName,
                l.sku,
                '${l.ordered} ${l.unit}',
                '${l.receivedNow}',
                '${l.receivedToDate}',
                '${l.outstandingAfter}',
              ],
          ],
          numeric: {2, 3, 4, 5},
          widths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.3),
            5: const pw.FlexColumnWidth(1.2),
          },
        ),
        kit.totals([('Units received', '$units')]),
        kit.signatures(['Received by', 'Checked by', 'Delivered by (supplier)']),
      ],
    ),
  );
  return doc.save();
}

/// A payment made on a purchase ([paymentIndex] is 0-based, oldest first):
/// numbered PO-0001-PAY-1, -2, ...
Future<Uint8List> buildPaymentReceipt(DocumentKit kit, Purchase p, int paymentIndex, {Party? supplier}) {
  final payment = p.payments[paymentIndex];
  final standing = paymentStanding(p, paymentIndex);
  final number = '${p.reference}-PAY-${paymentIndex + 1}';
  final doc = kit.document('Payment receipt $number');
  doc.addPage(
    pw.Page(
      pageTheme: kit.pageTheme(),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          kit.header('Payment receipt', [
            ('No.', number),
            ('Date', kit.dateTime(payment.createdAt)),
            ('Purchase', p.reference),
          ]),
          _boxes(
            kit,
            kit.infoBox('Paid to', _supplierLines(p, supplier)),
            kit.infoBox('For', ['Purchase ${p.reference}', 'Ordered ${kit.date(p.orderDate)}', 'Into ${p.warehouseName}']),
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
                pw.Text('AMOUNT PAID', style: pw.TextStyle(fontSize: 8, color: DocumentKit.muted, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(kit.money(payment.amount), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                if (payment.note != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(payment.note!, style: const pw.TextStyle(fontSize: 9, color: DocumentKit.muted)),
                ],
              ],
            ),
          ),
          kit.totals([
            ('Purchase total', kit.money(p.total)),
            ('Paid to date', kit.money(standing.paidToDate)),
            ('Balance after this payment', kit.money(standing.balanceAfter)),
          ]),
          if (payment.userName != null) ...[
            pw.SizedBox(height: 10),
            pw.Text('Recorded by ${payment.userName}', style: const pw.TextStyle(fontSize: 8.5, color: DocumentKit.muted)),
          ],
          pw.Spacer(),
          kit.signatures(['Paid by', 'Received by (supplier)']),
          kit.footer(context),
        ],
      ),
    ),
  );
  return doc.save();
}

String _describe(CreditEntry e) {
  final note = e.note?.trim();
  if (note != null && note.isNotEmpty) return note;
  return switch (e.kind) {
    CreditKind.charge => 'Invoice',
    CreditKind.payment => 'Payment',
    CreditKind.adjustment => 'Adjustment',
  };
}

/// A supplier's account over a period: opening balance, every purchase,
/// payment and adjustment with the running balance, and the closing
/// balance. The balance is what the business owes the supplier.
Future<Uint8List> buildSupplierStatement(DocumentKit kit, Party supplier, Statement statement) {
  final period =
      '${statement.from == null ? 'Start' : kit.date(statement.from!)} – '
      '${kit.date(statement.to.subtract(const Duration(seconds: 1)))}';
  final doc = kit.document('Statement ${supplier.name}');
  doc.addPage(
    pw.MultiPage(
      pageTheme: kit.pageTheme(),
      header: (context) => context.pageNumber == 1
          ? kit.header('Supplier statement', [('Period', period), ('Date', kit.date(DateTime.now()))])
          : pw.SizedBox(),
      footer: kit.footer,
      build: (context) => [
        _boxes(
          kit,
          kit.infoBox('Supplier', [
            supplier.name,
            if (supplier.contactPerson != null) 'Attn: ${supplier.contactPerson}',
            supplier.phone,
            supplier.email,
            supplier.address,
          ]),
          kit.infoBox('Summary', [
            'Closing balance ${kit.money(statement.closingBalance)}',
            'Opening balance ${kit.money(statement.openingBalance)}',
            'Purchases & charges ${kit.money(statement.totalCharges)}',
            'Payments & credits ${kit.money(statement.totalCredits)}',
          ]),
        ),
        kit.table(
          headers: ['Date', 'Description', 'Purchases', 'Payments', 'Balance'],
          rows: [
            ['', 'Opening balance', '', '', kit.money(statement.openingBalance)],
            for (final r in statement.rows)
              [
                kit.date(r.entry.createdAt),
                _describe(r.entry),
                r.charge > 0 ? kit.money(r.charge) : '',
                r.credit > 0 ? kit.money(r.credit) : '',
                kit.money(r.balance),
              ],
          ],
          numeric: {2, 3, 4},
          widths: {
            0: const pw.FlexColumnWidth(1.3),
            1: const pw.FlexColumnWidth(3.4),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.6),
          },
        ),
        kit.totals([
          ('Purchases & charges', kit.money(statement.totalCharges)),
          ('Payments & credits', kit.money(statement.totalCredits)),
          (statement.closingBalance < 0 ? 'Closing balance (supplier owes you)' : 'Closing balance owed', kit.money(statement.closingBalance.abs())),
        ]),
        if (statement.rows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text('Nothing was recorded on this account in the period.',
                style: const pw.TextStyle(fontSize: 9, color: DocumentKit.muted)),
          ),
      ],
    ),
  );
  return doc.save();
}
