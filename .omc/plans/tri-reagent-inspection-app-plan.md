# 구현 계획: TRI 표면 시약 검사 앱 (v3 — consensus 최종)

- Status: **구현 완료 (2026-07-06, /goal 실행 승인)** — GAS 백엔드·Flutter 앱 코드 작성, analyze 0건, 테스트 15개 통과, Android APK(55.5MB)·웹 PWA 릴리스 빌드 성공. 잔여: GAS 배포·현장 E2E 검증(SETUP.md 절차, 사용자 Google 계정 필요)
  - 참고: Phase -1 AppSheet 스파이크는 사용자의 직접 구현 지시(/goal)로 생략. iOS는 사용자 지시로 App Store 대신 웹 PWA + 홈 화면 추가 방식 채택
- Source Spec: `.omc/specs/deep-interview-tri-reagent-inspection-app.md` (모호도 18%, PASSED)
- Generated: 2026-07-06 | Revised: 2026-07-06 (v2 Architect 반영 → v2.1 사용자 지시 → v3 Critic 필수 보강)
- **계획 범위 주의:** 본 계획은 "Flutter 분기 상세 + Phase -1 AppSheet 게이트"이다. 스파이크 5게이트 전부 통과 시 AppSheet로 전환(별도 축소 계획 작성)하며, 본 계획 승인이 곧 Flutter 확정을 의미하지 않는다.

## 1. Requirements Summary

현장 검사자(베트남어)가 스마트폰으로 TRI 공정 후 표면 시약 검사를 기록하는 Android/iOS 크로스플랫폼 앱. 검사 1건 = LOT 1개, Rack 1~5 각각 OK/NG + 증빙 사진 ≥1장. 1개라도 NG면 LOT은 NG → rework 대상 자동 등록. 데이터는 Google Sheets(사진은 Google Drive), 검사자는 이름 선택만(로그인 없음), 네트워크는 대체로 온라인·가끔 끊김(로컬 큐 필수), UI는 베트남어+한국어. 관리자(한국어)는 대시보드로 NG율 모니터링. 현행 베트남어 엑셀 양식("KIỂM TRA THUỐC THỬ": CA/Ngày/검사자 헤더, STT·시간·Số Bar·Model·Rack1~5 열)과 1:1 대응하되, **STT(순번) 열은 LOT번호로 대체**하고 **Rack5 다음 열에 종합판정(OK/NG) 자동 입력 열을 추가**한다 (사용자 확정 지시, 2026-07-06).

**Non-Goals:** 생산 일지, rework 처리 추적, NG 알림, 개인 Google 로그인, 마스터 관리 화면, 바코드 스캔, 기록 필드 수정(오입력은 void 무효화+재입력으로 처리 — 수정 이력 audit 목적).

## 2. RALPLAN-DR Summary

### Principles (원칙)
1. **양식 보존:** 현행 엑셀 구조와 1:1 대응하는 시트 스키마 — 현장·관리자 전환 비용 최소화
2. **1분 입력:** 검사자 조작은 사진 포함 1분 이내 완료되는 최소 입력 흐름 (기본값 자동화: 날짜/시간 자동, 직전 CA·검사자 유지)
3. **자격증명·접근 통제:** Google 자격증명을 앱에 넣지 않고, 엔드포인트는 앱 공유 토큰으로 보호 (무인증 개방 금지)
4. **판정 우선 무손실:** 핵심 품질 데이터(판정 JSON)를 사진과 분리해 먼저 전송 — 무손실 보장이 사진 전송 성공에 종속되지 않게 함
5. **인프라 무신설:** 별도 서버/DB 없이 Google Workspace(Sheets/Drive/Apps Script) 범위 내 해결 — 착수 전 AppSheet 스파이크로 build-vs-buy 검증

### Decision Drivers (결정 요인 Top 3)
1. Google Sheets를 DB로 사용하라는 확정 제약 + 사진은 Drive 저장이 기술적 귀결
2. 현장 네트워크 간헐 단절 + 데이터 무손실 수용 기준
3. 소규모 현장 팀의 관리 부담 최소화 (로그인 없음, "간단한 앱")

### Viable Options

**[전체 접근] Option A: Flutter 커스텀 앱 + Apps Script 프록시 (선택 — 스파이크 통과 조건부)**
- Pros: 장갑 친화 대형 토글·1분 입력 등 커스텀 UX 완전 제어, 이중 언어 완전 제어, 검증된 오프라인 큐 패턴
- Cons: Dart 스택 유지보수 부채, iOS 서명/배포 마찰, Apps Script 전송 병목

**[전체 접근] Option B: Google AppSheet (no-code)**
- Pros: 오프라인·Drive 사진·무로그인 기본 제공, GAS/큐/멱등성 코드 전부 불요, 원칙 5에 최적, iOS 배포 마찰 없음
- Cons: 1분-입력 UX(대형 토글, 촬영 흐름) 커스터마이즈 한계, 이중 언어 전환 제약, 벤더 종속
- **처리:** 착수 전 1일 스파이크로 검증 (Phase -1). 5개 게이트 기준(§4) 중 하나라도 미달 시 Option A 확정

**[전체 접근] Option C: PWA (Service Worker + Background Sync)**
- Pros: iOS 배포 마찰 없음(계정/TestFlight 불요), 즉시 업데이트
- Cons: iOS Safari의 Background Sync 미지원·카메라/저장 제약으로 원칙 4 달성 불확실, 사용자의 "앱" 요구와 인식 차 → **기각** (무손실 요구와 직접 충돌)

**[백엔드 접근] 서비스 계정 키 앱 내장 직접 호출** — 키가 바이너리에 노출되어 원칙 3 위반 → **기각**

## 3. Architecture

```
[Flutter 앱 (vi/ko)]
  ├─ UI: 검사입력 / 이력·LOT상세 / 대시보드 / Rework목록 / 설정
  ├─ 로컬 큐(Hive): ① 판정레코드 큐  ② 사진업로드 큐 (분리)
  ├─ 마스터 캐시(Hive): 검사자·Model·CA (오프라인 콜드스타트 대비)
  └─ SyncService: 온라인 감지 → 레코드 우선 전송 → 사진 후속 전송(지수 백오프)
        │ HTTPS POST/GET (JSON + X-App-Token 공유 토큰)
        ▼
[Google Apps Script Web App]  ← 토큰 검증(Script Properties) + LockService
  ├─ Sheets: 검사기록(월별 탭) / Rework / Masters
  └─ Drive: 사진 폴더 (YYYY-MM/LOT번호_photoUUID.jpg — 결정적 파일명 = 멱등키)
```

### 보안 (Architect BLOCKER-1 반영)
- 모든 요청에 **앱 공유 토큰**(`X-App-Token` 또는 바디 필드) 필수. `doPost`/`doGet` 첫 단계에서 Script Properties의 토큰과 비교, 불일치 시 즉시 거부
- 토큰은 Script Properties에 저장(코드에 하드코딩 금지). 로테이션: Masters `config`에 신규 토큰 배포 → 앱이 마스터 동기화 시 수신 → 유예기간(구/신 병행) 후 구 토큰 폐기 — 앱 재배포 불필요
- **로테이션 × 장기 오프라인 방어 (Critic 갭 반영):** 유예기간은 현장 최장 예상 오프라인 기간보다 길게 설정(기본 30일). 구 토큰 폐기 전 pending 큐 보유 기기가 없는지 확인(전 기기 마스터 동기화 시각을 config에 기록) — 폐기로 인한 레코드 무손실 위반 차단
- 요청 크기 상한(사진 ≤2MB base64) 및 액션당 rate 상식선 검증으로 Drive 용량 소진 공격 완화

### 전송 2단계 분리 (Architect BLOCKER-3 반영)
1. **레코드 전송(소형 JSON, 수 KB):** 판정·LOT·메타데이터 먼저 전송 — 사진 실패에 인질 잡히지 않음. 시트에는 즉시 행 생성(사진링크 열은 `pending`)
2. **사진 전송(별도 큐 잡):** 레코드 전송 성공 후 사진을 개별 업로드(`attachPhoto` 액션: 레코드 UUID + **photoUUID**(클라이언트 생성) + base64) → 해당 행 사진링크 갱신. 실패 시 사진 잡만 재시도
- UI 규칙은 불변: **촬영 없이는 저장 자체가 차단** (사진 필수는 입력 시점에 보장, 전송만 분리)
- **사진 멱등성 (Critic M1 반영):** Drive 파일명에 photoUUID 포함(`LOT번호_photoUUID.jpg`) — `attachPhoto` 수신 시 해당 파일명 존재 여부를 먼저 검사, 존재하면 재저장 없이 기존 링크 반환. 행 사진링크 갱신도 photoUUID 중복 시 append 금지 → 응답 유실 후 재시도에도 중복 저장·중복 링크 0건
- **pending 종착 정책 (Critic M2 반영):**
  (a) 로컬 사진 큐 항목은 **업로드 확정 응답 수신 전까지 절대 삭제 금지** (앱이 사진의 유일 사본인 동안 영속 보장)
  (b) 재시도 정책: 지수 백오프(상한 1시간 간격), 횟수 무제한 — 단 10회 연속 실패 시 앱 홈에 경고 배지 + 해당 검사 건 표시
  (c) `stats` 응답에 pending 사진 카운트 포함 → 관리자 대시보드에 노출. 운영 절차: 시트에서 `사진링크=pending` 필터 주간 점검
  (d) 기기 분실/앱 삭제로 인한 사진 유실은 잔존 리스크로 수용하되, (c)의 pending 가시성으로 조기 발견

### 멱등성 (Architect BLOCKER-2 반영)
- 검사기록에 UUID 열 고정. `submit` 수신 시 **CacheService**(최근 6시간 UUID 캐시)로 1차 중복 검사 → 미스 시 해당 월 탭 UUID 열만 **TextFinder**로 조회(전 행 스캔 금지)
- Lock 범위 최소화: 중복 검사·행 구성은 Lock 밖, **월 탭 존재 보장(없으면 생성) + appendRow**만 Lock 안 (신월 첫 기록 동시 제출 시 중복 탭 생성 방지 — Critic 갭 반영)
- 규모 상한 문서화: 일 ~40건 × 월 26일 ≈ 1,000행/월 탭 — TextFinder 단일 열 조회는 이 규모에서 <100ms

### 타임스탬프 권위 (Architect HIGH-5 반영)
- **검사 시각 = 기기 시각(Asia/Ho_Chi_Minh 고정)이 유일한 권위.** 날짜/시간 열, 월별 탭 라우팅 모두 검사 시각 기준
- 서버 수신 시각은 별도 열(`서버기록시각`)에 참고용으로만 기록. 오프라인 큐잉으로 수 시간 뒤 도착해도 원래 검사 날짜의 탭·행에 기록됨
- **시계 편차 가드 (Critic m4 반영):** `submit` 시 기기시각-서버시각 편차가 10분 초과면 행에 편차 플래그 기록 + 앱에 시계 확인 경고 표시 (기기 시계 오설정으로 인한 오배치 조기 탐지)
- Apps Script `Session.getScriptTimeZone()`도 ICT로 고정 설정

### Google Sheets 스키마
- **`Inspections` 월별 탭(`YYYY-MM`, 검사 시각 기준 라우팅):** UUID | 날짜 | CA | 검사자 | **LOT번호(STT 대체)** | 시간 | Bar번호 | Model | Rack1 | Rack2 | Rack3 | Rack4 | Rack5 | **종합판정(Rack5 다음 열, OK/NG 자동 파생)** | 사진링크(쉼표구분, 초기 `pending`) | Rework등록 | Void(무효) | 서버기록시각
  - 열 순서는 현행 양식 순서(STT→시간→Số Bar→Model→Rack1~5)를 따르되 STT 자리에 LOT번호, Rack5 직후에 종합판정 자동 열 배치
- **`Rework` 탭:** LOT번호 | Model | 등록시각 | 검사기록UUID
- **`Masters` 탭:** 검사자 목록, Model 목록, CA 목록, config(토큰 로테이션 등)

### Apps Script 엔드포인트 (`action` 분기, 전 액션 토큰 검증)
| action | 기능 |
|--------|------|
| `submit` | 판정 레코드 기록(사진 제외). CacheService+TextFinder 멱등 검사. NG 시 Rework 탭 자동 추가 |
| `attachPhoto` | 레코드 UUID + photoUUID + base64 → Drive 저장(파일명 멱등키 검사, 중복 시 기존 링크 반환) → 행 사진링크 갱신(photoUUID 중복 append 금지) |
| `list` | 조회 (lot / model / ngOnly / dateRange). dateRange가 월 경계를 넘으면 대상 월 탭들을 순회 병합(최대 12개월 제한) |
| `masters` | 검사자·Model·CA·config 반환 (앱은 Hive에 캐시, 오프라인 콜드스타트 시 캐시 사용) |
| `stats` | 기간·Model별 집계(건수·NG율) + **pending 사진 카운트**. list와 동일한 다중 탭 순회. Void 행 제외 |
| `void` | UUID 대상 기록 무효화 플래그 (행 삭제 금지 — audit 보존). 이후 재입력으로 정정 |

### Flutter 프로젝트 구조 (신규 파일)
```
app/
  lib/main.dart
  lib/l10n/app_ko.arb, app_vi.arb           # 이중 언어
  lib/models/inspection.dart, rework.dart    # LOT판정 파생 로직 포함
  lib/services/api_client.dart               # Apps Script 호출(+토큰 헤더)
  lib/services/sync_queue.dart               # 레코드/사진 2단 큐 + 재시도
  lib/services/master_cache.dart             # 마스터 Hive 캐시
  lib/services/photo_service.dart            # 촬영·압축(≤1.3MB — base64 팽창 후 ~1.75MB로 요청 상한 2MB 이내 보장)
  lib/screens/inspection_form_screen.dart    # 검사 입력
  lib/screens/history_screen.dart            # 이력 (LOT검색/Model/NG필터)
  lib/screens/lot_detail_screen.dart         # LOT 상세 (결과·사진·rework·void)
  lib/screens/dashboard_screen.dart          # 검사자 요약/관리자 NG율
  lib/screens/settings_screen.dart           # 언어 전환, 검사자 선택
gas/
  Code.gs                                    # Apps Script 소스 (repo 보관)
  appsscript.json                            # 타임존 ICT 고정
```

## 4. Implementation Steps

**Phase -1 — Build-vs-Buy 스파이크 (1일, Architect antithesis 검증)**
0. AppSheet로 검사 입력 프로토타입 구성 후 5개 게이트 평가:
   ① Rack1~5 대형 토글 입력이 장갑 착용 상태에서 실용적인가 ② 사진 필수 강제 가능한가 ③ vi/ko 전환이 가능한가 ④ 오프라인 저장→복구 전송이 무손실인가 ⑤ 검사 1건 입력 1분 이내인가
   — **전부 통과 시 AppSheet 채택으로 계획 전환(별도 축소 계획 작성), 하나라도 미달 시 Option A(Flutter) 확정 진행**

**Phase 0 — Google 리소스 준비 (iOS 게이트 포함)**
1. **iOS 배포 게이트 → 해소 (사용자 지시, 2026-07-06):** 점검 결과 iOS 네이티브 배포는 App Store/TestFlight 경유가 사실상 필수(Apple Developer 계정 + 심사). 사용자 지시에 따라 **iOS는 Flutter Web(PWA) 빌드 + Safari '홈 화면에 추가'** 방식으로 배포. Android는 네이티브 APK 유지. 동일 Flutter 코드베이스에서 두 타깃 빌드 (웹 빌드는 HTTPS 정적 호스팅 필요 — GitHub Pages/Firebase Hosting 등)
   - 기술 파급: API 호출은 브라우저 CORS 제약 대응(Apps Script는 preflight 미지원 → POST Content-Type `text/plain` 단순 요청 사용), 로컬 큐는 Hive의 IndexedDB 백엔드 사용, 카메라는 image_picker 웹 지원(파일 input capture) 사용
2. **기존 스프레드시트 사용 (사용자 제공, 2026-07-06):** `https://docs.google.com/spreadsheets/d/1WUWJz92onLbD4fF-3yy3lCq_beErjoV2aaKUVprdQz0/edit` — 탭 3종(Inspections 월별/Rework/Masters) + 헤더 구성, Drive 사진 폴더 생성
3. `gas/Code.gs` 작성: 6개 액션 + 토큰 검증 + LockService(최소 범위) + CacheService/TextFinder 멱등 + ICT 타임존
4. Web App 배포 → URL·초기 토큰을 Script Properties에 설정
5. **GAS 단독 검증 (Critic 갭 반영):** 앱 개발 전 curl/스크립트로 6개 액션 전부 계약 테스트 — submit 멱등(동일 UUID 2회), attachPhoto 멱등(동일 photoUUID 2회), 토큰 거부, 월 경계 list, void 반영

**Phase 1 — 앱 스캐폴드**
6. Flutter 프로젝트 생성, i18n(ko/vi), 공통 테마·큰 터치 타깃(장갑 고려)
7. 설정 화면: 언어 전환, 검사자 선택(masters 캐시 로드)

**Phase 2 — 데이터 계층**
8. `inspection.dart`: Rack1~5 중 NG 존재 → 종합판정 NG 파생 로직 + 단위 테스트
9. `sync_queue.dart`: 레코드 큐/사진 큐 분리, 연결 감지 → 레코드 우선 순차 전송 → 사진 후속, 실패 시 지수 백오프(상한 1시간)·업로드 확정 전 삭제 금지, 상태 표시(대기/전송중/완료/사진대기)
10. `master_cache.dart`: masters 응답 Hive 캐시 + 콜드스타트 폴백
11. `api_client.dart`(토큰 헤더) + `photo_service.dart`(촬영, 리사이즈·압축 ≤1.3MB — base64 팽창 후 ~1.75MB로 상한 2MB 이내, photoUUID 부여)

**Phase 3 — 검사 입력 화면**
12. 헤더(날짜 자동, CA·검사자 직전값 유지) + LOT번호·Bar번호·Model 입력(Model 자동완성) + Rack1~5 대형 OK/NG 토글 + 카메라 버튼
13. 저장 검증: 사진 0장 시 저장 차단, 필수 필드 검증 → 로컬 큐 저장(즉시 완료) → 다음 검사 진행 가능

**Phase 4 — 이력·LOT 상세**
14. 이력 화면: LOT번호 검색, Model별 필터, NG만 필터, 날짜 범위(월 경계 초과 시 다중 탭 병합 결과)
15. LOT 상세: Rack1~5 결과, 사진 뷰어, rework 등록 여부, void(무효화) 버튼 — void 시 재입력 안내

**Phase 5 — 대시보드**
16. 검사자 요약: 당일/기간 본인 검사 건수·NG 건수
17. 관리자 모니터링: 기간·Model별 NG율 추이, Rework 대상 목록 (Void 제외 집계), pending 사진 카운트

**Phase 6 — QA·배포**
18. 수용 기준 시나리오 테스트(§6) — 비행기 모드 단절, 사진 분리 전송·영구 실패, 토큰 거부 케이스 포함
19. Android APK 배포 + iOS 빌드(Phase 0 게이트 결과에 따름)

## 5. Risks & Mitigations
| 위험 | 영향 | 완화 |
|------|------|------|
| Web App URL 유출로 무단 접근 | 데이터 오염·유출·Drive 소진 | 공유 토큰 검증 + 요청 크기 상한 + 토큰 무재배포 로테이션 경로 |
| Apps Script 응답 지연(1~3초) | 입력 흐름 지연 | 저장은 로컬 큐 즉시 완료, 전송은 백그라운드 — UI 비차단 |
| 사진 전송 실패 반복 | 큐 적체·쿼터 소모 | 레코드/사진 분리 전송 — 판정 데이터는 먼저 도달, 사진 잡만 독립 재시도(백오프 상한 1시간) |
| pending 사진 영구 잔존 | 사진 무손실 위반 | 로컬 큐 삭제 금지(업로드 확정까지) + 10회 실패 경고 배지 + stats pending 카운트 + 주간 시트 점검 절차 |
| 재시도로 인한 사진 중복 저장 | Drive 낭비·링크 오염 | photoUUID 결정적 파일명 멱등키 — 중복 시 기존 링크 반환, append 금지 |
| 기기 시계 오설정 | 날짜/탭 오배치 | 기기-서버 편차 10분 초과 시 행 플래그 + 앱 경고 |
| 동시 쓰기 충돌(기기 여러 대) | 행 유실/중복 | LockService(append만) + CacheService/TextFinder 멱등 |
| 오프라인 콜드스타트 | 검사 시작 불가 | 마스터 Hive 캐시 폴백 |
| 큐잉 지연 도착 기록의 날짜 오배치 | 양식 무결성 훼손 | 검사 시각(기기, ICT) 권위 고정 — 탭 라우팅·날짜 열 모두 검사 시각 기준 |
| iOS 배포 경로 부재 | 출시 지연 | Phase 0 게이트에서 확인, 미확보 시 Android 선행 로드맵 |
| Sheets 행 증가 | 조회 지연 | 월별 탭 + 단일 열 TextFinder + 조회 범위 12개월 제한 (규모 상한 문서화: ~1,000행/월) |
| AppSheet가 실제로 충분한데 커스텀 개발 착수 | 수개월 유지보수 부채 낭비 | Phase -1 스파이크 5게이트로 착수 전 강제 검증 |

## 6. Verification Steps (수용 기준 대응)
1. **엑셀 대체:** 시연일 하루치 검사 전 건을 앱으로만 기록 → 시트에서 기존 양식 열 구성으로 확인 — **STT 자리에 LOT번호가 기록되고, 전 건(OK 포함) Rack5 다음 열에 종합판정이 자동 채워졌는지 명시 확인**
2. **추적성:** 임의 LOT번호 검색 → 결과·사진·rework 여부 표시 확인 (3건 표본)
3. **무손실(레코드):** 비행기 모드에서 검사 3건 저장 → 재연결 → 판정 레코드 3건 먼저 시트 도달, 사진 후속 도달, 중복 0건
4. **속도:** 스톱워치로 검사 1건(사진 1장) 입력 5회 측정 → 전 회 60초 이내 (저장 완료 = 로컬 큐 기록 시점)
5. **자동 판정:** Rack 1건만 NG 입력 → LOT판정 NG + Rework 탭 자동 등록 확인
6. **사진 필수:** 사진 없이 저장 시도 → 차단 메시지 확인
7. **필터:** Model별/NG만/월 경계 넘는 날짜 범위 조회 동작 확인
8. **대시보드:** 기간·Model NG율 수치가 시트 수동 집계와 일치 (void 행 제외 확인)
9. **이중 언어:** 전 화면 vi/ko 전환 확인
10. **보안:** 토큰 없는 요청 → 전 액션 거부 확인. 토큰 로테이션 시나리오(구/신 병행 → 구 폐기) 확인
11. **멱등:** 동일 UUID submit 2회 → 행 1개만 생성 확인
12. **타임스탬프:** 오프라인 자정 전 기록 → 다음날 전송 → 원래 날짜/탭에 기록 확인
13. **사진 잡 영구 실패 시나리오 (Critic M2):** 사진 전송을 강제 실패시킨 상태로 10회 재시도 초과 → 앱 경고 배지 표시 + 시트 `pending` 잔존 + stats의 pending 카운트 반영 확인. 이후 네트워크 복구 → 사진 도달 + 중복 저장 0건(photoUUID 멱등) 확인

## 7. Open Questions (실행 착수 시 확인)
1. ~~Google 계정: 스프레드시트·Apps Script를 소유할 회사 계정은?~~ → **해소 (2026-07-06):** 사용자 제공 스프레드시트 사용 — `https://docs.google.com/spreadsheets/d/1WUWJz92onLbD4fF-3yy3lCq_beErjoV2aaKUVprdQz0/edit` (Apps Script는 이 시트에 바인딩, 소유 계정 동일)
2. 검사자·Model 초기 목록 데이터
3. 사진 보존 기간·Drive 용량 정책 (기본: 무기한 보관)
4. 사진 잡 재시도 운영 상한(현 기본: 무제한 재시도 + 10회 실패 시 경고) 및 토큰 로테이션 유예기간(기본 30일)의 현장 적정성

## 8. ADR

- **Decision:** Flutter 크로스플랫폼 앱 + Google Apps Script Web App 프록시(공유 토큰 보호) + Hive 2단 큐(레코드/사진 분리), Google Sheets(데이터)/Drive(사진) 저장. 단, 착수 전 1일 AppSheet 스파이크가 5개 게이트를 전부 통과하면 AppSheet로 전환
- **Drivers:** Sheets DB 확정 제약, 간헐 단절 무손실 요구, 관리 부담 최소화
- **Alternatives considered:** ① AppSheet no-code(스파이크로 검증 예정) ② PWA(iOS Background Sync 부재로 무손실 불충족 — 기각) ③ 서비스 계정 키 앱 내장(자격증명 노출 — 기각) ④ React Native/Expo — 실행 가능한 동급 후보(카메라·백그라운드 태스크 지원 성숙). 단일 코드베이스 유지보수, Hive급 경량 로컬DB, i18n 툴체인 일관성에서 Flutter가 근소 우위로 판단. Expo로 바꿔도 본 계획의 아키텍처(토큰 프록시·2단 큐·시트 스키마)는 그대로 유효한 프레임워크 하위 선택임
- **Why chosen:** 접근 통제 원칙을 실질 충족(토큰)하면서 커스텀 UX(1분 입력·장갑 토글·이중언어) 완전 제어 + 인프라 무신설 유지. 판정/사진 분리로 무손실 보장을 핵심 데이터에 fine-grained 적용
- **Consequences:** Apps Script 지연은 큐로 흡수, Google Workspace 종속(수용), Dart 스택 채택, 사진은 최종 일관성(행 생성 후 링크 후속 갱신)
- **Follow-ups:** AppSheet 스파이크 실행, iOS 배포 게이트 확인, 마스터 데이터 수집, 사진 보존 정책, 토큰 로테이션 운영 절차 문서화

## 9. Changelog (consensus 반영 이력)
- **v6 (생산 이력 통합 — 대규모 기능 추가, 2026-07-06):** 별도 스펙 `deep-interview-tri-production-history.md` 기준 구현·배포 완료
  - 데이터 모델 이원화: 신규 `Production` 시트(LOT·MODEL·수량·투입시간·검사결과·Rework·Rework투입시간·Rework수량·상태) + 기존 월별탭(검사 상세) LOT 연결
  - LOT 채번 권위를 검사 submit → 생산 `produce` 액션으로 이동(YYMMDD+일련번호·업무일 08:00)
  - 검사 흐름 재설계: 미검사 생산LOT 드롭다운 선택 + MODEL 자동채움, 결과가 생산행 검사결과 자동 반영
  - Rework 상태 머신: NG→R접두 자동등록(NG_REWORK_WAIT)→reworkInput 재투입(REWORK_READY)→재검사→DONE_OK
  - GAS 신규 액션: produce/listUninspected/reworkInput/productionList/productionStats, submit·void 생산행 연동. Rework 수량 초과 경고. GAS v5 재배포
  - Flutter: 5탭(생산·검사·이력·대시보드·설정), 생산 화면(투입+Rework 재투입 대기 목록), 검사 폼 재설계, 대시보드 생산 지표 4종(미검사·검사율·생산량/Rework율·기간추이)
  - 버그 수정: 투입시간 Date 저장 → normIntime_ 읽기 정규화(날짜 필터·표시)
  - 검증: analyze 0/테스트 26개, GAS 계약 테스트 전 흐름(produce·멱등·검사→생산행·R접두·reworkInput·재검사·수량경고·통계), 브라우저 E2E(생산투입→미검사LOT드롭다운→MODEL자동채움→대시보드 생산지표)

- **v5 (업무일 08:00 규칙, 2026-07-06):**
  - 하루 업무 시작 08:00(ICT). 00:00~07:59 검사는 전날 업무일에 귀속 → LOT 일련번호가 08:00에 리셋
  - 앱이 `workDate = (ICT now − 8h).date`를 계산해 `date`로 전송 → 서버는 기존대로 date를 신뢰(LOT prefix·일련번호·월탭 라우팅 모두 업무일 기준). **GAS 재배포 불필요**(서버 로직 무변경)
  - 시간 열은 실제 벽시계(ICT 24시) 유지. 대시보드/이력 기본 조회범위도 업무일 기준으로 전환
  - 업무일 경계 단위테스트 추가(08:00 전후·월/연 경계), 앱 재빌드
- **v4 (사용자 지시 4건 반영 + 구현/배포 완료, 2026-07-06):**
  - LOT 자동 채번: 사용자 입력 제거 → 서버가 날짜기준 YYMMDD+일련번호 채번(lock 내, 충돌 방지). 응답으로 lot 반환, 오프라인 시 동기화 시점 부여
  - NG Rework에 `R` 접두 LOT 등록 (예 R260706001)
  - Rack별 사진 5장: 시트 스키마에 Rack1~5사진 5열 추가, attachPhoto에 rackIndex, 폼 5슬롯 필수
  - 시간 자동 입력(ICT 24시) — 표시 강화
  - GAS 재배포(버전 3), 시트 신규 스키마로 초기화, 계약 테스트 재검증, APK/웹 재빌드
  - 발견·수정: 사진 재전송 중복 링크 버그(URL 기준 검사로 수정)

- **v3 (Critic 조건부 승인 — 필수 보강 반영, 2026-07-06):**
  - [M1 필수] attachPhoto 멱등성: photoUUID 결정적 파일명 멱등키, 중복 저장·중복 링크 차단
  - [M2 필수] pending 사진 종착 정책: 로컬 큐 삭제 금지, 백오프 상한 1시간, 10회 실패 경고 배지, stats pending 카운트, 주간 점검 절차, 검증 스텝 13 추가
  - [m3] 사진 압축 목표 1.5MB → 1.3MB (base64 팽창 후 2MB 상한 이내)
  - [m4] 기기-서버 시계 편차 10분 가드 추가
  - [갭] 월 탭 생성을 Lock 범위에 포함, 토큰 로테이션 × 장기 오프라인 방어(유예 30일+pending 확인), GAS 단독 계약 테스트 단계 추가
  - [m1] RN/Expo 기각 근거 보강 (동급 후보 인정, 하위 선택 명시)
  - [m6/V1] STT→LOT 대체 및 종합판정 OK 자동 채움 명시 검증 추가
  - [모호성] 계획 범위 주의문 추가 (Flutter 분기 + AppSheet 게이트)
  - [사용자 제공] Google Sheet URL 반영 — Open Question 1 해소
- **v2.1 (사용자 지시 반영, 2026-07-06):**
  - 시트 STT(순번) 열 → LOT번호로 대체
  - Rack5 다음 열에 종합판정(OK/NG) 자동 입력 열 추가 (Rack1~5 중 NG 존재 시 NG 파생)
- **v2 (Architect 조건부 승인 반영):**
  - [BLOCKER-1] 앱 공유 토큰 + Script Properties + 무재배포 로테이션 + 요청 크기 상한 추가
  - [BLOCKER-3] 레코드/사진 전송 2단계 분리 (판정 우선 무손실 — 원칙 4 재정의)
  - [BLOCKER-2] 멱등성: CacheService + 단일 열 TextFinder, Lock 범위 최소화, 규모 상한 문서화
  - [HIGH-4] 마스터 Hive 캐시 (오프라인 콜드스타트 방어)
  - [HIGH-5] 타임스탬프 권위 확정 (기기 검사 시각, ICT 고정, 탭 라우팅 기준)
  - [MED-6] 크로스-월 조회: 다중 탭 순회 병합 + 12개월 제한
  - [MED-7] void(무효화) 액션 추가 — 수정은 non-goal 유지, 무효화+재입력 경로 신설
  - [LOW-8] iOS 배포를 Open Question → Phase 0 게이트로 승격
  - [Antithesis] Phase -1 AppSheet 1일 스파이크 (5게이트 build-vs-buy 강제 검증) 추가
