// 생산 이력 모델 (이원화: 생산이력 시트 = 요약/원천).
// LOT은 생산 투입 시 서버가 채번(YYMMDD+일련번호, 업무일 08:00 기준).
// 검사는 미검사 생산LOT을 선택해 진행하고, 결과가 생산행 검사결과에 자동 반영된다.

/// 미검사 생산LOT (검사 화면 드롭다운용).
/// 상태 PRODUCED(미검사) 또는 REWORK_READY(재투입됨, 재검사 대기).
class UninspectedLot {
  final String lot;
  final String model;
  final num qty;
  final String intime; // 'yyyy-MM-dd HH:mm'
  final String status; // PRODUCED | REWORK_READY
  final String? reworkLot; // REWORK_READY면 'R'+lot

  const UninspectedLot({
    required this.lot,
    required this.model,
    required this.qty,
    required this.intime,
    required this.status,
    this.reworkLot,
  });

  bool get isRework => status == 'REWORK_READY';

  /// 드롭다운 표시 라벨: 재검사 대기면 R접두를 앞에 노출.
  String get displayLabel {
    final base = '$lot · $model · ${qty}ea';
    return isRework ? '↻ ${reworkLot ?? 'R$lot'} · $model · ${qty}ea (재검사)' : base;
  }

  factory UninspectedLot.fromJson(Map<String, dynamic> j) => UninspectedLot(
        lot: '${j['lot'] ?? ''}',
        model: '${j['model'] ?? ''}',
        qty: (j['qty'] is num) ? j['qty'] as num : num.tryParse('${j['qty']}') ?? 0,
        intime: '${j['intime'] ?? ''}',
        status: '${j['status'] ?? ''}',
        reworkLot: j['reworkLot'] == null ? null : '${j['reworkLot']}',
      );
}

/// 생산 이력 전체 레코드 (생산 탭 목록·Rework 재투입 대기 목록용).
class ProductionRecord {
  final String lot;
  final String model;
  final num qty;
  final String intime;
  final String result; // '' | OK | NG
  final String rework; // '' | R+lot
  final String reworkTime;
  final num reworkQty;
  final String status;

  const ProductionRecord({
    required this.lot,
    required this.model,
    required this.qty,
    required this.intime,
    required this.result,
    required this.rework,
    required this.reworkTime,
    required this.reworkQty,
    required this.status,
  });

  /// NG 판정 후 Rework 재투입을 아직 안 한 상태(재투입 대기).
  bool get awaitingReworkInput =>
      status == 'NG_REWORK_WAIT' && reworkTime.isEmpty;

  factory ProductionRecord.fromJson(Map<String, dynamic> j) => ProductionRecord(
        lot: '${j['lot'] ?? ''}',
        model: '${j['model'] ?? ''}',
        qty: (j['qty'] is num) ? j['qty'] as num : num.tryParse('${j['qty']}') ?? 0,
        intime: '${j['intime'] ?? ''}',
        result: '${j['result'] ?? ''}',
        rework: '${j['rework'] ?? ''}',
        reworkTime: '${j['reworkTime'] ?? ''}',
        reworkQty: (j['reworkQty'] is num)
            ? j['reworkQty'] as num
            : num.tryParse('${j['reworkQty']}') ?? 0,
        status: '${j['status'] ?? ''}',
      );
}
