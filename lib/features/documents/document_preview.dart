import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../shared/utils/friendly_error.dart';
import '../auth/presentation/auth_controller.dart';
import 'document_kit.dart';

/// Builds one document's PDF with the shared [DocumentKit].
typedef DocumentBuilder = Future<Uint8List> Function(DocumentKit kit);

/// Opens documents. Screens call this rather than showing the preview
/// themselves, so tests can see what was asked for without a print engine.
class DocumentOpener {
  const DocumentOpener();

  Future<void> open(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String fileName,
    required DocumentBuilder build,
  }) async {
    final company = ref.read(authControllerProvider).valueOrNull?.organization;
    if (company == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DocumentPreviewScreen(
          title: title,
          fileName: fileName,
          build: () async => build(await DocumentKit.load(company)),
        ),
      ),
    );
  }
}

final documentOpenerProvider = Provider<DocumentOpener>((ref) => const DocumentOpener());

/// The PDF as it will print, with Print (any installed printer) and Save
/// PDF. Everything it shows was already loaded, so it works offline (the
/// logo is left out if it can't be fetched).
class DocumentPreviewScreen extends StatefulWidget {
  const DocumentPreviewScreen({super.key, required this.title, required this.fileName, required this.build});

  final String title;
  final String fileName;
  final Future<Uint8List> Function() build;

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  Uint8List? _bytes;

  /// Built once: the preview, Print and Save all use the same bytes, so what
  /// is printed is exactly what was previewed.
  Future<Uint8List> _pdf(PdfPageFormat _) async => _bytes ??= await widget.build();

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _pdf(PdfPageFormat.a4);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${widget.title}',
        fileName: widget.fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (path == null) return;
      final target = path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';
      await File(target).writeAsBytes(bytes, flush: true);
      messenger.showSnackBar(SnackBar(content: Text('Saved to $target')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save the PDF: ${friendlyError(e)}")));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                key: const Key('document-save'),
                onPressed: () => _save(context),
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('Save PDF'),
              ),
            ),
          ],
        ),
        body: PdfPreview(
          build: _pdf,
          pdfFileName: widget.fileName,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          loadingWidget: const Center(child: CircularProgressIndicator()),
          onError: (context, error) => Center(child: Text('Couldn\'t prepare the document: ${friendlyError(error)}')),
        ),
      );
}
