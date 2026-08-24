# TRI 표면 시약 검사 앱 (TRI Reagent Inspection)

TRI 공정 후 표면 시약 검사를 스마트폰으로 기록하는 현장용 앱.
현행 베트남어 엑셀 양식("KIỂM TRA THUỐC THỬ")을 대체한다.

## 통합 구성 (생산 + 검사)
5탭 통합 앱: **생산·검사·이력·대시보드·설정**. 데이터는 이원화 —
- **Production 시트**: 생산 이력(LOT·MODEL·수량·투입시간·검사결과·Rework·Rework투입시간·Rework수량·상태). LOT은 **생산 투입 시** 서버 채번.
- **월별 탭**: 검사 상세(Rack1~5·사진5·CA·검사자·Bar). LOT번호로 Production과 연결.
- 검사는 **미검사 생산LOT을 선택**해 진행 → 결과가 생산행에 자동 반영. NG→Rework(R접두)→재투입→재검사.

## 핵심 규칙
- 검사 1건 = **LOT 1개**. **LOT번호는 서버가 날짜기준 자동 채번** (YYMMDD+일련번호, 예 `260706001`). Bar번호(대차)만 사용자 입력, 판정은 LOT 귀속
- **업무일 기준 08:00:** 하루 업무 시작은 오전 08:00. 00:00~07:59 검사는 전날 업무일에 귀속되며, LOT 일련번호는 08:00에 리셋된다 (예: 7/7 06:00 검사 → `260706NNN`)
- **Rack 1~5** 각각 OK/NG 판정, **1개라도 NG면 종합판정 NG** → Rework 대상 자동 등록. NG의 Rework 식별자는 **`R` 접두** (예 `R260706001`)
- **Rack마다 사진 1장, 총 5장 필수** (미첨부 시 저장 차단, 업로드 시 자동 압축 ≤1.3MB)
- 시간은 **등록 시각 자동 입력** (베트남 ICT, 24시 표기)
- 타임존: **베트남(ICT, UTC+7)** — 검사 시각·월별 탭 라우팅 기준
- 검사자는 이름 선택만 (로그인 없음), UI는 **베트남어+한국어**

## 구조
| 경로 | 내용 |
|------|------|
| `app/` | Flutter 앱 (Android APK + iOS용 웹 PWA — 동일 코드베이스) |
| `gas/` | Google Apps Script 백엔드 (스프레드시트 바인딩, 토큰 보호) |
| `SETUP.md` | 배포 가이드 (GAS 배포 → APK/웹 빌드 → 검증 체크리스트) |
| `.omc/specs/` | 요구사항 스펙 (deep-interview, 모호도 18%) |
| `.omc/plans/` | 구현 계획 v3 (Architect+Critic 합의) |

## 아키텍처 요약
```
Flutter 앱 ──(HTTPS, 공유 토큰, text/plain JSON)──▶ Apps Script Web App
  · 로컬 큐(Hive) 선저장 → 백그라운드 전송            · Google Sheets (월별 탭)
  · 판정 레코드 먼저, 사진(photoUUID 멱등) 후속       · Google Drive (사진)
```

- 데이터 시트: https://docs.google.com/spreadsheets/d/1WUWJz92onLbD4fF-3yy3lCq_beErjoV2aaKUVprdQz0/edit
- iOS는 App Store 미경유 — 웹 빌드를 HTTPS 호스팅 후 Safari **"홈 화면에 추가"**로 설치

## 개발
```powershell
$env:PATH = "C:\Users\USER\flutter\bin;$env:PATH"
cd app
flutter analyze          # 정적 분석
flutter test             # 단위 테스트 (판정 규칙·백오프·직렬화)
flutter build apk --release   # Android (JDK17 + Android SDK 필요)
flutter build web --release   # iOS용 PWA
```
