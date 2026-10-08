# Blind site selection V0.2

```text
selection_id: CAL-0002-SEL01
target_case_id: CAL-0002
status: FROZEN_BEFORE_SITE_INSPECTION_BY_MANIFEST
prior_target_retrieval_exposure: false
```

## 선택 기준점과 seed

- 기준점: `CAL-0001` Google place anchor 좌표 `37.3540936, 126.9310404`
- seed: `CAL-0002|CAL-0001|2026-08-11|blind-calibration`
- seed SHA-256: `D2E0114661C5233E45A35E927EE01D84D552EC40E5A7C5A5161027777F875860`
- 방향 순서: `N, NE, E, SE, S, SW, W, NW`
- 거리 순서: `400m, 600m, 800m, 1000m`
- 시작 방향: 첫 byte `210 mod 8 = 2`, 즉 `E`
- 시작 거리: 둘째 byte `224 mod 4 = 0`, 즉 `400m`

후보 `k=0..31`은 같은 거리에서 시작 방향부터 시계방향으로 8개 방향을 확인한 뒤 다음 거리로 이동한다. 좌표는 WGS84 국소 근사로 계산한다.

```text
latitude  = base_lat + north_m / 111320
longitude = base_lon + east_m / (111320 × cos(base_lat))
```

## 적격 조건

일반 웹·Google Search·Naver Search·Place 상세를 열지 않고 거리영상 UI만 사용한다. 다음을 모두 만족하는 첫 후보를 채택한다.

1. 기준점과 다른 site다.
2. 2014-01-01~2016-12-31 사이로 표시된 역사 거리영상이 있다.
3. 한 화면에 완전히 보이는 인접 1층 facade bay가 3개 이상이다.
4. 그중 최소 2개 bay에서 간판 문자열 또는 업종 단서를 판독할 수 있다.
5. 얼굴·차량번호를 연구 원장에 옮기지 않고 facade crop을 보존할 수 있다.
6. 거리영상의 위치 표시 또는 사업체명을 제외한 주소 전용 geocoding으로 K0 공간 앵커를 얻을 수 있다.

적격 여부 판단 중 현재 업체명·Place 결과가 노출되면 그 후보는 `selection_leakage`로 기각하고 다음 후보로 이동한다.

## 선택 후 동결

첫 적격 후보에서 즉시 다음을 수행한다.

1. 거리영상 제공자·표시 시점·좌표·화면을 저장한다.
2. 조사할 연속 facade의 왼쪽·오른쪽 앵커를 문장으로 지정한다.
3. 모든 완전 가시 1층 bay를 왼쪽부터 번호화한다.
4. `scope`, `bay register`, 원영상 SHA-256을 봉인한다.
5. 간판 원문만 이용해 K1/K2 query를 작성하고 plan을 봉인한다.

그 전에는 어떤 target 상호도 검색하지 않는다.
