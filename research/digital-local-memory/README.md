# 지역 상업공간의 디지털 기억 연구

## 현재 상태

- 연구 단계: `measurement_calibration`
- 프로토콜: `PILOT_PROTOCOL_V0.1` (`DRAFT_UNFROZEN`), query plan `CAL-0001-QP01`은 검색 전 해시 봉인
- 최초 사례: `CAL-0001` 율곡A상가 롤리팝/세계수입과자할인점
- 외부 검색 실행: `CAL-0001-DR01` 완료; 교정 결과만 유효, substantive result는 금지
- 현재 판정: `V1.0-FROZEN` 승격 불가; V0.2 측정 규칙 수정 필요
- 자동화: 금지. 수작업 dry-run에서 반복 병목이 확인된 뒤에만 검토

## 핵심 질문

> 현실의 과거가 디지털 기록으로 변환될 때 무엇이 기록되고, 무엇이 보존되며, 무엇이 현재의 조사자에게 다시 회수되는가?

이 연구는 `존재`, `기록 관측`, `보존`, `색인`, `현재 회수`를 같은 것으로 취급하지 않는다. 특히 검색 실패를 존재 부정이나 기록 부재로 바꾸지 않는다.

## 현재의 주장 한계

`CAL-0001`은 찾기 어려웠던 가게 때문에 선택된 편향된 최초 사례다. 따라서 다음 용도로만 쓴다.

- 관측 단위와 증거 스키마를 시험한다.
- 동일성 판정 규칙을 깨뜨려 본다.
- 검색 경로와 사전지식 조건을 분리한다.
- 수작업 조사 예산과 실패 기록 방식을 교정한다.

다음 용도로는 쓰지 않는다.

- 군포·산본 또는 일반 상권의 디지털 소실률 추정
- 인허가, 업종, 상호 고유성 등의 효과 추정
- 최초 발견 난이도 또는 평균 검색시간 계산
- 특정 플랫폼이 기록을 삭제했다는 주장

## 문서 지도

- [BACKGROUND.md](BACKGROUND.md): 연구의 출발점과 개념 경계
- [protocol/RED_TEAM.md](protocol/RED_TEAM.md): 현재 설계를 무효화할 수 있는 위협과 통과 조건
- [protocol/PILOT_PROTOCOL_V0.1.md](protocol/PILOT_PROTOCOL_V0.1.md): dry-run용 동결 전 프로토콜
- [protocol/DRY_RUN_QUERY_PLAN_V0.1.md](protocol/DRY_RUN_QUERY_PLAN_V0.1.md): 23개 질의·열람범위·예산 계약
- [protocol/dry-run-query-plan.v0.1.json](protocol/dry-run-query-plan.v0.1.json): 기계 판독 query plan
- [protocol/query-plan-freeze-manifest.json](protocol/query-plan-freeze-manifest.json): 검색 전 query plan SHA-256 봉인 영수증
- [protocol/PROTOCOL_DELTA_V0.2.md](protocol/PROTOCOL_DELTA_V0.2.md): dry-run에서 드러난 V0.2 필수 수정안
- [protocol/VALIDATION.md](protocol/VALIDATION.md): 해시·스키마·경계 검증 결과와 남은 미검증 항목
- [schema/case-record.schema.json](schema/case-record.schema.json): 사례·증거·검색 실행 기록 스키마
- [schema/facade-bay-register.template.csv](schema/facade-bay-register.template.csv): 공간 표본 원장 템플릿
- [evidence/CAL-0001/OBSERVATION.md](evidence/CAL-0001/OBSERVATION.md): 최초 사례의 사람이 읽는 관측 원장
- [evidence/CAL-0001/case.json](evidence/CAL-0001/case.json): 최초 사례의 기계 판독 기록
- [evidence/CAL-0001/SCOPE.md](evidence/CAL-0001/SCOPE.md): 제공 영상 안에서 봉인한 3개 bay 교정 범위
- [evidence/CAL-0001/facade-bay-register.csv](evidence/CAL-0001/facade-bay-register.csv): 봉인된 bay 원장
- [evidence/CAL-0001/scope-freeze-manifest.json](evidence/CAL-0001/scope-freeze-manifest.json): 원영상·범위·원장의 SHA-256 동결 영수증
- [evidence/CAL-0001/dry-run/DRY_RUN_FINDINGS.md](evidence/CAL-0001/dry-run/DRY_RUN_FINDINGS.md): bay별 결과, 오탐, 인과 한계, 다음 판정
- [evidence/CAL-0001/dry-run/outcomes.json](evidence/CAL-0001/dry-run/outcomes.json): 기계 판독 결과 요약
- [evidence/CAL-0001/dry-run/EXECUTION_DEVIATIONS.md](evidence/CAL-0001/dry-run/EXECUTION_DEVIATIONS.md): 동결 계획 이탈과 측정 결함 원장
- [evidence/CAL-0001/dry-run/run-freeze-manifest.json](evidence/CAL-0001/dry-run/run-freeze-manifest.json): 실행 원자료 7개의 byte size·SHA-256 봉인 영수증
- [evidence/CAL-0001/dry-run/CORRECTION-0001.md](evidence/CAL-0001/dry-run/CORRECTION-0001.md): 동결 후 발견한 사업장 전화 마스킹 누락과 공개 금지 경계

## 작업 순서

1. `CAL-0001-S01`의 세 1층 bay를 검색 전에 봉인한다. `완료`
2. 세 bay에 사용할 정확한 query·채널·예산 순서를 봉인한다. `완료`
3. 서로 다른 실패 모드를 가진 세 점포로 dry-run한다. `완료, deviations 포함`
4. 프로토콜의 모호성과 조사자 효과를 기록한다. `완료`
5. V0.2 안정화·예산·모듈·스키마 규칙을 구현하고 새 blind calibration에서 재검증한다.
6. 재검증이 통과한 뒤에만 `V1.0-FROZEN`을 검토한다.
7. 측정 가능성이 확인된 뒤에만 결과를 모르는 별도 추론 표본을 설계한다.

## 2026-08-11 CAL-0002 갱신

- V0.2는 검색 전 선택된 파사드의 한 물리 bay 안에 두 entity hypothesis가 나타나면서 pre-retrieval fail했다.
- 다대다 `facade_bay <-> entity_hypothesis` 구조를 추가한 `PILOT_PROTOCOL_V0.3`와 `CAL-0002-QP01`을 target retrieval 전에 별도 해시 봉인했다.
- `CAL-0002-DR01`에서 Google 10개와 Naver 10개 동결 query를 완료했다.
- 자체 V0.3 validator와 privacy scan은 통과했다. raw DOM은 저장하지 않았고 공개 artifact의 전화·이메일 패턴은 0건이다.
- 결과는 `SINGLE_READER_PASS_SECOND_READER_PENDING`이다. active-review 자동 timer와 독립 Draft 2020-12 schema validator는 아직 없다.
- 인과 판정은 `not isolated`, V1 승격은 계속 `NO-GO`다.

CAL-0002 핵심 파일:

- [evidence/CAL-0002/SELECTION_LOG.md](evidence/CAL-0002/SELECTION_LOG.md): blind site selection과 bounded overshoot
- [protocol/V0.2_SITE_MODEL_FAILURE.md](protocol/V0.2_SITE_MODEL_FAILURE.md): target query 0개에서 적발한 V0.2 모델 실패
- [protocol/PILOT_PROTOCOL_V0.3.md](protocol/PILOT_PROTOCOL_V0.3.md): 복수 entity hypothesis 계약
- [protocol/CAL-0002_QUERY_PLAN_V0.3.md](protocol/CAL-0002_QUERY_PLAN_V0.3.md): 20개 동결 query와 14개 budget cell
- [evidence/CAL-0002/dry-run-v03/FINDINGS.md](evidence/CAL-0002/dry-run-v03/FINDINGS.md): entity별 결과와 현재 최선 설명
- [evidence/CAL-0002/dry-run-v03/retrieval-run.json](evidence/CAL-0002/dry-run-v03/retrieval-run.json): probe·module·result·entity outcome 원장
- [evidence/CAL-0002/dry-run-v03/supplemental-source-checks.json](evidence/CAL-0002/dry-run-v03/supplemental-source-checks.json): frozen outcome에서 제외한 후보 페이지 확인
- [evidence/CAL-0002/dry-run-v03/run-freeze-manifest.json](evidence/CAL-0002/dry-run-v03/run-freeze-manifest.json): 결과 파일 SHA-256 동결 영수증
