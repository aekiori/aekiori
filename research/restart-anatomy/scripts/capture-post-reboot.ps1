[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evidence\runs'),
    [string]$RunId,
    [switch]$AllowSameBoot,
    [switch]$NonInteractive,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RestartAnatomy.psm1') -Force

function Read-OptionalRating {
    if ($NonInteractive -or $SelfTest) {
        return $null
    }
    while ($true) {
        $raw = Read-Host 'Current machine slowness after reboot [0-10, Enter to skip]'
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        $value = 0
        if ([int]::TryParse($raw, [ref]$value) -and $value -ge 0 -and $value -le 10) {
            return $value
        }
        Write-Host 'Enter an integer from 0 to 10, or press Enter to skip.' -ForegroundColor Yellow
    }
}

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    throw "Evidence root does not exist: $OutputRoot"
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $pending = Get-RestartAnatomyLatestPendingRun -OutputRoot $OutputRoot
    if ($null -eq $pending) {
        throw 'No valid run awaiting a post-reboot capture was found.'
    }
    $runDirectory = $pending.FullName
}
else {
    $runDirectory = Join-Path $OutputRoot $RunId
    if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) {
        throw "Run not found: $runDirectory"
    }
}

$run = Get-Content -Raw -Encoding UTF8 (Join-Path $runDirectory 'run.json') | ConvertFrom-Json
$ledger = Test-RestartAnatomyLedger -RunDirectory $runDirectory
if (-not $ledger.valid) {
    throw "Ledger validation failed: $($ledger.error)"
}
if (@($ledger.events | Where-Object { $_.event_type -eq 'run_closed' }).Count -gt 0) {
    throw 'This run is already closed.'
}

$snapshotFiles = @(Get-ChildItem -LiteralPath (Join-Path $runDirectory 'snapshots') -Filter '*.json' -File | Sort-Object Name)
if ($snapshotFiles.Count -eq 0) {
    throw 'The pending run has no pre-reboot snapshot.'
}
$preRebootSnapshots = @($snapshotFiles | ForEach-Object {
    $candidate = Get-Content -Raw -Encoding UTF8 $_.FullName | ConvertFrom-Json
    if ($candidate.label -ne 'post-reboot') { $candidate }
})
if ($preRebootSnapshots.Count -eq 0) {
    throw 'The pending run has no usable pre-reboot snapshot.'
}
$beforeSnapshot = $preRebootSnapshots[-1]

Write-Host "Run: $($run.run_id)" -ForegroundColor Cyan
Write-Host 'Capturing post-reboot state (up to about 20 seconds)...'
$afterSnapshot = New-RestartAnatomySnapshot -RunId $run.run_id -Label 'post-reboot' -Phase $(if ($SelfTest) { 'synthetic' } else { 'post_reboot' }) -Synthetic:$SelfTest
$boundary = Test-RestartAnatomyRebootBoundary -BeforeSnapshot $beforeSnapshot -AfterSnapshot $afterSnapshot
$sameBootAllowed = $AllowSameBoot -or $SelfTest -or [bool]$run.synthetic

if (-not $boundary.verified -and -not $sameBootAllowed) {
    Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'post_reboot_check_rejected' -Data ([ordered]@{
        reason = $boundary.reason
        boot_time_delta_seconds = $boundary.boot_time_delta_seconds
        snapshot_not_persisted = $true
    }) | Out-Null
    Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'awaiting_reboot' -Message 'Post-reboot capture was rejected because a new boot was not verified.'
    throw 'A new boot was not verified. Reboot normally, then run this launcher again.'
}

$snapshotPath = Write-RestartAnatomySnapshot -RunDirectory $runDirectory -Snapshot $afterSnapshot
Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'reboot_boundary_evaluated' -Data ([ordered]@{
    verified = [bool]$boundary.verified
    reason = $boundary.reason
    boot_time_delta_seconds = $boundary.boot_time_delta_seconds
    same_boot_allowed_for_test = [bool](-not $boundary.verified -and $sameBootAllowed)
}) | Out-Null

$rating = Read-OptionalRating
if ($null -ne $rating) {
    Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'subjective_report' -Data ([ordered]@{
        phase = 'post_reboot'
        slowness_0_to_10 = $rating
    }) | Out-Null
}

Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'run_closed' -Data ([ordered]@{
    outcome = $(if ($boundary.verified) { 'post_reboot_capture_complete' } else { 'synthetic_same_boot_capture_complete' })
    reboot_verified = [bool]$boundary.verified
}) | Out-Null
Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'closed_complete' -Message 'Post-reboot capture recorded and run closed.'

Write-Host "Post-reboot snapshot saved: $snapshotPath" -ForegroundColor Green
$analysisScript = Join-Path $PSScriptRoot 'analyze-run.ps1'
if (Test-Path -LiteralPath $analysisScript) {
    & $analysisScript -RunDirectory $runDirectory
}
