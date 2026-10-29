import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../expenses/data/expense_report.dart';
import '../sales/domain/sale.dart';
import 'document_kit.dart';

/// The expense report as a PDF: totals by category (with budgets), by month
/// and by warehouse, then every expense in the period.
Future<Uint8List> buildExpenseReportPdf(DocumentKit kit, ExpenseReport r) {
  final doc = kit.document('Expense report');
  final period = '${kit.date(r.from)} – ${kit.date(r.to.subtract(const Duration(days: 1)))}';
  doc.addPage(
    pw.MultiPage(
      pageTheme: kit.pageTheme(),
      header: (context) => context.pageNumber == 1
          ? kit.header('Expense report', [('Period', period), ('Expenses', '${r.count}'), ('Total', kit.money(r.total))])
          : pw.SizedBox(),
      footer: kit.footer,
      build: (context) => [
        kit.table(
          headers: ['Category', 'Expenses', 'Spent', 'Budget', 'Left'],
          rows: [
            for (final c in r.byCategory)
              [
                c.name,
                '${c.count}',
                kit.money(c.total),
                c.hasBudget ? kit.money(c.budget) : '',
                c.hasBudget ? (c.overBudget ? 'Over by ${kit.money(-c.left)}' : kit.money(c.left)) : '',
              ],
          ],
          numeric: {1, 2, 3, 4},
          widths: {
            0: const pw.FlexColumnWidth(2.6),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1.4),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.6),
          },
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: kit.table(
                headers: ['Month', 'Spent'],
                rows: [for (final (m, t) in r.byMonth) [DateFormat('MMM yyyy').format(m), kit.money(t)]],
                numeric: {1},
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: kit.table(
                headers: ['Warehouse', 'Spent'],
                rows: [for (final (w, t) in r.byWarehouse) [w, kit.money(t)]],
                numeric: {1},
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        kit.table(
          headers: ['Ref.', 'Date', 'Category', 'Description / paid to', 'Paid by', 'Amount'],
          rows: [
            for (final e in r.expenses)
              [
                e.reference,
                kit.date(e.expenseDate),
                e.categoryName,
                [?e.description, if (e.payee != null) 'to ${e.payee}'].join(' · '),
                e.paymentMethod.label,
                kit.money(e.amount),
              ],
          ],
          numeric: {5},
          widths: {
            0: const pw.FlexColumnWidth(1.1),
            1: const pw.FlexColumnWidth(1.1),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(3),
            4: const pw.FlexColumnWidth(1.1),
            5: const pw.FlexColumnWidth(1.3),
          },
        ),
        kit.totals([('Total', kit.money(r.total))]),
      ],
    ),
  );
  return doc.save();
}
