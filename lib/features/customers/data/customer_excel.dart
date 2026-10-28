import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../parties/domain/party.dart';
import 'customer_types.dart';

/// One spreadsheet row ready to become a customer.
class ImportedCustomerRow {
  const ImportedCustomerRow({
    required this.rowNumber,
    required this.input,
    this.openingBalance = 0,
    this.warnings = const [],
  });

  /// As a spreadsheet program shows it (row 1 is the header).
  final int rowNumber;
  final PartyInput input;

  /// What they already owed when they were brought in, recorded as a
  /// charge right after the customer is created.
  final double openingBalance;
  final List<String> warnings;
}

class CustomerRowError {
  const CustomerRowError({required this.rowNumber, required this.messages});

  final int rowNumber;
  final List<String> messages;
}

class CustomerImport {
  const CustomerImport({this.rows = const [], this.errors = const [], this.skipped = const [], this.sheetError});

  final List<ImportedCustomerRow> rows;
  final List<CustomerRowError> errors;

  /// Rows left out because the customer already exists (by name).
  final List<CustomerRowError> skipped;

  /// The file couldn't be read at all.
  final String? sheetError;
}

const _headers = <String, List<String>>{
  'name': ['name', 'customer', 'customername', 'businessname', 'supplier', 'suppliername', 'vendor'],
  'contactPerson': ['contactperson', 'contact', 'attention'],
  'terms': ['paymentterms', 'terms', 'termsdays', 'paymenttermsdays'],
  'type': ['type', 'customertype', 'category'],
  'phone': ['phone', 'phonenumber', 'mobile', 'telephone', 'tel'],
  'email': ['email', 'emailaddress'],
  'address': ['address', 'location'],
  'creditLimit': ['creditlimit', 'limit'],
  'openingBalance': ['openingbalance', 'balance', 'owes', 'amountowed', 'debt'],
  'notes': ['notes', 'note', 'comments'],
};

String _normalize(String raw) => raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Names compared the way people mean them: case and spacing ignored.
String customerNameKey(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _text(Data? cell) => cell?.value?.toString().trim() ?? '';

/// Reads the first sheet of an `.xlsx` into customers. Columns are matched
/// by header name in any order; only Name is required. A Type is matched by
/// name against [types] (unknown types import without one, with a warning);
/// an empty Credit limit or Payment terms takes the type's default. Names
/// already among [existing] customers, or repeated in the file, are skipped.
CustomerImport parseCustomerWorkbook(
  List<int> bytes, {
  List<CustomerType> types = const [],
  List<Party> existing = const [],
}) =>
    parsePartyWorkbook(bytes, type: PartyType.customer, types: types, existing: existing);

/// The same for customers or suppliers: suppliers have a Contact person and
/// no type or credit limit; both have Payment terms (days) and an Opening
/// balance (what is owed when they are brought in).
CustomerImport parsePartyWorkbook(
  List<int> bytes, {
  required PartyType type,
  List<CustomerType> types = const [],
  List<Party> existing = const [],
}) {
  final isCustomer = type == PartyType.customer;
  final Excel workbook;
  try {
    workbook = Excel.decodeBytes(bytes);
  } catch (_) {
    return const CustomerImport(sheetError: "That file couldn't be read. Choose a .xlsx spreadsheet.");
  }
  final sheetName = workbook.sheets.keys.firstOrNull;
  final rows = sheetName == null ? const <List<Data?>>[] : workbook.sheets[sheetName]!.rows;
  if (rows.isEmpty) return const CustomerImport(sheetError: 'The sheet is empty.');

  final column = <String, int>{};
  for (var c = 0; c < rows.first.length; c++) {
    final header = _normalize(_text(rows.first[c]));
    for (final entry in _headers.entries) {
      if (!column.containsKey(entry.key) && entry.value.contains(header)) column[entry.key] = c;
    }
  }
  if (!column.containsKey('name')) {
    return const CustomerImport(sheetError: 'The first row must have headers, including a Name column.');
  }

  final typeByName = {for (final t in types) customerNameKey(t.name): t};
  final taken = {for (final p in existing) customerNameKey(p.name): 'already a ${type.label.toLowerCase()}'};
  final imported = <ImportedCustomerRow>[];
  final errors = <CustomerRowError>[];
  final skipped = <CustomerRowError>[];

  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    String cell(String field) {
      final c = column[field];
      return c == null || c >= row.length ? '' : _text(row[c]);
    }

    if (row.every((c) => _text(c).isEmpty)) continue;
    final rowNumber = r + 1;
    final messages = <String>[];
    final warnings = <String>[];

    final name = cell('name');
    if (name.isEmpty) messages.add('Name is required');
    if (name.length > 200) messages.add('Name is longer than 200 characters');

    double? money(String field, String label) {
      final raw = cell(field).replaceAll(',', '');
      if (raw.isEmpty) return null;
      final value = double.tryParse(raw);
      if (value == null || value < 0) {
        messages.add('$label must be a number, 0 or more');
        return null;
      }
      return value;
    }

    final limit = isCustomer ? money('creditLimit', 'Credit limit') : null;
    final opening = money('openingBalance', 'Opening balance') ?? 0;

    final typeText = isCustomer ? cell('type') : '';
    final customerType = typeText.isEmpty ? null : typeByName[customerNameKey(typeText)];
    if (typeText.isNotEmpty && customerType == null) {
      warnings.add('Type "$typeText" not found, so imported without a type');
    }

    int? terms;
    final termsText = cell('terms');
    if (termsText.isNotEmpty) {
      terms = int.tryParse(termsText) ?? double.tryParse(termsText)?.round();
      if (terms == null || terms < 0 || terms > 365) {
        messages.add('Payment terms must be 0 to 365 days');
        terms = null;
      }
    }

    if (messages.isNotEmpty) {
      errors.add(CustomerRowError(rowNumber: rowNumber, messages: messages));
      continue;
    }
    final key = customerNameKey(name);
    final clash = taken[key];
    if (clash != null) {
      skipped.add(CustomerRowError(rowNumber: rowNumber, messages: ['"$name" is $clash']));
      continue;
    }
    taken[key] = 'repeated (row $rowNumber)';

    String? optional(String field) {
      final value = cell(field);
      return value.isEmpty ? null : value;
    }

    imported.add(
      ImportedCustomerRow(
        rowNumber: rowNumber,
        input: PartyInput(
          type: type,
          name: name,
          contactPerson: isCustomer ? null : optional('contactPerson'),
          phone: optional('phone'),
          email: optional('email'),
          address: optional('address'),
          notes: optional('notes'),
          creditLimit: isCustomer ? (limit ?? customerType?.defaultCreditLimit ?? 0) : 0,
          customerTypeId: customerType?.id,
          paymentTermsDays: terms ?? customerType?.defaultPaymentTermsDays ?? 30,
        ),
        openingBalance: opening,
        warnings: warnings,
      ),
    );
  }
  return CustomerImport(rows: imported, errors: errors, skipped: skipped);
}

const _templateHeaders = ['Name', 'Type', 'Phone', 'Email', 'Address', 'Credit limit', 'Payment terms', 'Opening balance', 'Notes'];
const _supplierTemplateHeaders = ['Name', 'Contact person', 'Phone', 'Email', 'Address', 'Payment terms', 'Opening balance', 'Notes'];

/// The starter sheet "Download template" saves.
List<int> buildCustomerImportTemplate() => buildPartyImportTemplate(PartyType.customer);

List<int> buildPartyImportTemplate(PartyType type) {
  final workbook = Excel.createExcel();
  final sheet = workbook[workbook.getDefaultSheet()!];
  if (type == PartyType.customer) {
    sheet.appendRow([for (final h in _templateHeaders) TextCellValue(h)]);
    sheet.appendRow([
      TextCellValue('Blessing Retail Store'),
      TextCellValue('Retail'),
      TextCellValue('+234 706 555 0201'),
      TextCellValue(''),
      TextCellValue('12 Market Road, Lagos'),
      DoubleCellValue(200000),
      IntCellValue(30),
      DoubleCellValue(45000),
      TextCellValue(''),
    ]);
  } else {
    sheet.appendRow([for (final h in _supplierTemplateHeaders) TextCellValue(h)]);
    sheet.appendRow([
      TextCellValue('Dangote Foods Ltd'),
      TextCellValue('Musa Bello'),
      TextCellValue('+234 801 555 0101'),
      TextCellValue('orders@example.com'),
      TextCellValue('Apapa, Lagos'),
      IntCellValue(30),
      DoubleCellValue(150000),
      TextCellValue(''),
    ]);
  }
  return workbook.encode() ?? const [];
}

/// The supplier list as a spreadsheet: contacts, terms, what you owe (and
/// what is overdue) and what you have bought from them.
List<int> buildSupplierExport(List<Party> suppliers) {
  final workbook = Excel.createExcel();
  final sheet = workbook[workbook.getDefaultSheet()!];
  final date = DateFormat('yyyy-MM-dd');
  sheet.appendRow([
    for (final h in [
      'Name', 'Contact person', 'Phone', 'Email', 'Address', 'Payment terms', 'You owe', 'Overdue',
      'Bought (all time)', 'Purchases', 'Last purchase', 'Status', 'Notes',
    ])
      TextCellValue(h),
  ]);
  for (final s in suppliers) {
    sheet.appendRow([
      TextCellValue(s.name),
      TextCellValue(s.contactPerson ?? ''),
      TextCellValue(s.phone ?? ''),
      TextCellValue(s.email ?? ''),
      TextCellValue(s.address ?? ''),
      IntCellValue(s.paymentTermsDays),
      DoubleCellValue(s.balanceOwed),
      DoubleCellValue(s.overdue),
      DoubleCellValue(s.totalPurchases),
      IntCellValue(s.purchaseCount),
      TextCellValue(s.lastPurchaseAt == null ? '' : date.format(s.lastPurchaseAt!)),
      TextCellValue(s.isActive ? 'Active' : 'Archived'),
      TextCellValue(s.notes ?? ''),
    ]);
  }
  return workbook.encode() ?? const [];
}

/// The customer list as a spreadsheet: contact details, type, limit, what
/// they owe and what they have bought.
List<int> buildCustomerExport(List<Party> customers, String? Function(Party) typeName) {
  final workbook = Excel.createExcel();
  final sheet = workbook[workbook.getDefaultSheet()!];
  final date = DateFormat('yyyy-MM-dd');
  sheet.appendRow([
    for (final h in [
      'Name', 'Type', 'Phone', 'Email', 'Address', 'Credit limit', 'Owes you',
      'Bought (all time)', 'Sales', 'Last purchase', 'Status', 'Notes',
    ])
      TextCellValue(h),
  ]);
  for (final c in customers) {
    sheet.appendRow([
      TextCellValue(c.name),
      TextCellValue(typeName(c) ?? ''),
      TextCellValue(c.phone ?? ''),
      TextCellValue(c.email ?? ''),
      TextCellValue(c.address ?? ''),
      DoubleCellValue(c.creditLimit),
      DoubleCellValue(c.balanceOwed),
      DoubleCellValue(c.totalSales),
      IntCellValue(c.salesCount),
      TextCellValue(c.lastSaleAt == null ? '' : date.format(c.lastSaleAt!)),
      TextCellValue(c.isActive ? 'Active' : 'Archived'),
      TextCellValue(c.notes ?? ''),
    ]);
  }
  return workbook.encode() ?? const [];
}
