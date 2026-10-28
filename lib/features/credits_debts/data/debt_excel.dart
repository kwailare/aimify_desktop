import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../parties/domain/party.dart';
import 'debt_report.dart';

/// The debt report as a spreadsheet: one sheet with each customer (or
/// supplier) and what they owe in each age band, and one with every open
/// debt.
List<int> buildDebtReportExcel(DebtReport report) {
  final workbook = Excel.createExcel();
  final date = DateFormat('yyyy-MM-dd');
  final who = report.type == PartyType.customer ? 'Customer' : 'Supplier';

  final summary = workbook[workbook.getDefaultSheet()!];
  summary.appendRow([
    for (final h in [
      who, 'Phone', 'Terms (days)', 'Balance', 'Overdue',
      for (final b in AgeBucket.values) b.label,
      'Most days overdue', 'Last payment', 'Days since payment',
    ])
      TextCellValue(h),
  ]);
  for (final p in report.parties) {
    summary.appendRow([
      TextCellValue(p.name),
      TextCellValue(p.phone ?? ''),
      IntCellValue(p.paymentTermsDays),
      DoubleCellValue(p.balance),
      DoubleCellValue(p.overdue),
      for (final b in AgeBucket.values) DoubleCellValue(p.buckets[b] ?? 0),
      IntCellValue(p.maxDaysOverdue),
      TextCellValue(p.lastPaymentAt == null ? '' : date.format(p.lastPaymentAt!)),
      p.daysSinceLastPayment == null ? TextCellValue('') : IntCellValue(p.daysSinceLastPayment!),
    ]);
  }
  summary.appendRow([
    TextCellValue('Total'),
    TextCellValue(''),
    TextCellValue(''),
    DoubleCellValue(report.balance),
    DoubleCellValue(report.overdue),
    for (final b in AgeBucket.values) DoubleCellValue(report.buckets[b] ?? 0),
  ]);

  final items = workbook['Open items'];
  items.appendRow([
    for (final h in [who, 'Item', 'Date', 'Due', 'Amount', 'Still open', 'Days overdue']) TextCellValue(h),
  ]);
  for (final p in report.parties) {
    for (final i in p.items) {
      items.appendRow([
        TextCellValue(p.name),
        TextCellValue(i.reference),
        TextCellValue(date.format(i.date)),
        TextCellValue(date.format(i.dueDate)),
        DoubleCellValue(i.amount),
        DoubleCellValue(i.openAmount),
        IntCellValue(i.daysOverdue),
      ]);
    }
  }
  workbook.rename(workbook.getDefaultSheet()!, 'By ${who.toLowerCase()}');
  return workbook.encode() ?? const [];
}
