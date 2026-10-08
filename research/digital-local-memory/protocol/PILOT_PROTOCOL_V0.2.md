# PILOT_PROTOCOL_V0.2

```text
status: FROZEN_FOR_CALIBRATION_BY_MANIFEST
created: 2026-08-11
derived_from: CAL-0001-DR01 D01-D06 and CAL-0001-DR01-C01
scope: measurement calibration only
substantive_hypothesis_test: prohibited
automated_retrieval: prohibited
```

## 1. 목적과 주장 경계

V0.2는 과거 점포의 인터넷 잔존율을 측정하지 않는다. 검색 UI의 비동기 상태, 플랫폼별 결과 모듈, 검색 예산, 동일성 오탐, 개인정보 변환을 손실 없이 기록할 수 있는지 새 blind calibration에서 시험한다.

다음 추론은 계속 금지한다.

- 검색 실패를 기록 미생성·삭제·비보존 중 하나로 확정
- Google과 Naver의 숫자 rank 직접 비교
- 프랜차이즈·업종·상호 고유성의 인과 효과
- calibration 사례의 적중 빈도를 모집단 비율로 해석

## 2. 결과를 보기 전 동결 순서

1. 이 프로토콜, V0.2 retrieval schema, 개인정보 fixture와 validator를 해시 봉인한다.
2. 결과와 독립적인 위치 선택 규칙을 해시 봉인한다.
3. 일반 웹·Place 검색 없이 역사 거리영상에서 새 site와 facade bay를 선택한다.
4. 원영상·scope·bay register를 봉인한다.
5. 정확한 query, 순서, 셀별 예산, 열람 범위를 plan manifest로 봉인한다.
6. 그 뒤에만 retrieval을 실행한다.

어느 단계에서 결과를 먼저 봤다면 `blind=false`로 기록하고 새 site ID를 사용한다.

## 3. 페이지 상태기계

각 query는 다음 terminal state 중 정확히 하나로 끝난다.

```text
navigating
  -> stabilizing
    -> usable_results
    -> explicit_no_results
    -> rewritten_or_fallback
    -> blocked
    -> render_timeout
```

고정 파라미터:

```text
probe_interval_ms: 1000
stable_probe_count: 2
max_stabilization_ms: 8000
```

- `usable_results`: 1초 이상 떨어진 마지막 두 probe에서 visible title 수가 같고 1개 이상이다.
- `explicit_no_results`: 플랫폼별 명시적 무결과 UI 문구가 probe에 관측됐다.
- `rewritten_or_fallback`: 제안어를 따랐거나 자동 fallback 결과 블록이 표시됐다. 원질의 결과와 fallback을 별도 module로 기록한다.
- `blocked`: CAPTCHA, 접근 제한 또는 자동화 차단이 표시됐다. 우회하지 않는다.
- `render_timeout`: 8초 상한까지 위 terminal condition이 하나도 성립하지 않았다.

0개 title만 보고 `not_found_under_protocol`을 부여하지 않는다. `not_found_under_protocol`은 `usable_results` 또는 `explicit_no_results`가 성립한 query와 budget 종료를 근거로만 산출한다.

## 4. 예산 셀

예산 단위는 `platform × knowledge_regime × bay_or_site`다. 한 셀의 query는 실행 순서상 연속이어야 하며 다른 셀과 교차하지 않는다.

```text
K0 site cell: 120 active-review seconds
K1 per-bay cell: 120 active-review seconds
K2 per-bay cell: 180 active-review seconds
```

`active_review_seconds`에는 terminal page 판정 뒤의 결과 판독, 후보 클릭, 동일성 메모만 포함한다. navigation·stabilization 대기는 `network_wait_seconds`로 분리한다. 조사자가 다른 업무로 전환하면 pause/resume event를 저장한다. 셀 종료 후 몰래 시간을 추가하지 않는다.

## 5. 지식 조건

- `K0`: site의 주소·공간 앵커·기준연도만 사용한다. bay 상호·업종·전화는 금지한다.
- `K1`: K0에 영상에서 보이는 불완전 문자열, 추정 업종, 인접 공간 단서를 추가한다. 정규화된 정답 상호는 금지한다.
- `K2`: 기준영상에서 판독한 전체 간판 문자열을 쓸 수 있다. 전화번호는 질의하지 않는다.
- `K3`: 검색 중 새로 얻은 식별자다. K0~K2 결과에 소급 반영하지 않는다.

한 조사자의 K0→K1→K2는 progressive ladder다. regime 간 적중률을 독립 실험처럼 비교하지 않는다.

## 6. 플랫폼별 결과 surface

Google module:

- `GOOGLE_ORGANIC_WEB`
- `GOOGLE_MAP_PLACE`
- `GOOGLE_AI`
- `GOOGLE_IMAGE`
- `GOOGLE_OTHER`
- `GOOGLE_FALLBACK` — outcome 비적격

Naver module:

- `NAVER_PLACE`
- `NAVER_WEB_DOCUMENT`
- `NAVER_BLOG_CAFE`
- `NAVER_IMAGE`
- `NAVER_AD` — outcome 비적격
- `NAVER_OTHER`

각 module은 `module_screen_order`, `rank_system`, module 내부 `position`을 가진다. Naver module 사이에 전역 organic rank를 만들지 않는다. Google organic result는 최대 10개, module별 후보 클릭은 query당 합계 최대 2개, page 2는 금지한다.

## 7. query match audit

모든 query에 다음을 저장한다.

- `planned_query`
- `submitted_query`
- 입력창에서 다시 읽은 `returned_query`
- `suggested_rewrite`
- `suggestion_followed`
- `fallback_shown`
- `match_behavior`

입력창 문자열 일치는 엔진이 모든 용어를 강제했다는 뜻이 아니다. 각 result의 title·snippet·후보 페이지에서 상호 단서와 위치 단서가 실제로 나타났는지 `query_term_presence`로 별도 판정한다.

## 8. 결과 변수와 동일성

각 query와 bay outcome은 다음을 분리한다.

- `search_surface_retrieval_hit`
- `entity_location_match`
- `historical_time_anchor`
- `current_place_listing_match`
- `identity_status`
- `false_positive_types`

현재 Place listing은 역사 시점 증거가 아니다. 이름+도시 목록은 retrieval hit일 수 있지만 storefront 주소가 없으면 `entity_location_match`를 `yes`로 만들지 않는다.

`confirmed`는 최소 두 종류의 비순환 identity anchor와 물질적 충돌 0건을 요구한다. 같은 이름 하나, 같은 주소 하나, 업종 하나, 같은 원자료의 재게시 여러 건으로는 `confirmed`가 될 수 없다.

오탐 taxonomy:

- `same_name_wrong_address`
- `same_address_other_business`
- `product_term_collision`
- `polysemy_music_software_media`
- `category_only_same_building`
- `stale_index_current_page_mismatch`
- `aggregate_snippet_collision`
- `automatic_query_fallback`
- `other`

## 9. 개인정보 계약

- 무관한 개인·의료·지원 정보가 보이면 snippet을 저장하지 않고 title·URL·제외 사유만 기록한다.
- 원문을 열지 않는다.
- 휴대전화와 지역번호형 사업장 전화는 하이픈·공백 유무와 관계없이 공개 원장에서 `[business phone redacted]`로 바꾼다.
- 이메일은 `[email redacted]`로 바꾼다.
- 저장 전과 JSON 직렬화 후 두 번 검사한다.
- raw 브라우저 DOM·HAR·전체 페이지 export는 만들지 않는다.
- synthetic fixture 이외의 public artifact에 원전화번호가 하나라도 남으면 run은 privacy gate 실패다.

## 10. 실행 환경과 순서

- Google URL은 `hl=ko&pws=0`을 요청한다. 로그인·지역·실험 상태는 관측해 기록하되 통제됐다고 주장하지 않는다.
- Naver 로그인 상태와 표시 모듈을 별도 기록한다.
- plan의 query order를 그대로 따른다.
- CAPTCHA나 접근 제한을 우회하지 않는다.
- 자동 수집 스크립트 대신 수작업 UI 판독을 사용한다. 로컬 schema·privacy 검증 자동화만 허용한다.

## 11. blind calibration 통과 조건

다음이 모두 필요하다.

1. site와 query plan이 retrieval 결과 전에 해시 봉인됐다.
2. 모든 query가 terminal page state와 probe 근거를 가진다.
3. 모든 budget cell이 상한 안에서 끝나거나 정해진 `budget_exhausted`로 닫힌다.
4. Naver module 위치가 전역 rank 없이 보존된다.
5. 같은 주소의 타 업소와 같은 이름의 타 주소가 `confirmed`로 오르지 않는다.
6. public artifact의 원전화·이메일이 0건이다.
7. plan과 run의 ID·query 문자열·hash provenance가 일치한다.
8. 두 번째 판독자가 query page state와 bay identity outcome을 blind 재판독하고 불일치를 기록한다.

1~7만 통과하고 8이 없으면 `SINGLE_READER_PASS_SECOND_READER_PENDING`이다. 이를 V1 통과로 승격하지 않는다.

## 12. 정지 규칙

- site 선택 중 현재 검색 결과가 노출되어 outcome을 알게 됨
- 정확한 공간 범위를 봉인할 수 없음
- query plan 동결 전 target 검색을 실행함
- 개인정보를 안전하게 최소기록할 수 없음
- plan과 다른 alias·전화번호·page 2가 필요해짐

정지 후에는 규칙을 사후 수정해 같은 run을 살리지 않는다. 새 site·plan·run ID를 만든다.
