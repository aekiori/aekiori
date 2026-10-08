# RESTART-ANATOMY-V0.1

상태: `observation-only pilot-ready`

## 관찰

사용자는 대여섯 개의 Codex 세션을 장시간 실행한 뒤 Codex를 정상 종료해도 Windows가 매우 느리며, 재부팅 후에는 빠르게 회복된다고 보고했다.

이 관찰은 다음을 아직 구분하지 못한다.

```text
장시간 다중 세션
  -> 사용자 공간 작업자 잔류
  -> memory / handle / thread pressure 잔류
  -> DWM / GPU / driver / kernel state 잔류
  -> 열 또는 전원 제한
  -> 단순한 시간 경과와 부하 감소
  -> 체감 버벅임
```

## 질문

> Codex 창을 닫는 행위와 Codex가 생성한 전체 로컬 작업 상태가 종료되는 행위 사이에는 어떤 차이가 있으며, 재부팅이 제거하는 최소 잔류 상태는 무엇인가?

## 최초 run의 사전 고정 범위

첫 자연 run은 개입이 아니라 관측이다.

- Codex 정상 종료 전에 활성 기준선을 수집한다.
- 정상 종료 직후 외부 감시기에서 사용자가 Enter로 close marker를 남기고, 그 시점부터 0초, 30초, 120초, 600초에 같은 측정을 반복한다.
- 600초까지 프로세스나 서비스를 강제 종료하지 않는다.
- 사용자가 실제로 재부팅한 뒤 같은 측정을 한 번 더 한다.
- 명령행은 수집하지 않는다.
- 수집 도중 얻은 결과를 보고 표본 시각이나 지표를 바꾸지 않는다.

## 살아 있는 가설과 판별 예측

### H1. 사용자 공간 잔류 작업자

예측:

- 기준선에서 Codex 실행 파일 또는 부모 계보에 묶인 프로세스 identity가 600초 뒤에도 남는다.
- 해당 identity가 의미 있는 CPU, private bytes, handle 또는 thread를 유지한다.
- 다음 재발에서 그 identity만 종료하면 전체 재부팅 없이 객관 지표와 체감이 회복된다.

약화 조건:

- 기준선의 Codex-affiliated identity가 모두 사라졌는데도 버벅임이 같은 강도로 지속된다.

### H2. 메모리 또는 커널 pool 압력

예측:

- Codex 프로세스가 사라진 뒤에도 commit, page-in, nonpaged/paged pool 또는 system handle이 유지된다.
- 재부팅 후 해당 값과 체감이 함께 크게 낮아진다.

약화 조건:

- 종료 전후 및 재부팅 후 값이 비슷하고 page-in도 낮다.

### H3. DWM, GPU 또는 드라이버 상태

예측:

- CPU·RAM·디스크는 정상화되지만 UI 체감과 scheduler/frame 계열 지표는 나쁘다.
- 후속 재발에서 사용자 세션, DWM 또는 장치 경계의 제한된 개입이 회복을 만든다.

약화 조건:

- 높은 CPU를 유지하는 특정 사용자 프로세스가 관측되고 그 프로세스 개입만으로 회복된다.

### H4. 열 또는 전원 제한

예측:

- 아무것도 재설정하지 않고 재부팅에 걸리는 시간만큼 기다려도 회복된다.
- 재부팅 직후의 회복이 오래 유지되지 않고 지속 부하에서 빠르게 재발한다.

약화 조건:

- 같은 시간의 wait-only 대조에서는 회복되지 않고 특정 상태 경계를 지운 뒤에만 회복된다.

### H5. 다중 요인 상호작용

예측:

- 작은 개입 A와 B는 각각 실패하지만 A+B는 재부팅 없이 회복시킨다.
- 단순한 선형 reset ladder보다 조합 개입이 결과를 더 잘 설명한다.

## 후속 개입 순서

첫 자연 run 결과를 본 뒤 별도 재발에서만 시행한다. 각 재발은 하나의 소비된 사례로 취급한다.

1. 같은 시간의 `wait-only` 대조
2. 증거로 식별한 Codex-descendant 잔류 작업자 하나만 종료
3. 식별한 Codex 사용자 공간 process tree 종료
4. Windows 로그아웃/로그인 경계
5. 증거가 가리키는 DWM·GPU·장치·서비스의 제한된 reset
6. 전체 재부팅

각 개입 전에 기대 결과와 약화 조건을 기록한다. 앞 단계가 성공했다고 원인을 확정하지 않고, 가능하면 격리 환경에서 상태를 재생성한다.

## 판정 단계

1. `observation`: 버벅임과 상태가 함께 관측됨
2. `recovery associated`: 특정 reset 뒤 회복됨
3. `minimal recovery boundary`: 더 약한 개입은 실패하고 사전 지정 개입은 반복 성공
4. `cause isolated`: 상태 조작으로 장애를 재현하고 해당 기전을 차단하면 예방됨
5. `generalized`: 다른 날·다른 작업 조합의 held-out 재발을 사전 예측

첫 run은 최대 2단계까지만 갈 수 있다. 테스트, 깨끗한 리포트 또는 재부팅 후 수치 개선만으로 3~5단계로 승격하지 않는다.

## 증거 및 실패 규칙

- `run.json`과 `snapshots/*.json`은 생성 후 수정하지 않는다.
- 모든 snapshot SHA-256은 `events.jsonl` hash chain에 기록한다.
- 중단·실패도 원장에 append하고 기존 줄을 수정하지 않는다.
- `run_closed`는 최대 한 번만 존재한다.
- invalid ledger나 snapshot hash mismatch가 있으면 분석을 fail closed한다.
- 합성 자체 테스트는 `synthetic_pipeline_validation_only`이며 실제 성능 주장에 사용하지 않는다.
