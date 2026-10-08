[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Ra {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $PSScriptRoot 'RestartAnatomy.psm1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('restart-anatomy-selftest-' + [guid]::NewGuid().ToString('N'))
$resolvedTempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())

try {
    Write-Host '1/6 Parsing PowerShell sources...'
    foreach ($file in @(Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') })) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert-Ra -Condition (@($parseErrors).Count -eq 0) -Message "$($file.Name) has parser errors: $($parseErrors -join '; ')"
    }

    Write-Host '2/6 Importing module and creating synthetic run...'
    Import-Module $modulePath -Force
    $run = New-RestartAnatomyRun -OutputRoot $tempRoot -Synthetic
    Assert-Ra -Condition (Test-Path -LiteralPath (Join-Path $run.run_directory 'run.json')) -Message 'run.json was not created'

    Write-Host '3/6 Capturing one real read-only snapshot...'
    $baseline = New-RestartAnatomySnapshot -RunId $run.run_id -Label 'active-baseline' -Phase 'synthetic' -Synthetic
    Assert-Ra -Condition (@($baseline.processes).Count -gt 0) -Message 'process inventory is empty'
    Assert-Ra -Condition (@($baseline.processes | Where-Object { $_.name -eq 'powershell' }).Count -gt 0) -Message 'current PowerShell process was not observed'
    $baselineJson = $baseline | ConvertTo-Json -Depth 24
    Assert-Ra -Condition ($baselineJson -notmatch 'command_line') -Message 'snapshot unexpectedly contains command-line data'
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
        Assert-Ra -Condition ($baselineJson -notmatch [regex]::Escape($userProfile)) -Message 'snapshot contains an unsanitized user-profile path'
    }
    Write-RestartAnatomySnapshot -RunDirectory $run.run_directory -Snapshot $baseline | Out-Null

    Write-Host '4/6 Building synthetic close/reboot phases and ledger...'
    Add-RestartAnatomyEvent -RunDirectory $run.run_directory -EventType 'close_marker' -Data ([ordered]@{ trigger = 'synthetic_test' }) | Out-Null
    $postClose = $baseline | ConvertTo-Json -Depth 24 | ConvertFrom-Json
    $postClose.label = 'post-close-0000s'
    $postClose.phase = 'synthetic'
    $postClose.seconds_from_close = 0
    $postClose.synthetic = $true
    Write-RestartAnatomySnapshot -RunDirectory $run.run_directory -Snapshot $postClose | Out-Null
    Add-RestartAnatomyEvent -RunDirectory $run.run_directory -EventType 'awaiting_reboot' -Data ([ordered]@{ synthetic = $true }) | Out-Null

    & (Join-Path $PSScriptRoot 'capture-post-reboot.ps1') -OutputRoot $tempRoot -RunId $run.run_id -SelfTest -NonInteractive -AllowSameBoot

    Write-Host '5/6 Validating immutable evidence and analysis output...'
    $ledger = Test-RestartAnatomyLedger -RunDirectory $run.run_directory
    Assert-Ra -Condition $ledger.valid -Message "ledger is invalid: $($ledger.error)"
    Assert-Ra -Condition (@($ledger.events | Where-Object { $_.event_type -eq 'run_closed' }).Count -eq 1) -Message 'ledger does not contain exactly one closure'
    Assert-Ra -Condition (Test-Path -LiteralPath (Join-Path $run.run_directory 'analysis.json')) -Message 'analysis.json was not created'
    Assert-Ra -Condition (Test-Path -LiteralPath (Join-Path $run.run_directory 'analysis.md')) -Message 'analysis.md was not created'
    $analysis = Get-Content -Raw -Encoding UTF8 (Join-Path $run.run_directory 'analysis.json') | ConvertFrom-Json
    Assert-Ra -Condition ($analysis.claim_ceiling -eq 'synthetic_pipeline_validation_only') -Message 'synthetic claim ceiling was not enforced'

    Write-Host '6/6 Proving ledger tamper detection...'
    $tamperDirectory = Join-Path $tempRoot 'tampered-ledger'
    New-Item -ItemType Directory -Path $tamperDirectory -Force | Out-Null
    $ledgerText = Get-Content -Raw -Encoding UTF8 (Join-Path $run.run_directory 'events.jsonl')
    $tampered = $ledgerText -replace 'run_created', 'run_createx'
    [IO.File]::WriteAllText((Join-Path $tamperDirectory 'events.jsonl'), $tampered, (New-Object Text.UTF8Encoding($false)))
    $tamperResult = Test-RestartAnatomyLedger -RunDirectory $tamperDirectory
    Assert-Ra -Condition (-not $tamperResult.valid) -Message 'tampered ledger incorrectly validated'

    Write-Host ''
    Write-Host 'PASS: Restart Anatomy synthetic pipeline validation succeeded.' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTarget = [IO.Path]::GetFullPath($tempRoot)
        $leaf = Split-Path -Leaf $resolvedTarget
        if ($resolvedTarget.StartsWith($resolvedTempBase, [StringComparison]::OrdinalIgnoreCase) -and $leaf.StartsWith('restart-anatomy-selftest-', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
        }
        else {
            Write-Warning "Self-test cleanup refused for unexpected path: $resolvedTarget"
        }
    }
}
