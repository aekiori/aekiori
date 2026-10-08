# Protocol delta V0.2 — draft

```text
status: DRAFT_FROM_CAL-0001-DR01
not_frozen: true
substantive_use: prohibited
requires_new_blind_calibration: true
```

## 승격 판정

V0.1을 직접 수정해 결과를 소급 정당화하지 않는다. 아래 변경은 새 plan ID와 새 run ID에서만 적용한다. `CAL-0001-DR01` 결과는 계속 V0.1 교정 결과로 남긴다.

## 1. usable page 상태기계

검색 페이지는 다음 상태 중 하나로 끝나야 한다.

```text
navigating
  -> stabilizing
    -> usable_results
    -> explicit_no_results
    -> rewritten_or_fallback
    -> blocked
    -> render_timeout
```

`usable_results`는 결과 title 수가 사전 지정 간격의 연속 2회 관측에서 같고 1개 이상일 때만 부여한다. `explicit_no_results`는 플랫폼별로 사전 지정한 UI 문구가 보일 때만 부여한다. 둘 다 아니면 대기상한 뒤 `render_timeout`이며, `not_found_under_protocol`로 바꾸지 않는다.

Google이 정확 따옴표 질의 무결과 뒤 따옴표 제거 결과를 표시하면 두 블록을 분리한다. 계획이 rewrite를 금지하면 fallback 결과는 보존하되 outcome에서 제외한다.

## 2. 예산 셀

예산 키를 다음처럼 고정한다.

```text
platform × knowledge_regime × bay_or_site
```

각 셀은 실행 순서상 연속 구간이어야 한다. 시작은 첫 usable page, 종료는 마지막 query disposition 또는 stop 상태다. 다른 셀을 수행하는 동안 clock을 멈추려면 `active_review_clock`으로 이름을 바꾸고 pause/resume event를 저장한다. 벽시계라고 부르면서 암묵적으로 멈추는 방식은 금지한다.

## 3. 플랫폼별 result surface

### Google

- `ORGANIC_WEB`: 첫 페이지 title link 최대 10개
- `MAP/PLACE`, `AI`, `IMAGE`, 기타 모듈: 별도 module observation
- 자동 fallback: 별도 결과 집합

### Naver

- `PLACE`
- `WEB_DOCUMENT`
- `BLOG_CAFE`
- `IMAGE`
- `AD` — 기록 여부만 남기고 outcome 제외

Naver 모듈 사이에 전역 rank를 만들지 않는다. 각 모듈의 화면 위치와 모듈 내부 position만 기록한다. Google organic rank와 숫자 비교를 금지한다.

## 4. query match audit

각 query에 다음을 저장한다.

- `planned_query`
- `submitted_query`
- 입력창에서 읽은 `returned_query`
- `suggested_rewrite`
- `suggestion_followed=false/true`
- `fallback_shown`
- `match_behavior=exact/loose/rewritten/unknown`

입력창 문자열이 같다는 사실은 엔진이 모든 용어를 강제했다는 뜻이 아니다. 결과 문서에 핵심 용어·주소가 실제로 있는지 별도로 판정한다.

## 5. 결과 변수 분리

하나의 `found`를 쓰지 않는다.

```text
search_surface_retrieval_hit
entity_location_match
historical_time_anchor
current_place_listing_match
identity_status
false_positive_type[]
```

현재 Place listing은 `current_place_listing_match`에는 기여하지만 2015 anchor에는 기여하지 않는다. 이름+도시 목록은 검색 hit일 수 있지만 storefront 주소가 없으면 `entity_location_match=false/ambiguous`다.

## 6. 동일성 및 오탐 taxonomy

최소 오탐 유형:

- `same_name_wrong_address`
- `same_address_other_business`
- `product_term_collision`
- `polysemy_music_software_media`
- `category_only_same_building`
- `stale_index_current_page_mismatch`
- `aggregate_snippet_collision`
- `automatic_query_fallback`

각 오탐은 버리지 않고 query result로 보존하되 적격 evidence와 분리한다.

## 7. 수집 단계 개인정보 방어

1. 검색 결과에 연구와 무관한 민감정보가 보이면 snippet 본문을 저장하지 않는다.
2. URL·title·제외 사유만 최소 기록한다.
3. 원문을 열지 않는다.
4. 사업장 전화도 공개 원장에는 마스킹한다. 하이픈·공백이 없는 지역번호형 문자열까지 포함해 저장 전과 직렬화 후 두 번 검사한다.
5. 개인 이름·주민번호·의료·지원 상태가 있는 대량 문서는 대상 사업체와 직접 관련되지 않으면 후보에서 즉시 제외한다.
6. 회귀 fixture에는 `031` 10자리 무구분 형식을 포함하고, 원자료와 공개용 파생본의 해시를 분리한다.

## 8. 새 retrieval record 필수 필드

기존 V0.1 `case-record.schema.json`에 직접 억지로 넣지 않는다. V0.2 record에는 최소한 다음이 필요하다.

- site/scope/bay ID
- plan/run/query ID와 query order
- platform, source channel, module, position/rank system
- planned/submitted/returned query
- 시작·usable·관측·종료시각
- budget cell, elapsed, status
- page state와 stabilization observations
- title/URL/snippet의 privacy transform
- result disposition, identity anchors, independence group
- retrieval/entity-location/historical/current-place 결과
- false-positive type과 K3/cross-bay 노출

## 9. 다음 dry-run 통과 조건

결과를 모르는 새 장소에서 다음이 모두 충족되어야 한다.

1. 페이지 상태를 두 조사자가 같은 규칙으로 판정한다.
2. 무결과와 render timeout을 혼동하지 않는다.
3. 모든 platform×regime×bay 셀이 예산 안에서 끝난다.
4. Naver module 위치가 손실 없이 기록된다.
5. 같은 주소의 다른 업소와 같은 이름의 다른 주소가 `confirmed`로 오르지 않는다.
6. 민감 스니펫 원문이 로컬 산출물에 남지 않는다.
7. query record에서 bay·platform·module·시각·예산을 역추적할 수 있다.
8. 사전 query plan과 실제 실행의 hash/provenance가 통과한다.

통과 전에는 자동화, 유병률/잔존율 계산, 플랫폼 비교, 프랜차이즈 효과 추정을 금지한다.
