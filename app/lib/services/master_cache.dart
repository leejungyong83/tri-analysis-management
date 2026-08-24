import 'package:hive/hive.dart';

import '../core/app_settings.dart';
import 'api_client.dart';

class Masters {
  final List<String> inspectors;
  final List<String> models;
  final List<String> cas;
  final Map<String, String> config;

  const Masters({
    required this.inspectors,
    required this.models,
    required this.cas,
    required this.config,
  });

  static const empty = Masters(inspectors: [], models: [], cas: [], config: {});
}

/// 마스터 데이터(검사자/Model/CA/config) Hive 캐시.
///
/// 오프라인 콜드스타트 방어: 네트워크가 없어도 마지막 캐시로 검사 시작 가능
/// (Architect HIGH-4 반영). config의 token_new 수신 시 무재배포 토큰 로테이션.
class MasterCache {
  static const String boxName = 'masters';

  Box get _box => Hive.box(boxName);

  Masters get cached {
    final raw = _box.get('data');
    if (raw == null) return Masters.empty;
    final m = Map<dynamic, dynamic>.from(raw as Map);
    return Masters(
      inspectors: List<String>.from(m['inspectors'] as List? ?? const []),
      models: List<String>.from(m['models'] as List? ?? const []),
      cas: List<String>.from(m['cas'] as List? ?? const []),
      config: Map<String, String>.from(
          (m['config'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'))),
    );
  }

  Future<Masters> refresh(ApiClient api) async {
    final data = await api.call('masters', {});
    final m = data['masters'] as Map<String, dynamic>;
    final masters = Masters(
      inspectors: List<String>.from(m['inspectors'] as List? ?? const []),
      models: List<String>.from(m['models'] as List? ?? const []),
      cas: List<String>.from(m['cas'] as List? ?? const []),
      config: Map<String, String>.from(
          (m['config'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v'))),
    );
    await _box.put('data', {
      'inspectors': masters.inspectors,
      'models': masters.models,
      'cas': masters.cas,
      'config': masters.config,
    });

    // 토큰 로테이션: 서버 config에 token_new가 배포되면 자동 수신 (계획 §3 보안)
    final newToken = masters.config['token_new'];
    if (newToken != null && newToken.isNotEmpty && newToken != AppSettings.token) {
      AppSettings.token = newToken;
    }
    return masters;
  }
}
