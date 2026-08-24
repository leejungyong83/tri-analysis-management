import 'package:flutter_test/flutter_test.dart';
import 'package:tri_inspection_app/models/production.dart';

void main() {
  group('UninspectedLot (미검사 생산LOT)', () {
    test('PRODUCED 상태 파싱 + 라벨', () {
      final l = UninspectedLot.fromJson(const {
        'lot': '260706001',
        'model': 'MODEL-A',
        'qty': 500,
        'intime': '2026-07-06 09:00',
        'status': 'PRODUCED',
        'reworkLot': null,
      });
      expect(l.isRework, isFalse);
      expect(l.displayLabel, contains('260706001'));
      expect(l.displayLabel, contains('MODEL-A'));
    });

    test('REWORK_READY 상태 → R접두 라벨', () {
      final l = UninspectedLot.fromJson(const {
        'lot': '260706002',
        'model': 'MODEL-B',
        'qty': 300,
        'intime': '2026-07-06 10:00',
        'status': 'REWORK_READY',
        'reworkLot': 'R260706002',
      });
      expect(l.isRework, isTrue);
      expect(l.displayLabel, contains('R260706002'));
      expect(l.displayLabel, contains('재검사'));
    });
  });

  group('ProductionRecord (생산 이력)', () {
    test('NG 후 Rework 미투입 → 재투입 대기', () {
      final r = ProductionRecord.fromJson(const {
        'lot': '260706003',
        'model': 'MODEL-A',
        'qty': 100,
        'intime': '2026-07-06 08:30',
        'result': 'NG',
        'rework': 'R260706003',
        'reworkTime': '',
        'reworkQty': 0,
        'status': 'NG_REWORK_WAIT',
      });
      expect(r.awaitingReworkInput, isTrue);
    });

    test('Rework 재투입 완료 → 재투입 대기 아님', () {
      final r = ProductionRecord.fromJson(const {
        'lot': '260706003',
        'model': 'MODEL-A',
        'qty': 100,
        'intime': '2026-07-06 08:30',
        'result': 'NG',
        'rework': 'R260706003',
        'reworkTime': '2026-07-06 15:00',
        'reworkQty': 20,
        'status': 'REWORK_READY',
      });
      expect(r.awaitingReworkInput, isFalse);
    });

    test('생산 직후(미검사) → 재투입 대기 아님', () {
      final r = ProductionRecord.fromJson(const {
        'lot': '260706004',
        'model': 'MODEL-A',
        'qty': 100,
        'intime': '2026-07-06 08:30',
        'result': '',
        'rework': '',
        'reworkTime': '',
        'reworkQty': 0,
        'status': 'PRODUCED',
      });
      expect(r.awaitingReworkInput, isFalse);
    });
  });
}
