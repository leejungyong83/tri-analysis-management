import 'package:hive/hive.dart';

/// Hive 설정 저장소 — API URL/토큰은 재빌드 없이 설정 화면에서 변경 가능.
class AppSettings {
  static const String boxName = 'settings';

  static Box get _box => Hive.box(boxName);

  /// Supabase 앱 토큰 (app_config 테이블의 app_token 값 — 로테이션 가능, 재빌드 불요).
  /// Supabase Project URL/anon key는 api_client.dart에 상수로 고정(공개 가능한 값).
  /// 배포본에는 현재 유효한 토큰을 기본값으로 내장 — 직원이 직접 입력할 필요 없음.
  /// 토큰 로테이션 시: Settings에서 새 값 입력(기기별) 또는 이 기본값 자체를 바꿔 재배포.
  static const String _defaultToken = '4f29106552299b19569ad4b405f7dec12d9fd4d335bc3002';
  static String get token => _box.get('token', defaultValue: _defaultToken) as String;
  static set token(String v) => _box.put('token', v.trim());

  /// 현장 기본 언어는 베트남어 (스펙: 검사자=vi, 관리자=ko)
  static String get locale => _box.get('locale', defaultValue: 'vi') as String;
  static set locale(String v) => _box.put('locale', v);

  static String get inspector => _box.get('inspector', defaultValue: '') as String;
  static set inspector(String v) => _box.put('inspector', v);

  static String get ca => _box.get('ca', defaultValue: '') as String;
  static set ca(String v) => _box.put('ca', v);

  static String get lastModel => _box.get('lastModel', defaultValue: '') as String;
  static set lastModel(String v) => _box.put('lastModel', v);

  /// 화면 테마: 'system' | 'light' | 'dark'. 현장 조도 편차 대응(기본 시스템 연동).
  static String get themeMode => _box.get('themeMode', defaultValue: 'system') as String;
  static set themeMode(String v) => _box.put('themeMode', v);
}
