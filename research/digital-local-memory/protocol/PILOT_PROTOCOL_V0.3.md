# PILOT_PROTOCOL_V0.3 — entity/bay amendment

```text
status: FROZEN_FOR_CALIBRATION_BY_MANIFEST
created: 2026-08-11
base_contract: PILOT_PROTOCOL_V0.2
base_manifest_sha256: A359F0DADEE3C6CA4298A32E4538057197BB238FCA9A779993B07D19B12F33F5
trigger: CAL-0002-PF01
target_searches_before_amendment: 0
substantive_hypothesis_test: prohibited
```

## 1. 적용 방식

V0.3은 V0.2의 페이지 상태기계, probe 간격, 셀별 active-review 예산, 플랫폼 module, query match audit, 개인정보 계약, 정지 규칙을 그대로 계승한다. 다음 관측 단위와 record만 V0.3으로 교체한다.

V0.2 파일을 수정하지 않는다. 실행 record의 `protocol_version`은 `PILOT_PROTOCOL_V0.3`이어야 하며 V0.2 결과와 같은 버전으로 합치지 않는다.

## 2. 관측 단위

```text
site
  -> historical capture
    -> facade_bay
      <-> sign_observation
        -> entity_hypothesis
          -> query
            -> result
              -> entity_outcome
```

`facade_bay`는 물리 공간 단위이고 `entity_hypothesis`는 간판이 가리킬 수 있는 사업체 후보다. 관계는 일대일을 가정하지 않는다.

- 한 bay에 복수 entity 후보가 있을 수 있다.
- 한 entity가 복수 bay를 차지할 수 있다.
- 간판 문자열 하나가 브랜드·서비스·건물명·이전 간판 중 무엇인지 불명확할 수 있다.
- 검색 전에 entity를 합치거나 버리지 않는다.

## 3. entity 원장

scope freeze에는 다음을 별도 저장한다.

- `entity_id`
- 연결된 `bay_ids`
- 영상에서 직접 판독한 `observed_sign_strings`
- 각 문자열의 `role_candidate`
- K1에 허용되는 `category_clues`
- entity 간 관계 판정 `distinct / possibly_same / co_located_unknown / successor_unknown / unknown`

전화번호는 판독 가능해도 원문을 기록하거나 질의하지 않는다.

## 4. query 계약

각 query는 `target_entity_ids`를 가진다.

- K0 site query는 빈 배열이다.
- K1/K2는 목표 entity를 하나 이상 명시한다.
- 같은 bay의 두 entity 후보는 별도 query 또는 두 ID를 명시한 공동 query로 기록한다.
- query 결과가 다른 entity를 노출하면 `cross_bay_exposure`와 별도로 entity ID를 기록한다.

query-level `aggregate_outcome`은 검색 화면 전체 판정이다. `entity_outcomes`는 그 query가 각 entity에 제공한 증거를 분리한다. 둘을 서로 대체하지 않는다.

## 5. outcome 계약

run에는 두 층의 outcome을 둔다.

- `bay_outcomes`: 물리 경계와 연결된 entity ID 목록만 저장한다.
- `entity_outcomes`: retrieval, entity-location match, historical anchor, current Place listing, identity status, anchor, conflict를 entity별 저장한다.

한 entity가 `confirmed`가 되려면 최소 두 종류의 비순환 identity anchor와 물질적 충돌 0건이 필요하다. 같은 bay의 다른 entity 증거를 빌려 확정할 수 없다.

## 6. V0.3 추가 실패 시험

1. 같은 bay의 두 이름이 query·result·outcome에서 별도 ID로 역추적된다.
2. 둘 중 하나의 current Place hit가 다른 하나를 자동으로 `confirmed`로 만들지 않는다.
3. 복합 서비스 한 사업체라는 증거가 나오더라도 검색 전 원장을 소급 합치지 않고 관계 판정만 업데이트한다.
4. 검색 실패가 bay 공실, entity 부재, 과거 간판 잔존 중 하나로 승격되지 않는다.

V0.2 통과 조건 1~8과 위 네 조건을 모두 통과해야 한다. 두 번째 판독자가 없으면 최대 판정은 계속 `SINGLE_READER_PASS_SECOND_READER_PENDING`이다.
