import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../credits_debts/data/debt_report.dart';
import '../parties/domain/party.dart';
import '../sales/domain/sale.dart';
import 'document_kit.dart';

/// Documents about what is owed, as PDF bytes: the receipt for a payment a
/// customer made on their account, and the debt (aging) report.

String _methodLabel(String? method) => SalePaymentMethodX.fromApi(method).label;

/// The receipt for a payment on a customer's account ([entry] has its
/// receipt number), listing the debts it settled, oldest first.
Future<Uint8List> buildAccountReceipt(DocumentKit kit, Party customer, CreditEntry entry) {
  final number = entry.receiptNumber ?? 'Receipt';
  final paid = -entry.amount;
  final settled = entry.allocations.fold(0.0, (sum, a) => sum + a.amount);
  final doc = kit.document('Receipt $number');
  doc.addPage(
    pw.Page(
      pageTheme: kit.pageTheme(),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          kit.header('Receipt', [('No.', number), ('Date', kit.dateTime(entry.createdAt))]),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 14),
            child: kit.infoBox('Received from', [customer.name, customer.phone, customer.email, customer.address]),
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
                pw.Text(kit.money(paid), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text(
                  [_methodLabel(entry.method), ?entry.note].join('  ·  '),
                  style: const pw.TextStyle(fontSize: 9, color: DocumentKit.muted),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          if (entry.allocations.isNotEmpty) ...[
            pw.Text('Applied to', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            kit.table(
              headers: ['Invoice / item', 'Amount applied'],
              rows: [
                for (final a in entry.allocations) [a.reference, kit.money(a.amount)],
              ],
              numeric: {1},
              widths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1.4)},
            ),
          ],
          kit.totals([
            ('Received', kit.money(paid)),
            ('Applied to invoices', kit.money(settled)),
            if (paid - settled > 0.004) ('Held as credit on the account', kit.money(paid - settled)),
          ]),
          pw.Spacer(),
          kit.signatures(['Received by', 'Paid by (customer)']),
          kit.footer(context),
        ],
      ),
    ),
  );
  return doc.save();
}

/// The aging report: totals by age, then every customer (or supplier) with
/// what they owe in each age band, most overdue first.
Future<Uint8List> buildDebtReport(DocumentKit kit, DebtReport report) {
  final isCustomer = report.type == PartyType.customer;
  final title = isCustomer ? 'Customer debt report' : 'Supplier debt report';
  final doc = kit.document(title);
  doc.addPage(
    pw.MultiPage(
      pageTheme: kit.pageTheme(landscape: true),
      header: (context) => context.pageNumber == 1
          ? kit.header(title, [('As of', kit.dateTime(report.asOf))])
          : pw.SizedBox(),
      footer: kit.footer,
      build: (context) => [
        kit.table(
          headers: [
            isCustomer ? 'Owed to you' : 'You owe',
            'Overdue',
            for (final b in AgeBucket.values) b.label,
          ],
          rows: [
            [
              kit.money(report.balance),
              kit.money(report.overdue),
              for (final b in AgeBucket.values) kit.money(report.buckets[b] ?? 0),
            ],
          ],
          numeric: {for (var i = 0; i < AgeBucket.values.length + 2; i++) i},
        ),
        pw.SizedBox(height: 16),
        kit.table(
          headers: [
            isCustomer ? 'Customer' : 'Supplier',
            'Phone',
            'Terms',
            'Balance',
            for (final b in AgeBucket.values) b.label,
            'Last paid',
          ],
          rows: [
            for (final p in report.parties)
              [
                p.name,
                p.phone ?? '',
                '${p.paymentTermsDays} days',
                kit.money(p.balance),
                for (final b in AgeBucket.values) (p.buckets[b] ?? 0) > 0 ? kit.money(p.buckets[b]!) : '',
                p.lastPaymentAt == null ? 'Never' : kit.date(p.lastPaymentAt!),
              ],
          ],
          numeric: {3, 4, 5, 6, 7, 8},
          widths: {
            0: const pw.FlexColumnWidth(2.6),
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(0.9),
            3: const pw.FlexColumnWidth(1.3),
            for (var i = 4; i < 9; i++) i: const pw.FlexColumnWidth(1.2),
            9: const pw.FlexColumnWidth(1.2),
          },
        ),
        if (report.parties.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text('Nothing is owed.', style: const pw.TextStyle(fontSize: 9, color: DocumentKit.muted)),
          ),
        if (report.credit > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              isCustomer
                  ? 'Customers in credit (owed back to them): ${kit.money(report.credit)}'
                  : 'Suppliers who owe you back: ${kit.money(report.credit)}',
              style: const pw.TextStyle(fontSize: 9, color: DocumentKit.muted),
            ),
          ),
      ],
    ),
  );
  return doc.save();
}
