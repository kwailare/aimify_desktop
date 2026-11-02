import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../reports/data/report_document.dart';
import 'document_kit.dart';

/// A period report as a PDF (landscape, for the wide tables): the period
/// and filters, the headline figures, every table, then the notes.
Future<Uint8List> buildReportPdf(DocumentKit kit, ReportDocument doc) {
  final pdf = kit.document(doc.title);
  pdf.addPage(
    pw.MultiPage(
      pageTheme: kit.pageTheme(landscape: true),
      header: (context) => context.pageNumber == 1
          ? kit.header(doc.title, [('Period', doc.range.dates), ...doc.filters])
          : pw.SizedBox(),
      footer: kit.footer,
      build: (context) => [
        _kpis(doc),
        for (final section in doc.sections) ...[
          pw.SizedBox(height: 14),
          pw.Text(
            section.title,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: DocumentKit.ink),
          ),
          pw.SizedBox(height: 5),
          if (section.rows.isEmpty)
            pw.Text(section.emptyText, style: const pw.TextStyle(fontSize: 8.5, color: DocumentKit.muted))
          else
            _table(section),
        ],
        if (doc.notes.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          for (final note in doc.notes)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Text(note, style: const pw.TextStyle(fontSize: 8, color: DocumentKit.muted)),
            ),
        ],
      ],
    ),
  );
  return pdf.save();
}

pw.Widget _kpis(ReportDocument doc) => pw.Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final k in doc.kpis)
      pw.Container(
        width: 120,
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(color: DocumentKit.band, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              k.label.toUpperCase(),
              style: pw.TextStyle(fontSize: 7, color: DocumentKit.muted, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              k.value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: k.tone == KpiTone.bad ? const PdfColor.fromInt(0xFFC0392B) : DocumentKit.ink,
              ),
            ),
            if (k.caption != null)
              pw.Text(k.caption!, style: const pw.TextStyle(fontSize: 7, color: DocumentKit.muted)),
          ],
        ),
      ),
  ],
);

pw.Widget _table(ReportSection s) {
  const header = pw.BoxDecoration(color: PdfColor.fromInt(0xFF1D2545));
  const odd = pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F7F8));
  pw.Widget cell(String text, int column, {bool bold = false, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Text(
      text,
      textAlign: s.columns[column].numeric ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : null, color: color),
    ),
  );
  final rows = [...s.rows, ?s.footer];
  return pw.Table(
    columnWidths: {
      for (var i = 0; i < s.columns.length; i++)
        i: s.columns[i].numeric ? const pw.FlexColumnWidth(1) : const pw.FlexColumnWidth(1.6),
    },
    children: [
      pw.TableRow(
        decoration: header,
        children: [for (final (i, c) in s.columns.indexed) cell(c.label, i, bold: true, color: PdfColors.white)],
      ),
      for (final (r, row) in rows.indexed)
        pw.TableRow(
          decoration: s.footer != null && r == rows.length - 1
              ? const pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: DocumentKit.ink, width: 0.8)),
                )
              : (r.isOdd ? odd : null),
          children: [
            for (final (i, v) in row.indexed)
              cell(
                formatCell(v, s.columns[i].kind),
                i,
                bold: s.strongRows.contains(r) || (s.footer != null && r == rows.length - 1),
              ),
          ],
        ),
    ],
  );
}
