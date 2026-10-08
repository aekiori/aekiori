# CAL-0002-S01 scope

```text
case_id: CAL-0002
scope_id: CAL-0002-S01
protocol: PILOT_PROTOCOL_V0.3
status: FROZEN_BY_SCOPE_MANIFEST
cohort_role: blind_measurement_calibration
substantive_use: prohibited
```

## 공간·시점 앵커

- provider: Google Street View
- provider pano ID: `1VQdRuuei3DwrmxGDgKDxA`
- Google UI 표시 시점: `2015년 7월`
- 후보 요청 좌표: `37.3591752, 126.9246476`
- 주소 전용 공간 앵커: `우륵 주공7단지아파트`, `산본천로`, `궁내동`, 대한민국
- 정확한 도로명 번지: 검색 전 미확인
- 보존 view: yaw `285`, requested FOV `120`
- source image: [google-streetview-2015-07-candidate21-yaw285-fov120.jpg](source/google-streetview-2015-07-candidate21-yaw285-fov120.jpg)

이 이미지는 Google Street View 파노라마 전체가 아니라 선택 scope를 판독하기 위해 고정한 1024×512 thumbnail view다. Google Search·Naver Search·Place 결과가 아니며 retrieval outcome에서 제외한다.

## facade 경계

- 왼쪽 앵커: CU 점포 왼쪽 외벽과 조경 통로가 만나는 수직 경계
- 오른쪽 앵커: 붉은 차양 공인중개사 점포 오른쪽 외벽과 주차·차도 공간이 만나는 수직 경계
- 층: 완전히 보이는 지상 1층 frontage만 포함
- 포함 bay: 왼쪽부터 `CAL-0002-B01`, `CAL-0002-B02`, `CAL-0002-B03`
- 제외: 상층 주거공간, 조경, 공중전화, 차량·사람, 화면 밖 인접 점포

scope는 아파트 단지 전체 상가나 건물 전체를 대표하지 않는다.

## bay 관측

### `CAL-0002-B01`

- 상태: `occupied_candidate`
- 완전 가시: yes
- 판독 간판: `CU`
- 업종 단서: 편의점 외관·진열
- entity 후보: `CAL-0002-E01`

### `CAL-0002-B02`

- 상태: `occupied_candidate`
- 완전 가시: yes
- 판독 간판: `김연주 헤어샵`, `하얀크리닝`
- 업종 단서: 미용, 세탁·크리닝
- entity 후보: `CAL-0002-E02`, `CAL-0002-E03`
- 경계: 물리 bay 하나에 두 entity 후보가 공존한다. 별도 사업체, 복합 서비스, 잔존 간판 중 어느 것인지 검색 전에는 확정하지 않는다.

### `CAL-0002-B03`

- 상태: `occupied_candidate`
- 완전 가시: yes
- 판독 간판: `우륵 공인중개사`
- 업종 단서: 부동산 중개
- entity 후보: `CAL-0002-E04`

## 개인정보·판독 경계

간판에 전화번호형 문자열이 보이지만 원문을 전사·저장·질의하지 않았다. 얼굴과 차량번호는 제공자 영상에서 흐림 처리돼 있으며 연구 원장에 별도 추출하지 않는다.

거리영상은 촬영 시점의 간판·외관 관측이지 법적 영업, 사업자 등록, 현재 존속의 ground truth가 아니다.
