[CmdletBinding()]
param(
    [string]$RunDirectory,
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evidence\runs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RestartAnatomy.psm1') -Force

function Format-OptionalNumber {
    param($Value, [int]$Digits = 1)
    if ($null -eq $Value) { return 'n/a' }
    return ([math]::Round([double]$Value, $Digits)).ToString()
}

function Get-CpuAverage {
    param($Snapshot)
    if ($null -eq $Snapshot.system.cpu_pct) { return $null }
    return $Snapshot.system.cpu_pct.average
}

function Get-Rating {
    param([object[]]$Events, [string]$Phase)
    $event = $Events | Where-Object { $_.event_type -eq 'subjective_report' -and $_.data.phase -eq $Phase } | Select-Object -Last 1
    if ($null -eq $event) { return $null }
    return $event.data.slowness_0_to_10
}

function New-MetricRow {
    param(
        $Snapshot,
        [hashtable]$BaselineAffiliated,
        [object[]]$Events,
        [AllowNull()][string]$FinalPostCloseLabel
    )

    $residuals = @($Snapshot.processes | Where-Object { $BaselineAffiliated.ContainsKey([string]$_.identity_key) })
    $ratingPhase = $null
    if ($Snapshot.phase -eq 'active') { $ratingPhase = 'active' }
    elseif ($Snapshot.phase -eq 'post_reboot' -or $Snapshot.label -eq 'post-reboot') { $ratingPhase = 'post_reboot' }
    elseif ($null -ne $FinalPostCloseLabel -and $Snapshot.label -eq $FinalPostCloseLabel) { $ratingPhase = 'post_close_final' }
    $rating = $null
    if ($null -ne $ratingPhase) { $rating = Get-Rating -Events $Events -Phase $ratingPhase }

    return [pscustomobject][ordered]@{
        label = $Snapshot.label
        phase = $Snapshot.phase
        seconds_from_close = $Snapshot.seconds_from_close
        cpu_avg_pct = Get-CpuAverage -Snapshot $Snapshot
        cpu_max_pct = $(if ($null -eq $Snapshot.system.cpu_pct) { $null } else { $Snapshot.system.cpu_pct.maximum })
        available_memory_mb = $Snapshot.system.available_memory_mb
        committed_pct = $Snapshot.system.committed_bytes_in_use_pct
        nonpaged_pool_mb = $Snapshot.system.nonpaged_pool_mb
        pages_input_avg_per_sec = $(if ($null -eq $Snapshot.system.pages_input_per_sec) { $null } else { $Snapshot.system.pages_input_per_sec.average })
        disk_time_avg_pct = $(if ($null -eq $Snapshot.system.disk_time_pct) { $null } else { $Snapshot.system.disk_time_pct.average })
        scheduler_p99_overshoot_ms = $Snapshot.system.scheduler_jitter.p99_overshoot_ms
        all_process_count = $Snapshot.process_summary.all.process_count
        all_handle_count = $Snapshot.process_summary.all.handle_count
        codex_affiliated_count = $Snapshot.process_summary.codex_affiliated.process_count
        codex_affiliated_cpu_pct = $Snapshot.process_summary.codex_affiliated.cpu_pct_total_capacity
        codex_affiliated_private_mb = $Snapshot.process_summary.codex_affiliated.private_mb
        baseline_codex_affiliated_still_alive_count = $residuals.Count
        baseline_codex_affiliated_still_alive_cpu_pct = [math]::Round([double](($residuals | Measure-Object cpu_pct_total_capacity -Sum).Sum), 3)
        baseline_codex_affiliated_still_alive_private_mb = [math]::Round([double](($residuals | Measure-Object private_bytes -Sum).Sum) / 1MB, 3)
        subjective_slowness_0_to_10 = $rating
        collection_error_count = @($Snapshot.collection_errors).Count
    }
}

if ([string]::IsNullOrWhiteSpace($RunDirectory)) {
    $latest = Get-ChildItem -LiteralPath $OutputRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'run.json')
    } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $latest) {
        throw "No Restart Anatomy run found under $OutputRoot"
    }
    $RunDirectory = $latest.FullName
}

$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$run = Get-Content -Raw -Encoding UTF8 (Join-Path $RunDirectory 'run.json') | ConvertFrom-Json
$ledger = Test-RestartAnatomyLedger -RunDirectory $RunDirectory
if (-not $ledger.valid) {
    throw "Ledger validation failed: $($ledger.error)"
}

$integrityErrors = New-Object System.Collections.Generic.List[string]
$snapshotEvents = @($ledger.events | Where-Object { $_.event_type -eq 'snapshot_recorded' })
foreach ($event in $snapshotEvents) {
    $relative = ([string]$event.data.file).Replace('/', [IO.Path]::DirectorySeparatorChar)
    $path = Join-Path $RunDirectory $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $integrityErrors.Add("missing_snapshot: $relative")
        continue
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne [string]$event.data.sha256) {
        $integrityErrors.Add("snapshot_hash_mismatch: $relative")
    }
}
if ($integrityErrors.Count -gt 0) {
    throw "Snapshot integrity validation failed: $($integrityErrors -join '; ')"
}

$snapshotFiles = @(Get-ChildItem -LiteralPath (Join-Path $RunDirectory 'snapshots') -Filter '*.json' -File | Sort-Object Name)
if ($snapshotFiles.Count -eq 0) {
    throw 'Run contains no snapshots.'
}
$snapshots = @($snapshotFiles | ForEach-Object { Get-Content -Raw -Encoding UTF8 $_.FullName | ConvertFrom-Json })
$baseline = $snapshots | Where-Object { $_.label -eq 'active-baseline' } | Select-Object -First 1
if ($null -eq $baseline) { $baseline = $snapshots[0] }
$postClose = @($snapshots | Where-Object { $_.label -like 'post-close-*' })
$lastPostClose = $postClose | Select-Object -Last 1
$postReboot = $snapshots | Where-Object { $_.label -eq 'post-reboot' } | Select-Object -Last 1

$baselineAffiliated = @{}
foreach ($process in @($baseline.processes | Where-Object { $_.codex_relation -ne 'unrelated_or_unattributed' })) {
    $baselineAffiliated[[string]$process.identity_key] = $process
}
$finalPostCloseLabel = $null
if ($null -ne $lastPostClose) { $finalPostCloseLabel = [string]$lastPostClose.label }
$rows = @($snapshots | ForEach-Object { New-MetricRow -Snapshot $_ -BaselineAffiliated $baselineAffiliated -Events $ledger.events -FinalPostCloseLabel $finalPostCloseLabel })

$residualsAtFinalClose = @()
if ($null -ne $lastPostClose) {
    $residualsAtFinalClose = @($lastPostClose.processes | Where-Object { $baselineAffiliated.ContainsKey([string]$_.identity_key) } | Sort-Object cpu_pct_total_capacity -Descending)
}
$rebootEvent = $ledger.events | Where-Object { $_.event_type -eq 'reboot_boundary_evaluated' } | Select-Object -Last 1
$rebootVerified = $false
if ($null -ne $rebootEvent) { $rebootVerified = [bool]$rebootEvent.data.verified }

$observations = New-Object System.Collections.Generic.List[string]
if ($null -eq $lastPostClose) {
    $observations.Add('No post-close snapshot exists; the run cannot test persistence after the Codex window closes.')
}
else {
    if ($residualsAtFinalClose.Count -gt 0) {
        $observations.Add("$($residualsAtFinalClose.Count) process identities that were Codex-affiliated at baseline were still alive in the final post-close snapshot.")
    }
    else {
        $observations.Add('No baseline Codex-affiliated process identity remained alive in the final post-close snapshot.')
    }
    $cpu = Get-CpuAverage -Snapshot $lastPostClose
    if ($null -ne $cpu) {
        $observations.Add("Final post-close system CPU averaged $([math]::Round([double]$cpu, 1))% during the bounded sample.")
    }
}
if ($null -eq $postReboot) {
    $observations.Add('No post-reboot snapshot exists yet; reboot-associated recovery is unmeasured.')
}
elseif ($rebootVerified) {
    $observations.Add('The post-reboot snapshot crossed a verified boot-time boundary.')
    if ($null -ne $lastPostClose) {
        $beforeCpu = Get-CpuAverage -Snapshot $lastPostClose
        $afterCpu = Get-CpuAverage -Snapshot $postReboot
        if ($null -ne $beforeCpu -and $null -ne $afterCpu) {
            $observations.Add("Bounded CPU average changed from $([math]::Round([double]$beforeCpu, 1))% before reboot to $([math]::Round([double]$afterCpu, 1))% after reboot.")
        }
    }
}
else {
    $observations.Add('A post-reboot-labelled snapshot exists, but the boot-time boundary was not verified; it cannot support a reboot claim.')
}

$claimCeiling = 'incomplete_observation'
if ([bool]$run.synthetic) {
    $claimCeiling = 'synthetic_pipeline_validation_only'
}
elseif ($null -ne $lastPostClose -and $null -eq $postReboot) {
    $claimCeiling = 'post_close_persistence_observation_only'
}
elseif ($null -ne $lastPostClose -and $null -ne $postReboot -and $rebootVerified) {
    $claimCeiling = 'reboot_associated_recovery_observation_not_root_cause'
}

$analysis = [ordered]@{
    schema_version = 'restart-anatomy-analysis-v1'
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    run_id = $run.run_id
    synthetic = [bool]$run.synthetic
    ledger_valid = [bool]$ledger.valid
    ledger_event_count = $ledger.event_count
    snapshot_count = $snapshots.Count
    snapshot_hashes_valid = $true
    reboot_verified = $rebootVerified
    claim_ceiling = $claimCeiling
    observations = @($observations)
    metrics = $rows
    final_post_close_residuals = @($residualsAtFinalClose | Select-Object -First 30 | ForEach-Object {
        [pscustomobject][ordered]@{
            name = $_.name
            process_id = $_.process_id
            parent_process_id = $_.parent_process_id
            baseline_relation = $baselineAffiliated[[string]$_.identity_key].codex_relation
            current_relation = $_.codex_relation
            cpu_pct_total_capacity = $_.cpu_pct_total_capacity
            private_mb = $(if ($null -eq $_.private_bytes) { $null } else { [math]::Round([double]$_.private_bytes / 1MB, 3) })
            handle_count = $_.handle_count
            thread_count = $_.thread_count
            executable_path = $_.executable_path
        }
    })
    limitations = @(
        'Association with Codex is based on executable path and point-in-time parent lineage, not command-line inspection.',
        'A surviving process plus high resource use is evidence of persistence, not proof that it caused perceived lag.',
        'Reboot changes many variables simultaneously; pre/post recovery alone does not isolate a root cause.',
        'Scheduler sleep overshoot is a coarse responsiveness proxy, not direct UI input-to-frame latency.',
        'Threshold-free descriptive output is intentional in V0.1; causal labels require later controlled interventions.'
    )
}

$jsonPath = Join-Path $RunDirectory 'analysis.json'
$mdPath = Join-Path $RunDirectory 'analysis.md'
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jsonPath, ($analysis | ConvertTo-Json -Depth 24), $encoding)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Restart Anatomy analysis: $($run.run_id)")
$lines.Add('')
$lines.Add("- Claim ceiling: ``$claimCeiling``")
$lines.Add("- Synthetic: ``$([bool]$run.synthetic)``")
$lines.Add("- Ledger: valid, $($ledger.event_count) events")
$lines.Add("- Snapshots: $($snapshots.Count), all ledger-bound hashes valid")
$lines.Add("- Reboot verified: ``$rebootVerified``")
$lines.Add('')
$lines.Add('## Observations')
$lines.Add('')
foreach ($observation in $observations) { $lines.Add("- $observation") }
$lines.Add('')
$lines.Add('## Measurements')
$lines.Add('')
$lines.Add('| Snapshot | Phase | +seconds | CPU avg % | Available MB | Commit % | Jitter p99 ms | Processes | Codex-affiliated | Codex private MB | Baseline Codex IDs alive | Slowness 0-10 |')
$lines.Add('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
foreach ($row in $rows) {
    $lines.Add('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} |' -f @(
        $row.label,
        $row.phase,
        (Format-OptionalNumber $row.seconds_from_close 1),
        (Format-OptionalNumber $row.cpu_avg_pct 1),
        (Format-OptionalNumber $row.available_memory_mb 0),
        (Format-OptionalNumber $row.committed_pct 1),
        (Format-OptionalNumber $row.scheduler_p99_overshoot_ms 2),
        $row.all_process_count,
        $row.codex_affiliated_count,
        (Format-OptionalNumber $row.codex_affiliated_private_mb 1),
        $row.baseline_codex_affiliated_still_alive_count,
        (Format-OptionalNumber $row.subjective_slowness_0_to_10 0)
    ))
}

$lines.Add('')
$lines.Add('## Final post-close residual identities')
$lines.Add('')
if ($residualsAtFinalClose.Count -eq 0) {
    $lines.Add('None observed, or no final post-close snapshot exists.')
}
else {
    $lines.Add('| Name | PID | Baseline relation | Current relation | CPU % | Private MB | Handles | Threads |')
    $lines.Add('|---|---:|---|---|---:|---:|---:|---:|')
    foreach ($process in @($analysis.final_post_close_residuals)) {
        $lines.Add('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f @(
            $process.name,
            $process.process_id,
            $process.baseline_relation,
            $process.current_relation,
            (Format-OptionalNumber $process.cpu_pct_total_capacity 2),
            (Format-OptionalNumber $process.private_mb 1),
            $process.handle_count,
            $process.thread_count
        ))
    }
}

$lines.Add('')
$lines.Add('## Claim boundary')
$lines.Add('')
$lines.Add('This report can establish bounded persistence and reboot-associated recovery. It cannot name a root cause until a later recurrence includes a discriminating minimal intervention or controlled reproduction.')
$lines.Add('')
$lines.Add('Generated files are derived analysis. Immutable snapshots and the hash-chained event ledger remain the evidence authority.')
[System.IO.File]::WriteAllText($mdPath, ($lines -join [Environment]::NewLine), $encoding)

Write-Host "Analysis written: $mdPath" -ForegroundColor Green
Write-Host "Claim ceiling: $claimCeiling" -ForegroundColor Cyan
