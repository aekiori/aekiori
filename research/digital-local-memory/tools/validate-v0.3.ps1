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

function Add-ErrorItem {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Protect-PublicText {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return $null }
    $phonePattern = '(?<!\d)(?:01[016789]|0(?:2|3[1-3]|4[1-4]|5[1-5]|6[1-4]))[\s-]?\d{3,4}[\s-]?\d{4}(?!\d)'
    $emailPattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    $value = [regex]::Replace($Value, $phonePattern, '[business phone redacted]')
    return [regex]::Replace($Value, $emailPattern, '[email redacted]')
}

function Test-PrivacyFixture {
    $fixture = Get-Content -Raw -Encoding UTF8 -LiteralPath $FixturePath | ConvertFrom-Json
    if ($fixture.fixture_version -ne '0.2' -or $fixture.synthetic_only -ne $true) {
        Add-ErrorItem 'privacy fixture identity mismatch'
    }
    foreach ($case in @($fixture.cases)) {
        $inputValue = [string]::Join([string]$case.joiner, [string[]]$case.segments)
        if ((Protect-PublicText $inputValue) -cne $case.expected) {
            Add-ErrorItem "privacy fixture failed: $($case.fixture_id)"
        }
    }
    foreach ($case in @($fixture.negative_cases)) {
        if ((Protect-PublicText ([string]$case.value)) -cne $case.value) {
            Add-ErrorItem "privacy negative fixture changed: $($case.fixture_id)"
        }
    }
}

function Test-TerminalState {
    param($Query, $Contract)
    $observations = @($Query.stabilization_observations)
    if ($observations.Count -lt 1) { Add-ErrorItem "$($Query.query_id): no probes"; return }

    switch ($Query.terminal_page_state) {
        'usable_results' {
            if ($observations.Count -lt $Contract.stable_probe_count) {
                Add-ErrorItem "$($Query.query_id): insufficient stable probes"
                break
            }
            $a = $observations[-2]
            $b = $observations[-1]
            if ($a.visible_title_count -lt 1 -or $a.visible_title_count -ne $b.visible_title_count) {
                Add-ErrorItem "$($Query.query_id): unstable or zero title count"
            }
            if (([datetimeoffset]$b.observed_at - [datetimeoffset]$a.observed_at).TotalMilliseconds -lt $Contract.probe_interval_ms) {
                Add-ErrorItem "$($Query.query_id): probe interval too short"
            }
        }
        'explicit_no_results' {
            if (-not ($observations | Where-Object { $_.explicit_no_results_signal -eq $true })) {
                Add-ErrorItem "$($Query.query_id): missing explicit-no-result signal"
            }
        }
        'rewritten_or_fallback' {
            if ($Query.fallback_shown -ne $true -and $Query.suggestion_followed -ne $true) {
                Add-ErrorItem "$($Query.query_id): missing rewrite evidence"
            }
        }
        'blocked' {
            if (-not ($observations | Where-Object { $_.blocked_signal -eq $true })) {
                Add-ErrorItem "$($Query.query_id): missing blocked signal"
            }
        }
        'render_timeout' {
            if ($Query.timing.stabilization_elapsed_ms -lt $Contract.max_stabilization_ms) {
                Add-ErrorItem "$($Query.query_id): render timeout before ceiling"
            }
            if ($observations | Where-Object { $_.explicit_no_results_signal -eq $true -or $_.blocked_signal -eq $true }) {
                Add-ErrorItem "$($Query.query_id): render timeout conflicts with UI signal"
            }
        }
        default { Add-ErrorItem "$($Query.query_id): unknown terminal state" }
    }
}

function Test-PublicResultPrivacy {
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
    if ($phoneCount -ne 0) { Add-ErrorItem "public result fields contain $phoneCount phone-like strings" }
    if ($emailCount -ne 0) { Add-ErrorItem "public result fields contain $emailCount email-like strings" }
    if ($Run.privacy_audit.phone_like_strings_remaining -ne $phoneCount) { Add-ErrorItem 'privacy phone count mismatch' }
    if ($Run.privacy_audit.email_like_strings_remaining -ne $emailCount) { Add-ErrorItem 'privacy email count mismatch' }
    if ($Run.privacy_audit.pre_storage_filter_applied -ne $true -or $Run.privacy_audit.post_serialization_scan_applied -ne $true) {
        Add-ErrorItem 'required privacy scan stage missing'
    }
    if ($Run.privacy_audit.raw_dom_export_created -ne $false) { Add-ErrorItem 'raw DOM export forbidden' }
    if ($phoneCount -eq 0 -and $emailCount -eq 0 -and $Run.privacy_audit.status -ne 'pass') {
        Add-ErrorItem 'privacy status should be pass'
    }
}

Test-PrivacyFixture

if (($PlanPath -and -not $RunPath) -or ($RunPath -and -not $PlanPath)) {
    Add-ErrorItem 'PlanPath and RunPath must be supplied together'
}

if ($PlanPath -and $RunPath) {
    $plan = Get-Content -Raw -Encoding UTF8 -LiteralPath $PlanPath | ConvertFrom-Json
    $run = Get-Content -Raw -Encoding UTF8 -LiteralPath $RunPath | ConvertFrom-Json

    if ($run.schema_version -ne '0.3') { Add-ErrorItem 'run schema_version must be 0.3' }
    if ($run.protocol_version -ne 'PILOT_PROTOCOL_V0.3') { Add-ErrorItem 'run protocol_version mismatch' }
    if ($run.plan_id -ne $plan.plan_id -or $run.scope_id -ne $plan.scope_id) { Add-ErrorItem 'run/plan identity mismatch' }

    $entityById = @{}
    foreach ($entity in @($run.entity_hypotheses)) {
        if ($entityById.ContainsKey($entity.entity_id)) { Add-ErrorItem "duplicate entity: $($entity.entity_id)" }
        else { $entityById[$entity.entity_id] = $entity }
    }

    $bayById = @{}
    foreach ($bay in @($run.bay_outcomes)) {
        if ($bayById.ContainsKey($bay.bay_id)) { Add-ErrorItem "duplicate bay: $($bay.bay_id)" }
        else { $bayById[$bay.bay_id] = $bay }
        foreach ($entityId in @($bay.entity_ids)) {
            if (-not $entityById.ContainsKey($entityId)) { Add-ErrorItem "$($bay.bay_id): unknown entity $entityId" }
        }
    }
    foreach ($entity in @($run.entity_hypotheses)) {
        foreach ($bayId in @($entity.bay_ids)) {
            if (-not $bayById.ContainsKey($bayId)) { Add-ErrorItem "$($entity.entity_id): unknown bay $bayId"; continue }
            if ($entity.entity_id -notin @($bayById[$bayId].entity_ids)) { Add-ErrorItem "$($entity.entity_id): asymmetric bay/entity link" }
        }
    }

    $topOutcomeByEntity = @{}
    foreach ($outcome in @($run.entity_outcomes)) {
        if (-not $entityById.ContainsKey($outcome.entity_id)) { Add-ErrorItem "outcome for unknown entity: $($outcome.entity_id)" }
        if ($topOutcomeByEntity.ContainsKey($outcome.entity_id)) { Add-ErrorItem "duplicate top entity outcome: $($outcome.entity_id)" }
        else { $topOutcomeByEntity[$outcome.entity_id] = $outcome }
        if ($outcome.identity_status -eq 'confirmed') {
            $anchorTypes = @($outcome.identity_anchors | ForEach-Object { $_.anchor_type } | Sort-Object -Unique)
            if ($anchorTypes.Count -lt 2) { Add-ErrorItem "$($outcome.entity_id): confirmed with fewer than two anchor types" }
            if (@($outcome.material_conflicts).Count -gt 0) { Add-ErrorItem "$($outcome.entity_id): confirmed despite material conflict" }
        }
    }
    foreach ($entityId in $entityById.Keys) {
        if (-not $topOutcomeByEntity.ContainsKey($entityId)) { Add-ErrorItem "missing top entity outcome: $entityId" }
    }

    $actualById = @{}
    foreach ($query in @($run.queries)) {
        if ($actualById.ContainsKey($query.query_id)) { Add-ErrorItem "duplicate query: $($query.query_id)" }
        else { $actualById[$query.query_id] = $query }
        Test-TerminalState -Query $query -Contract $run.stabilization_contract

        if ($query.knowledge_regime -eq 'K0' -and @($query.target_entity_ids).Count -ne 0) {
            Add-ErrorItem "$($query.query_id): K0 must not target an entity"
        }
        if ($query.knowledge_regime -in 'K1','K2' -and @($query.target_entity_ids).Count -lt 1) {
            Add-ErrorItem "$($query.query_id): K1/K2 lacks entity target"
        }
        foreach ($entityId in @($query.target_entity_ids)) {
            if (-not $entityById.ContainsKey($entityId)) { Add-ErrorItem "$($query.query_id): unknown target entity $entityId" }
        }
        foreach ($entityOutcome in @($query.entity_outcomes)) {
            if (-not $entityById.ContainsKey($entityOutcome.entity_id)) { Add-ErrorItem "$($query.query_id): outcome for unknown entity" }
        }
        foreach ($module in @($query.modules)) {
            if ($module.module_type -like 'NAVER_*' -and $module.rank_system -eq 'GOOGLE_ORGANIC_RANK') {
                Add-ErrorItem "$($query.query_id): Naver module has Google rank"
            }
            if ($module.module_type -in 'GOOGLE_FALLBACK','NAVER_AD' -and $module.outcome_eligible -ne $false) {
                Add-ErrorItem "$($query.query_id): excluded module marked eligible"
            }
        }
    }

    $planQueries = @($plan.queries)
    if ($planQueries.Count -ne @($run.queries).Count) { Add-ErrorItem 'planned/actual query count mismatch' }
    foreach ($planned in $planQueries) {
        if (-not $actualById.ContainsKey($planned.query_id)) { Add-ErrorItem "missing query: $($planned.query_id)"; continue }
        $actual = $actualById[$planned.query_id]
        foreach ($field in 'order','platform','knowledge_regime','bay_id','budget_cell_id') {
            if ($actual.$field -ne $planned.$field) { Add-ErrorItem "$($planned.query_id): $field mismatch" }
        }
        if ($actual.planned_query -cne $planned.query -or $actual.submitted_query -cne $planned.query) {
            Add-ErrorItem "$($planned.query_id): query text mismatch"
        }
        $plannedTargets = @($planned.target_entity_ids | Sort-Object)
        $actualTargets = @($actual.target_entity_ids | Sort-Object)
        if (($plannedTargets -join '|') -cne ($actualTargets -join '|')) { Add-ErrorItem "$($planned.query_id): target entity mismatch" }
    }

    $cellById = @{}
    foreach ($cell in @($run.budget_cells)) {
        if ($cellById.ContainsKey($cell.budget_cell_id)) { Add-ErrorItem "duplicate budget cell: $($cell.budget_cell_id)" }
        else { $cellById[$cell.budget_cell_id] = $cell }
        if ($cell.contiguous_execution -ne $true) { Add-ErrorItem "$($cell.budget_cell_id): execution not contiguous" }
        if ($cell.active_review_seconds -gt $cell.max_active_review_seconds -and $cell.status -ne 'budget_exhausted') {
            Add-ErrorItem "$($cell.budget_cell_id): budget exceeded without status"
        }
    }
    foreach ($query in @($run.queries)) {
        if (-not $cellById.ContainsKey($query.budget_cell_id)) { Add-ErrorItem "$($query.query_id): missing budget cell"; continue }
        if ($query.query_id -notin @($cellById[$query.budget_cell_id].query_ids)) { Add-ErrorItem "$($query.query_id): absent from budget cell" }
    }

    Test-PublicResultPrivacy -Run $run
}

[pscustomobject]@{
    validation = if ($errors.Count -eq 0) { 'PASS' } else { 'FAIL' }
    protocol_version = '0.3'
    fixture_version = '0.2'
    run_checked = [bool]($PlanPath -and $RunPath)
    error_count = $errors.Count
    errors = @($errors)
} | ConvertTo-Json -Depth 5

if ($errors.Count -gt 0) { exit 1 }
