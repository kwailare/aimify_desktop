import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Thin wrapper around `package:http` for calling the real, wired-up
/// aimify-web endpoints (`/api/v1/auth/login`, `/api/v1/me`).
///
/// This is the ONLY place in the app that should talk to the network. Every
/// other module (products, inventory, purchases, ...) reads from a local
/// mock repository until its own backend endpoints exist.
class ApiClient {
  ApiClient(this._http);

  final http.Client _http;

  Future<Map<String, dynamic>> postJson(
    String url,
    Map<String, dynamic> body,
  ) async {
    final response = await _http.post(
      Uri.parse(url),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> getJson(String url, {String? bearerToken}) async {
    final response = await _http.get(
      Uri.parse(url),
      headers: {
        if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
      },
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Map<String, dynamic> body = response.body.isEmpty
        ? const {}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body['error'] as String? ??
          'Something went wrong (HTTP ${response.statusCode}).';
      throw ApiException(response.statusCode, message);
    }

    return body;
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(http.Client());
});
