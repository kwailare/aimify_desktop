import '../parties/domain/party.dart';
import '../purchases/domain/purchase.dart';

/// The figures each printed document shows, worked out separately from the
/// PDF drawing so they can be checked directly.

/// One product's line on a goods received note.
class GrnLine {
  const GrnLine({
    required this.productName,
    required this.sku,
    required this.unit,
    required this.ordered,
    required this.receivedNow,
    required this.receivedToDate,
  });

  final String productName;
  final String sku;
  final String unit;
  final int ordered;
  final int receivedNow;

  /// Everything received up to and including this delivery.
  final int receivedToDate;

  int get outstandingAfter => ordered - receivedToDate;
}

/// The lines of delivery number [receiptIndex] (0-based, oldest first).
/// Receipts record products, so a product on two lines is shown once.
List<GrnLine> goodsReceivedLines(Purchase purchase, int receiptIndex) {
  final receipt = purchase.receipts[receiptIndex];
  final now = <String, int>{};
  for (final l in receipt.lines) {
    now[l.productId] = (now[l.productId] ?? 0) + l.quantity;
  }
  final toDate = <String, int>{};
  for (final r in purchase.receipts.take(receiptIndex + 1)) {
    for (final l in r.lines) {
      toDate[l.productId] = (toDate[l.productId] ?? 0) + l.quantity;
    }
  }
  final seen = <String>{};
  final lines = <GrnLine>[];
  for (final line in purchase.lines) {
    if (!now.containsKey(line.productId) || !seen.add(line.productId)) continue;
    final ordered = purchase.lines
        .where((l) => l.productId == line.productId)
        .fold(0, (sum, l) => sum + l.quantity);
    lines.add(
      GrnLine(
        productName: line.productName,
        sku: line.sku,
        unit: line.unit,
        ordered: ordered,
        receivedNow: now[line.productId]!,
        receivedToDate: toDate[line.productId] ?? 0,
      ),
    );
  }
  return lines;
}

/// Where a purchase stood after payment number [paymentIndex] (0-based,
/// oldest first).
({double paidToDate, double balanceAfter}) paymentStanding(Purchase purchase, int paymentIndex) {
  final paidToDate = purchase.payments
      .take(paymentIndex + 1)
      .fold(0.0, (sum, p) => sum + p.amount);
  return (paidToDate: paidToDate, balanceAfter: purchase.total - paidToDate);
}

/// One line of a supplier statement, with the balance after it.
class StatementRow {
  const StatementRow({required this.entry, required this.balance});

  final CreditEntry entry;
  final double balance;

  /// What raised the balance (purchases, upward adjustments).
  double get charge => entry.amount > 0 ? entry.amount : 0;

  /// What lowered it (payments, downward adjustments).
  double get credit => entry.amount < 0 ? -entry.amount : 0;
}

class Statement {
  const Statement({
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.rows,
  });

  /// `null` means from the very first entry.
  final DateTime? from;

  /// Exclusive end of the period.
  final DateTime to;
  final double openingBalance;
  final List<StatementRow> rows;

  double get totalCharges => rows.fold(0.0, (sum, r) => sum + r.charge);
  double get totalCredits => rows.fold(0.0, (sum, r) => sum + r.credit);
  double get closingBalance => rows.isEmpty ? openingBalance : rows.last.balance;
}

/// Builds a statement from the period's [entries] (any order) and what was
/// owed before it.
Statement buildStatement({
  required DateTime? from,
  required DateTime to,
  required double openingBalance,
  required List<CreditEntry> entries,
}) {
  final sorted = [...entries]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  var running = openingBalance;
  final rows = <StatementRow>[];
  for (final e in sorted) {
    running += e.amount;
    rows.add(StatementRow(entry: e, balance: running));
  }
  return Statement(from: from, to: to, openingBalance: openingBalance, rows: rows);
}
