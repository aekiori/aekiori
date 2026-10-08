# CAL-0002 V0.3 blind calibration findings

## 판정

**관측 패턴은 나왔지만 원인은 아직 격리되지 않았다. V1 승격은 NO-GO다.**

`CAL-0002-DR01`은 검색 전에 선정한 2015년 7월 파사드에서 Google 10개, Naver 10개 질의를 동결 순서로 수행한 단일 판독자 보정 실행이다. 자체 V0.3 validator는 통과했지만 두 번째 blind reader가 없고, active-review clock이 자동 계측되지 않았으며, 일부 인접 셀 질의가 한 helper batch로 실행됐다. 따라서 최대 상태는 `SINGLE_READER_PASS_SECOND_READER_PENDING`이며 substantive inference는 금지된다.

## 파사드 안에서 갈린 결과

| Entity | 2015 anchor sign | Google | Naver | 최종 identity 판정 | qualifying historical web anchor |
|---|---|---|---|---|---|
| `CAL-0002-E01` | `CU` | K2에서 `CU군포우륵점`과 단지 기준 73m가 노출됨. 144m 거리의 다른 CU도 함께 존재 | 동결 K1/K2에서 정확한 점포 identity 미회수 | `possible` | 없음 |
| `CAL-0002-E02` | `김연주 헤어샵` | K2 1위에 정확한 상호, `산본천로 33`, `우륵일반상가 102호`가 함께 노출 | K2에 같은 상호의 로컬맵 문서 노출 | `probable` | 없음 |
| `CAL-0002-E03` | `하얀크리닝` | 정확 상호 K2는 타 지역 동명이름과 전국 집계 노이즈가 우세. K1의 AI module에는 `하얀세탁소` 후보가 나왔으나 outcome에서 제외 | K2에 `하얀세탁소` 수리동 오탐과 궁내동 후보가 함께 노출 | `possible` | 없음 |
| `CAL-0002-E04` | `우륵 공인중개사` | K1/K2에서 정확 상호, K2에서 `산본천로 33` 연결 회수 | K2에서 `우륵공인중개사 - 114On` 회수 | `probable` | 없음 |

여기서 `probable`은 “2015년부터 같은 법적 사업자가 끊김 없이 영업했다”는 뜻이 아니다. 2015 anchor의 간판과 현재 검색면의 상호·주소가 강하게 맞는다는 뜻이다. 중단 없는 법적 연속성, 운영자 동일성, 과거 시점의 검색 가능성은 확인되지 않았다.

## 가장 중요한 해석

이번 표본에서 검색엔진이 되살린 것은 대체로 **가게의 과거 서사**가 아니라, 현재도 재공급되는 **상호-주소 edge**였다.

- `김연주헤어샵`은 검색 snippet 자체가 정확한 상호·주소·호수를 회수했다. 셀 종료 뒤 확인한 보조 페이지는 행정 인허가 재게시 경로와 2001년 개업일을 표시했지만, 그 upstream 공공 원문은 직접 검증하지 않았고 이 페이지 확인은 frozen outcome에서 제외했다.
- `우륵공인중개사`는 업체 디렉터리와 통신사 제공 디렉터리에서 같은 상호-주소 edge가 재유통됐다.
- `CU`는 브랜드 POI/주변 편의시설 데이터에서는 강하지만, generic brand와 복수 근접 점포 때문에 2015 bay를 격리하지 못했다.
- `하얀크리닝`은 이름 변형(`하얀세탁소`)과 같은 이름의 타 주소가 섞여, location-compatible 후보가 있어도 동일 entity로 승격할 수 없었다.

따라서 현재의 최선 설명은 다음과 같다.

> 인터넷의 동네 가게 기억은 “실제로 존재했는가”보다, 그 entity-location 관계가 행정 인허가·통신사·프랜차이즈 POI·업체 디렉터리 같은 재공급 파이프라인에 들어갔는가에 더 크게 좌우될 수 있다.

이 문장은 **best current explanation**이지 `cause isolated`가 아니다. 업종, 영업기간, 프랜차이즈 여부, 이름 고유성, 현재 영업 여부, 주소 정규화, 소스 간 복제관계가 동시에 다르다. 네 entity 한 파사드로는 이들을 분리할 수 없다.

## CAL-0001의 롤리팝 사례와 연결

`CAL-0001`에서는 건물과 현재 Paris Baguette entity는 쉽게 회수됐지만, 2015년 `롤리팝 / 세계수입과자할인점`은 K0-K2에서 회수되지 않았다. `CAL-0002`는 그 실패가 단순히 “오래돼서”만은 아닐 가능성을 높인다. 같은 2015 파사드에서도 정확 상호가 살아남는 entity와 변형명·근접 POI·집계 노이즈로만 남는 entity가 갈렸다.

그러나 두 calibration을 합쳐도 다음은 말할 수 없다.

- 롤리팝이 공공데이터에 원래 없었다.
- 특정 검색엔진이 롤리팝을 삭제했다.
- 폐업이 곧 디지털 소멸을 일으켰다.
- 규제 업종이면 반드시 기억되고 비규제 업종이면 반드시 잊힌다.

## 프로토콜이 실제로 잡아낸 결함

1. 검색 전에 V0.2의 `one bay = one identity` 모델이 B02의 두 상호를 표현하지 못했다. target query 0개 상태에서 실패를 봉인하고 V0.3의 `facade_bay <-> entity_hypothesis` 다대다 구조로 교정했다.
2. 첫 Google query에서 probe 시점의 returned-query reader가 비어 있었다. probe 값은 `null`로 보존하고 post-terminal exact read만 기록했다.
3. 일부 인접 셀이 combined browser batch로 실행됐다. 동결 query에 대한 중간 피드백은 조사자에게 노출되지 않았지만, wall-clock cell accounting이 깔끔하지 않다.
4. active-review 시간은 자동 pause-aware timer가 아니라 query/terminal/tool 경계에서 수동 재구성했다. 모든 셀이 cap보다 최소 40초 이상 낮지만 정확한 초 단위 계측으로 주장하지 않는다.
5. Naver stabilization count에는 AI/Mate 등 outcome-ineligible title-like links가 포함됐다. 이 수는 stable rendered page 판정에만 썼고 결과 코딩은 module별로 다시 분리했다.

## 다음 실험의 단일 핵심 가설

다음 blind calibration의 주가설은 하나로 좁힌다.

> **동일한 역사적 파사드 노출을 가진 가게 중 upstream structured source에 entity-location edge가 있는 가게가, 없는 가게보다 K2 exact-name retrieval에서 더 잘 회수되는가?**

필요한 설계 변경은 다음과 같다.

1. 한 번에 query 하나만 실행하고, terminal 판정 직후 같은 셀 안에서 판독·허용된 click·메모를 끝낸 뒤 다음 query로 넘어가는 자동 timer를 둔다.
2. retrieval outcome을 먼저 봉인한 뒤 별도 K3 explanatory lane에서 upstream source를 확인한다. 공공 인허가 원문, 통신사 디렉터리, franchise POI, 단순 재게시를 같은 것으로 합치지 않는다.
3. source URL 수가 아니라 independence group 수를 센다. 같은 공공 row의 복제 10건은 독립 증거 10건이 아니다.
4. `exact entity-location retrieval`, `historical dated retrieval`, `current listing`, `name variant`, `wrong-address collision`을 별도 종속변수로 유지한다.
5. 최소 여러 파사드에서 업종·프랜차이즈·현재 영업 여부를 교차시켜야 한다. 이론 검정 전에 “규제 업종 하나 vs 비규제 업종 하나” 비교로 결론내리지 않는다.

## 증거 파일

- [`retrieval-run.json`](retrieval-run.json): 20개 query, terminal probes, module/result 최소 레코드, entity outcomes, deviations, privacy audit
- [`supplemental-source-checks.json`](supplemental-source-checks.json): 셀 밖 또는 ineligible module에서 확인한 설명용 후보; frozen outcome에는 반영하지 않음
- [`EXECUTION_DEVIATIONS.md`](EXECUTION_DEVIATIONS.md): 측정 결함과 영향 범위
- [`VALIDATION.md`](VALIDATION.md): validator, hash, privacy, manifest 검증 결과

