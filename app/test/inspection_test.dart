import 'package:flutter_test/flutter_test.dart';
import 'package:tri_inspection_app/core/ict_time.dart';
import 'package:tri_inspection_app/models/inspection.dart';

void main() {
  group('종합판정 파생 규칙 (스펙: Rack 5개 중 1개라도 NG → LOT NG)', () {
    test('전부 OK → OK', () {
      expect(Inspection.deriveVerdict(['OK', 'OK', 'OK', 'OK', 'OK']), 'OK');
    });

    test('1개만 NG → NG (Rack1)', () {
      expect(Inspection.deriveVerdict(['NG', 'OK', 'OK', 'OK', 'OK']), 'NG');
    });

    test('1개만 NG → NG (Rack5)', () {
      expect(Inspection.deriveVerdict(['OK', 'OK', 'OK', 'OK', 'NG']), 'NG');
    });

    test('전부 NG → NG', () {
      expect(Inspection.deriveVerdict(['NG', 'NG', 'NG', 'NG', 'NG']), 'NG');
    });

    test('Inspection.verdict 게터도 동일 규칙', () {
      final insp = Inspection(
        uuid: 'u1',
        date: '2026-07-06',
        ca: 'CA1',
        inspector: '검사자A',
        lot: '260706001',
        time: '08:30',
        bar: 'BAR-07',
        model: 'MODEL-X',
        racks: const ['OK', 'OK', 'NG', 'OK', 'OK'],
      );
      expect(insp.verdict, 'NG');
    });
  });

  group('직렬화 왕복 (로컬 큐 저장/복원 무손실)', () {
    test('toJson에 선택 LOT 포함 + 왕복 후 필드 보존', () {
      final original = Inspection(
        uuid: 'uuid-123',
        date: '2026-07-06',
        ca: 'CA2',
        inspector: 'Nguyễn Văn A',
        lot: '260706042',
        time: '14:05',
        bar: 'BAR-12',
        model: 'TRI-500',
        racks: const ['OK', 'NG', 'OK', 'OK', 'OK'],
      );
      final json = original.toJson();
      expect(json['lot'], '260706042'); // 선택한 생산LOT 포함
      final restored = Inspection.fromJson(json);
      expect(restored.uuid, original.uuid);
      expect(restored.date, original.date);
      expect(restored.ca, original.ca);
      expect(restored.inspector, original.inspector);
      expect(restored.lot, original.lot);
      expect(restored.time, original.time);
      expect(restored.bar, original.bar);
      expect(restored.model, original.model);
      expect(restored.racks, original.racks);
      expect(restored.verdict, 'NG');
    });
  });

  group('RemoteRecord (서버 응답 파싱 — Rack별 사진 5개)', () {
    test('일부 pending 인식 + pendingPhotoCount', () {
      final r = RemoteRecord.fromJson(const {
        'uuid': 'u1',
        'date': '2026-07-06',
        'ca': 'CA1',
        'inspector': 'A',
        'lot': '260706001',
        'time': '09:00',
        'bar': 'B1',
        'model': 'M1',
        'racks': ['OK', 'OK', 'OK', 'OK', 'OK'],
        'verdict': 'OK',
        'photos': ['http://a', 'pending', 'http://c', 'pending', 'pending'],
        'rework': false,
        'voided': false,
      });
      expect(r.anyPhotoPending, isTrue);
      expect(r.pendingPhotoCount, 3);
      expect(r.photos.length, 5);
    });

    test('전부 업로드 완료 → pending 없음', () {
      final r = RemoteRecord.fromJson(const {
        'uuid': 'u2',
        'date': '2026-07-06',
        'ca': 'CA1',
        'inspector': 'A',
        'lot': '260706002',
        'time': '09:10',
        'bar': 'B2',
        'model': 'M1',
        'racks': ['OK', 'OK', 'OK', 'OK', 'NG'],
        'verdict': 'NG',
        'photos': ['http://1', 'http://2', 'http://3', 'http://4', 'http://5'],
        'rework': true,
        'voided': false,
      });
      expect(r.anyPhotoPending, isFalse);
      expect(r.pendingPhotoCount, 0);
      expect(r.rework, isTrue);
      expect(r.reworkLot, 'R260706002'); // NG rework 식별자 = R 접두
    });

    test('photos 길이가 5가 아니면 5칸으로 정규화', () {
      final r = RemoteRecord.fromJson(const {
        'uuid': 'u3',
        'lot': '260706003',
        'racks': ['OK', 'OK', 'OK', 'OK', 'OK'],
        'verdict': 'OK',
        'photos': ['http://only-one'],
      });
      expect(r.photos.length, 5);
      expect(r.photos[0], 'http://only-one');
      expect(r.photos[4], 'pending');
    });
  });

  group('IctTime (베트남 UTC+7 — 검사 시각 권위)', () {
    test('monthTab: 날짜 → 월별 탭 라우팅', () {
      expect(IctTime.monthTab('2026-07-06'), '2026-07');
      expect(IctTime.monthTab('2026-12-31'), '2026-12');
    });

    test('dateStr/timeStr 0패딩 (24시)', () {
      final d = DateTime(2026, 1, 5, 8, 3);
      expect(IctTime.dateStr(d), '2026-01-05');
      expect(IctTime.timeStr(d), '08:03');
    });

    test('24시 표기 — 오후 시각', () {
      final d = DateTime(2026, 1, 5, 14, 30);
      expect(IctTime.timeStr(d), '14:30');
    });

    test('nowIct는 UTC+7', () {
      final utc = DateTime.now().toUtc();
      final ict = IctTime.nowIct();
      final diff = ict.difference(utc).inMinutes;
      expect(diff, inInclusiveRange(419, 421)); // 7시간 ± 실행 오차
    });
  });

  group('업무일(work-day) 규칙 — 하루 시작 08:00 (사용자 지시)', () {
    test('08:00 이전은 전날 업무일', () {
      expect(IctTime.workDateOf(DateTime(2026, 7, 7, 6, 0)), '2026-07-06');
      expect(IctTime.workDateOf(DateTime(2026, 7, 7, 7, 59)), '2026-07-06');
    });

    test('08:00 정각부터 당일 업무일', () {
      expect(IctTime.workDateOf(DateTime(2026, 7, 7, 8, 0)), '2026-07-07');
      expect(IctTime.workDateOf(DateTime(2026, 7, 7, 9, 0)), '2026-07-07');
      expect(IctTime.workDateOf(DateTime(2026, 7, 7, 23, 30)), '2026-07-07');
    });

    test('월 경계: 7/1 새벽 검사는 6/30 업무일', () {
      expect(IctTime.workDateOf(DateTime(2026, 7, 1, 2, 0)), '2026-06-30');
    });

    test('연 경계: 1/1 새벽 검사는 전년 12/31 업무일', () {
      expect(IctTime.workDateOf(DateTime(2026, 1, 1, 3, 0)), '2025-12-31');
    });
  });
}
