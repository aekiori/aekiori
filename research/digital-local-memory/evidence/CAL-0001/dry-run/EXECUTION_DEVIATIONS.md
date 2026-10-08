# CAL-0001 dry-run execution deviations

## D01 — Google 결과 안정화 조건 누락

```text
detected_at: 2026-08-11T06:44:50+09:00
affected_queries: G-K0-02, G-K0-03, G-K0-04
severity: measurement-validity
status: preserved_and_technically_recaptured
```

### 관측

첫 묶음 실행에서 `goto()` 완료 직후 결과 DOM을 읽었다. `G-K0-02`와 `G-K0-04`는 그 순간 `h3` 결과가 0개였지만, 잠시 뒤 같은 페이지에는 각각 9개와 8개의 제목 요소가 있었다. 따라서 최초의 0개는 검색 부재가 아니라 비동기 렌더링 중 조기 관측이었다.

### 조치

- 최초 관측은 삭제하지 않았다.
- 네 K0 질의를 같은 문자열·같은 순서로 다시 열고 1.2초 후 기술 재측정했다.
- 재측정은 사전 계획에 없던 절차이므로 `technical_recapture_after_missing_stabilization_rule`로 표시했다.
- K0 벽시계는 최초 실행 시작부터 재측정 종료까지 계산했다. 총 97.324초로 300초 상한 안이다.
- 결과가 없는 페이지도 Google의 정확 질의 무결과 문구와 따옴표 제거 fallback을 분리해 기록했다.

### 영향

재측정 데이터는 프로토콜 교정에는 쓸 수 있지만, 동결 계획을 완벽히 준수한 substantive 결과가 아니다. V0.2에는 “usable result page”의 기계적 안정화 조건이 필요하다. 고정 대기시간만 쓰면 네트워크 상태에 따라 다시 오판할 수 있으므로 다음 중 하나를 사전 지정해야 한다.

1. 정확 질의 무결과 문구가 보임,
2. 자연검색 결과가 하나 이상 보이고 결과 수가 두 차례 연속 같음,
3. 정해진 대기 상한 후 `render_timeout`으로 종료.

이 변경은 이번 실행에 소급 적용하지 않는다.

## D02 — 안정화 후에도 `0 titles`와 명시적 무결과를 구분하지 못함

```text
affected_queries: G-B01-K2-01, G-B03-K2-01
status: render_indeterminate
```

두 페이지는 1.2초 뒤에도 기록된 제목이 0개였지만 Google의 명시적 무결과 문구는 검출되지 않았다. 실제 결과 부재, AI/모듈 전용 화면, 더 늦은 렌더링을 현재 자료로 구분할 수 없다. 두 질의를 `not_found_under_protocol`로 세지 않았다. 같은 bay의 다른 사전 질의가 별도로 결과를 냈더라도 이 두 query-level 관측은 보정하지 않는다.

## D03 — 플랫폼 순서와 K0 공유 벽시계 예산 충돌

```text
first_K0_started_at: 2026-08-10T21:44:04.545Z
N-K0-observed_at: 2026-08-10T21:50:58.540Z
elapsed_seconds: 413.995
budget_seconds: 300
status: N-K0-executed-but-excluded
```

동결 순서는 Google K0→K1→K2 뒤에 Naver K0를 두었지만, 예산은 K0 공유 셀의 연속 벽시계 300초로 정의했다. 두 규칙을 동시에 지키지 못했다. Naver K0는 이미 실행됐으므로 삭제하지 않았지만 K0 결과 판정에서 제외했다. V0.2는 플랫폼별 셀을 연속 배치하거나 active-review clock의 시작·정지 규칙을 명시해야 한다.

## D04 — Naver 전역 자연검색 순위 부재

Naver 통합검색은 광고, Place, 웹 문서, 인기글, 이미지가 모듈별로 섞였다. 모듈을 가로지르는 하나의 자연검색 rank를 관측할 수 없었다. 저장한 `heuristic_display_order`는 가시적 비광고 title link의 추출 순서일 뿐 Google의 organic rank와 비교할 수 없다.

따옴표를 넣어도 모든 용어가 강제되지 않았다. 일부 주소 질의에는 `광정로` 대신 `광적로`를 쓰라는 제안이 나왔고, 주소와 무관한 결과도 표시됐다. 제안이나 상세검색 링크는 누르지 않았으며 입력창의 원 질의는 확인했다. V0.2에는 `submitted_query`, `returned_query`, `suggested_rewrite`, `fallback`, `match_behavior`가 필요하다.

## D05 — 무관한 스니펫의 민감정보 노출

Naver K0 화면의 무관한 문서 스니펫 하나가 개인식별 가능성이 있는 의료·지원 자료 일부를 표시했다. 연구 대상과 무관해 원문을 열지 않았고, 해당 스니펫을 로컬 원장에 복사하지 않았다. 이는 공개 산출물 마스킹만으로 부족하다는 실패 시험이다. 수집 시점에 민감정보 감지→본문 미보존→최소 메타데이터만 기록하는 규칙이 필요하다.

## D06 — 기존 retrieval schema의 단위 손실

`schema/case-record.schema.json` V0.1의 `retrievalRun`에는 `bay_id`, `platform`, `query_id`, 종료시각, 예산 상태, module/rank 체계, page/render 상태가 없다. 세 bay×두 플랫폼 결과를 해당 배열에 넣으면 서로 다른 관측을 합치거나 핵심 맥락을 버려야 한다. 그래서 이번 원자료는 별도 query ledger에 보존했고 `case.json.retrieval_runs`에 억지로 축약하지 않았다.
