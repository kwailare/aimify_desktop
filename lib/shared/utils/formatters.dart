import 'package:intl/intl.dart';

/// Shared number/date formatting. Currency defaults to Naira (₦) since
/// that's what the sample/seed data in every mock module uses; once real
/// purchase/sales endpoints exist, format using the signed-in org's actual
/// `currency` field instead of this hardcoded symbol.
final currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
final dateFormat = DateFormat('MMM d, yyyy');
