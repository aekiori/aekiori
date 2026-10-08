# CAL-0002 blind selection log

```text
selection_id: CAL-0002-SEL01
protocol_manifest_sha256: A359F0DADEE3C6CA4298A32E4538057197BB238FCA9A779993B07D19B12F33F5
target_retrieval_queries_before_selection: 0
selected_candidate: 21
selection_status: FIRST_ELIGIBLE_WITH_BOUNDED_OVERSHOOT_DEVIATION
```

## 후보 진행

동결된 방향·거리 순서대로 후보를 확인했다.

- `0`: 2020년 10월 사용자 제공 360 이미지이며 공식 2014~2016 영상이 아님.
- `1`, `3`, `5`, `7`, `8`, `9`, `12`, `13`, `15`, `17`, `18`, `19`, `20`: 거리영상 없음 UI 신호.
- `2`: 공식 파노라마는 열렸으나 아파트 주차장으로, 연속 점포 bay 3개가 없음.
- `4`, `6`, `10`, `11`, `14`, `16`: 제한시간 안에 유효 pano ID와 적격 facade를 얻지 못함.
- `21`: 공식 Google Street View, UI 표시 `2015년 7월`, 연속된 완전 가시 1층 bay 3개와 판독 가능한 간판 단서가 있어 첫 적격 후보.

## 선택 후보 공간 앵커

- 요청 후보 좌표: `37.3591752, 126.9246476`
- Google pano ID: `1VQdRuuei3DwrmxGDgKDxA`
- OSM 공간 앵커: `우륵 주공7단지아파트`, `산본천로`, `궁내동`, 대한민국
- 정확한 도로명 번지는 검색 전 단계에서 확인되지 않았으며 미확인으로 둔다.
- facade image: `source/google-streetview-2015-07-candidate21-yaw285-fov120.jpg`

Google Search, Naver Search, Google Place 상세는 이 선택 전에 열지 않았다. Nominatim·Overpass에서는 주소·주거단지 공간 필드만 출력했고 target 사업체 결과를 조회하지 않았다.

## 선택 overshoot deviation

`candidate 21~23`의 공식 pano 존재 여부를 한 batch에서 연속 확인했다. `21`을 시각적으로 적격 판정하기 전에 `22`, `23`의 공식 pano 존재 여부까지 확인됐으나, 두 후보의 이미지·간판·주소·업체명은 열람하지 않았다. 따라서 `21`은 여전히 순서상 첫 적격 후보지만 selection controller는 첫 잠재 후보에서 즉시 멈추지 못했다.

```text
deviation_id: CAL-0002-SEL-D01
effect: bounded_no_target_result_exposure
remedy: future selector checks and visually adjudicates one candidate before navigating to the next
```

## 검색 전 관측 모형 실패

가운데 bay에 `김연주 헤어샵`과 `하얀크리닝` 두 entity 후보가 공존한다. V0.2 schema가 이를 표현하지 못해 `CAL-0002-PF01`로 V0.2를 pre-retrieval fail 처리했다. V0.3 계약 봉인 전 target 검색은 계속 금지한다.
