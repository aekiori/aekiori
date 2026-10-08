# CAL-0002 V0.3 validation

## Result

- V0.3 custom validator: `PASS`
- Planned/actual query count: `20 / 20`
- Unique query IDs: `20`
- Budget cells: `14`
- Entity hypotheses/outcomes: `4 / 4`
- Duplicate result IDs: `0`
- Unresolved identity-anchor source IDs: `0`
- Supplemental checks marked outcome-eligible: `0`
- Public phone-like strings: `0`
- Public email-like strings: `0`
- Raw DOM export: `false`
- Second blind reader: `pending`
- Run status: `SINGLE_READER_PASS_SECOND_READER_PENDING`

Validation command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File research\digital-local-memory\tools\validate-v0.3.ps1 `
  -PlanPath research\digital-local-memory\protocol\cal-0002-query-plan.v0.3.json `
  -RunPath research\digital-local-memory\evidence\CAL-0002\dry-run-v03\retrieval-run.json
```

Returned:

```text
validation: PASS
protocol_version: 0.3
fixture_version: 0.2
run_checked: true
error_count: 0
```

## Frozen upstream receipts

| Receipt | SHA-256 |
|---|---|
| V0.3 protocol freeze manifest | `95C7A872A02A3F6345CBBF8D993CD46E2550030DEDE08802EEF8F5DC1C16511F` |
| CAL-0002 query-plan freeze manifest | `C2EDEF8A8A3D39A819C227EF306462455B1EA032EA1608EA97751B2329773E12` |
| CAL-0002 scope freeze manifest | `EC9C6D3D97B13E79B061E204320AB5F7454FDAEFDEFE3E74B5B2B239628346C6` |
| 2015-07 facade JPEG | `AD14A2DE99FF5594EDF09E3708D05BF32D3737F1187EEB940E6BF1C04E6F15B2` |

## Core artifact hashes before run-manifest creation

| File | Bytes | SHA-256 |
|---|---:|---|
| `retrieval-run.json` | 136569 | `CF492CD9FEE7CD8328DB6C43C7BA17F417B6820C2E35AF6A79FEC855ECF5E268` |
| `supplemental-source-checks.json` | 6587 | `42D8AB658945FE871BEDD8AAA2E3EB65E81A2F6B7CFD500F71CBB8C5110B8D44` |
| `FINDINGS.md` | 7370 | `18205F740BCBB7364F8F2F38868A20C518E013BB49A926657326C0EB2268EDE2` |
| `EXECUTION_DEVIATIONS.md` | 2685 | `5AC52D23450CA4732B903E43C0DFC4F11A8520DE28EBDFC4DADBDFAA98DF421D` |

## What this validation does not establish

- The custom PowerShell validator checks the run/plan contract, terminal probes, entity/bay references, budget membership, module rank rules, privacy fixtures, and public-result phone/email absence.
- No independent third-party Draft 2020-12 JSON Schema implementation was available in the workspace. Full standards-conformance validation against `retrieval-run.v0.3.schema.json` therefore remains `unverified`.
- `active_review_seconds` are bounded manual reconstructions, not automatically measured exact durations.
- Validator success is not evidence of causal isolation, historical continuity, current business operation, or generalizability.
- The run cannot be promoted until a second blind reader adjudicates page state and entity identity outcomes.

