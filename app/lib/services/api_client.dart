import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_settings.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

/// Google Apps Script Web App 호출 클라이언트.
///
/// - Apps Script는 CORS preflight(OPTIONS)를 처리하지 못하므로
///   Content-Type을 text/plain으로 보내 단순 요청으로 우회한다 (웹/PWA 필수).
/// - dart:io는 POST 302 리다이렉트를 자동으로 따르지 않으므로 수동 follow.
///   (Apps Script는 항상 script.googleusercontent.com으로 302 응답)
class ApiClient {
  static const Duration _timeout = Duration(seconds: 60);

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final url = AppSettings.apiUrl;
    if (url.isEmpty) throw ApiException('API_URL_NOT_SET');

    final body = jsonEncode({
      ...payload,
      'action': action,
      'token': AppSettings.token,
    });

    var res = await http
        .post(
          Uri.parse(url),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: body,
        )
        .timeout(_timeout);

    if (res.statusCode >= 300 && res.statusCode < 400) {
      final loc = res.headers['location'];
      if (loc == null) throw ApiException('REDIRECT_WITHOUT_LOCATION');
      res = await http.get(Uri.parse(loc)).timeout(_timeout);
    }
    if (res.statusCode != 200) throw ApiException('HTTP_${res.statusCode}');

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw ApiException('${data['error'] ?? 'UNKNOWN_ERROR'}');
    }
    return data;
  }
}
