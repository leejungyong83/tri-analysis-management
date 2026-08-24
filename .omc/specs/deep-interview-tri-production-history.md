# Deep Interview Spec: TRI 생산 투입 이력 통합 (Production History Integration)

## Metadata
- Interview ID: deep-interview-tri-production-history-2026-07-06
- Rounds: 10 (+ Round 0 토폴로지 게이트, 8개 구성 요소)
- Final Ambiguity Score: 18%
- Type: brownfield (기존 배포 완료된 검사 앱에 대규모 기능 추가)
- Generated: 2026-07-06
- Threshold: 0.2
- Threshold Source: default
- Status: PASSED
- 선행 스펙: `.omc/specs/deep-interview-tri-reagent-inspection-app.md` (검사 앱 v1)

## Clarity Breakdown
| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Goal Clarity | 0.86 | 0.35 | 0.301 |
| Constraint Clarity | 0.82 | 0.25 | 0.205 |
| Success Criteria | 0.80 | 0.25 | 0.200 |
| Context Clarity (brownfield) | 0.78 | 0.15 | 0.117 |
| **Total Clarity** | | | **0.823** |
| **Ambiguity** | | | **0.177 (18%)** |

## Topology (8개 구성 요소)
| Component | Status | Description | Coverage |
|-----------|--------|-------------|----------|
| 생산투입 이력 | active | 생산LOT 등록 화면 + 생산이력 시트, 생산투입 시점 LOT 자동채번 | R2, R10 |
| 검사 흐름 재설계 | active | LOT 자동채번 제거 → 미검사 생산LOT 선택, 결과 생산행 자동 반영 | R1, R7, R10 |
| Rework 흐름 | active | NG→R접두 자동등록 + 재투입(시간·수량) → 재검사 | R3 |
| 앱 통합·네비게이션 | active | 5탭 통합, Rework는 생산 탭 통합 | R5 |
| 역할·권한 분리 | active | 화면 분리만(강제 없음), 로그인 없음 유지 | R4 |
| 생산 통계/대시보드 확장 | active | 미검사 현황·검사율·생산량·Rework율·기간추이 | R8 |
| 데이터 마이그레이션 | active | 새로 시작, 기존 월별탭 구조 유지, 수입 없음 | R9 |
| 수량 검증 | active | Rework≤생산수량 경고만 | R6 |

## Goal
기존 TRI 표면 시약 검사 앱에 **TRI LINE 생산 투입 이력 관리**를 통합해 하나의 앱으로 만든다. LOT 번호 채번의 권위가 검사 시점에서 **생산 투입 시점**으로 이동한다: 생산 작업자가 TRI 라인에 LOT을 투입할 때 LOT이 자동 채번(YYMMDD+일련번호, 업무일 08:00 기준 — 기존 방식 동일)되고 MODEL·수량·투입시간이 생산이력 시트에 기록된다. 검사자는 더 이상 LOT을 생성하지 않고, **미검사 생산LOT을 목록에서 선택**해 검사하며, 검사 결과(종합판정)는 생산이력 행의 검사결과 컬럼에 자동 반영된다. NG면 생산행 Rework 컬럼에 `R`+LOT이 자동 등록되고, Rework 재투입(시간·수량) 후 그 LOT이 미검사 목록에 다시 나타나 재검사된다. 데이터는 **이원화**: 생산이력 시트(요약·원천)와 기존 검사 상세(월별탭·Rack·사진)를 LOT번호로 연결한다.

## Constraints
- **데이터 모델 이원화 (R1 확정):** 생산이력 시트 = LOT 요약/원천(검사결과 포함). 기존 월별탭 = 검사 상세(Rack1~5·사진5·CA·검사자·Bar). LOT번호로 연결. 월별탭 스키마 불변.
- **LOT 채번 이동:** 서버측 채번(generateLot)을 검사 submit에서 **생산투입(produce) 액션으로 이동**. YYMMDD+일련번호, 업무일 08:00 기준 유지.
- **생산이력 시트 컬럼 순서 (사용자 지정, 고정):** LOT번호 · MODEL · 수량 · 투입시간(자동) · 검사결과(검사 시 자동) · Rework(NG시 R접두 자동) · Rework투입시간 · Rework수량
- **생산 입력:** MODEL은 Masters 목록 선택, 수량은 수동 입력, LOT·투입시간 자동. LOT당 1건 등록.
- **검사 입력:** 미검사 생산LOT을 드롭다운/목록에서 선택(최신순, MODEL·투입시간 표시). MODEL 자동채움(수정불가), Bar·CA·검사자·Rack1~5·사진5장은 기존대로 입력.
- **역할 분리:** 화면(탭) 분리만. 로그인/권한 강제 없음. 기존 이름 선택 방식 유지.
- **수량 검증:** Rework수량 > 생산수량이면 경고만(저장 허용).
- **UI 언어·플랫폼·백엔드:** 기존 유지 (베트남어+한국어, Android APK + iOS 웹PWA, Google Sheets/Drive + Apps Script 토큰 프록시, 오프라인 큐).
- **탭 구조:** 5탭 — 생산 · 검사 · 이력 · 대시보드 · 설정. Rework(재투입 대기 목록)는 생산 탭 내 통합.

## Non-Goals
- 로그인·PIN·권한 강제 (화면 분리만)
- 기존 종이/엑셀 생산 이력 수입(마이그레이션) — 새로 시작
- 월별탭(검사 상세) 스키마 재설계 — 현행 유지
- 잔량 자동 차감 관리·재고 관리 (Rework≤생산 경고만)
- 다회 Rework 사이클(2회 이상 재작업)의 정교한 이력 — 1사이클 컬럼 구조로 처리, 다회는 후속
- 생산 계획/스케줄링, 설비 연동

## Acceptance Criteria
- [ ] 생산 탭에서 MODEL 선택 + 수량 입력 → 저장 시 LOT 자동채번(YYMMDD+일련번호, 08:00 업무일)되고 생산이력 시트에 LOT·MODEL·수량·투입시간(자동) 행 생성
- [ ] 검사 탭의 LOT 선택 목록에는 **미검사 생산LOT만** 표시(이미 검사된 LOT 제외), 최신순, MODEL·투입시간 함께 표시
- [ ] 검사LOT 선택 시 MODEL 자동채움(수정불가), Bar·CA·검사자·Rack1~5·사진5장 입력 후 저장 → 생산이력 행의 검사결과가 종합판정(OK/NG)으로 자동 갱신
- [ ] 검사 결과 NG면 생산이력 행 Rework 컬럼에 `R`+LOT번호 자동 등록 (예 R260706001)
- [ ] Rework 재투입(투입시간·수량 등록) → 해당 LOT이 미검사 목록에 다시 나타나 재검사 가능, 재검사 결과로 검사결과 갱신
- [ ] Rework수량 > 생산수량 입력 시 경고 표시(저장은 허용)
- [ ] 하단 탭 5개(생산·검사·이력·대시보드·설정), Rework 재투입 대기 목록은 생산 탭 내 접근
- [ ] 대시보드에 생산 지표 4종 추가: 미검사 현황(건수/목록), 검사율(검사완료/생산), 생산량·Rework율(기간·Model별), 기간별 추이(일/주별 생산량·NG율)
- [ ] 기존 검사 상세(월별탭·Rack·사진), 오프라인 큐, 이중 언어, 08:00 업무일, 토큰 인증은 회귀 없이 동작

## Assumptions Exposed & Resolved
| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| 생산이력이 단일 원천이 될 것 | R1 데이터 원천 질문 | 이원화 — 생산이력(요약)+검사 상세(월별탭) LOT 연결 |
| LOT은 여전히 검사 시 채번 | R2·R10 | 생산투입 시점으로 이동, 검사는 미검사 LOT 선택 |
| Rework는 기록만 | R3 | 재투입 → 재검사(같은 LOT) 상태 머신 |
| 로그인 기반 권한 필요 | R4 컨트래리언 | 화면 분리만, 권한 강제 없음(로그인 없음 유지) |
| 복잡한 수량 검증 필요 | R6 심플리파이어 | Rework≤생산수량 경고만 |
| 검사에서 MODEL·Bar 재입력 | R7 | MODEL 자동채움, Bar·CA·검사자·Rack·사진은 입력 유지 |
| 기존 데이터 마이그레이션 부담 | R9 | 실데이터 없음 → 새로 시작, 월별탭 구조 유지 |

## Rework 상태 머신 (생산이력 행 1개 기준)
```
[생산 투입]  검사결과=(빈값)          → 미검사 목록에 표시
     │ 검사
     ▼
[검사 완료]  검사결과=OK              → 목록에서 제외 (종료)
     │ 검사결과=NG → Rework=R+LOT 자동
     ▼
[Rework 대기] Rework투입시간·수량 등록  → (재투입)
     │
     ▼
[재검사 대기] 미검사 목록에 재등장       → 재검사
     │ 재검사
     ▼
[재검사 완료] 검사결과=OK/NG 갱신        (다회 Rework는 non-goal)
```
- **미검사 목록 판정식:** 검사결과가 비었거나, (Rework투입시간이 채워졌고 재검사 전) → 목록 표시.

## Technical Context (brownfield)
- **기존 코드** (`.omc/plans/tri-reagent-inspection-app-plan.md` v5 배포본):
  - `app/lib/`: core(ict_time·app_settings·strings), models(inspection), services(api_client·sync_queue·master_cache·photo_service), screens(inspection_form·history·lot_detail·dashboard·settings)
  - `gas/Code.gs`: submit/attachPhoto/list/masters/stats/void, **generateLot**(서버 LOT 채번, 현재 submit 내), Masters/Rework/월별탭. 웹앱 v3 배포됨(토큰 보호).
- **GAS 변경 예상:**
  - 신규 `produce` 액션: 생산LOT 등록, generateLot을 여기로 이동, Production 탭에 행 append
  - `submit` 변경: LOT 채번 제거 → req.lot(선택된 생산LOT) 대상. 저장 후 Production 행 검사결과 갱신 + NG시 Rework=R+LOT
  - 신규 `listUninspected`(미검사 생산LOT 목록), `reworkInput`(Rework 투입시간·수량), `productionStats`(생산 지표)
  - 신규 **Production 시트**(사용자 지정 컬럼 순서). 기존 Rework 탭은 Production 행의 Rework 컬럼으로 흡수 검토
- **Flutter 변경 예상:** 생산 탭 화면(신규), 검사 폼 재설계(LOT 선택 드롭다운·MODEL 자동채움), 대시보드 생산 지표 4종, sync_queue에 produce/reworkInput 큐 추가, 5탭 네비.

## Ontology (Key Entities)
| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| 생산LOT (ProductionLot) | core domain | LOT번호(채번), MODEL, 수량, 투입시간, 검사결과, Rework(R접두), Rework투입시간, Rework수량, 상태(파생) | 1 생산LOT ↔ 1 검사기록(LOT 연결), NG시 Rework 파생 |
| 검사기록 (Inspection) | core domain | UUID, 날짜, CA, 검사자, LOT, 시간, Bar, Model(자동), Rack1~5, 종합판정, 사진5 | belongs to 생산LOT(LOT), 결과가 생산LOT.검사결과 갱신 |
| Rework | supporting | R+LOT번호, 투입시간, 수량 | 생산LOT의 NG 파생, 재투입 시 재검사 트리거 |
| MODEL | supporting | 모델명 | Masters, 생산LOT·검사 분류 |
| CA / 검사자 / 생산작업자 | supporting | 이름(선택, 로그인 없음) | 검사기록·생산LOT 기록자 |
| 대시보드 지표 | supporting | 미검사·검사율·생산량·Rework율·추이 | 생산LOT+검사기록 집계 |
| Production 시트 / 월별탭 / Drive | external system | 생산이력 / 검사상세 / 사진 | LOT번호로 연결 |

## Ontology Convergence
| Round | Entity Count | New | Changed | Stable | Stability Ratio |
|-------|-------------|-----|---------|--------|----------------|
| 1 | 5 | 5 | - | - | N/A |
| 2 | 6 | 1 (생산작업자) | 0 | 5 | 83% |
| 3 | 7 | 1 (Rework 재정의) | 1 | 6 | 100% |
| 4–6 | 7 | 0 | 0 | 7 | 100% |
| 7–10 | 7 | 0 | 0 | 7 | 100% |

## Interview Transcript
<details>
<summary>Full Q&A (Round 0 + 10 rounds)</summary>

### Round 0 (토폴로지)
**A:** 8개 구성 확정 (생산투입·검사재설계·Rework·앱통합 + 역할권한·생산통계·데이터마이그레이션·수량검증)

### Round 1 — 데이터 원천
**A:** 이원화: 생산이력 + 검사이력 별도 (LOT 연결)

### Round 2 — 생산 입력
**A:** MODEL 목록선택 + 수량 수동 (LOT·투입시간 자동)

### Round 3 — Rework 재검사
**A:** 재투입 → 재검사 (같은 LOT)

### Round 4 (컨트래리언) — 권한
**A:** 화면 분리만 (강제 없음)

### Round 5 — 탭 구조
**A:** 5탭: 생산·검사·이력·대시보드·설정

### Round 6 (심플리파이어) — 수량 검증
**A:** Rework≤생산수량 경고만

### Round 7 — 검사 폼
**A:** MODEL 자동, Bar·CA·검사자·Rack·사진 입력

### Round 8 — 생산 지표
**A:** 미검사 현황, 검사율, 생산량·Rework율, 기간별 추이

### Round 9 — 전환/마이그레이션
**A:** 새로 시작 (기존 월별탭 구조 유지)

### Round 10 — LOT 선택 UX
**A:** 드롭다운/목록에서 선택 (채번은 생산투입 시점, 08:00 업무일 유지)

</details>
