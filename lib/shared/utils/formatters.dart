import 'package:intl/intl.dart';

/// Shared number/date formatting for the whole app.
///
/// These are deliberately mutable top-level variables, not `final` — call
/// [updateLocaleFormatsFromOrg] once `/api/v1/me` resolves with an
/// organization and every existing `currencyFormat.format(...)` /
/// `dateFormat.format(...)` call site picks up the change on its next
/// build, with no call-site changes needed. Before the first successful
/// `/me` (or if the org hasn't set these), they fall back to Naira and a
/// generic date pattern — the defaults every mock module's sample data was
/// already written against.
NumberFormat currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
DateFormat dateFormat = DateFormat('MMM d, yyyy');

/// Applies the signed-in organization's `currency` and `dateFormat`
/// (`"DD/MM/YYYY"`-style, per `docs/desktop-api.md`) to the shared
/// formatters above. Safe to call with unrecognized values — falls back
/// rather than throwing, since a display preference should never be able to
/// crash the app.
void updateLocaleFormatsFromOrg({String? currency, String? dateFormatPattern}) {
  if (currency != null && currency.isNotEmpty) {
    try {
      currencyFormat = NumberFormat.simpleCurrency(name: currency, decimalDigits: 0);
    } catch (_) {
      // Unrecognized ISO code — keep whatever formatter was already active.
    }
  }

  if (dateFormatPattern != null && dateFormatPattern.isNotEmpty) {
    final pattern = _intlPatternFor(dateFormatPattern);
    if (pattern != null) {
      try {
        dateFormat = DateFormat(pattern);
      } catch (_) {
        // Malformed pattern — keep the previous one.
      }
    }
  }
}

/// Maps the organization's `DD/MM/YYYY`-style preference (as stored on
/// aimify-web) to an `intl` pattern (`dd/MM/yyyy`). Falls back to `null`
/// (meaning "don't change it") for anything unrecognized, rather than
/// guessing at a format the organization didn't actually choose.
String? _intlPatternFor(String orgPattern) {
  const known = {
    'DD/MM/YYYY': 'dd/MM/yyyy',
    'MM/DD/YYYY': 'MM/dd/yyyy',
    'YYYY-MM-DD': 'yyyy-MM-dd',
    'DD-MM-YYYY': 'dd-MM-yyyy',
  };
  return known[orgPattern.toUpperCase()];
}
