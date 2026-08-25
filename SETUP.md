# TRI 표면 시약 검사 앱 — 설치·배포 가이드

구성: **Flutter 앱**(`app/`, Android APK + iOS용 웹 PWA) + **Supabase 백엔드**(`supabase/schema.sql`, Postgres+Storage)

- Supabase 프로젝트: Project Settings → API에서 URL/키 확인
- 타임존: 베트남(ICT, UTC+7) — 검사 시각·월별 조회 라우팅의 기준
- iOS는 App Store를 쓰지 않고 **웹(PWA) + Safari '홈 화면에 추가'**로 배포 (사용자 확정)
- (레거시) `gas/` — 2026-08-25 이전에는 Google Apps Script + Sheets/Drive 조합이었으나, Google 시트 용량 한계로 Supabase(Postgres+Storage)로 전환. 코드는 참고용으로 보관.

---

> ## ✅ Supabase 전환 완료 (2026-08-25 검증됨)
> - `supabase/schema.sql` 실행 완료: `production`/`inspections`/`masters`/`app_config` 테이블 + 11개 RPC 함수(`rpc_produce`/`rpc_submit`/`rpc_attach_photo`/`rpc_list`/`rpc_stats`/`rpc_void`/`rpc_masters` 등) + Storage 버킷 `tri-photos`
> - RLS로 테이블 직접 접근 차단, RPC(SECURITY DEFINER)로만 접근 — 앱 토큰(`app_config.app_token`)이 모든 RPC 호출에서 검증됨
> - Project URL·anon(publishable) key는 `app/lib/services/api_client.dart`에 상수로 고정(공개 가능한 값), 앱 토큰은 Settings 화면에서 입력(재빌드 불요, 로테이션 가능)
> - Masters 시드: 검사자1/2, MODEL-A/B, CA-A/B (**자리표시자 — 실제 이름·모델로 교체 필요**, `masters` 테이블에 직접 행 추가)
> - E2E 검증 통과: 토큰 거부(403)/생산투입·LOT채번/미검사목록/검사제출(한글 UTF-8)/Rack별 사진5장 Storage업로드+공개URL 확인/멱등성(중복 submit)/`flutter analyze` 0건·테스트 26개

## 1단계 — Supabase 프로젝트 설정 (1회, 약 5분) — 재설정 시 참고용

1. https://supabase.com → 가입 → **New Project** 생성 (Region: Southeast Asia(Singapore) 권장 — 베트남과 가장 가까움)
2. 좌측 **SQL Editor → New query** → 이 저장소의 `supabase/schema.sql` 전체를 붙여넣고 **Run**
3. **Project Settings → API**에서 **Project URL**과 **anon/publishable key** 확인 → `app/lib/services/api_client.dart`의 `supabaseUrl`/`supabaseAnonKey` 상수와 일치하는지 확인(다른 프로젝트로 재설정한 경우 이 두 값을 교체하고 앱 재빌드 필요)
4. SQL Editor에서 앱 토큰 확인 후 앱 Settings 화면에 입력:
   ```sql
   select value from app_config where key = 'app_token';
   ```
5. `masters` 테이블에 실제 검사자/모델/CA 값 반영 (SQL Editor 또는 Table Editor):
   ```sql
   insert into masters (kind, value) values ('inspector', '실제이름') on conflict do nothing;
   ```

### Supabase 단독 계약 테스트 (앱 없이 검증)

```bash
SUPA_URL="https://<project-ref>.supabase.co"
ANON="<anon/publishable key>"
TOKEN="<app_config.app_token 값>"

# masters 조회 (토큰 검증 포함)
curl -s -X POST "$SUPA_URL/rest/v1/rpc/rpc_masters" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
  -d "{\"p_token\":\"$TOKEN\"}"

# 잘못된 토큰 → HTTP 403 확인
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$SUPA_URL/rest/v1/rpc/rpc_masters" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
  -d '{"p_token":"wrong"}'

# submit 멱등성: 동일 p_uuid로 2회 → 두 번째는 {"ok":true,"duplicate":true}
# ⚠️ 한글 등 비ASCII 값은 명령줄에 직접 넣지 말고 UTF-8 파일로 저장 후 --data-binary @file 로 전송할 것
# (쉘 인코딩에 따라 깨질 수 있음 — 실제로 이 문제로 테스트 데이터가 한 번 오염된 적 있음)
```

---

## 2단계 — Android APK 빌드·배포

요구: Flutter SDK, JDK 17, Android SDK (이 저장소 개발 PC에는 `C:\Users\USER\flutter`, `C:\Users\USER\jdk17`, `C:\Users\USER\android-sdk`로 설치됨)

```powershell
$env:PATH = "C:\Users\USER\flutter\bin;$env:PATH"
$env:JAVA_HOME = "C:\Users\USER\jdk17"
cd "C:\Work Drive\APP\TRI Analysis Management\app"
flutter build apk --release
# 산출물: build\app\outputs\flutter-apk\app-release.apk
```

배포: APK 파일을 현장 Android 폰에 전달(메신저/USB/사내 공유) → 설치 시 "알 수 없는 앱 설치 허용" 필요. Play Store 불요.

---

## 3단계 — iOS용 웹(PWA) 빌드·배포

```powershell
cd "C:\Work Drive\APP\TRI Analysis Management\app"
flutter build web --release
# 산출물: build\web\  (정적 파일 — 아무 HTTPS 호스팅에나 업로드)
```

호스팅(택1, 모두 무료 티어 가능):
- **GitHub Pages**: 리포지토리에 `build/web` 내용 푸시 → Settings→Pages 활성화
- **Firebase Hosting**: `firebase init hosting` → public을 `build/web`로 → `firebase deploy`
- 사내 웹서버(HTTPS 필수 — 카메라 권한은 HTTPS에서만 동작)

iPhone 설치 절차(검사자 안내용):
1. Safari로 호스팅 URL 접속
2. 공유 버튼(□↑) → **"홈 화면에 추가"**
3. 홈 화면 아이콘 "TRI Inspection"으로 실행 — 전체 화면 앱처럼 동작
4. 첫 사진 촬영 시 카메라 권한 허용

---

## 4단계 — 앱 초기 설정 (기기별 1회)

1. 앱 실행 → **설정 탭**
2. **앱 토큰**: 1단계 4번에서 확인한 `app_config.app_token` 값 입력 → 저장 (서버 URL/API 키는 앱에 이미 고정되어 있어 입력 불요)
3. **목록 새로고침** → 검사자 선택
4. 언어 선택 (기본 베트남어 / 한국어 전환 가능)

---

## 5단계 — 수용 기준 검증 체크리스트 (계획 §6)

| # | 검증 | 방법 | 통과 기준 |
|---|------|------|----------|
| 1 | 엑셀 대체 | 하루치 검사를 앱으로만 기록 | Supabase `inspections`/`production` 테이블에 LOT번호(YYMMDD+일련번호)·Rack1~5·종합판정·Rack1~5사진 URL로 기록 |
| 2 | LOT 자동채번 | 같은 업무일 3건 연속 저장 | 260706001, 260706002, 260706003 순차 부여 (오프라인 시 동기화 후 부여) |
| 2b | 업무일 08:00 | 기기 시각을 07:00으로 맞추고 저장 → 08:30으로 맞추고 저장 | 07:00 저장은 전날 LOT(전날일련번호), 08:30 저장은 당일 001부터 |
| 3 | R접두 Rework | NG 검사 저장 | `production.rework` 열에 `R`+LOT (예 R260706002) 등록 |
| 4 | 추적성 | 이력 탭에서 임의 LOT번호 검색 | 결과·Rack별 사진 5장·rework 여부 즉시 표시 |
| 5 | 무손실 | 비행기 모드로 3건 저장 → 재연결 | 판정 레코드 먼저 도달, 사진 후속, 중복 0건 |
| 6 | 속도 | 검사 1건(사진 5장 포함) 입력 측정 | 로컬 큐 저장 즉시 완료 (전송은 백그라운드) |
| 7 | 자동 판정 | Rack 1개만 NG로 저장 | 종합판정 NG + Rework 탭 자동 등록 |
| 8 | Rack별 사진 필수 | 5장 미만으로 저장 시도 | 차단 메시지("Rack 1~5 각각 1장, 총 5장") |
| 9 | 시간 자동 | 저장 시 | 시간 열에 ICT(베트남) 24시 자동 기록 |
| 10 | 필터 | Model별/NG만/월 경계 날짜 범위 조회 | 정상 동작 |
| 11 | 대시보드 | 기간·Model NG율 확인 | 시트 수동 집계와 일치 (void 제외), pending 사진 카운트 |
| 12 | 이중 언어 | 설정에서 vi↔ko 전환 | 전 화면 반영 |
| 13 | 보안 | 토큰 없는 curl 요청 | 전 RPC HTTP 403 거부(UNAUTHORIZED) |
| 14 | 멱등 | 동일 UUID submit 2회 | 행 1개만 생성, `{"duplicate":true}` 반환 |
| 15 | 타임스탬프 | 자정 전 오프라인 기록 → 익일 전송 | 원래 날짜에 기록 (서버는 클라이언트 업무일 date를 신뢰) |
| 16 | 사진 영구실패 | 사진 전송 실패 지속 | 10회 초과 시 경고 배지, `photoN='pending'` 잔존, 대시보드 pending 카운트, 복구 후 중복 없이 도달 |

---

## 운영 절차

- **토큰 로테이션**: `update app_config set value = '<새토큰>' where key = 'app_token';` 실행 후 각 기기 Settings에서 새 토큰 입력 (GAS 시절과 달리 앱이 자동 수신하지 않음 — 필요 시 마스터 갱신 흐름에 태워 자동화 가능)
- **pending 사진 주간 점검**: `select * from inspections where photo1='pending' or photo2='pending' or photo3='pending' or photo4='pending' or photo5='pending';` 또는 대시보드 pending 카운트 확인
- **오입력 정정**: LOT 상세 → 기록 무효화(void) → 재입력 (행 삭제 없음, `void_flag`로 audit 보존)
- **사진 보관**: Supabase Storage `tri-photos` 버킷에 월별(`YYYY-MM`) 폴더로 자동 분류, 파일명에 uuid+rackIndex+photoUUID 포함
