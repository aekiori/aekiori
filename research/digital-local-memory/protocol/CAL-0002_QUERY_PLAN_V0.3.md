# CAL-0002 query plan V0.3

```text
plan_id: CAL-0002-QP01
scope_id: CAL-0002-S01
protocol: PILOT_PROTOCOL_V0.3
status: FROZEN_BEFORE_RETRIEVAL_BY_MANIFEST
created_at: 2026-08-11T07:42:13+09:00
investigator_prior_target_results: none
substantive_use: prohibited
```

## 실행 계약

- 단일 조사자의 progressive K0→K1→K2 ladder다. regime 간 독립 성공률을 만들지 않는다.
- Google lane을 모두 끝낸 뒤 Naver lane을 실행한다.
- 각 `platform × regime × bay_or_site` 셀은 중단 없이 연속 실행한다.
- Google organic은 최대 10개, Naver는 module별 position을 저장한다.
- query당 후보 클릭은 전체 module 합계 최대 2개다.
- page 2, 전화번호, 검색 후 발견 alias, 제안어 클릭은 금지한다.
- anchor image는 retrieval outcome에서 제외한다.

## 페이지 판정

1초 간격 probe 두 개에서 visible candidate title 수가 같은 양수일 때 `usable_results`다. 명시적 무결과 UI, fallback/rewrite, blocked 신호는 별도 terminal state다. 어느 것도 8초 안에 성립하지 않으면 `render_timeout`이다.

Google explicit-no-result 패턴은 `일치하는 검색결과가 없습니다` 또는 `검색어와 일치하는 결과가 없습니다`다. Naver는 `검색결과가 없습니다` 또는 `검색 결과가 없습니다`다. 자동 따옴표 제거·추천 fallback은 별도 module로 보존하되 outcome에서 제외한다.

## 예산

| 셀 | active-review 상한 |
|---|---:|
| platform별 K0 site | 120초 |
| platform별 K1 bay | 120초 |
| platform별 K2 bay | 180초 |

navigation·stabilization은 `network_wait_seconds`로 분리한다.

## 질의 순서

| order | ID | cell | entity | frozen query |
|---:|---|---|---|---|
| 1 | `G-K0-01` | `G-K0-SITE` | — | `"우륵 주공7단지아파트" 2015` |
| 2 | `G-K0-02` | `G-K0-SITE` | — | `"우륵주공7단지" 상가` |
| 3 | `G-B01-K1-01` | `G-K1-B01` | E01 | `편의점 "우륵 주공7단지아파트"` |
| 4 | `G-B02-E02-K1-01` | `G-K1-B02` | E02 | `미용실 "우륵 주공7단지아파트"` |
| 5 | `G-B02-E03-K1-01` | `G-K1-B02` | E03 | `세탁소 "우륵 주공7단지아파트"` |
| 6 | `G-B03-K1-01` | `G-K1-B03` | E04 | `공인중개사 "우륵 주공7단지아파트"` |
| 7 | `G-B01-K2-01` | `G-K2-B01` | E01 | `"CU" "우륵주공7단지"` |
| 8 | `G-B02-E02-K2-01` | `G-K2-B02` | E02 | `"김연주 헤어샵" 군포 산본` |
| 9 | `G-B02-E03-K2-01` | `G-K2-B02` | E03 | `"하얀크리닝" 군포 산본` |
| 10 | `G-B03-K2-01` | `G-K2-B03` | E04 | `"우륵 공인중개사" 군포` |
| 11 | `N-K0-01` | `N-K0-SITE` | — | `"우륵 주공7단지아파트" 2015` |
| 12 | `N-K0-02` | `N-K0-SITE` | — | `"우륵주공7단지" 상가` |
| 13 | `N-B01-K1-01` | `N-K1-B01` | E01 | `편의점 "우륵 주공7단지아파트"` |
| 14 | `N-B02-E02-K1-01` | `N-K1-B02` | E02 | `미용실 "우륵 주공7단지아파트"` |
| 15 | `N-B02-E03-K1-01` | `N-K1-B02` | E03 | `세탁소 "우륵 주공7단지아파트"` |
| 16 | `N-B03-K1-01` | `N-K1-B03` | E04 | `공인중개사 "우륵 주공7단지아파트"` |
| 17 | `N-B01-K2-01` | `N-K2-B01` | E01 | `"CU" "우륵주공7단지"` |
| 18 | `N-B02-E02-K2-01` | `N-K2-B02` | E02 | `"김연주 헤어샵" 군포 산본` |
| 19 | `N-B02-E03-K2-01` | `N-K2-B02` | E03 | `"하얀크리닝" 군포 산본` |
| 20 | `N-B03-K2-01` | `N-K2-B03` | E04 | `"우륵 공인중개사" 군포` |

## outcome 경계

- current Place listing은 `current_place_listing_match`일 뿐 2015 anchor가 아니다.
- complex name·주소만 같은 타 업소는 target entity match가 아니다.
- E02와 E03은 같은 bay를 쓰지만 한쪽 결과를 다른 쪽으로 전이하지 않는다.
- `not_found_under_protocol`은 terminal page state와 셀 예산 안에서만 부여한다.
- 이 calibration의 적중 빈도와 플랫폼 차이를 모집단이나 인과 효과로 해석하지 않는다.
