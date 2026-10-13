# Regenerate the Windows x86_64 MCR recording fixture.
#
# Produces TWO outputs:
#   1. trace.ct — raw MCR recording (for emulator unit tests)
#   2. trace-portable.ct — enriched portable trace with binaries,
#      debug symbols, and source files (for GUI E2E tests)
#
# Native commands (cl, ct-mcr) are checked by exit code: PowerShell's
# $ErrorActionPreference does not stop on a failing executable.
#
# Prerequisites:
#   - Windows x86_64 host
#   - Visual Studio Build Tools (provides cl.exe)
#   - ct-mcr.exe built from codetracer-native-recorder
#
# Run from the codetracer-example-recordings repo root:
#   .\mcr\windows-x86_64\regenerate.ps1

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..") | Select-Object -ExpandProperty Path
$NativeRecorder = if ($env:NATIVE_RECORDER) { $env:NATIVE_RECORDER } else {
  Resolve-Path (Join-Path $RepoRoot "..\codetracer-native-recorder") | Select-Object -ExpandProperty Path
}

$Source   = Join-Path $RepoRoot "programs\ct_fixture_prog.c"
$Binary   = Join-Path $ScriptDir "binaries\ct_fixture_prog.exe"
$Trace    = Join-Path $ScriptDir "trace.ct"
$Portable = Join-Path $ScriptDir "trace-portable.ct"
$CtMcr    = Join-Path $NativeRecorder "ct_cli\ct_mcr.exe"

# Canonical, pinned recording id of the portable export. Consumers hardcode it:
#   codetracer/src/common/fixture_ids.nim
#   codetracer/src/db-backend/tests/common/fixture_ids.rs
#   codetracer-example-recordings/FIXTURE_IDS.md
# `ct-mcr record` has no option to pin the raw trace's id.
$PortableRecordingId = "019e3a35-2545-7a00-8aaa-43ff20060002"

Write-Host "=== Regenerating Windows x86_64 MCR fixture ==="
Write-Host "  Source:   $Source"
Write-Host "  Binary:   $Binary"
Write-Host "  Trace:    $Trace"
Write-Host "  Portable: $Portable"
Write-Host ""

# Step 1: Enter VS Developer Shell (for cl.exe)
$vsInstall = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
    -latest -property installationPath -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 2>$null

if (-not $vsInstall) {
    # Fallback: try common BuildTools path
    $vsInstall = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
}

$devShellDll = Join-Path $vsInstall "Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
if (-not (Test-Path $devShellDll)) {
    throw "Cannot find VS DevShell module at $devShellDll. Install Visual Studio Build Tools."
}

Import-Module $devShellDll
Enter-VsDevShell -VsInstallPath $vsInstall -DevCmdArguments '-arch=x64' -SkipAutomaticLocation

# Step 2: Compile
Write-Host ">>> Compiling ct_fixture_prog..."
New-Item -ItemType Directory -Path (Split-Path $Binary) -Force | Out-Null
Push-Location $ScriptDir
try {
    cl /Od /Zi /Fe:$Binary $Source /link /DEBUG
    if ($LASTEXITCODE -ne 0) { throw "cl failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
# Clean intermediate build artifacts
Remove-Item -Path (Join-Path $ScriptDir "*.obj") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $ScriptDir "*.pdb") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path (Split-Path $Binary) "*.ilk") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path (Split-Path $Binary) "*.pdb") -Force -ErrorAction SilentlyContinue
Write-Host ""

# Step 3: Record raw trace
Write-Host ">>> Recording with ct-mcr (raw)..."
if (-not (Test-Path $CtMcr)) {
    throw "ct-mcr not found at $CtMcr. Build it from codetracer-native-recorder first."
}
Remove-Item -Path $Trace -Force -ErrorAction SilentlyContinue
# The recording captures the program's environment, so it is made with only
# what the program and the recorder need (the PowerShell equivalent of
# `env -i`); the shell's environment is restored afterwards. Recording from a
# CI job or a developer shell otherwise publishes that shell's tokens in the
# fixture.
#
# TEMP and TMP are set to a neutral directory, not kept from the shell: a
# shell's TEMP is `C:\Users\<user>\AppData\Local\Temp`, so keeping it put the
# recording user's name into the environment block of the recorded child, in
# both traces (measured 2026-10-11 with the recorder's corpus_leak_scan.nim:
# 9 user-name and 8 `C:\Users\` hits per trace). The environment is not the
# only route: the program's DLLs read per-user registry values (one recording
# captured HKCU's INetCache shell folder, `C:\Users\<user>\...`), so record
# under an account whose name may be published, such as the CI runner's, and
# from a directory that is not a junction (the recorder captures resolved NT
# paths of mapped files).
$keepVars = @("SystemRoot", "windir", "SystemDrive", "ComSpec", "PATHEXT",
              "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE",
              "CT_LICENSE_DEV_NO_FFI", "CODETRACER_LICENSE_FILE")
$NeutralTemp = Join-Path $env:SystemDrive "ct-fixture-tmp"
New-Item -ItemType Directory -Path $NeutralTemp -Force | Out-Null
$savedEnv = @(Get-ChildItem env: | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
try {
    foreach ($v in $savedEnv) {
        if ($keepVars -notcontains $v.Name) { Remove-Item -Path "env:$($v.Name)" -ErrorAction SilentlyContinue }
    }
    $env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
    $env:LANG = "C"
    $env:TEMP = $NeutralTemp
    $env:TMP = $NeutralTemp
    & $CtMcr record -o $Trace -- $Binary
    $recordExit = $LASTEXITCODE
} finally {
    foreach ($v in $savedEnv) { Set-Item -Path "env:$($v.Name)" -Value $v.Value }
    foreach ($n in @("LANG", "TEMP", "TMP")) {
        if ($savedEnv.Name -notcontains $n) { Remove-Item -Path "env:$n" -ErrorAction SilentlyContinue }
    }
    Remove-Item -Path $NeutralTemp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($recordExit -ne 0) { throw "ct-mcr record failed with exit code $recordExit" }
Write-Host ""

# Step 4: Export portable trace (for GUI E2E tests)
Write-Host ">>> Exporting portable trace..."
Remove-Item -Path $Portable -Force -ErrorAction SilentlyContinue
& $CtMcr export --portable -v --recording-id $PortableRecordingId -o $Portable $Trace
if ($LASTEXITCODE -ne 0) { throw "ct-mcr export failed with exit code $LASTEXITCODE" }
Write-Host ""

# Step 5: Verify
$TraceSize = (Get-Item $Trace).Length
$PortableSize = (Get-Item $Portable).Length
$BinarySize = (Get-Item $Binary).Length
Write-Host "=== Done ==="
Write-Host "  trace.ct:          $TraceSize bytes (raw, for emulator tests)"
Write-Host "  trace-portable.ct: $PortableSize bytes (enriched, for GUI E2E)"
Write-Host "  binary:            $BinarySize bytes"
