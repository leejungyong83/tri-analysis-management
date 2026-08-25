import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_settings.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

/// Supabase(PostgREST RPC + Storage) 호출 클라이언트.
///
/// - Project URL/anon(publishable) key는 Supabase가 "공개 노출 가능"으로 명시한
///   값이라 상수로 고정한다. 실제 접근 통제는 앱 토큰(app_token)이 담당한다:
///   모든 RPC 호출에 p_token으로 실려가며 서버(supabase/schema.sql의 check_token_)가
///   검증한다 — Settings 화면에서 재빌드 없이 입력·로테이션 가능 (기존 GAS 토큰과 동일 역할).
/// - action(카멜케이스) → Postgres RPC 함수명(snake_case) 매핑 + p_ 접두 파라미터 변환.
///   화면/서비스 코드는 액션 이름과 payload 키를 그대로 쓰므로 이 파일 밖은 무변경.
/// - attachPhoto는 2단계 유지(레코드 우선 무손실 원칙, GAS 시절과 동일):
///   ① Storage 버킷(tri-photos)에 사진 바이트 업로드(photoUUID 결정적 경로 = 멱등)
///   ② rpc_attach_photo로 업로드된 공개 URL을 검사 레코드의 해당 Rack 컬럼에 기록
class ApiClient {
  static const Duration _timeout = Duration(seconds: 60);

  // Supabase 프로젝트 정보 — publishable key는 브라우저/앱에 노출되어도 안전한 값.
  static const String supabaseUrl = 'https://cwzyekmbjcepcpmojwhd.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_iXUe_5PBxxJSq2OVDXhljA_UMTSpApU';
  static const String photoBucket = 'tri-photos';

  static const Map<String, String> _fn = {
    'produce': 'rpc_produce',
    'listUninspected': 'rpc_list_uninspected',
    'reworkInput': 'rpc_rework_input',
    'productionList': 'rpc_production_list',
    'productionStats': 'rpc_production_stats',
    'submit': 'rpc_submit',
    'attachPhoto': 'rpc_attach_photo', // _attachPhoto() 2단계에서 내부 호출
    'list': 'rpc_list',
    'stats': 'rpc_stats',
    'void': 'rpc_void',
    'masters': 'rpc_masters',
  };

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> payload,
  ) async {
    if (action == 'attachPhoto') return _attachPhoto(payload);
    return _rpc(action, _buildParams(action, payload));
  }

  Map<String, dynamic> _buildParams(String action, Map<String, dynamic> p) {
    switch (action) {
      case 'produce':
        return {
          'p_req_id': p['reqId'],
          'p_date': p['date'],
          'p_time': p['time'],
          'p_model': p['model'],
          'p_qty': p['qty'],
        };
      case 'listUninspected':
        return {};
      case 'reworkInput':
        return {
          'p_lot': p['lot'],
          'p_date': p['date'],
          'p_time': p['time'],
          'p_qty': p['qty'],
        };
      case 'productionList':
        return {'p_date_from': p['dateFrom'], 'p_date_to': p['dateTo']};
      case 'productionStats':
        return {'p_date_from': p['dateFrom'], 'p_date_to': p['dateTo']};
      case 'submit':
        return {
          'p_uuid': p['uuid'],
          'p_date': p['date'],
          'p_ca': p['ca'],
          'p_inspector': p['inspector'],
          'p_lot': p['lot'],
          'p_time': p['time'],
          'p_bar': p['bar'],
          'p_model': p['model'],
          'p_racks': p['racks'],
          'p_device_now': p['deviceNow'],
        };
      case 'list':
        return {
          'p_lot': p['lot'],
          'p_model': p['model'],
          'p_ng_only': p['ngOnly'] != null,
          'p_date_from': p['dateFrom'],
          'p_date_to': p['dateTo'],
        };
      case 'stats':
        return {
          'p_date_from': p['dateFrom'],
          'p_date_to': p['dateTo'],
          'p_model': p['model'],
        };
      case 'void':
        return {'p_uuid': p['uuid']};
      case 'masters':
        return {};
      default:
        throw ApiException('UNKNOWN_ACTION:$action');
    }
  }

  Future<Map<String, dynamic>> _rpc(
      String action, Map<String, dynamic> params) async {
    final fnName = _fn[action];
    if (fnName == null) throw ApiException('UNKNOWN_ACTION:$action');

    final token = AppSettings.token;
    if (token.isEmpty) throw ApiException('APP_TOKEN_NOT_SET');

    final uri = Uri.parse('$supabaseUrl/rest/v1/rpc/$fnName');
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'apikey': supabaseAnonKey,
            'Authorization': 'Bearer $supabaseAnonKey',
          },
          body: jsonEncode({...params, 'p_token': token}),
        )
        .timeout(_timeout);

    return _parseResponse(res);
  }

  Map<String, dynamic> _parseResponse(http.Response res) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('HTTP_${res.statusCode}');
    }
    if (res.statusCode >= 300) {
      // PostgREST 오류 형식: {message, code, details, hint}
      // (check_token_의 RAISE EXCEPTION 'UNAUTHORIZED' 메시지가 그대로 담겨온다)
      throw ApiException('${data['message'] ?? 'HTTP_${res.statusCode}'}');
    }
    if (data['ok'] != true) {
      throw ApiException('${data['error'] ?? 'UNKNOWN_ERROR'}');
    }
    return data;
  }

  /// ① Storage 업로드 → ② rpc_attach_photo로 URL 기록.
  /// payload: { uuid, rackIndex, photoUuid, date, base64 }
  Future<Map<String, dynamic>> _attachPhoto(Map<String, dynamic> p) async {
    final token = AppSettings.token;
    if (token.isEmpty) throw ApiException('APP_TOKEN_NOT_SET');

    final uuid = '${p['uuid']}';
    final rackIndex = p['rackIndex'];
    final photoUuid = '${p['photoUuid']}';
    final date = '${p['date']}';
    final bytes = base64Decode(p['base64'] as String);

    final month = date.length >= 7 ? date.substring(0, 7) : date;
    // photoUuid 포함 경로 = 결정적(멱등) 파일명 — 재시도해도 동일 경로에 덮어쓰기만.
    final path = '$month/${uuid}_rack${rackIndex}_$photoUuid.jpg';

    final uploadUri =
        Uri.parse('$supabaseUrl/storage/v1/object/$photoBucket/$path');
    final uploadRes = await http
        .post(
          uploadUri,
          headers: {
            'Content-Type': 'image/jpeg',
            'apikey': supabaseAnonKey,
            'Authorization': 'Bearer $supabaseAnonKey',
            'x-upsert': 'true', // 재시도 시 같은 경로 덮어쓰기 허용(멱등)
          },
          body: bytes,
        )
        .timeout(_timeout);
    if (uploadRes.statusCode >= 300) {
      throw ApiException('PHOTO_UPLOAD_HTTP_${uploadRes.statusCode}');
    }

    final publicUrl =
        '$supabaseUrl/storage/v1/object/public/$photoBucket/$path';

    return _rpc('attachPhoto', {
      'p_uuid': uuid,
      'p_rack_index': rackIndex,
      'p_photo_path': publicUrl,
    });
  }
}
