# 검증 영수증

```text
validated_at: 2026-08-11
protocol: PILOT_PROTOCOL_V0.1
scope: CAL-0001-S01
verdict: READY_FOR_QUERY_PLAN
full_pilot_ready: false
```

## 통과한 검사

- `case-record.schema.json`, `case.json`, `scope-freeze-manifest.json` JSON 문법
- 현재 스키마가 사용하는 `type`, `required`, `additionalProperties`, `enum`, `const`, `pattern`, `format`, `minimum`, `minItems`, `$ref` 계약
- 모든 claim·간판 항목의 evidence ID 교차참조
- 네 evidence 파일의 존재, byte size, SHA-256
- PNG 두 장의 헤더 기준 픽셀 크기
- scope freeze manifest의 원영상·범위문·bay 원장 해시
- freeze manifest와 CSV의 bay ID 및 순서 일치
- bay 3개 모두 `boundary_status=frozen`, `eligible_for_search=true`
- calibration 사례의 prevalence·query difficulty·causal effect 사용 금지 플래그
- Markdown 내부 링크 존재
- 연구 폴더 텍스트의 trailing whitespace 부재

검사 결과:

```text
VALIDATION: PASS
evidence_items=4
claims=7
unknowns=9
frozen_bays=3
```

## 도구 제약과 대체 검사

기본 Python과 번들 Python 모두 `jsonschema` 패키지가 없어 표준 Draft 2020-12 엔진 검증은 실행되지 않았다. 의존성을 즉석 설치해 환경 상태를 바꾸지 않았다. 대신 표준 라이브러리만 사용한 일회성 검사로 현재 스키마가 실제 사용하는 제약을 검증하고, JSON Schema 자체가 검사하지 않는 파일 존재·해시·PNG 크기·evidence 교차참조까지 추가 확인했다.

따라서 현재 판정은 다음과 같다.

- JSON 문법: `verified`
- 현재 계약에 대한 사례 적합성: `verified_by_local_contract_check`
- 제3자 Draft 2020-12 엔진 적합성: `unverified_dependency_missing`

V1.0 프로토콜 동결 전에는 표준 스키마 엔진 검증 경로를 추가하거나 별도 신뢰 가능한 환경에서 재검증해야 한다.

## 지도 확인 결과와 실패 경계

- Google Maps 장소 상세 DOM에서 `율곡아파트중심상가`, `경기도 군포시 금정동 광정로 25-57`, 장소 URL 좌표를 관측했다.
- 대화형 Street View에는 진입했지만 인앱 브라우저와 Chrome 자동 캡처 모두 WebGL 파노라마가 검게 나왔다.
- 오류 로그는 관측되지 않았다.
- 검은 화면에서는 어떤 점포·간판·경계 정보도 추출하지 않았다.
- 이 실패 때문에 전체 건물을 추정하지 않고 제공된 2015년 이미지 안의 완전 가시 구간으로 범위를 축소했다.

## 아직 검증되지 않은 것

- 율곡A상가 전체 점포 경계
- `롤리팝`의 법적 상호·사업자·개폐업일
- 사용자가 과거에 수행한 검색의 정확한 질의·예산·결과
- K0/K1/K2 query plan과 실제 retrieval 결과
- 두 번째 판독자 또는 블라인드 재판독의 일치도
- substantive hypothesis 또는 일반화 가능성

## 다음 통과문

다음 단계는 세 bay의 정확한 질의·채널 순서·열람 범위·시간 예산을 결과 확인 전에 고정하는 것이다. 그 query plan이 별도 해시로 봉인되기 전에는 점포 검색 dry-run을 시작하지 않는다.

---

# 사후 검증 영수증 — `CAL-0001-DR01`

```text
validated_at: 2026-08-11T07:07:20+09:00
protocol: PILOT_PROTOCOL_V0.1
plan: CAL-0001-QP01
run: CAL-0001-DR01
verdict: FROZEN_WITH_PRIVACY_CORRECTION
full_pilot_ready: false
V1_promotion_allowed: false
```

이 절은 위의 검색 전 검증 영수증을 대체하지 않고, 그 이후 실행과 사후 검사를 이어 붙인 기록이다.

## 무결성·대응 검사

- query plan manifest SHA-256: `85EBCFEC09D50D75959B70B1D5469DCFFD89ADC5953FCD5CB0CDE09335AD4B59`
- run manifest SHA-256: `33E95385A096F20F51DFDA3E7241DE5240DBF327D9E3E04971387754E84A6645`
- query plan manifest가 봉인한 파일 5개의 SHA-256: 모두 일치
- run manifest가 봉인한 원자료 7개의 byte size·SHA-256: 모두 일치
- 계획 질의 23개와 실제 query record 23개의 ID·문자열: exact match, 누락·추가·중복 0
- 연구 폴더 JSON 12개: 문법 통과
- Markdown 로컬 링크: 끊어진 링크 0
- 텍스트 trailing whitespace: 0

run manifest가 선언한 추가 실행은 Google K0 기술 재캡처 4회와 candidate source check 3회다. 재캡처는 D01의 렌더 안정화 결함을 관측하기 위한 것이며 substantive retrieval로 세지 않는다.

## 개인정보 계약 정정

확장 정규식 검사에서 `google-k1-k2-results.json`의 `G-B02-K1-02`, `display_order=7` 스니펫에 하이픈 없는 `031` 지역번호형 10자리 사업장 전화 문자열 두 개가 남아 있음을 발견했다. 원문 숫자는 정정 파일에 복제하지 않았다.

- 사람의 의료·지원 상태가 드러난 Naver K0 스니펫 원문은 보존되지 않았다는 D05 관측은 유지된다.
- 그러나 해당 Google JSON의 `privacy_transform` 문장은 이 레코드에 대해 거짓이다.
- 동결 원자료를 고치지 않았으므로 run manifest 무결성은 유지된다.
- bay 결과와 identity 판정에는 영향이 없지만, 원 JSON의 외부 배포는 차단한다.
- append-only 정정: `evidence/CAL-0001/dry-run/CORRECTION-0001.md` (`95BC81BFEB3757CCCECBD3AC074B1B3F712A583858804359B76E24CECB599E4C`)
- 기계 판독 정정: `evidence/CAL-0001/dry-run/correction-0001.json` (`348B69053BCC665455ABBC54F10A102CF5862C594BBA1899AD13E4E31209242D`)

따라서 개인정보 검사는 `PASS`가 아니라 `FAIL_WITH_APPEND_ONLY_CORRECTION`이다.

## 실행 결함과 결과 경계

- D01: Google 비동기 렌더 때문에 K0 4개를 같은 순서로 기술 재캡처했다.
- D02: `G-B01-K2-01`, `G-B03-K2-01`은 명시적 no-result가 아니라 `render_indeterminate`다.
- D03: Naver K0는 K0 시간 예산을 넘겨 실행되어 보존하되 K0 outcome에서 제외했다.
- D04: Naver 모듈형 결과에는 Google과 비교 가능한 전역 organic rank가 없다.
- D05: 무관한 민감 스니펫은 본문 미보존 처리했지만, 위 사업장 전화 마스킹 누락은 사후 정정했다.
- D06: V0.1 retrieval schema가 bay·platform·query·budget·module·render 상태를 표현하지 못해 `case.json.retrieval_runs`에는 축약 입력하지 않았다.

이 실행으로 K0/K1/K2 query plan과 실제 retrieval 원장은 검증되었다. 그러나 다음은 여전히 검증되지 않았다.

- 두 번째 판독자 또는 blind 재실행의 일치도
- 2015년의 별도 텍스트·구조화 temporal anchor
- 기록 생성·삭제·비보존·비색인·비랭킹 중 어느 경로가 B02 실패를 만들었는지
- 일반 상권의 잔존율, 플랫폼 효과, 프랜차이즈 효과
- 제3자 Draft 2020-12 JSON Schema 엔진 적합성

## 다음 통과문

V0.2에서 렌더 상태기계, platform×regime×bay 예산 셀, module별 순위, current/historical 결과 분리, false-positive 분류, 저장 전·직렬화 후 개인정보 검사를 구현한다. 특히 하이픈 없는 지역번호형 전화번호를 회귀 fixture로 고정한다. 그 뒤 결과를 모르는 새 장소에서 blind calibration을 통과하기 전에는 `V1.0-FROZEN`으로 승격하지 않는다.
