# Deep Interview Spec: TRI 공정 후 표면 시약 검사 앱 (Reagent Inspection App)

## Metadata
- Interview ID: deep-interview-tri-inspection-app-2026-07-06
- Rounds: 11 (+ Round 0 토폴로지 게이트)
- Final Ambiguity Score: 18%
- Type: greenfield
- Generated: 2026-07-06
- Threshold: 0.2
- Threshold Source: default
- Initial Context Summarized: no
- Status: PASSED

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.82 | 0.40 | 0.328 |
| Constraint Clarity | 0.80 | 0.30 | 0.240 |
| Success Criteria | 0.85 | 0.30 | 0.255 |
| **Total Clarity** | | | **0.823** |
| **Ambiguity** | | | **0.177 (18%)** |

## Topology
| Component | Status | Description | Coverage / Deferral Note |
|-----------|--------|-------------|--------------------------|
| 검사 기록 | active | TRI 공정 후 표면 시약 검사 결과를 LOT 단위로 OK/NG 판정·입력 | 기록 단위·필드·판정 규칙 확정 (R1, R2, R9 + 엑셀 양식) |
| 사진 촬영·저장 | active | 검사 시 제품/시약 반응 사진 촬영 및 기록 첨부 | 매 검사 필수 1장 이상, 증빙 목적 (R5) |
| LOT 이력 관리 | active | LOT 단위 검사 이력 조회·검색·추적 | LOT번호 검색·Model별 조회·NG 필터 확정 (R8, R11) |
| Google Sheets 백엔드 | active | 검사 데이터·사진의 저장·동기화 | 공용 자격증명, 이름 선택 인증, 재전송 큐 (R6, R7) |
| 통계/대시보드 | active | 검사자용 요약 + 관리자용 NG율 모니터링 | 대상·용도 확정, 세부 지표는 PRD에서 기본안 제안 (R4) |
| NG 조치 | active | NG LOT의 rework 대상 등록 | 범위: rework 등록까지만, 생산일지는 외부 관리 (R3) |

## Goal
현장 검사자가 스마트폰 앱으로 TRI 공정 후 표면 시약 검사(현행 베트남어 엑셀 양식 "KIỂM TRA THUỐC THỬ")를 종이/엑셀 없이 기록한다. 검사 1건 = LOT 1개에 대해 Rack 1~5 각각 OK/NG 판정 + 증빙 사진 1장 이상이며, 5개 중 1개라도 NG면 LOT은 NG로 자동 판정되어 rework 대상으로 등록된다. 모든 기록은 Google Sheets에 저장되어 LOT 번호로 언제든 이력(결과·사진·rework 여부)을 추적할 수 있고, 검사자·관리자는 앱 내 대시보드에서 검사 현황과 NG율을 확인한다.

## Constraints
- **플랫폼:** Android/iOS 크로스플랫폼 "간단한 앱" (기술 스택은 계획 단계에서 결정 — Flutter/React Native 등)
- **DB:** Google Sheets 사용 (사용자 지정 필수 조건). 사진은 Sheets에 저장 불가하므로 Google Drive 저장 + 시트에 링크 기록이 기술적 귀결
- **네트워크:** 현장은 대체로 온라인이나 가끔 끊김 → 로컬 임시저장 + 자동 재전송 큐 필요 (오프라인 우선 설계까지는 불요)
- **인증:** 로그인 없음. 앱에서 검사자 이름만 목록 선택. Sheets 접근은 공용 자격증명(서비스 계정 등)
- **UI 언어:** 베트남어 + 한국어 이중 언어 (검사자=베트남어, 관리자=한국어, 전환 지원)
- **기존 양식 준수(수정 반영):** 현행 엑셀 구조를 계승 — 헤더(CA 근무조/날짜/검사자), 행(LOT번호[기존 STT 순번 열 대체], 시간, Bar번호, Model, Rack 1~5 결과, **Rack5 다음 열에 종합판정 OK/NG 자동 입력**)
- **LOT번호와 Bar번호는 별개 필드로 모두 입력** (LOT=작업 LOT 번호, Bar=사용 중인 대차 번호). 판정은 LOT에 귀속

## Non-Goals
- 생산 일지 관리 (별도 시스템으로 관리 중)
- rework 처리 과정 추적·재검사 워크플로 (rework 대상 등록까지만)
- NG 발생 시 메신저/이메일 알림 (선택되지 않음)
- 개인별 Google 계정 로그인·권한 관리
- 마스터 데이터 관리 화면, 바코드/QR 스캔 (Round 0에서 추가되지 않음 — 필요 시 후속 버전)

## Acceptance Criteria
- [ ] **엑셀 완전 대체:** 하루치 검사 전체가 종이/엑셀 없이 앱으로만 기록되고, Google Sheets에서 기존 양식과 동등한 형태로 확인 가능하다
- [ ] **추적성:** 임의 LOT 번호로 검색하면 과거 검사 결과(Rack 1~5)·사진·rework 등록 여부가 앱에서 바로 조회된다
- [ ] **데이터 무손실:** 네트워크가 끊긴 상태에서 저장해도 기록이 유실되지 않고, 연결 복구 후 자동 전송된다
- [ ] **입력 속도:** 검사 1건(사진 포함) 입력이 1분 이내에 완료된다
- [ ] 검사 1건 저장 시 Rack 1~5 중 하나라도 NG면 LOT 판정이 자동으로 NG가 되고 rework 대상 목록에 등록된다
- [ ] 시트에서 Rack5 다음 열에 종합판정(OK/NG)이 자동 기록되고, 기존 STT(순번) 열 자리는 LOT번호로 대체된다

### 추가 확정 사항 (2026-07-06 사용자 지시)
- [ ] **LOT번호 자동 채번:** 날짜기준 YYMMDD+일련번호(예 260706001). 서버가 부여(여러 기기 충돌 방지), 오프라인 시 동기화 시점 부여
- [ ] **업무일 08:00 기준:** 하루 업무 시작 08:00(ICT). 00:00~07:59 검사는 전날 업무일에 귀속, LOT 일련번호는 08:00에 리셋 (앱이 업무일 계산해 전송, 월탭 라우팅·기록 날짜도 업무일 기준)
- [ ] **NG Rework 식별자 R접두:** NG LOT은 Rework에 `R`+LOT번호(예 R260706001)로 등록
- [ ] **Rack별 사진 5장:** 각 Rack마다 사진 1장씩 총 5장 촬영·업로드, 자동 압축(≤1.3MB)
- [ ] **시간 자동 입력:** 등록 시각을 베트남 ICT 24시 표기로 자동 기록
- [ ] 사진 미첨부 시 검사 기록 저장이 차단된다 (필수 1장 이상)
- [ ] Model별 조회와 NG만 필터가 이력 화면에서 동작한다
- [ ] 검사자용 요약(당일/기간 본인 검사 건수·NG 현황)과 관리자용 모니터링(기간·Model별 NG율 추이)이 앱 내에서 확인된다
- [ ] 전 화면이 베트남어/한국어 전환을 지원한다

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| 판정은 샘플별로 기록될 것 | R1~R2 판정 단위 질문 | Rack별 판정(LOT당 5건), 엑셀 양식과 동일 |
| Số Bar = LOT 식별자 | R8에서 사용자 교정 | LOT번호(작업 LOT)와 Bar번호(대차)는 별개 필드, 판정은 LOT 귀속 |
| NG 시 알림·재검사 추적 필요 | R3 NG 흐름 질문 | rework 대상 등록까지만, 생산일지 별도 관리 |
| 대시보드는 Sheets 차트로 충분 | R4 컨트래리언 질문 | 검사자 요약 + 관리자 모니터링 모두 앱 내 필요 |
| 항상 온라인 가정 가능 | R6 심플리파이어 질문 | 대체로 온라인, 가끔 끊김 → 로컬 큐 + 재전송 필요 |
| 사진은 NG 시에만 필요할 것 | R5 사진 시점 질문 | 매 검사 필수 1장 이상 (증빙 목적) |
| 검사자 로그인 필요할 것 | R7 식별 방식 질문 | 이름 선택만, 로그인 없음 |
| UI는 한국어면 충분할 것 | R10 (엑셀 양식이 베트남어인 증거 기반) | 베트남어+한국어 이중 언어 |

## Technical Context
- Greenfield — 작업 디렉터리(`C:\Work Drive\APP\TRI Analysis Management`)에 기존 소스 없음
- 현행 업무 양식: 베트남어 엑셀 "KIỂM TRA THUỐC THỬ" — 헤더(CA/Ngày/Người kiểm tra), 열(STT, Thời gian, Số Bar, Model, Kết quả: Rack 1~5), 1일 최대 37행 규모
- 크로스플랫폼 후보: Flutter 또는 React Native(Expo) — 카메라·로컬 큐·Google API 연동 요구 기준으로 계획 단계에서 결정
- Google Sheets API 쓰기 + Google Drive API 사진 업로드, 공용 서비스 계정 방식 유력
- 데이터 볼륨: 하루 수십 건 수준 → Sheets 성능 한계 문제없음. 다만 장기 운영 시 시트 분할 전략(월별 탭 등)을 계획 단계에서 정의 필요

## Ontology (Key Entities)
| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| LOT | core domain | LOT번호, 종합판정(OK/NG, 파생), rework등록여부 | LOT has 검사기록 1건, LOT uses Bar(대차), NG 시 → Rework대상 |
| 검사기록 (Inspection) | core domain | 순번, 날짜, CA, 검사자, 시간, LOT번호, Bar번호, Model, Rack1~5 판정, 사진≥1 | belongs to LOT, has 사진 N장, recorded by 검사자 |
| Rack | core domain | 위치 1~5, 판정(OK/NG) | 검사기록 내 5개 고정 |
| 사진 (Photo) | core domain | 파일(Drive), 촬영시각, 링크 | attached to 검사기록 (최소 1장 필수) |
| Bar (대차) | supporting | Bar번호 | used by LOT (검사 시점 기록) |
| 검사자 (Inspector) | supporting | 이름 (목록 선택, 로그인 없음) | performs 검사기록 |
| 근무조 (CA) | supporting | 조 구분 | groups 검사기록 |
| Model | supporting | 제품 모델명 | classifies LOT/검사기록 |
| Rework대상 | supporting | LOT번호, 등록시각 | NG LOT 자동/수동 등록 (처리 추적은 non-goal) |
| 관리자 (Manager) | supporting | — | views 대시보드 (한국어) |
| Google Sheets/Drive | external system | 시트(데이터), Drive(사진) | stores all records |

## Ontology Convergence
| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | 8 | 8 | - | - | N/A |
| 2 | 9 | 2 (CA, Model) | 0 | 7 (Sample 제거) | 78% |
| 3 | 9 | 0 | 1 (NG조치→Rework등록) | 8 | 100% |
| 4 | 10 | 1 (관리자) | 0 | 9 | 90% |
| 5–7 | 10 | 0 | 0 | 10 | 100% |
| 8 | 11 | 1 (Bar 분리) | 1 (LOT 재정의) | 9 | 91% |
| 9–11 | 11 | 0 | 0 | 11 | 100% |

## Interview Transcript
<details>
<summary>Full Q&A (Round 0 + 11 rounds)</summary>

### Round 0 (토폴로지)
**Q:** 4개 구성 요소(검사 기록, 사진, LOT 이력, Sheets 백엔드)가 맞는가?
**A:** 구성 요소 추가 — 통계 대시보드와 NG 조치

### Round 1
**Q:** 검사 기록의 기본 단위는? (LOT당 1판정 / 샘플별 / 샘플×항목별)
**A:** 1개 LOT당 5개의 Rack에서 샘플 검사 진행
**Ambiguity:** 80% (Goal 0.30, Constraints 0.15, Criteria 0.10)

### Round 2
**Q:** OK/NG 판정이 기록되는 레벨은? (+사용자가 현행 엑셀 양식 이미지 공유)
**A:** Rack별 판정 (LOT당 5건). 엑셀 양식: CA/Ngày/Người kiểm tra 헤더, STT·Thời gian·Số Bar·Model·Rack1~5 열
**Ambiguity:** 64% (Goal 0.55, Constraints 0.25, Criteria 0.20)

### Round 3
**Q:** NG 발생 시 현장에서 무슨 일이 일어나고 앱은 무엇을 기록해야 하나?
**A:** rework 대상 등록까지만 진행, 생산 일지는 따로 관리 중. (추가) 샘플 5개 중 1개라도 NG이면 LOT은 NG 판정
**Ambiguity:** 56% (Goal 0.62, Constraints 0.35, Criteria 0.30)

### Round 4 (컨트래리언 모드)
**Q:** Sheets 차트로도 통계가 가능한데 앱 내 대시보드가 필요한 이유는? 누가/무엇을 보나?
**A:** 둘 다 필요 (검사자용 요약 + 관리자용 모니터링)
**Ambiguity:** 52% (Goal 0.66, Constraints 0.38, Criteria 0.33)

### Round 5
**Q:** 사진은 언제, 무엇을 촬영해야 하나?
**A:** 매 검사마다 필수 1장 이상
**Ambiguity:** 49% (Goal 0.68, Constraints 0.40, Criteria 0.38)

### Round 6 (심플리파이어 모드)
**Q:** 현장 네트워크 상태는? 항상 온라인 가정으로 단순화 가능한가?
**A:** 대체로 온라인, 가끔 끊김
**Ambiguity:** 44% (Goal 0.68, Constraints 0.55, Criteria 0.42)

### Round 7
**Q:** 검사자는 어떻게 식별하나? (이름 선택 / PIN / Google 로그인)
**A:** 이름 선택만 (로그인 없음)
**Ambiguity:** 39% (Goal 0.72, Constraints 0.62, Criteria 0.45)

### Round 8
**Q:** LOT 이력을 주로 어떤 기준으로 조회하나?
**A:** Model별 조회, NG만 필터. LOT 번호를 추가하고 Số Bar도 입력해야 함 (별개 필드)
**Ambiguity:** 36% (Goal 0.74, Constraints 0.63, Criteria 0.50)

### Round 9 (온톨로지스트 모드)
**Q:** LOT과 Bar의 관계는? 판정 1세트는 어느 단위에 붙나?
**A:** LOT은 작업 LOT 번호, Bar는 사용 중인 대차의 Bar 번호 — 따로 입력. 판정 1세트는 LOT 번호에 귀속 (LOT 관리 목적)
**Ambiguity:** 32% (Goal 0.80, Constraints 0.65, Criteria 0.55)

### Round 10
**Q:** UI 언어는? (엑셀 양식이 베트남어인 증거 기반)
**A:** 베트남어 + 한국어 이중
**Ambiguity:** 27% (Goal 0.80, Constraints 0.80, Criteria 0.58)

### Round 11
**Q:** 1차 버전의 성공 판정 기준은? (복수 선택)
**A:** 엑셀 완전 대체 + 추적성 + 데이터 무손실 + 입력 속도 기준 모두
**Ambiguity:** 18% (Goal 0.82, Constraints 0.80, Criteria 0.85) — PASSED

</details>
