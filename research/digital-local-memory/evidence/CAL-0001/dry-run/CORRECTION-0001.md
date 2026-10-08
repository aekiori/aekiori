# 사후 정정 C01 — 전화번호 마스킹 누락

```text
correction_id: CAL-0001-DR01-C01
run_id: CAL-0001-DR01
detected_at: 2026-08-11T07:06:09+09:00
status: APPEND_ONLY_CORRECTION
outcome_impact: none
public_release_status: blocked_for_raw_target_file
```

## 관측

동결 후 개인정보 형식 검사를 확장하자 `google-k1-k2-results.json`의 `G-B02-K1-02`, `display_order=7` 스니펫에 하이픈 없는 `031` 지역번호형 10자리 문자열 두 개가 남아 있었다. 원문 숫자는 이 정정 기록에 복제하지 않는다. 해당 결과는 연구 대상과 무관한 타 지역 사업체 목록이며, 두 문자열은 문맥상 사업장 전화번호다.

이것은 D05에서 보존하지 않았던 개인의 의료·지원 정보와 별개의 결함이다. 개인·의료 스니펫 원문은 여전히 로컬 원장에 복사되지 않았지만, 해당 JSON의 `privacy_transform`이 말한 "사업장 전화번호 마스킹"은 완전히 성립하지 않는다.

## 동결 처리

`run-freeze-manifest.json`에 등재된 원자료는 수정하지 않았다. 따라서 실행 원장의 해시 무결성은 유지되지만, `google-k1-k2-results.json`은 그대로 외부 배포하면 안 된다. 공개용 산출물은 새 run ID에서 재수집하거나, 원자료와 분리된 마스킹 파생본을 만들고 별도 해시로 봉인해야 한다.

이 누락은 bay 결과, identity 판정, K0/K1/K2 적중 여부를 바꾸지 않는다. 다만 이번 dry-run의 개인정보 계약은 `fail_with_append_only_correction`이다.

## 다음 규칙

- 하이픈·공백이 있거나 없는 휴대전화·지역번호형 문자열을 직렬화 후 전수 검사한다.
- 스니펫을 저장하기 전에 같은 검사를 수행하고, 무관한 사업체 목록이면 title·URL·제외 사유만 남긴다.
- 마스킹 회귀 fixture에 `031` 10자리 무구분 형식을 포함한다.
- 이 기록 자체를 고치지 않는다. 추가 정정은 `CAL-0001-DR01-C02`처럼 새 ID로 남긴다.
