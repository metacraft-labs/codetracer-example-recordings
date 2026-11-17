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
#   replay      each file is copied ALONE into an empty directory, as the
#               committed fixture is, and `ct-mcr replay-worker --verify
#               --replay-strict` (default `--bootstrap auto`) replays it to
#               completion in the recorded total order: exit 0, `verify:
#               replay complete`, the stage-0 runtime taken from the copy the
#               trace carries in `sidecars.bin` (not from a file beside it or
#               from this build), and the replayed stdout byte-equal to the
#               recorded stdout.  A recorder that does not carry its stage-0
#               runtime in the trace fails this check: its fixtures replay
#               only beside the build that recorded them.
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

    # replay, alone in an empty directory
    $log = Join-Path $LogDir ("replay-strict-" + [IO.Path]::GetFileNameWithoutExtension($f) + ".log")
    $alone = Join-Path ([IO.Path]::GetTempPath()) ("ct-verify-alone-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $alone | Out-Null
    $copy = Join-Path $alone (Split-Path $f -Leaf)
    Copy-Item -LiteralPath $f -Destination $copy
    & $CtMcr replay-worker --verify --replay-strict $copy *> $log
    $replayExit = $LASTEXITCODE
    $complete = Select-String -Path $log -SimpleMatch "verify: replay complete" -Quiet
    $carried = Select-String -Path $log -SimpleMatch "(the copy the trace carries)" -Quiet
    $replayed = (Select-String -Path $log -Pattern 'verify: \d+ events replayed successfully' |
        Select-Object -Last 1 | ForEach-Object { $_.Line.Trim() })
    $recordedStdout = "$Trace.recorded_stdout.bin"
    $replayedStdout = "$copy.replay_stdout.bin"
    $sameStdout = $false
    if ((Test-Path -LiteralPath $recordedStdout) -and (Test-Path -LiteralPath $replayedStdout)) {
        $a = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $recordedStdout))
        $b = [IO.File]::ReadAllBytes($replayedStdout)
        $sameStdout = ($a.Length -gt 0) -and ([Convert]::ToBase64String($a) -eq [Convert]::ToBase64String($b))
    }
    Report ($replayExit -eq 0 -and $complete -and $carried -and $sameStdout) `
        "${f}: replay strict, alone, total order: exit $replayExit, complete=$complete, carried runtime=$carried, stdout equal=$sameStdout; $replayed (log $log)"
    if (-not ($replayExit -eq 0 -and $complete)) {
        Get-Content $log -Tail 15 | ForEach-Object { Write-Host "       replay: $_" }
    }
    Remove-Item -LiteralPath $alone -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failed) { exit 1 }
exit 0
