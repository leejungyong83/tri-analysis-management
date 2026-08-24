/// 검사 기록 모델.
///
/// 검사 1건 = LOT 1개. Rack 1~5 각각 OK/NG, 종합판정은 파생값.
/// LOT번호는 생산 투입 시 서버가 채번하며, 검사는 미검사 생산LOT을 선택한다
/// (검사가 LOT을 생성하지 않고 기존 생산LOT을 참조). MODEL은 생산LOT에서 자동채움.
/// Bar번호(대차)는 사용자 입력. Rack마다 사진 1장(총 5장)을 첨부한다.
class Inspection {
  final String uuid;
  final String date; // yyyy-MM-dd (검사 업무일 — 월별 탭 라우팅 권위)
  final String ca;
  final String inspector;
  final String lot; // 선택한 생산LOT (서버 채번값)
  final String time; // HH:mm (ICT, 24시)
  final String bar;
  final String model; // 생산LOT에서 자동채움
  final List<String> racks; // 'OK' | 'NG' — 항상 5개

  const Inspection({
    required this.uuid,
    required this.date,
    required this.ca,
    required this.inspector,
    required this.lot,
    required this.time,
    required this.bar,
    required this.model,
    required this.racks,
  }) : assert(racks.length == 5);

  /// 종합판정 파생 규칙: Rack 5개 중 1개라도 NG면 LOT은 NG (스펙 확정 규칙).
  static String deriveVerdict(List<String> racks) =>
      racks.contains('NG') ? 'NG' : 'OK';

  String get verdict => deriveVerdict(racks);

  /// 선택한 생산LOT을 payload에 포함 (서버는 이 LOT의 생산행 검사결과를 갱신).
  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'date': date,
        'ca': ca,
        'inspector': inspector,
        'lot': lot,
        'time': time,
        'bar': bar,
        'model': model,
        'racks': racks,
      };

  factory Inspection.fromJson(Map<dynamic, dynamic> j) => Inspection(
        uuid: j['uuid'] as String,
        date: j['date'] as String,
        ca: j['ca'] as String,
        inspector: j['inspector'] as String,
        lot: j['lot'] as String,
        time: j['time'] as String,
        bar: j['bar'] as String,
        model: j['model'] as String,
        racks: (j['racks'] as List).map((e) => e as String).toList(),
      );
}

/// 서버(list 액션)에서 내려오는 조회용 레코드.
class RemoteRecord {
  final String uuid;
  final String date;
  final String ca;
  final String inspector;
  final String lot; // 서버 채번 값 (YYMMDD+일련번호)
  final String time;
  final String bar;
  final String model;
  final List<String> racks;
  final String verdict;
  final List<String> photos; // Rack별 5개. 각 원소는 URL 또는 'pending'
  final bool rework;
  final bool voided;

  const RemoteRecord({
    required this.uuid,
    required this.date,
    required this.ca,
    required this.inspector,
    required this.lot,
    required this.time,
    required this.bar,
    required this.model,
    required this.racks,
    required this.verdict,
    required this.photos,
    required this.rework,
    required this.voided,
  });

  bool get anyPhotoPending => photos.any((p) => p == 'pending' || p.isEmpty);

  int get pendingPhotoCount =>
      photos.where((p) => p == 'pending' || p.isEmpty).length;

  /// NG LOT의 rework 식별자 (Rework 탭 표기와 동일: "R" 접두).
  String get reworkLot => 'R$lot';

  factory RemoteRecord.fromJson(Map<String, dynamic> j) {
    final rawPhotos = (j['photos'] as List? ?? const []).map((e) => '$e').toList();
    // 하위호환: 과거 단일 문자열 형태가 오면 5칸으로 정규화
    final photos = rawPhotos.length == 5
        ? rawPhotos
        : List<String>.generate(5, (i) => i < rawPhotos.length ? rawPhotos[i] : 'pending');
    return RemoteRecord(
      uuid: '${j['uuid'] ?? ''}',
      date: '${j['date'] ?? ''}',
      ca: '${j['ca'] ?? ''}',
      inspector: '${j['inspector'] ?? ''}',
      lot: '${j['lot'] ?? ''}',
      time: '${j['time'] ?? ''}',
      bar: '${j['bar'] ?? ''}',
      model: '${j['model'] ?? ''}',
      racks: (j['racks'] as List? ?? const []).map((e) => '$e').toList(growable: false),
      verdict: '${j['verdict'] ?? ''}',
      photos: photos,
      rework: j['rework'] == true,
      voided: j['voided'] == true,
    );
  }
}
