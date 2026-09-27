// The organization's display preferences from its company profile: time
// zone, date format and tax. Server timestamps are exact instants, so they
// must read the same for everyone on the team whatever zone their computer
// is set to.

import 'package:aimify_desktop/shared/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    updateLocaleFormatsFromOrg(
      currency: 'NGN',
      dateFormatPattern: 'DD/MM/YYYY',
      timezone: 'Africa/Lagos',
      taxRate: 0,
      taxName: 'Tax',
    );
  });

  group('time zone', () {
    test('an instant is shown in the organization zone, not the computer zone', () {
      // 23:30 UTC on 26 Sep is 00:30 on 27 Sep in Lagos (UTC+1).
      final instant = DateTime.utc(2026, 9, 26, 23, 30);

      expect(dateFormat.format(instant), '27/09/2026');
      expect(dateTimeFormat.format(instant), '27/09/2026 00:30');
    });

    test('a zone ahead of and behind UTC both convert correctly', () {
      final instant = DateTime.utc(2026, 9, 26, 23, 30);

      updateLocaleFormatsFromOrg(timezone: 'Pacific/Auckland');
      expect(dateTimeFormat.format(instant), '27/09/2026 12:30'); // UTC+13 (NZDT)

      updateLocaleFormatsFromOrg(timezone: 'America/New_York');
      expect(dateTimeFormat.format(instant), '26/09/2026 19:30'); // UTC-4 (EDT)
    });

    test('the same instant reads the same whether it arrives as UTC or local', () {
      final utc = DateTime.utc(2026, 9, 26, 12, 0);
      final local = utc.toLocal();

      expect(dateTimeFormat.format(local), dateTimeFormat.format(utc));
    });

    test('an unknown zone name falls back instead of crashing', () {
      updateLocaleFormatsFromOrg(timezone: 'Not/AZone');

      expect(() => dateTimeFormat.format(DateTime.utc(2026, 9, 26, 12)), returnsNormally);
    });
  });

  group('date format', () {
    test('follows the organization preference', () {
      final instant = DateTime.utc(2026, 9, 5, 12);

      updateLocaleFormatsFromOrg(dateFormatPattern: 'MM/DD/YYYY');
      expect(dateFormat.format(instant), '09/05/2026');

      updateLocaleFormatsFromOrg(dateFormatPattern: 'YYYY-MM-DD');
      expect(dateFormat.format(instant), '2026-09-05');
    });

    test('an unrecognized preference keeps the current one', () {
      updateLocaleFormatsFromOrg(dateFormatPattern: 'whatever');

      expect(dateFormat.format(DateTime.utc(2026, 9, 5, 12)), '05/09/2026');
    });
  });

  group('tax', () {
    test('no tax set means nothing is added or shown', () {
      expect(hasTax, isFalse);
      expect(priceWithTax(1000), 1000);
    });

    test('a rate is added to the price and labelled without trailing zeros', () {
      updateLocaleFormatsFor(rate: 7.5, name: 'VAT');

      expect(hasTax, isTrue);
      expect(priceWithTax(1000), closeTo(1075, 1e-9));
      expect(taxLabel, 'VAT 7.5%');

      updateLocaleFormatsFor(rate: 5, name: 'VAT');
      expect(taxLabel, 'VAT 5%');
    });

    test('a missing tax name falls back to a generic label', () {
      updateLocaleFormatsFromOrg(taxRate: 10, taxName: '   ');

      expect(taxLabel, contains('10%'));
    });
  });
}

void updateLocaleFormatsFor({required double rate, required String name}) =>
    updateLocaleFormatsFromOrg(taxRate: rate, taxName: name);
