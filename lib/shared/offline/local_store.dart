import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Where the app keeps what it must not lose when the network is poor or
/// gone: cached server data, the queue of changes waiting to sync, and the
/// local-only modules. Values are JSON text under a short key.
///
/// The auth token is deliberately NOT stored here — it stays in the OS
/// secure store (see `secure_token_storage.dart`).
abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Every key that starts with [prefix] (used to clear one user's data).
  Future<List<String>> keys(String prefix);
}

/// One JSON file per key in the app's support directory. Writes go to a
/// temporary file first and are renamed into place, so a crash or power cut
/// mid-write never leaves a half-written (corrupt) file behind.
class FileLocalStore implements LocalStore {
  FileLocalStore([Directory? directory]) : _directory = directory;

  Directory? _directory;

  Future<Directory> _dir() async {
    final existing = _directory;
    if (existing != null) return existing;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}aimify_data');
    await dir.create(recursive: true);
    return _directory = dir;
  }

  static String _fileName(String key) => '${Uri.encodeComponent(key)}.json';

  Future<File> _file(String key) async =>
      File('${(await _dir()).path}${Platform.pathSeparator}${_fileName(key)}');

  @override
  Future<String?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      return await file.readAsString(encoding: utf8);
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _file(key);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, encoding: utf8, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> delete(String key) async {
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Already gone or locked — nothing useful to do.
    }
  }

  @override
  Future<List<String>> keys(String prefix) async {
    final dir = await _dir();
    final found = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), '');
      final key = Uri.decodeComponent(name);
      if (key.startsWith(prefix)) found.add(key);
    }
    return found;
  }
}

/// In-memory store for tests.
class MemoryLocalStore implements LocalStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<List<String>> keys(String prefix) async =>
      data.keys.where((k) => k.startsWith(prefix)).toList();
}

final localStoreProvider = Provider<LocalStore>((ref) => FileLocalStore());

/// Reads JSON from the store, treating a missing or corrupt file as "no
/// data" rather than a crash — a damaged cache must never stop the app
/// from starting.
Future<Object?> readJson(LocalStore store, String key) async {
  final text = await store.read(key);
  if (text == null) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

Future<void> writeJson(LocalStore store, String key, Object value) =>
    store.write(key, jsonEncode(value));
