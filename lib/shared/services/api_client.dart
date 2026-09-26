import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Thin wrapper around `package:http` for the aimify-web `/api/v1`
/// endpoints. It only speaks HTTP: it attaches the bearer token it is
/// given, decodes the `{ error, code, ... }` error shape into an
/// [ApiException], and turns "no answer" failures into [NetworkException].
///
/// Feature repositories don't use this directly — they go through
/// `AuthedApi`, which adds the stored token and the app-wide reactions
/// (session ended, subscription locked, offline).
class ApiClient {
  ApiClient(this._http);

  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  Map<String, String> _headers(String? bearerToken, {bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
      };

  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) =>
      _send(
        () => _http.post(
          Uri.parse(url),
          headers: _headers(bearerToken, json: true),
          body: jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> patchJson(
    String url,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) =>
      _send(
        () => _http.patch(
          Uri.parse(url),
          headers: _headers(bearerToken, json: true),
          body: jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> getJson(String url, {String? bearerToken}) =>
      _send(() => _http.get(Uri.parse(url), headers: _headers(bearerToken)));

  Future<Map<String, dynamic>> deleteJson(String url, {String? bearerToken}) =>
      _send(() => _http.delete(Uri.parse(url), headers: _headers(bearerToken)));

  /// `multipart/form-data` with one file part — used for product images.
  Future<Map<String, dynamic>> postFile(
    String url, {
    required String field,
    required List<int> bytes,
    required String filename,
    String? bearerToken,
  }) =>
      _send(() async {
        final request = http.MultipartRequest('POST', Uri.parse(url))
          ..headers.addAll(_headers(bearerToken))
          ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
        return http.Response.fromStream(await _http.send(request));
      });

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    final http.Response response;
    try {
      response = await call().timeout(_timeout);
    } on SocketException catch (e) {
      throw NetworkException(e);
    } on http.ClientException catch (e) {
      throw NetworkException(e);
    } on TimeoutException catch (e) {
      throw NetworkException(e);
    } on HandshakeException catch (e) {
      throw NetworkException(e);
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> body = const {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        // A proxy or crash page instead of JSON — treated as an empty body
        // below so users never see raw markup.
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        body['error'] as String? ?? 'Something went wrong (HTTP ${response.statusCode}).',
        code: body['code'] as String?,
        details: body,
      );
    }

    return body;
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(http.Client());
});
