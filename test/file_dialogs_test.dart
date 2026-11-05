// Saving files (Excel exports, import templates, PDFs) through one helper:
// the Save dialog must be tied to the app window (it opened behind Aimify
// otherwise, so nothing seemed to happen), the file must get its extension
// even if the name was edited, and cancelling saves nothing.

import 'dart:io';
import 'dart:typed_data';

import 'package:aimify_desktop/shared/utils/file_dialogs.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSave extends FilePicker {
  _FakeSave(this.answer);

  final String? answer;
  bool? lockedToWindow;
  List<String>? extensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    lockedToWindow = lockParentWindow;
    extensions = allowedExtensions;
    return answer;
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('aimify-save-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the dialog stays in front of the app, and the file is written', () async {
    final fake = _FakeSave('${dir.path}${Platform.pathSeparator}report.xlsx');
    FilePicker.platform = fake;
    final path = await saveBytesAs(dialogTitle: 'Save', fileName: 'report.xlsx', bytes: [1, 2, 3], extension: 'xlsx');
    expect(fake.lockedToWindow, isTrue);
    expect(fake.extensions, ['xlsx']);
    expect(path, endsWith('report.xlsx'));
    expect(File(path!).readAsBytesSync(), [1, 2, 3]);
  });

  test('a name typed without the extension still gets it', () async {
    FilePicker.platform = _FakeSave('${dir.path}${Platform.pathSeparator}my products');
    final path = await saveBytesAs(dialogTitle: 'Save', fileName: 'x.xlsx', bytes: [7], extension: 'xlsx');
    expect(path, endsWith('my products.xlsx'));
    expect(File(path!).existsSync(), isTrue);
  });

  test('cancelling saves nothing', () async {
    FilePicker.platform = _FakeSave(null);
    expect(await saveBytesAs(dialogTitle: 'Save', fileName: 'x.pdf', bytes: [1], extension: 'pdf'), isNull);
    expect(dir.listSync(), isEmpty);
  });
}
