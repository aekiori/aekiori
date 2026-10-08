[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evidence\runs'),
    [ValidateRange(1, 30)][int]$PollSeconds = 1,
    [ValidateRange(1, 60)][int]$CloseStableSeconds = 5,
    [ValidateRange(1, 1440)][int]$MaxWaitMinutes = 240,
    [int[]]$PostCloseOffsetsSeconds = @(0, 30, 120, 600),
    [switch]$NonInteractive,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RestartAnatomy.psm1') -Force

function Read-OptionalRating {
    param([string]$Prompt)

    if ($NonInteractive -or $SelfTest) {
        return $null
    }
    while ($true) {
        $raw = Read-Host "$Prompt [0-10, Enter to skip]"
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

function Read-TimedOptionalRating {
    param(
        [string]$Prompt,
        [int]$TimeoutSeconds = 30
    )

    if ($NonInteractive -or $SelfTest) {
        return $null
    }
    Write-Host "$Prompt [0-9, A=10, Enter/S=skip; auto-skip in $TimeoutSeconds seconds]" -ForegroundColor Cyan
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -ge '0' -and $key.KeyChar -le '9') {
                    return [int]::Parse([string]$key.KeyChar)
                }
                if ($key.Key -eq [ConsoleKey]::A) {
                    return 10
                }
                if ($key.Key -eq [ConsoleKey]::Enter -or $key.Key -eq [ConsoleKey]::S) {
                    return $null
                }
            }
        }
        catch {
            return $null
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host 'Post-close rating skipped after timeout.' -ForegroundColor Yellow
    return $null
}

function Wait-UntilUtc {
    param([datetime]$TargetUtc)

    while ([DateTime]::UtcNow -lt $TargetUtc) {
        $remaining = ($TargetUtc - [DateTime]::UtcNow).TotalMilliseconds
        $sleep = [math]::Max(50, [math]::Min(1000, [int]$remaining))
        Start-Sleep -Milliseconds $sleep
    }
}

function Wait-ForCloseMarker {
    param([int]$InitialVisibleWindows)

    if ($SelfTest) {
        return [pscustomobject]@{ reason = 'synthetic_close_marker'; captured_at_utc = [DateTime]::UtcNow }
    }

    $deadline = [DateTime]::UtcNow.AddMinutes($MaxWaitMinutes)
    $hadVisibleWindow = $InitialVisibleWindows -gt 0
    $zeroSince = $null

    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Enter) {
                    return [pscustomobject]@{ reason = 'manual_enter_after_close'; captured_at_utc = [DateTime]::UtcNow }
                }
                if ($key.Key -eq [ConsoleKey]::Q) {
                    return [pscustomobject]@{ reason = 'user_abort'; captured_at_utc = [DateTime]::UtcNow }
                }
            }
        }
        catch {
            # Automatic window detection remains available when console input is redirected.
        }

        $visible = Get-RestartAnatomyVisibleWindowCount
        if ($visible -gt 0) {
            $hadVisibleWindow = $true
            $zeroSince = $null
        }
        elseif ($hadVisibleWindow) {
            if ($null -eq $zeroSince) {
                $zeroSince = [DateTime]::UtcNow
            }
            elseif (([DateTime]::UtcNow - $zeroSince).TotalSeconds -ge $CloseStableSeconds) {
                return [pscustomobject]@{ reason = 'visible_codex_window_absent'; captured_at_utc = [DateTime]::UtcNow }
            }
        }
        Start-Sleep -Seconds $PollSeconds
    }

    return [pscustomobject]@{ reason = 'wait_timeout'; captured_at_utc = [DateTime]::UtcNow }
}

$normalizedOffsets = @($PostCloseOffsetsSeconds | Where-Object { $_ -ge 0 } | Sort-Object -Unique)
if ($normalizedOffsets.Count -eq 0 -or $normalizedOffsets[0] -ne 0) {
    $normalizedOffsets = @(0) + $normalizedOffsets
}

$run = New-RestartAnatomyRun -OutputRoot $OutputRoot -Synthetic:$SelfTest
$runDirectory = $run.run_directory
Write-Host ''
Write-Host "Restart Anatomy run: $($run.run_id)" -ForegroundColor Cyan
Write-Host "Evidence: $runDirectory"
Write-Host 'This first run is observation-only. It will not stop or restart anything.' -ForegroundColor Green

try {
    $activeRating = Read-OptionalRating -Prompt 'Current machine slowness'
    if ($null -ne $activeRating) {
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'subjective_report' -Data ([ordered]@{
            phase = 'active'
            slowness_0_to_10 = $activeRating
        }) | Out-Null
    }

    Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'capturing_active_baseline' -Message 'Capturing active Codex baseline.'
    Write-Host 'Capturing active baseline (up to about 20 seconds on the first snapshot)...'
    $activeSnapshot = New-RestartAnatomySnapshot -RunId $run.run_id -Label 'active-baseline' -Phase 'active' -Synthetic:$SelfTest
    $activePath = Write-RestartAnatomySnapshot -RunDirectory $runDirectory -Snapshot $activeSnapshot
    $visibleWindows = Get-RestartAnatomyVisibleWindowCount
    Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'watcher_armed' -Data ([ordered]@{
        visible_codex_window_count = $visibleWindows
        automatic_close_stability_seconds = $CloseStableSeconds
        post_close_offsets_seconds = $normalizedOffsets
    }) | Out-Null
    Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'armed' -Message 'Waiting for normal Codex window closure or manual Enter marker.'

    Write-Host ''
    Write-Host "Baseline saved: $activePath" -ForegroundColor Green
    Write-Host 'Now close Codex normally. Keep this PowerShell window open.' -ForegroundColor Cyan
    Write-Host 'Immediately return to this PowerShell window and press Enter to mark the close.' -ForegroundColor Cyan
    Write-Host 'Automatic detection is only a fallback because packaged apps may not expose a window handle.'
    Write-Host 'Press Q only to abort this run.'

    $trigger = Wait-ForCloseMarker -InitialVisibleWindows $visibleWindows
    if ($trigger.reason -eq 'user_abort' -or $trigger.reason -eq 'wait_timeout') {
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'run_aborted' -Data ([ordered]@{ reason = $trigger.reason }) | Out-Null
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'run_closed' -Data ([ordered]@{ outcome = 'aborted_before_close_observation' }) | Out-Null
        Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'closed_aborted' -Message "Run ended: $($trigger.reason)"
        Write-Host "Run ended: $($trigger.reason)" -ForegroundColor Yellow
        exit 2
    }

    $closeMarkerUtc = [datetime]$trigger.captured_at_utc
    Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'close_marker' -Data ([ordered]@{
        trigger = $trigger.reason
        close_marker_utc = $closeMarkerUtc.ToString('o')
    }) | Out-Null
    Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'capturing_post_close' -Message "Close marker recorded by $($trigger.reason)."
    Write-Host ''
    Write-Host "Close marker recorded: $($trigger.reason)" -ForegroundColor Green

    foreach ($offset in $normalizedOffsets) {
        $target = $closeMarkerUtc.AddSeconds([double]$offset)
        Wait-UntilUtc -TargetUtc $target
        $actualSeconds = ([DateTime]::UtcNow - $closeMarkerUtc).TotalSeconds
        $label = 'post-close-{0:D4}s' -f $offset
        Write-Host "Capturing $label (actual start +$([math]::Round($actualSeconds, 1))s)..."
        $snapshot = New-RestartAnatomySnapshot -RunId $run.run_id -Label $label -Phase $(if ($SelfTest) { 'synthetic' } else { 'post_close' }) -SecondsFromClose $actualSeconds -Synthetic:$SelfTest
        Write-RestartAnatomySnapshot -RunDirectory $runDirectory -Snapshot $snapshot | Out-Null
    }

    $postCloseRating = Read-TimedOptionalRating -Prompt 'Machine slowness after the observation window'
    if ($null -ne $postCloseRating) {
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'subjective_report' -Data ([ordered]@{
            phase = 'post_close_final'
            slowness_0_to_10 = $postCloseRating
            seconds_from_close = ([DateTime]::UtcNow - $closeMarkerUtc).TotalSeconds
        }) | Out-Null
    }

    if ($SelfTest) {
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'self_test_capture_complete' -Data ([ordered]@{ outcome = 'synthetic_no_reboot_expected' }) | Out-Null
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'run_closed' -Data ([ordered]@{ outcome = 'synthetic_capture_complete'; reboot_verified = $false }) | Out-Null
        Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'closed_complete' -Message 'Synthetic capture complete.'
        Write-Host 'Synthetic capture complete.' -ForegroundColor Green
    }
    else {
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'awaiting_reboot' -Data ([ordered]@{
            instruction = 'After a real reboot, run CAPTURE_AFTER_REBOOT.cmd before reopening Codex or heavy applications.'
        }) | Out-Null
        Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'awaiting_reboot' -Message 'Post-close observation complete. Awaiting verified post-reboot capture.'
        Write-Host ''
        Write-Host 'Post-close observation complete.' -ForegroundColor Green
        Write-Host 'If the machine is still slow, reboot normally.' -ForegroundColor Cyan
        Write-Host 'After boot, run CAPTURE_AFTER_REBOOT.cmd before reopening Codex or other heavy apps.' -ForegroundColor Cyan
    }
}
catch {
    try {
        Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'capture_failure' -Data ([ordered]@{
            message = $_.Exception.Message
            category = [string]$_.CategoryInfo.Category
        }) | Out-Null
        Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'interrupted' -Message $_.Exception.Message
    }
    catch {}
    Write-Error $_
    exit 1
}
