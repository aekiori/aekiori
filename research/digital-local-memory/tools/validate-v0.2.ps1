param(
    [Parameter(Mandatory = $false)]
    [string]$PlanPath,

    [Parameter(Mandatory = $false)]
    [string]$RunPath,

    [Parameter(Mandatory = $false)]
    [string]$FixturePath
)

$ErrorActionPreference = 'Stop'
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
    $FixturePath = Join-Path $scriptDirectory '..\schema\privacy-regression-fixtures.v0.2.json'
}
$errors = [System.Collections.Generic.List[string]]::new()

function Add-ContractError {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Protect-PublicText {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return $null }

    $phonePattern = '(?<!\d)(?:01[016789]|0(?:2|3[1-3]|4[1-4]|5[1-5]|6[1-4]))[\s-]?\d{3,4}[\s-]?\d{4}(?!\d)'
    $emailPattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    $protected = [regex]::Replace($Value, $phonePattern, '[business phone redacted]')
    return [regex]::Replace($protected, $emailPattern, '[email redacted]')
}

function Test-PrivacyFixtures {
    param([string]$Path)

    $fixture = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
    if ($fixture.fixture_version -ne '0.2') { Add-ContractError 'privacy fixture version must be 0.2' }
    if ($fixture.synthetic_only -ne $true) { Add-ContractError 'privacy fixtures must be synthetic_only' }

    foreach ($case in $fixture.cases) {
        $inputValue = [string]::Join([string]$case.joiner, [string[]]$case.segments)
        $actual = Protect-PublicText $inputValue
        if ($actual -cne $case.expected) {
            Add-ContractError "privacy fixture failed: $($case.fixture_id)"
        }
    }

    foreach ($case in $fixture.negative_cases) {
        $actual = Protect-PublicText ([string]$case.value)
        if ($actual -cne $case.value) {
            Add-ContractError "privacy negative fixture changed: $($case.fixture_id)"
        }
    }
}

function Test-TerminalState {
    param($Query, $Contract)

    $observations = @($Query.stabilization_observations)
    if ($observations.Count -lt 1) {
        Add-ContractError "$($Query.query_id): no stabilization observations"
        return
    }

    switch ($Query.terminal_page_state) {
        'usable_results' {
            if ($observations.Count -lt $Contract.stable_probe_count) {
                Add-ContractError "$($Query.query_id): usable_results lacks stable probes"
                break
            }
            $last = $observations[-1]
            $previous = $observations[-2]
            if ($last.visible_title_count -lt 1 -or $last.visible_title_count -ne $previous.visible_title_count) {
                Add-ContractError "$($Query.query_id): usable_results title counts are not stable and positive"
            }
            $gap = ([datetimeoffset]$last.observed_at - [datetimeoffset]$previous.observed_at).TotalMilliseconds
            if ($gap -lt $Contract.probe_interval_ms) {
                Add-ContractError "$($Query.query_id): stable probe interval is too short"
            }
        }
        'explicit_no_results' {
            if (-not ($observations | Where-Object { $_.explicit_no_results_signal -eq $true })) {
                Add-ContractError "$($Query.query_id): explicit_no_results lacks UI signal"
            }
        }
        'rewritten_or_fallback' {
            if ($Query.fallback_shown -ne $true -and $Query.suggestion_followed -ne $true) {
                Add-ContractError "$($Query.query_id): rewritten_or_fallback lacks rewrite evidence"
            }
        }
        'blocked' {
            if (-not ($observations | Where-Object { $_.blocked_signal -eq $true })) {
                Add-ContractError "$($Query.query_id): blocked lacks blocked signal"
            }
        }
        'render_timeout' {
            if ($Query.timing.stabilization_elapsed_ms -lt $Contract.max_stabilization_ms) {
                Add-ContractError "$($Query.query_id): render_timeout before wait ceiling"
            }
            if ($observations | Where-Object { $_.explicit_no_results_signal -eq $true -or $_.blocked_signal -eq $true }) {
                Add-ContractError "$($Query.query_id): render_timeout conflicts with terminal UI signal"
            }
        }
        default { Add-ContractError "$($Query.query_id): unknown terminal page state" }
    }
}

function Test-RunPrivacy {
    param($Run)

    $phonePattern = '(?<!\d)(?:01[016789]|0(?:2|3[1-3]|4[1-4]|5[1-5]|6[1-4]))[\s-]?\d{3,4}[\s-]?\d{4}(?!\d)'
    $emailPattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    $phoneCount = 0
    $emailCount = 0

    foreach ($query in @($Run.queries)) {
        foreach ($module in @($query.modules)) {
            foreach ($result in @($module.results)) {
                foreach ($field in 'title', 'url', 'snippet_excerpt', 'notes') {
                    $value = [string]$result.$field
                    if ([string]::IsNullOrEmpty($value)) { continue }
                    $phoneCount += [regex]::Matches($value, $phonePattern).Count
                    $emailCount += [regex]::Matches($value, $emailPattern).Count
                }
            }
        }
    }

    if ($phoneCount -ne 0) { Add-ContractError "public result fields contain $phoneCount phone-like strings" }
    if ($emailCount -ne 0) { Add-ContractError "public result fields contain $emailCount email-like strings" }
    if ($Run.privacy_audit.phone_like_strings_remaining -ne $phoneCount) { Add-ContractError 'privacy audit phone count mismatch' }
    if ($Run.privacy_audit.email_like_strings_remaining -ne $emailCount) { Add-ContractError 'privacy audit email count mismatch' }
    if ($Run.privacy_audit.pre_storage_filter_applied -ne $true) { Add-ContractError 'pre-storage privacy filter was not applied' }
    if ($Run.privacy_audit.post_serialization_scan_applied -ne $true) { Add-ContractError 'post-serialization privacy scan was not applied' }
    if ($Run.privacy_audit.raw_dom_export_created -ne $false) { Add-ContractError 'raw DOM export violates public run contract' }
    if ($phoneCount -eq 0 -and $emailCount -eq 0 -and $Run.privacy_audit.status -ne 'pass') {
        Add-ContractError 'privacy audit should pass when residual counts are zero'
    }
}

Test-PrivacyFixtures -Path $FixturePath

if (($PlanPath -and -not $RunPath) -or ($RunPath -and -not $PlanPath)) {
    Add-ContractError 'PlanPath and RunPath must be supplied together'
}

if ($PlanPath -and $RunPath) {
    $plan = Get-Content -Raw -Encoding UTF8 -LiteralPath $PlanPath | ConvertFrom-Json
    $run = Get-Content -Raw -Encoding UTF8 -LiteralPath $RunPath | ConvertFrom-Json

    if ($run.schema_version -ne '0.2') { Add-ContractError 'run schema_version must be 0.2' }
    if ($run.protocol_version -ne 'PILOT_PROTOCOL_V0.2') { Add-ContractError 'run protocol version mismatch' }
    if ($run.plan_id -ne $plan.plan_id) { Add-ContractError 'run plan_id does not match plan' }
    if ($run.scope_id -ne $plan.scope_id) { Add-ContractError 'run scope_id does not match plan' }

    $planQueries = @($plan.queries)
    $runQueries = @($run.queries)
    if ($planQueries.Count -ne $runQueries.Count) { Add-ContractError 'planned and actual query counts differ' }

    $actualById = @{}
    foreach ($query in $runQueries) {
        if ($actualById.ContainsKey($query.query_id)) {
            Add-ContractError "duplicate query ID: $($query.query_id)"
        } else {
            $actualById[$query.query_id] = $query
        }
        Test-TerminalState -Query $query -Contract $run.stabilization_contract

        foreach ($module in @($query.modules)) {
            if ($module.module_type -like 'NAVER_*' -and $module.rank_system -eq 'GOOGLE_ORGANIC_RANK') {
                Add-ContractError "$($query.query_id): Naver module uses Google organic rank"
            }
            if ($module.module_type -in 'GOOGLE_FALLBACK', 'NAVER_AD' -and $module.outcome_eligible -ne $false) {
                Add-ContractError "$($query.query_id): excluded module marked outcome eligible"
            }
        }
    }

    foreach ($planned in $planQueries) {
        if (-not $actualById.ContainsKey($planned.query_id)) {
            Add-ContractError "missing actual query: $($planned.query_id)"
            continue
        }
        $actual = $actualById[$planned.query_id]
        if ($actual.order -ne $planned.order) { Add-ContractError "$($planned.query_id): order mismatch" }
        if ($actual.platform -ne $planned.platform) { Add-ContractError "$($planned.query_id): platform mismatch" }
        if ($actual.knowledge_regime -ne $planned.knowledge_regime) { Add-ContractError "$($planned.query_id): regime mismatch" }
        if ($actual.bay_id -ne $planned.bay_id) { Add-ContractError "$($planned.query_id): bay mismatch" }
        if ($actual.budget_cell_id -ne $planned.budget_cell_id) { Add-ContractError "$($planned.query_id): budget cell mismatch" }
        if ($actual.planned_query -cne $planned.query) { Add-ContractError "$($planned.query_id): planned query text mismatch" }
        if ($actual.submitted_query -cne $planned.query) { Add-ContractError "$($planned.query_id): submitted query text mismatch" }
    }

    $cellById = @{}
    foreach ($cell in @($run.budget_cells)) {
        if ($cellById.ContainsKey($cell.budget_cell_id)) { Add-ContractError "duplicate budget cell: $($cell.budget_cell_id)" }
        else { $cellById[$cell.budget_cell_id] = $cell }

        if ($cell.contiguous_execution -ne $true) { Add-ContractError "$($cell.budget_cell_id): non-contiguous execution" }
        if ($cell.active_review_seconds -gt $cell.max_active_review_seconds -and $cell.status -ne 'budget_exhausted') {
            Add-ContractError "$($cell.budget_cell_id): active review exceeds budget without exhaustion status"
        }
    }

    foreach ($query in $runQueries) {
        if (-not $cellById.ContainsKey($query.budget_cell_id)) { Add-ContractError "$($query.query_id): missing budget cell"; continue }
        if ($query.query_id -notin @($cellById[$query.budget_cell_id].query_ids)) {
            Add-ContractError "$($query.query_id): absent from its budget cell query list"
        }
    }

    foreach ($bay in @($run.bay_outcomes)) {
        if ($bay.identity_status -eq 'confirmed') {
            $anchorTypes = @($bay.identity_anchors | ForEach-Object { $_.anchor_type } | Sort-Object -Unique)
            if ($anchorTypes.Count -lt 2) { Add-ContractError "$($bay.bay_id): confirmed with fewer than two anchor types" }
            if (@($bay.material_conflicts).Count -gt 0) { Add-ContractError "$($bay.bay_id): confirmed despite material conflicts" }
        }
    }

    Test-RunPrivacy -Run $run
}

$result = [pscustomobject]@{
    validation = if ($errors.Count -eq 0) { 'PASS' } else { 'FAIL' }
    fixture_version = '0.2'
    run_checked = [bool]($PlanPath -and $RunPath)
    error_count = $errors.Count
    errors = @($errors)
}

$result | ConvertTo-Json -Depth 5
if ($errors.Count -gt 0) { exit 1 }
