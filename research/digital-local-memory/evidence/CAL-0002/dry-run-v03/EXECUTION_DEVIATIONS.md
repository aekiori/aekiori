# CAL-0002 execution deviations

## 상태 요약

`CAL-0002-DR01`은 outcome을 폐기할 정도의 target leakage나 query 변경은 발견되지 않았다. 그러나 아래 항목 때문에 이 실행은 calibration record이며 V1 proof가 아니다.

| ID | 관측 | 영향 판정 | 처리 |
|---|---|---|---|
| `CAL-0002-SEL-D01` | candidate 21을 시각 판독하기 전에 22·23의 official pano availability가 batch로 확인됨 | bounded | 22·23에서는 이미지·간판·주소·상호를 보지 않았다. candidate 21은 여전히 첫 eligible site다. |
| `CAL-0002-PF01` | V0.2가 B02의 복수 entity hypothesis를 저장할 수 없음 | none after correction | target query 0개에서 V0.2 실패를 봉인하고 V0.3를 검색 전에 동결했다. |
| `CAL-0002-EX-D01` | 첫 Google query의 probe-time returned-query read가 비어 있음 | bounded | 두 probe의 값은 `null`로 보존했다. post-terminal exact read만 query-level returned value로 기록했다. |
| `CAL-0002-EX-D02` | 일부 인접 frozen cell query가 하나의 helper batch 안에서 연속 실행됨 | bounded | 각 terminal snapshot은 메모리에 분리 보존됐고 조사자는 batch 종료 전 중간 결과를 보지 못했다. 판독은 동결 cell 순서로 했다. 다음 실행에서는 금지한다. |
| `CAL-0002-EX-D03` | 일부 direct candidate page가 cell 종료 뒤 확인됨 | none on frozen outcome | 별도 supplemental file에 `outcome_eligible=false`로 저장했고 query/entity outcome을 바꾸지 않았다. |
| `CAL-0002-EX-D04` | active-review seconds가 자동 timer가 아닌 경계시각 기반 수동 재구성 | bounded | 모든 셀은 재구성값 기준 cap보다 최소 40초 이상 낮다. exact duration은 주장하지 않는다. |
| `CAL-0002-EX-D05` | Naver stability count가 ineligible module의 title-like links도 포함 | bounded | stable positive render 판정에만 사용했다. Naver result evidence에는 전역 rank를 부여하지 않고 module별 position만 저장했다. |

## 다음 버전에서 fail-closed로 바꿀 것

- batch helper가 두 budget cell을 넘으면 실행 자체를 거부한다.
- terminal state 뒤 active-review timer가 자동 시작되고, pause/resume과 candidate click을 같은 cell ledger에 기록한다.
- cell이 닫힌 뒤 candidate page를 열면 supplemental lane으로만 갈 수 있고 outcome 객체를 수정하지 못한다.
- Naver probe는 module eligibility와 무관한 page-render count임을 필드명으로 명시하거나, module별 title counter를 별도로 둔다.
- query-level record와 supplemental record 사이의 source result ID 참조를 validator가 검사한다.

