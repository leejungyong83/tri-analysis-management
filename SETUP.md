# TRI 표면 시약 검사 앱 — 설치·배포 가이드

구성: **Flutter 앱**(`app/`, Android APK + iOS용 웹 PWA) + **Google Apps Script 백엔드**(`gas/`, 스프레드시트 바인딩)

- 데이터 시트: https://docs.google.com/spreadsheets/d/1WUWJz92onLbD4fF-3yy3lCq_beErjoV2aaKUVprdQz0/edit
- 타임존: 베트남(ICT, UTC+7) — 검사 시각·월별 탭 라우팅의 기준
- iOS는 App Store를 쓰지 않고 **웹(PWA) + Safari '홈 화면에 추가'**로 배포 (사용자 확정)

---

> ## ✅ 1단계 완료 (2026-07-06 자동 배포·검증됨)
> 아래 1단계는 이미 완료되었습니다:
> - Apps Script 프로젝트 "TRI Inspection API"가 시트에 바인딩되어 **버전 3**으로 배포됨
> - **웹 앱 URL:** `https://script.google.com/macros/s/AKfycbyXT47Nb1osynnsyObHulFOHew5LIyz1KTMkLIAE252fCF0AlXzn5uvUBqJ7hOoE5rKhg/exec` (`.omc/state/webapp-url.txt`)
> - **앱 토큰:** `.omc/state/app-token.txt` (Script Properties `APP_TOKEN`에 설정됨 — 코드에는 없음)
> - 사진 폴더: Drive "TRI검사사진" (ID `1EkAvJiVO4o70fzKK0TZQoMZzWXqF-z84`)
> - Masters 탭 시드: 검사자1/2, MODEL-A/B, CA (**자리표시자 — 실제 이름·모델로 교체 필요**)
> - 시트는 신규 스키마로 초기화 완료 (테스트 데이터 전량 정리됨) — 첫 실제 검사부터 LOT `260706001`
> - 계약 테스트 통과: masters/토큰거부/submit 멱등/LOT 자동채번(YYMMDD+seq)/NG 자동판정+Rework(R접두)/Rack별 사진 5장 개별 업로드/photoUUID 멱등/list/stats/void
> - 참고: Drive `TRI검사사진/2026-07` 폴더에 4×4px 테스트 이미지 몇 개가 남아 있음(무해 — 원하면 삭제)

## 1단계 — Google Apps Script 배포 (1회, 약 10분) — 재배포 시 참고용

1. 위 스프레드시트를 열고 **확장 프로그램 → Apps Script** 클릭
2. 기본 `Code.gs` 내용을 지우고 이 저장소의 `gas/Code.gs` 전체를 붙여넣기
3. 좌측 **프로젝트 설정(톱니바퀴) → "appsscript.json 매니페스트 파일 표시" 체크** → 편집기에서 `appsscript.json`을 이 저장소의 `gas/appsscript.json` 내용으로 교체 (타임존 `Asia/Ho_Chi_Minh` 지정)
4. **Google Drive에서 사진 저장용 폴더 생성** (예: "TRI검사사진") → 폴더 URL의 `folders/` 뒤 ID 복사
5. **프로젝트 설정 → 스크립트 속성**에 추가:
   | 속성 | 값 |
   |------|-----|
   | `APP_TOKEN` | 임의의 긴 무작위 문자열 (예: 32자 이상) — 앱에도 동일하게 입력 |
   | `PHOTO_FOLDER_ID` | 4번에서 복사한 Drive 폴더 ID |
6. 시트에 **`Masters` 탭 생성** 후 기준정보 입력 (A열=종류, B열=값):
   ```
   inspector | 홍길동
   inspector | Nguyễn Văn A
   model     | MODEL-A
   model     | MODEL-B
   ca        | CA1
   ca        | CA2
   ca        | CA3
   ```
   (월별 검사 탭 `YYYY-MM`과 `Rework` 탭은 앱이 첫 기록 시 자동 생성)
7. **배포 → 새 배포 → 유형: 웹 앱** — "실행: 나", "액세스: 모든 사용자" → 배포 → **웹 앱 URL 복사** (`https://script.google.com/macros/s/…/exec`)

### GAS 단독 계약 테스트 (앱 없이 검증)

```bash
# masters 조회 (토큰 검증 포함)
curl -L -H "Content-Type: text/plain" -d "{\"action\":\"masters\",\"token\":\"<APP_TOKEN>\"}" "<웹앱URL>"

# 잘못된 토큰 → {"ok":false,"error":"UNAUTHORIZED"} 확인
curl -L -H "Content-Type: text/plain" -d "{\"action\":\"masters\",\"token\":\"wrong\"}" "<웹앱URL>"

# submit 멱등성: 동일 uuid로 2회 → 두 번째는 {"ok":true,"duplicate":true}, 시트에 행 1개만
curl -L -H "Content-Type: text/plain" -d "{\"action\":\"submit\",\"token\":\"<APP_TOKEN>\",\"uuid\":\"test-1\",\"date\":\"2026-07-06\",\"ca\":\"CA1\",\"inspector\":\"홍길동\",\"lot\":\"LOT-TEST\",\"time\":\"09:00\",\"bar\":\"BAR-1\",\"model\":\"MODEL-A\",\"racks\":[\"OK\",\"OK\",\"NG\",\"OK\",\"OK\"]}" "<웹앱URL>"
# → 시트 2026-07 탭에 행 생성, 종합판정 NG, Rework 탭 자동 등록 확인
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
2. **서버 URL**: 1단계 7번의 웹 앱 URL 입력
3. **앱 토큰**: `APP_TOKEN` 값 입력 → 저장
4. **목록 새로고침** → 검사자 선택
5. 언어 선택 (기본 베트남어 / 한국어 전환 가능)

---

## 5단계 — 수용 기준 검증 체크리스트 (계획 §6)

| # | 검증 | 방법 | 통과 기준 |
|---|------|------|----------|
| 1 | 엑셀 대체 | 하루치 검사를 앱으로만 기록 | 시트에 LOT번호(YYMMDD+일련번호)·Rack1~5·종합판정·Rack1~5사진 열로 기록 |
| 2 | LOT 자동채번 | 같은 업무일 3건 연속 저장 | 260706001, 260706002, 260706003 순차 부여 (오프라인 시 동기화 후 부여) |
| 2b | 업무일 08:00 | 기기 시각을 07:00으로 맞추고 저장 → 08:30으로 맞추고 저장 | 07:00 저장은 전날 LOT(전날일련번호), 08:30 저장은 당일 001부터 |
| 3 | R접두 Rework | NG 검사 저장 | Rework 탭에 `R`+LOT (예 R260706002) 등록 |
| 4 | 추적성 | 이력 탭에서 임의 LOT번호 검색 | 결과·Rack별 사진 5장·rework 여부 즉시 표시 |
| 5 | 무손실 | 비행기 모드로 3건 저장 → 재연결 | 판정 레코드 먼저 도달, 사진 후속, 중복 0건 |
| 6 | 속도 | 검사 1건(사진 5장 포함) 입력 측정 | 로컬 큐 저장 즉시 완료 (전송은 백그라운드) |
| 7 | 자동 판정 | Rack 1개만 NG로 저장 | 종합판정 NG + Rework 탭 자동 등록 |
| 8 | Rack별 사진 필수 | 5장 미만으로 저장 시도 | 차단 메시지("Rack 1~5 각각 1장, 총 5장") |
| 9 | 시간 자동 | 저장 시 | 시간 열에 ICT(베트남) 24시 자동 기록 |
| 10 | 필터 | Model별/NG만/월 경계 날짜 범위 조회 | 정상 동작 |
| 11 | 대시보드 | 기간·Model NG율 확인 | 시트 수동 집계와 일치 (void 제외), pending 사진 카운트 |
| 12 | 이중 언어 | 설정에서 vi↔ko 전환 | 전 화면 반영 |
| 13 | 보안 | 토큰 없는 curl 요청 | 전 액션 거부(UNAUTHORIZED) |
| 14 | 멱등 | 동일 UUID submit 2회 | 행 1개만 생성, 기존 LOT 반환 |
| 15 | 타임스탬프 | 자정 전 오프라인 기록 → 익일 전송 | 원래 날짜/월 탭에 기록 |
| 16 | 사진 영구실패 | 사진 전송 실패 지속 | 10회 초과 시 경고 배지, 시트 `pending` 잔존, 대시보드 pending 카운트, 복구 후 중복 없이 도달 |

---

## 운영 절차

- **토큰 로테이션**: Masters 탭에 `config | token_new | <새토큰>` 행 추가 → 전 기기가 마스터 새로고침으로 자동 수신 → 유예기간(기본 30일, 최장 오프라인 기간보다 길게) 동안 Script Properties의 `APP_TOKEN_OLD`에 구 토큰 유지 → 이후 `APP_TOKEN`을 새 토큰으로 교체하고 `APP_TOKEN_OLD` 삭제
- **pending 사진 주간 점검**: 시트에서 사진링크=`pending` 필터 또는 대시보드 pending 카운트 확인 — 잔존 시 해당 기기의 네트워크/앱 상태 확인
- **오입력 정정**: LOT 상세 → 기록 무효화(void) → 재입력 (행 삭제 없음, audit 보존)
- **사진 보관**: Drive 폴더에 월별(`YYYY-MM`) 자동 분류, 파일명 `LOT번호_photoUUID.jpg`
