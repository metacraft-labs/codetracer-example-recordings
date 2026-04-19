# MCR Recording: Windows x86_64

Pre-made `.ct` recording from a Windows x86_64 machine for DAP integration testing.

## Recording details

- **Platform:** x86_64-pc-windows-msvc
- **Recording mode:** hook (interpose)
- **Tick source:** none (interpose-based event capture)
- **Program:** `ct_fixture_prog.exe` (compiled from `programs/ct_fixture_prog.c`)
- **Threads:** 1 (events aggregated by interpose layer)
- **Events:** 101 total
- **Embedded binaries:** none (stored separately in `binaries/`)

## Files

| File | Description |
|------|-------------|
| `trace.ct` | CTFS container with event streams, recorded via `ct-mcr record --use-interpose`. Does NOT contain embedded binaries or filemap. |
| `binaries/ct_fixture_prog.exe` | x86_64 PE executable compiled from `programs/ct_fixture_prog.c` with `/Od /Zi` (MSVC, no optimizations, debug info). |
| `source.c` | Symlink to `../../programs/ct_fixture_prog.c` (shared cross-platform source). |
| `regenerate.ps1` | Script to rebuild the binary and re-record the trace. |

## What the program does

1. **Pure computation:** `calculate_sum`, `sum_with_for`, `sum_with_while`
   generate events via interpose hooks.
2. **File I/O:** `CreateFileW`/`ReadFile`/`CloseHandle` on `NUL` generate
   file I/O events in the event stream.
3. **Multi-threading:** 3 worker threads (via `CreateThread`) each perform
   computation and I/O, producing per-thread event streams.

## How to regenerate

```powershell
# From the codetracer-example-recordings repo root, in a VS Developer shell:
.\mcr\windows-x86_64\regenerate.ps1
```

Or step by step:

```powershell
# 1. Open a VS Developer PowerShell (or run vcvarsall.bat x64)
# 2. Compile
cl /Od /Zi /Fe:mcr\windows-x86_64\binaries\ct_fixture_prog.exe programs\ct_fixture_prog.c /link /DEBUG
# 3. Record
ct-mcr record --use-interpose -o mcr\windows-x86_64\trace.ct -- mcr\windows-x86_64\binaries\ct_fixture_prog.exe
```

## Usage in tests

Used by DAP integration tests as a fixture for Windows x86_64 replay.

Tests can:
1. Load `trace.ct` directly for DAP inspection (metadata, events, registers).
2. Read the binary from `binaries/ct_fixture_prog.exe` and embed it into a copy of
   the trace to test binary-aware replay.
3. Verify that replay works both with and without the original binary present.
