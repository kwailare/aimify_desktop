import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Shared number/date formatting for the whole app.
///
/// These are deliberately mutable top-level variables, not `final` — call
/// [updateLocaleFormatsFromOrg] once `/api/v1/me` resolves with an
/// organization and every existing `currencyFormat.format(...)` /
/// `dateFormat.format(...)` call site picks up the change on its next
/// build, with no call-site changes needed. Before the first successful
/// `/me` (or if the org hasn't set these), they fall back to Naira, the
/// computer's own time zone and a generic date pattern.
NumberFormat currencyFormat = NumberFormat.currency(symbol: '₦', decimalDigits: 0);
OrgDateFormat dateFormat = OrgDateFormat('MMM d, yyyy');

/// Like [dateFormat] but with the time of day (24-hour) — for records where
/// *when* matters, such as the stock ledger.
OrgDateFormat dateTimeFormat = OrgDateFormat('MMM d, yyyy HH:mm');

/// The organization's tax, from its company profile on the website. `0`
/// means none is set.
double orgTaxRate = 0;
String orgTaxName = 'Tax';

/// Formats a moment in time in the organization's time zone.
///
/// Timestamps from the server are exact instants. Showing them in the
/// organization's own zone (e.g. `Africa/Lagos`) rather than whatever zone
/// this computer is set to keeps the day and hour the same for everyone on
/// the team — a stock-out at 23:30 in Lagos must not read as tomorrow to a
/// laptop set to another zone. With no (or an unknown) zone it falls back to
/// this computer's local time.
class OrgDateFormat {
  OrgDateFormat(String pattern, [tz.Location? location])
      : _format = DateFormat(pattern),
        _location = location;

  final DateFormat _format;
  final tz.Location? _location;

  String format(DateTime moment) {
    final location = _location;
    return _format.format(location == null ? moment.toLocal() : tz.TZDateTime.from(moment, location));
  }
}

String _datePattern = 'MMM d, yyyy';
tz.Location? _location;
bool _timeZonesLoaded = false;

/// The organization's time zone, if it has a known one.
tz.Location? get orgLocation => _location;

/// Applies the signed-in organization's `currency`, `dateFormat`
/// (`"DD/MM/YYYY"`-style), `timezone` (`"Africa/Lagos"`) and tax to the
/// shared formatters above. Safe to call with unrecognized values — falls
/// back rather than throwing, since a display preference should never be
/// able to crash the app.
void updateLocaleFormatsFromOrg({
  String? currency,
  String? dateFormatPattern,
  String? timezone,
  double? taxRate,
  String? taxName,
}) {
  if (currency != null && currency.isNotEmpty) {
    try {
      currencyFormat = NumberFormat.simpleCurrency(name: currency, decimalDigits: 0);
    } catch (_) {
      // Unrecognized ISO code — keep whatever formatter was already active.
    }
  }

  if (dateFormatPattern != null && dateFormatPattern.isNotEmpty) {
    final pattern = _intlPatternFor(dateFormatPattern);
    if (pattern != null) _datePattern = pattern;
  }

  if (timezone != null && timezone.isNotEmpty) {
    try {
      if (!_timeZonesLoaded) {
        tzdata.initializeTimeZones();
        _timeZonesLoaded = true;
      }
      _location = tz.getLocation(timezone);
    } catch (_) {
      // Unknown zone name — keep showing this computer's local time.
      _location = null;
    }
  }

  try {
    dateFormat = OrgDateFormat(_datePattern, _location);
    dateTimeFormat = OrgDateFormat('$_datePattern HH:mm', _location);
  } catch (_) {
    // Malformed pattern — keep the previous formatters.
  }

  if (taxRate != null && taxRate >= 0) orgTaxRate = taxRate;
  if (taxName != null && taxName.trim().isNotEmpty) orgTaxName = taxName.trim();
}

/// True when the organization has set a tax rate above zero.
bool get hasTax => orgTaxRate > 0;

/// [price] with the organization's tax added. Prices in Aimify are entered
/// and stored without tax; this is what a customer would pay with it.
double priceWithTax(double price) => price * (1 + orgTaxRate / 100);

/// e.g. `VAT 7.5%` — the rate without trailing zeros.
String get taxLabel {
  final rate = orgTaxRate == orgTaxRate.roundToDouble()
      ? orgTaxRate.toInt().toString()
      : orgTaxRate.toString();
  return '$orgTaxName $rate%';
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
