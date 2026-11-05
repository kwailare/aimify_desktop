import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Asks where to save [bytes] and writes them there; returns the path, or
/// `null` when the person cancels.
///
/// The Save dialog is tied to the app's window (`lockParentWindow`), so it
/// opens in front of Aimify. Without that, Windows can open it behind the
/// app window, where nobody sees it and nothing seems to happen. The file
/// always ends in `.extension`, even if the name was edited without it.
/// On desktop the dialog only returns the chosen path; this writes the file.
Future<String?> saveBytesAs({
  required String dialogTitle,
  required String fileName,
  required List<int> bytes,
  required String extension,
}) async {
  final chosen = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
    lockParentWindow: true,
  );
  if (chosen == null) return null;
  final path = chosen.toLowerCase().endsWith('.${extension.toLowerCase()}') ? chosen : '$chosen.$extension';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
