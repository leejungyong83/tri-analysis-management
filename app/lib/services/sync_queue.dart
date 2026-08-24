import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/ict_time.dart';
import '../models/inspection.dart';
import 'api_client.dart';
import 'photo_service.dart';

/// 2단 분리 로컬 큐 (판정 우선 무손실).
///
/// - 레코드 큐: 판정 JSON(소형)을 먼저 전송 — 사진 실패에 인질 잡히지 않음.
///   LOT은 서버가 채번하므로 응답의 lot을 받아 로컬에 반영(표시용).
/// - 사진 큐: 레코드 전송 성공 후에만 Rack별로 개별 업로드(photoUUID 멱등).
/// - 항목은 업로드 확정 응답 수신 전까지 절대 삭제하지 않는다.
/// - 재시도: 지수 백오프(상한 1시간), 10회 연속 실패 시 경고 플래그.
class SyncQueue extends ChangeNotifier {
  static const String recordBoxName = 'recordQueue';
  static const String photoBoxName = 'photoQueue';
  static const int warnAfterFailures = 10;

  final ApiClient api;

  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _processing = false;
  int _consecutiveFailures = 0;

  SyncQueue(this.api);

  Box get _records => Hive.box(recordBoxName);
  Box get _photos => Hive.box(photoBoxName);

  int get pendingRecords => _records.length;
  int get pendingPhotos => _photos.length;
  int get consecutiveFailures => _consecutiveFailures;
  bool get warning => _consecutiveFailures >= warnAfterFailures;

  /// 지수 백오프: 30초 × 2^attempts, 상한 1시간.
  static Duration backoff(int attempts) {
    final secs = 30 * (1 << (attempts > 7 ? 7 : attempts));
    return Duration(seconds: secs > 3600 ? 3600 : secs);
  }

  /// 검사 저장: 로컬 큐 기록 즉시 완료 (UI 비차단 — "저장 완료" 시점).
  /// photos는 Rack별 CapturedPhoto 5개 (rackIndex 포함).
  Future<void> enqueue(Inspection insp, List<CapturedPhoto> photos) async {
    await _records.put(insp.uuid, {
      ...insp.toJson(),
      'attempts': 0,
      'nextAt': 0,
    });
    for (final p in photos) {
      // 사진 큐 키 = uuid + rack (Rack당 1장이므로 결정적)
      await _photos.put('${insp.uuid}#${p.rackIndex}', {
        'uuid': insp.uuid,
        'rackIndex': p.rackIndex,
        'photoUuid': p.photoUuid,
        'date': insp.date,
        'bytes': p.jpegBytes,
        'attempts': 0,
        'nextAt': 0,
      });
    }
    notifyListeners();
    unawaited(processQueue());
  }

  void start() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(processQueue());
      }
    });
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(processQueue());
    });
    unawaited(processQueue());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  /// 레코드 우선 → 사진 후속. 실패 항목은 nextAt 이후 재시도.
  Future<void> processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1단계: 판정 레코드 (핵심 품질 데이터 — 먼저 무손실 전송)
      for (final key in _records.keys.toList()) {
        final raw = _records.get(key);
        if (raw == null) continue;
        final entry = Map<dynamic, dynamic>.from(raw as Map);
        if ((entry['nextAt'] as int? ?? 0) > now) continue;
        try {
          await api.call('submit', {
            'uuid': entry['uuid'],
            'date': entry['date'],
            'ca': entry['ca'],
            'inspector': entry['inspector'],
            'lot': entry['lot'], // 선택된 생산LOT
            'time': entry['time'],
            'bar': entry['bar'],
            'model': entry['model'],
            'racks': entry['racks'],
            // 시계 편차 가드용 기기 현재 시각 (서버가 10분 초과 편차 플래그)
            'deviceNow': DateTime.now().toUtc().toIso8601String(),
          });
          await _records.delete(key); // 확정 응답 후에만 삭제
          _consecutiveFailures = 0;
        } catch (_) {
          await _bumpAttempt(_records, key, entry);
          _consecutiveFailures++;
        }
        notifyListeners();
      }

      // 2단계: 사진 — 소속 레코드가 전송 완료된 것만 (Rack별 개별 업로드)
      for (final key in _photos.keys.toList()) {
        final raw = _photos.get(key);
        if (raw == null) continue;
        final entry = Map<dynamic, dynamic>.from(raw as Map);
        if ((entry['nextAt'] as int? ?? 0) > now) continue;
        if (_records.containsKey(entry['uuid'])) continue; // 레코드 미전송 — 대기
        try {
          final bytes = entry['bytes'] as Uint8List;
          await api.call('attachPhoto', {
            'uuid': entry['uuid'],
            'rackIndex': entry['rackIndex'],
            'photoUuid': entry['photoUuid'],
            'date': entry['date'],
            'base64': base64Encode(bytes),
          });
          await _photos.delete(key); // 확정 응답 후에만 삭제
          _consecutiveFailures = 0;
        } catch (_) {
          await _bumpAttempt(_photos, key, entry);
          _consecutiveFailures++;
        }
        notifyListeners();
      }
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  Future<void> _bumpAttempt(Box box, dynamic key, Map entry) async {
    final attempts = (entry['attempts'] as int? ?? 0) + 1;
    await box.put(key, {
      ...entry,
      'attempts': attempts,
      'nextAt': DateTime.now().add(backoff(attempts)).millisecondsSinceEpoch,
    });
  }

  /// 오늘(ICT) 큐에 남아 있는 본인 검사 수 — 대시보드 보조용.
  int pendingRecordsForInspectorToday(String inspector) {
    final today = IctTime.workDate();
    var count = 0;
    for (final key in _records.keys) {
      final entry = Map<dynamic, dynamic>.from(_records.get(key) as Map);
      if (entry['inspector'] == inspector && entry['date'] == today) count++;
    }
    return count;
  }
}
