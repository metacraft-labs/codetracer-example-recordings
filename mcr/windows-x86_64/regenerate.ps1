# Regenerate the Windows x86_64 MCR recording fixture.
#
# Prerequisites:
#   - Windows x86_64 host
#   - Visual Studio Build Tools (provides cl.exe)
#   - ct-mcr.exe built from codetracer-native-recorder
#
# This script:
#   1. Enters a VS Developer Shell (for cl.exe)
#   2. Compiles the shared ct_fixture_prog source into an x86_64 PE binary
#   3. Records it with ct-mcr (interpose mode) to produce trace.ct
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

$Source = Join-Path $RepoRoot "programs\ct_fixture_prog.c"
$Binary = Join-Path $ScriptDir "binaries\ct_fixture_prog.exe"
$Trace  = Join-Path $ScriptDir "trace.ct"
$CtMcr  = Join-Path $NativeRecorder "ct_cli\ct_mcr.exe"

Write-Host "=== Regenerating Windows x86_64 MCR fixture ==="
Write-Host "  Source: $Source"
Write-Host "  Binary: $Binary"
Write-Host "  Trace:  $Trace"
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
} finally {
    Pop-Location
}
# Clean intermediate build artifacts
Remove-Item -Path (Join-Path $ScriptDir "*.obj") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $ScriptDir "*.pdb") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path (Split-Path $Binary) "*.ilk") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path (Split-Path $Binary) "*.pdb") -Force -ErrorAction SilentlyContinue
Write-Host ""

# Step 3: Record
Write-Host ">>> Recording with ct-mcr..."
if (-not (Test-Path $CtMcr)) {
    throw "ct-mcr not found at $CtMcr. Build it from codetracer-native-recorder first."
}
Remove-Item -Path $Trace -Force -ErrorAction SilentlyContinue
& $CtMcr record --use-interpose -o $Trace -- $Binary
Write-Host ""

# Step 4: Verify
$TraceSize = (Get-Item $Trace).Length
$BinarySize = (Get-Item $Binary).Length
Write-Host "=== Done ==="
Write-Host "  trace.ct: $TraceSize bytes"
Write-Host "  binary:   $BinarySize bytes"
