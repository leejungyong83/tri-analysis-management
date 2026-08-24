/// 베트남(ICT, UTC+7) 시각 유틸 + 업무일(work-day) 계산.
///
/// 검사 시각의 유일한 권위는 ICT 기준 기기 시각이다 (계획 §3 타임스탬프 권위).
/// 기기 타임존 설정과 무관하게 UTC+7로 환산해 기록한다.
///
/// **업무일 규칙 (사용자 지시):** 하루 업무 시작은 오전 08:00(ICT).
/// 00:00~07:59 검사는 "전날 업무일"에 속한다. LOT 채번·기록 날짜·월별 탭
/// 라우팅은 모두 업무일(workDate) 기준이며, 08:00에 일련번호가 리셋된다.
/// (시간 열은 실제 벽시계 시각을 그대로 기록한다.)
class IctTime {
  static const Duration ictOffset = Duration(hours: 7);
  static const Duration workDayStart = Duration(hours: 8);

  static DateTime nowIct() => DateTime.now().toUtc().add(ictOffset);

  /// 실제 벽시계 날짜 (자정 기준). 표시/디버그용.
  static String today() => dateStr(nowIct());

  /// 실제 벽시계 시각 HH:mm (ICT 24시). 기록 시간 열용.
  static String nowTime() => timeStr(nowIct());

  // --- 업무일(work-day) ---

  /// 임의 ICT 시각의 업무일 날짜 (순수 함수 — 테스트 가능).
  /// 08:00을 빼서 얻은 날짜가 업무일. 07:59 이전은 전날로 귀속.
  static String workDateOf(DateTime ictTime) =>
      dateStr(ictTime.subtract(workDayStart));

  /// 현재 업무일 날짜 (yyyy-MM-dd). LOT 채번·기록 날짜·월탭 라우팅 기준.
  static String workDate() => workDateOf(nowIct());

  /// 현재 업무일 기준 이번 달 1일 (조회 기본 시작일).
  static String workFirstOfMonth() {
    final n = nowIct().subtract(workDayStart);
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-01';
  }

  // --- 포맷 ---

  static String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String timeStr(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 'yyyy-MM-dd' → 월별 탭 이름 'yyyy-MM'
  static String monthTab(String date) => date.substring(0, 7);
}
