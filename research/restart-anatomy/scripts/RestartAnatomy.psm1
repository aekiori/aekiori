Set-StrictMode -Version Latest

$script:ProtocolVersion = 'RESTART-ANATOMY-V0.1'
$script:SnapshotSchemaVersion = 'restart-anatomy-snapshot-v1'
$script:LedgerSchemaVersion = 'restart-anatomy-event-v1'

function ConvertTo-RaIsoUtc {
    param([datetime]$Value)
    return $Value.ToUniversalTime().ToString('o')
}

function ConvertTo-RaSafePath {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $safe = $Value
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
        $safe = $safe -replace [regex]::Escape($userProfile), '%USERPROFILE%'
    }
    return $safe
}

function ConvertTo-RaJson {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [switch]$Compress
    )

    if ($Compress) {
        return ($Value | ConvertTo-Json -Depth 24 -Compress)
    }
    return ($Value | ConvertTo-Json -Depth 24)
}

function Write-RaUtf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$AllowOverwrite
    )

    if ((Test-Path -LiteralPath $Path) -and -not $AllowOverwrite) {
        throw "Refusing to overwrite immutable evidence file: $Path"
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Add-RaUtf8NoBomLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Line
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine, $encoding)
}

function Get-RaStringSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
    }
    finally {
        $sha.Dispose()
    }
}

function Initialize-RaNativeProcessReader {
    if ('RestartAnatomy.NativeProcessSnapshot' -as [type]) {
        return
    }

    $source = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace RestartAnatomy
{
    public sealed class ProcessEntry
    {
        public int ProcessId { get; set; }
        public int ParentProcessId { get; set; }
        public string ExecutableName { get; set; }
    }

    public static class NativeProcessSnapshot
    {
        private const uint TH32CS_SNAPPROCESS = 0x00000002;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PROCESSENTRY32
        {
            public uint dwSize;
            public uint cntUsage;
            public uint th32ProcessID;
            public IntPtr th32DefaultHeapID;
            public uint th32ModuleID;
            public uint cntThreads;
            public uint th32ParentProcessID;
            public int pcPriClassBase;
            public uint dwFlags;

            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string szExeFile;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32FirstW(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32NextW(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr hObject);

        public static ProcessEntry[] Read()
        {
            IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot == INVALID_HANDLE_VALUE)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            try
            {
                var output = new List<ProcessEntry>();
                var entry = new PROCESSENTRY32();
                entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));

                if (!Process32FirstW(snapshot, ref entry))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                do
                {
                    output.Add(new ProcessEntry
                    {
                        ProcessId = unchecked((int)entry.th32ProcessID),
                        ParentProcessId = unchecked((int)entry.th32ParentProcessID),
                        ExecutableName = entry.szExeFile
                    });
                    entry.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                }
                while (Process32NextW(snapshot, ref entry));

                return output.ToArray();
            }
            finally
            {
                CloseHandle(snapshot);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Get-RaParentMap {
    param([System.Collections.Generic.List[string]]$Errors)

    $parents = @{}
    try {
        Initialize-RaNativeProcessReader
        foreach ($entry in [RestartAnatomy.NativeProcessSnapshot]::Read()) {
            $parents[[int]$entry.ProcessId] = [int]$entry.ParentProcessId
        }
    }
    catch {
        if ($null -ne $Errors) {
            $Errors.Add("parent_process_snapshot_unavailable: $($_.Exception.Message)")
        }
    }
    return $parents
}

function Get-RaBaseRelation {
    param(
        [string]$Name,
        [AllowNull()][string]$Path
    )

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if ($Path -match '\\WindowsApps\\OpenAI\.Codex_') {
            return 'codex_package'
        }
        if ($Path -match '\\AppData\\Local\\OpenAI\\Codex\\') {
            return 'codex_runtime'
        }
    }

    if ($Name -eq 'codex-code-mode-host') {
        return 'codex_component_path_unavailable'
    }
    return 'unrelated_or_unattributed'
}

function Get-RaCodexAncestor {
    param(
        [int]$ProcessIdValue,
        [hashtable]$ById,
        [hashtable]$ParentMap
    )

    $seen = @{}
    $cursor = $ProcessIdValue
    for ($depth = 0; $depth -lt 20; $depth++) {
        if (-not $ParentMap.ContainsKey($cursor)) {
            return $null
        }
        $cursor = [int]$ParentMap[$cursor]
        if ($cursor -le 0 -or $seen.ContainsKey($cursor)) {
            return $null
        }
        $seen[$cursor] = $true
        if ($ById.ContainsKey($cursor)) {
            $parent = $ById[$cursor]
            if ($parent.base_relation -in @('codex_package', 'codex_runtime', 'codex_component_path_unavailable')) {
                return $cursor
            }
        }
    }
    return $null
}

function Get-RaProcessInventory {
    param([System.Collections.Generic.List[string]]$Errors)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $processes = @(Get-Process -ErrorAction SilentlyContinue)
    $stopwatch.Stop()
    $parentMap = Get-RaParentMap -Errors $Errors
    $records = New-Object System.Collections.ArrayList

    foreach ($process in $processes) {
        $processPath = $null
        $startTime = $null
        $cpuSeconds = $null
        $workingSet = $null
        $privateBytes = $null
        $handleCount = $null
        $threadCount = $null
        $windowHandle = 0

        try { $processPath = $process.Path } catch {}
        try { $startTime = ConvertTo-RaIsoUtc -Value $process.StartTime } catch {}
        try { if ($null -ne $process.CPU) { $cpuSeconds = [double]$process.CPU } } catch {}
        try { $workingSet = [int64]$process.WorkingSet64 } catch {}
        try { $privateBytes = [int64]$process.PrivateMemorySize64 } catch {}
        try { $handleCount = [int]$process.Handles } catch {}
        try { $threadCount = [int]$process.Threads.Count } catch {}
        try { $windowHandle = [int64]$process.MainWindowHandle } catch {}

        $parentId = $null
        if ($parentMap.ContainsKey([int]$process.Id)) {
            $parentId = [int]$parentMap[[int]$process.Id]
        }
        $safePath = ConvertTo-RaSafePath -Value $processPath
        $baseRelation = Get-RaBaseRelation -Name $process.ProcessName -Path $processPath
        $identityKey = '{0}|{1}' -f $process.Id, $(if ($null -ne $startTime) { $startTime } else { 'start-unavailable' })

        [void]$records.Add([pscustomobject][ordered]@{
            name = $process.ProcessName
            process_id = [int]$process.Id
            parent_process_id = $parentId
            identity_key = $identityKey
            started_at_utc = $startTime
            executable_path = $safePath
            base_relation = $baseRelation
            codex_relation = $baseRelation
            codex_ancestor_process_id = $null
            cpu_seconds_total = $cpuSeconds
            cpu_pct_total_capacity = $null
            working_set_bytes = $workingSet
            private_bytes = $privateBytes
            handle_count = $handleCount
            thread_count = $threadCount
            main_window_handle = $windowHandle
        })
    }

    $byId = @{}
    foreach ($record in $records) {
        $byId[[int]$record.process_id] = $record
    }
    foreach ($record in $records) {
        if ($record.base_relation -eq 'unrelated_or_unattributed') {
            $ancestor = Get-RaCodexAncestor -ProcessIdValue $record.process_id -ById $byId -ParentMap $parentMap
            if ($null -ne $ancestor) {
                $record.codex_relation = 'codex_descendant'
                $record.codex_ancestor_process_id = [int]$ancestor
            }
        }
    }

    return [pscustomobject][ordered]@{
        enumeration_milliseconds = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
        processes = @($records)
    }
}

function Get-RaSeriesMetric {
    param(
        [object[]]$Samples,
        [string]$Suffix,
        [double]$Scale = 1.0
    )

    $values = @($Samples | Where-Object { $_.Status -eq 0 -and $_.Path -like "*$Suffix" } | ForEach-Object { [double]$_.CookedValue / $Scale })
    if ($values.Count -eq 0) {
        return $null
    }
    return [pscustomobject][ordered]@{
        average = [math]::Round([double](($values | Measure-Object -Average).Average), 3)
        maximum = [math]::Round([double](($values | Measure-Object -Maximum).Maximum), 3)
        last = [math]::Round([double]$values[-1], 3)
        sample_count = $values.Count
    }
}

function Get-RaInstantMetric {
    param(
        [object[]]$Samples,
        [string]$Suffix,
        [double]$Scale = 1.0
    )

    $sample = $Samples | Where-Object { $_.Status -eq 0 -and $_.Path -like "*$Suffix" } | Select-Object -Last 1
    if ($null -eq $sample) {
        return $null
    }
    return [math]::Round(([double]$sample.CookedValue / $Scale), 3)
}

function Measure-RaSchedulerJitter {
    param(
        [int]$Iterations = 100,
        [int]$SleepMilliseconds = 20
    )

    $overshoots = New-Object System.Collections.Generic.List[double]
    for ($index = 0; $index -lt $Iterations; $index++) {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        [System.Threading.Thread]::Sleep($SleepMilliseconds)
        $timer.Stop()
        $overshoots.Add([math]::Max(0.0, $timer.Elapsed.TotalMilliseconds - $SleepMilliseconds))
    }

    $sorted = @($overshoots | Sort-Object)
    function Get-PercentileValue {
        param([double]$Percentile)
        if ($sorted.Count -eq 0) { return $null }
        $position = [math]::Ceiling(($Percentile / 100.0) * $sorted.Count) - 1
        $position = [math]::Max(0, [math]::Min($sorted.Count - 1, $position))
        return [math]::Round([double]$sorted[$position], 3)
    }

    return [pscustomobject][ordered]@{
        probe = 'thread_sleep_overshoot'
        iterations = $Iterations
        requested_sleep_ms = $SleepMilliseconds
        p50_overshoot_ms = Get-PercentileValue -Percentile 50
        p95_overshoot_ms = Get-PercentileValue -Percentile 95
        p99_overshoot_ms = Get-PercentileValue -Percentile 99
        max_overshoot_ms = [math]::Round([double](($sorted | Measure-Object -Maximum).Maximum), 3)
        over_25ms_count = @($overshoots | Where-Object { $_ -gt 25 }).Count
        limitation = 'Scheduler wake jitter is not direct mouse, keyboard, or frame latency.'
    }
}

function Get-RaAggregate {
    param([object[]]$Processes)

    $private = [double](($Processes | Measure-Object private_bytes -Sum).Sum)
    $working = [double](($Processes | Measure-Object working_set_bytes -Sum).Sum)
    $cpu = [double](($Processes | Measure-Object cpu_pct_total_capacity -Sum).Sum)
    $handles = [double](($Processes | Measure-Object handle_count -Sum).Sum)
    $threads = [double](($Processes | Measure-Object thread_count -Sum).Sum)
    return [pscustomobject][ordered]@{
        process_count = @($Processes).Count
        cpu_pct_total_capacity = [math]::Round($cpu, 3)
        working_set_mb = [math]::Round($working / 1MB, 3)
        private_mb = [math]::Round($private / 1MB, 3)
        handle_count = [int64]$handles
        thread_count = [int64]$threads
    }
}

function Get-RaTopProcessView {
    param(
        [object[]]$Processes,
        [string]$SortProperty,
        [int]$Count = 20
    )

    return @($Processes | Sort-Object $SortProperty -Descending | Select-Object -First $Count | ForEach-Object {
        [pscustomobject][ordered]@{
            name = $_.name
            process_id = $_.process_id
            parent_process_id = $_.parent_process_id
            codex_relation = $_.codex_relation
            cpu_pct_total_capacity = $_.cpu_pct_total_capacity
            private_mb = $(if ($null -eq $_.private_bytes) { $null } else { [math]::Round([double]$_.private_bytes / 1MB, 3) })
            working_set_mb = $(if ($null -eq $_.working_set_bytes) { $null } else { [math]::Round([double]$_.working_set_bytes / 1MB, 3) })
            handle_count = $_.handle_count
            thread_count = $_.thread_count
            started_at_utc = $_.started_at_utc
            executable_path = $_.executable_path
        }
    })
}

function New-RestartAnatomySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][ValidateSet('active', 'post_close', 'post_reboot', 'synthetic')][string]$Phase,
        [AllowNull()][Nullable[double]]$SecondsFromClose = $null,
        [switch]$Synthetic
    )

    $captureTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $errors = New-Object System.Collections.Generic.List[string]
    $logicalProcessors = [Environment]::ProcessorCount
    $before = Get-RaProcessInventory -Errors $errors
    $processWindowStart = [DateTime]::UtcNow

    $ratePaths = @(
        '\Processor(_Total)\% Processor Time',
        '\Processor(_Total)\% DPC Time',
        '\Processor(_Total)\% Interrupt Time',
        '\Memory\Pages Input/sec',
        '\PhysicalDisk(_Total)\% Disk Time',
        '\PhysicalDisk(_Total)\Avg. Disk Queue Length',
        '\PhysicalDisk(_Total)\Avg. Disk sec/Transfer'
    )
    $rateSamples = @()
    try {
        $rateResult = Get-Counter -Counter $ratePaths -SampleInterval 1 -MaxSamples 4 -ErrorAction Stop
        $rateSamples = @($rateResult.CounterSamples)
    }
    catch {
        $errors.Add("rate_counters_unavailable: $($_.Exception.Message)")
    }

    $after = Get-RaProcessInventory -Errors $errors
    $processWindowEnd = [DateTime]::UtcNow
    $elapsedSeconds = ($processWindowEnd - $processWindowStart).TotalSeconds
    $beforeById = @{}
    foreach ($record in $before.processes) {
        $beforeById[[int]$record.process_id] = $record
    }
    foreach ($record in $after.processes) {
        if ($beforeById.ContainsKey([int]$record.process_id)) {
            $prior = $beforeById[[int]$record.process_id]
            if ($prior.identity_key -eq $record.identity_key -and $null -ne $prior.cpu_seconds_total -and $null -ne $record.cpu_seconds_total -and $elapsedSeconds -gt 0) {
                $delta = [math]::Max(0.0, ([double]$record.cpu_seconds_total - [double]$prior.cpu_seconds_total))
                $record.cpu_pct_total_capacity = [math]::Round(($delta / $elapsedSeconds / $logicalProcessors) * 100.0, 3)
            }
        }
    }

    $instantPaths = @(
        '\Memory\Available MBytes',
        '\Memory\% Committed Bytes In Use',
        '\Memory\Pool Nonpaged Bytes',
        '\Memory\Pool Paged Bytes',
        '\Memory\Cache Bytes',
        '\Memory\Standby Cache Normal Priority Bytes',
        '\Memory\Modified Page List Bytes',
        '\System\System Up Time',
        '\System\Processes',
        '\System\Threads',
        '\System\Handle Count'
    )
    $instantSamples = @()
    try {
        $instantResult = Get-Counter -Counter $instantPaths -MaxSamples 1 -ErrorAction SilentlyContinue
        if ($null -ne $instantResult) {
            $instantSamples = @($instantResult.CounterSamples)
        }
    }
    catch {
        $errors.Add("instant_counters_unavailable: $($_.Exception.Message)")
    }

    $jitter = Measure-RaSchedulerJitter
    $capturedAt = [DateTime]::UtcNow
    $uptimeSeconds = Get-RaInstantMetric -Samples $instantSamples -Suffix '\system\system up time'
    $estimatedBoot = $null
    if ($null -ne $uptimeSeconds) {
        $estimatedBoot = ConvertTo-RaIsoUtc -Value $capturedAt.AddSeconds(-1.0 * [double]$uptimeSeconds)
    }

    $allProcesses = @($after.processes)
    $codexPackage = @($allProcesses | Where-Object { $_.codex_relation -in @('codex_package', 'codex_component_path_unavailable') })
    $codexRuntime = @($allProcesses | Where-Object { $_.codex_relation -eq 'codex_runtime' })
    $codexDescendants = @($allProcesses | Where-Object { $_.codex_relation -eq 'codex_descendant' })
    $codexAffiliated = @($allProcesses | Where-Object { $_.codex_relation -ne 'unrelated_or_unattributed' })

    $captureTimer.Stop()
    return [pscustomobject][ordered]@{
        schema_version = $script:SnapshotSchemaVersion
        protocol_version = $script:ProtocolVersion
        run_id = $RunId
        label = $Label
        phase = $Phase
        synthetic = [bool]$Synthetic
        captured_at_utc = ConvertTo-RaIsoUtc -Value $capturedAt
        seconds_from_close = $SecondsFromClose
        capture_duration_seconds = [math]::Round($captureTimer.Elapsed.TotalSeconds, 3)
        system = [pscustomobject][ordered]@{
            machine_name = $env:COMPUTERNAME
            powershell_version = $PSVersionTable.PSVersion.ToString()
            logical_processors = $logicalProcessors
            system_uptime_seconds = $uptimeSeconds
            estimated_boot_time_utc = $estimatedBoot
            cpu_pct = Get-RaSeriesMetric -Samples $rateSamples -Suffix '\processor(_total)\% processor time'
            dpc_pct = Get-RaSeriesMetric -Samples $rateSamples -Suffix '\processor(_total)\% dpc time'
            interrupt_pct = Get-RaSeriesMetric -Samples $rateSamples -Suffix '\processor(_total)\% interrupt time'
            pages_input_per_sec = Get-RaSeriesMetric -Samples $rateSamples -Suffix '\memory\pages input/sec'
            disk_time_pct = Get-RaSeriesMetric -Samples $rateSamples -Suffix '\physicaldisk(_total)\% disk time'
            disk_queue_length = Get-RaSeriesMetric -Samples $rateSamples -Suffix '\physicaldisk(_total)\avg. disk queue length'
            disk_seconds_per_transfer = Get-RaSeriesMetric -Samples $rateSamples -Suffix '\physicaldisk(_total)\avg. disk sec/transfer'
            available_memory_mb = Get-RaInstantMetric -Samples $instantSamples -Suffix '\memory\available mbytes'
            committed_bytes_in_use_pct = Get-RaInstantMetric -Samples $instantSamples -Suffix '\memory\% committed bytes in use'
            nonpaged_pool_mb = Get-RaInstantMetric -Samples $instantSamples -Suffix '\memory\pool nonpaged bytes' -Scale 1MB
            paged_pool_mb = Get-RaInstantMetric -Samples $instantSamples -Suffix '\memory\pool paged bytes' -Scale 1MB
            cache_mb = Get-RaInstantMetric -Samples $instantSamples -Suffix '\memory\cache bytes' -Scale 1MB
            standby_normal_priority_mb = Get-RaInstantMetric -Samples $instantSamples -Suffix '\memory\standby cache normal priority bytes' -Scale 1MB
            modified_page_list_mb = Get-RaInstantMetric -Samples $instantSamples -Suffix '\memory\modified page list bytes' -Scale 1MB
            system_process_count = Get-RaInstantMetric -Samples $instantSamples -Suffix '\system\processes'
            system_thread_count = Get-RaInstantMetric -Samples $instantSamples -Suffix '\system\threads'
            system_handle_count = Get-RaInstantMetric -Samples $instantSamples -Suffix '\system\handle count'
            process_enumeration_ms_before = $before.enumeration_milliseconds
            process_enumeration_ms_after = $after.enumeration_milliseconds
            scheduler_jitter = $jitter
        }
        process_summary = [pscustomobject][ordered]@{
            all = Get-RaAggregate -Processes $allProcesses
            codex_package = Get-RaAggregate -Processes $codexPackage
            codex_runtime = Get-RaAggregate -Processes $codexRuntime
            codex_descendants = Get-RaAggregate -Processes $codexDescendants
            codex_affiliated = Get-RaAggregate -Processes $codexAffiliated
            top_cpu = Get-RaTopProcessView -Processes $allProcesses -SortProperty 'cpu_pct_total_capacity'
            top_private_memory = Get-RaTopProcessView -Processes $allProcesses -SortProperty 'private_bytes'
            top_handles = Get-RaTopProcessView -Processes $allProcesses -SortProperty 'handle_count'
        }
        processes = $allProcesses
        collection_errors = @($errors)
        collection_boundaries = @(
            'No process command lines are collected.',
            'Process ancestry is a point-in-time Toolhelp snapshot and can be unavailable after a parent exits.',
            'Codex attribution requires a local executable path or a captured Codex ancestor.',
            'No process, service, cache, driver, or setting is changed by this snapshot.'
        )
    }
}

function Test-RestartAnatomyLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RunDirectory)

    $ledgerPath = Join-Path $RunDirectory 'events.jsonl'
    if (-not (Test-Path -LiteralPath $ledgerPath)) {
        return [pscustomobject][ordered]@{ valid = $true; event_count = 0; last_sha256 = $null; events = @(); error = $null }
    }

    $events = New-Object System.Collections.ArrayList
    $previousHash = $null
    $expectedSequence = 0
    $closureCount = 0
    try {
        $lines = @([System.IO.File]::ReadAllLines($ledgerPath, [System.Text.Encoding]::UTF8) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($line in $lines) {
            $outer = $line | ConvertFrom-Json -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace([string]$outer.payload_json) -or [string]::IsNullOrWhiteSpace([string]$outer.sha256)) {
                throw 'ledger line is missing payload_json or sha256'
            }
            $actualHash = Get-RaStringSha256 -Text ([string]$outer.payload_json)
            if ($actualHash -ne [string]$outer.sha256) {
                throw "ledger payload hash mismatch at sequence $expectedSequence"
            }
            $payload = [string]$outer.payload_json | ConvertFrom-Json -ErrorAction Stop
            if ([int]$payload.sequence -ne $expectedSequence) {
                throw "ledger sequence mismatch: expected $expectedSequence, got $($payload.sequence)"
            }
            $payloadPrevious = $payload.previous_sha256
            if ($expectedSequence -eq 0) {
                if ($null -ne $payloadPrevious -and -not [string]::IsNullOrWhiteSpace([string]$payloadPrevious)) {
                    throw 'first ledger event must have a null previous_sha256'
                }
            }
            elseif ([string]$payloadPrevious -ne $previousHash) {
                throw "ledger predecessor mismatch at sequence $expectedSequence"
            }
            if ($payload.event_type -eq 'run_closed') {
                $closureCount++
            }
            [void]$events.Add($payload)
            $previousHash = [string]$outer.sha256
            $expectedSequence++
        }
        if ($closureCount -gt 1) {
            throw 'ledger contains more than one run_closed event'
        }
        return [pscustomobject][ordered]@{
            valid = $true
            event_count = $events.Count
            last_sha256 = $previousHash
            events = @($events)
            error = $null
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            valid = $false
            event_count = $events.Count
            last_sha256 = $previousHash
            events = @($events)
            error = $_.Exception.Message
        }
    }
}

function Add-RestartAnatomyEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$EventType,
        [Parameter(Mandatory = $true)]$Data
    )

    $ledger = Test-RestartAnatomyLedger -RunDirectory $RunDirectory
    if (-not $ledger.valid) {
        throw "Refusing to append to invalid ledger: $($ledger.error)"
    }
    if (@($ledger.events | Where-Object { $_.event_type -eq 'run_closed' }).Count -gt 0) {
        throw 'Refusing to append after run_closed.'
    }

    $payload = [ordered]@{
        schema_version = $script:LedgerSchemaVersion
        sequence = [int]$ledger.event_count
        captured_at_utc = ConvertTo-RaIsoUtc -Value ([DateTime]::UtcNow)
        event_type = $EventType
        previous_sha256 = $ledger.last_sha256
        data = $Data
    }
    $payloadJson = ConvertTo-RaJson -Value $payload -Compress
    $outer = [ordered]@{
        payload_json = $payloadJson
        sha256 = Get-RaStringSha256 -Text $payloadJson
    }
    Add-RaUtf8NoBomLine -Path (Join-Path $RunDirectory 'events.jsonl') -Line (ConvertTo-RaJson -Value $outer -Compress)
    return [pscustomobject]$outer
}

function Write-RestartAnatomyStatus {
    param(
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$State,
        [AllowNull()][string]$Message
    )

    $status = [ordered]@{
        derived_non_authoritative = $true
        state = $State
        updated_at_utc = ConvertTo-RaIsoUtc -Value ([DateTime]::UtcNow)
        message = $Message
    }
    Write-RaUtf8NoBom -Path (Join-Path $RunDirectory 'status.json') -Text (ConvertTo-RaJson -Value $status) -AllowOverwrite
}

function New-RestartAnatomyRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [switch]$Synthetic
    )

    if (-not (Test-Path -LiteralPath $OutputRoot)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }
    $runId = 'RA-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runDirectory = Join-Path $OutputRoot $runId
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $runDirectory 'snapshots') -Force | Out-Null

    $run = [ordered]@{
        schema_version = 'restart-anatomy-run-v1'
        protocol_version = $script:ProtocolVersion
        run_id = $runId
        created_at_utc = ConvertTo-RaIsoUtc -Value ([DateTime]::UtcNow)
        synthetic = [bool]$Synthetic
        evidence_policy = 'immutable snapshots plus hash-chained append-only events'
        mutation_policy = 'observation only; no process, service, cache, driver, or setting changes'
        command_line_collection = 'disabled'
        claim_ceiling = 'observation and recovery-boundary evidence; not root cause without a discriminating intervention'
    }
    $runPath = Join-Path $runDirectory 'run.json'
    Write-RaUtf8NoBom -Path $runPath -Text (ConvertTo-RaJson -Value $run)
    $runHash = (Get-FileHash -LiteralPath $runPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Add-RestartAnatomyEvent -RunDirectory $runDirectory -EventType 'run_created' -Data ([ordered]@{
        run_id = $runId
        run_json_sha256 = $runHash
        synthetic = [bool]$Synthetic
    }) | Out-Null
    Write-RestartAnatomyStatus -RunDirectory $runDirectory -State 'created' -Message 'Run created; no baseline captured yet.'

    return [pscustomobject][ordered]@{
        run_id = $runId
        run_directory = $runDirectory
    }
}

function Write-RestartAnatomySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    $snapshotDirectory = Join-Path $RunDirectory 'snapshots'
    $existingCount = @(Get-ChildItem -LiteralPath $snapshotDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    $slug = ([string]$Snapshot.label -replace '[^A-Za-z0-9_-]+', '-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'snapshot' }
    $fileName = '{0:D3}-{1}.json' -f $existingCount, $slug
    $path = Join-Path $snapshotDirectory $fileName
    Write-RaUtf8NoBom -Path $path -Text (ConvertTo-RaJson -Value $Snapshot)
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Add-RestartAnatomyEvent -RunDirectory $RunDirectory -EventType 'snapshot_recorded' -Data ([ordered]@{
        file = "snapshots/$fileName"
        sha256 = $hash
        label = $Snapshot.label
        phase = $Snapshot.phase
        seconds_from_close = $Snapshot.seconds_from_close
        synthetic = [bool]$Snapshot.synthetic
    }) | Out-Null
    return $path
}

function Get-RestartAnatomyVisibleWindowCount {
    $count = 0
    foreach ($process in @(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue)) {
        $processPath = $null
        try { $processPath = $process.Path } catch {}
        if ($processPath -match '\\WindowsApps\\OpenAI\.Codex_' -and [int64]$process.MainWindowHandle -ne 0) {
            $count++
        }
    }
    return $count
}

function Get-RestartAnatomyLatestPendingRun {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$OutputRoot)

    $candidates = New-Object System.Collections.ArrayList
    foreach ($directory in @(Get-ChildItem -LiteralPath $OutputRoot -Directory -ErrorAction SilentlyContinue)) {
        $ledger = Test-RestartAnatomyLedger -RunDirectory $directory.FullName
        if (-not $ledger.valid) { continue }
        $hasAwaiting = @($ledger.events | Where-Object { $_.event_type -eq 'awaiting_reboot' }).Count -gt 0
        $hasClosure = @($ledger.events | Where-Object { $_.event_type -eq 'run_closed' }).Count -gt 0
        if ($hasAwaiting -and -not $hasClosure) {
            [void]$candidates.Add($directory)
        }
    }
    return $candidates | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
}

function Test-RestartAnatomyRebootBoundary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$BeforeSnapshot,
        [Parameter(Mandatory = $true)]$AfterSnapshot
    )

    if ([string]::IsNullOrWhiteSpace([string]$BeforeSnapshot.system.estimated_boot_time_utc) -or [string]::IsNullOrWhiteSpace([string]$AfterSnapshot.system.estimated_boot_time_utc)) {
        return [pscustomobject][ordered]@{ verified = $false; reason = 'boot_time_unavailable'; boot_time_delta_seconds = $null }
    }
    $beforeBoot = [datetime]::Parse([string]$BeforeSnapshot.system.estimated_boot_time_utc).ToUniversalTime()
    $afterBoot = [datetime]::Parse([string]$AfterSnapshot.system.estimated_boot_time_utc).ToUniversalTime()
    $delta = ($afterBoot - $beforeBoot).TotalSeconds
    $verified = $delta -gt 120
    return [pscustomobject][ordered]@{
        verified = $verified
        reason = $(if ($verified) { 'estimated_boot_time_advanced' } else { 'same_boot_estimate' })
        boot_time_delta_seconds = [math]::Round($delta, 3)
    }
}

Export-ModuleMember -Function @(
    'Add-RestartAnatomyEvent',
    'Get-RestartAnatomyLatestPendingRun',
    'Get-RestartAnatomyVisibleWindowCount',
    'New-RestartAnatomyRun',
    'New-RestartAnatomySnapshot',
    'Test-RestartAnatomyLedger',
    'Test-RestartAnatomyRebootBoundary',
    'Write-RestartAnatomySnapshot',
    'Write-RestartAnatomyStatus'
)
