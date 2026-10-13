# Check that a freshly regenerated mcr/windows-x86_64 fixture pair is one
# current readers and the recorder accept, beyond what verify-recordings.sh
# reads off the bytes:
#
#   turns       both files declare the `atomic_total_order` hook strategy:
#               every Windows recording carries the global turn (owner
#               decision 2026-10-10), and the recorder refuses a Windows
#               recording without it.  Read with `ct-print --meta-json`.
#   id          the portable export carries the pinned recording id
#               (`ct-mcr trace info`).  The raw trace's id is minted by the
#               recorder and only printed.
#   replay      `ct-mcr replay-worker --verify --replay-strict` replays each
#               file to completion in the recorded total order: exit 0 and
#               `verify: replay complete`.  The raw trace replays beside the
#               sidecars `ct-mcr record` wrote next to it (bootstrap mode and
#               stage-0 runtime), so run this in the job that recorded it; the
#               portable export carries its sidecars inside (`sidecars.bin`).
#
# Every check runs and is reported before the verdict.  Exits 1 if any fails.
#
# Usage (from the repository root, after mcr/windows-x86_64/regenerate.ps1):
#   .github/scripts/verify-windows-recordings.ps1 -CtMcr <ct_mcr.exe> `
#     -CtPrint <ct-print.exe> [-Dir mcr/windows-x86_64] [-LogDir regen-logs]

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CtMcr,
    [Parameter(Mandatory)] [string]$CtPrint,
    [string]$Dir = "mcr/windows-x86_64",
    [string]$LogDir = "regen-logs",
    # The pinned id regenerate.ps1 passes to `ct-mcr export --recording-id`;
    # consumers hardcode it (FIXTURE_IDS.md, codetracer fixture_ids.{nim,rs}).
    [string]$PortableRecordingId = "019e3a35-2545-7a00-8aaa-43ff20060002"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Trace = Join-Path $Dir "trace.ct"
$Portable = Join-Path $Dir "trace-portable.ct"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$failed = $false

function Report([bool]$Ok, [string]$Line) {
    if ($Ok) { Write-Host "OK   $Line" } else { Write-Host "FAIL $Line"; $script:failed = $true }
}

foreach ($f in @($Trace, $Portable)) {
    if (-not (Test-Path $f)) { Report $false "${f}: missing"; continue }

    # turns
    $metaText = (& $CtPrint --meta-json $f 2>&1 | Out-String)
    $metaExit = $LASTEXITCODE
    $strategies = @()
    if ($metaExit -eq 0) {
        try { $strategies = @((ConvertFrom-Json $metaText).metadata.hook_strategies) } catch { $strategies = @() }
    }
    Report ($strategies -contains "atomic_total_order") `
        "${f}: turns  hook_strategies=[$($strategies -join ',')] (ct-print exit $metaExit)"

    # id
    $info = (& $CtMcr trace info $f 2>&1 | Out-String)
    $infoExit = $LASTEXITCODE
    $id = ""
    if ($info -match '(?m)^recording_id:\s*(\S+)') { $id = $Matches[1] }
    if ($f -eq $Portable) {
        Report ($infoExit -eq 0 -and $id -eq $PortableRecordingId) `
            "${f}: id     recording_id=$id (want $PortableRecordingId; trace info exit $infoExit)"
    } else {
        Report ($infoExit -eq 0 -and $id -ne "" -and $id -ne $PortableRecordingId) `
            "${f}: id     recording_id=$id (minted by the recorder; trace info exit $infoExit)"
    }

    # replay
    $log = Join-Path $LogDir ("replay-strict-" + [IO.Path]::GetFileNameWithoutExtension($f) + ".log")
    $replayArgs = @("replay-worker", "--verify", "--replay-strict")
    if ($f -eq $Trace) { $replayArgs += @("--bootstrap", "stage0") }
    $replayArgs += $f
    & $CtMcr @replayArgs *> $log
    $replayExit = $LASTEXITCODE
    $complete = Select-String -Path $log -SimpleMatch "verify: replay complete" -Quiet
    $replayed = (Select-String -Path $log -Pattern 'verify: \d+ events replayed successfully' |
        Select-Object -Last 1 | ForEach-Object { $_.Line.Trim() })
    Report ($replayExit -eq 0 -and $complete) `
        "${f}: replay strict, total order: exit $replayExit, complete=$complete; $replayed (log $log)"
    if (-not ($replayExit -eq 0 -and $complete)) {
        Get-Content $log -Tail 15 | ForEach-Object { Write-Host "       replay: $_" }
    }
}

if ($failed) { exit 1 }
exit 0
