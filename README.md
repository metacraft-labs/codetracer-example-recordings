# CodeTracer Example Recordings

Pre-created trace recordings for CodeTracer integration tests. Each recording
was produced by a real CodeTracer recorder over a real program.

> **Warning:** This repository's history may be purged and force-pushed at any
> time. Do not depend on specific commit hashes.

## Recordings

| Language | Directory | Recorder | Trace Format |
|----------|-----------|----------|--------------|
| Rust | `rust/flow_test/` | `ct-rr-support` (RR) | RR trace + metadata |
| C | `c/flow_test/` | `ct-rr-support` (RR) | RR trace + metadata |
| Go | `go/flow_test/` | `ct-rr-support` (RR) | RR trace + metadata |
| Nim | `nim/flow_test/` | `ct-rr-support` (RR) | RR trace + metadata |
| Python | `python/flow_test/` | `codetracer-python-recorder` | CBOR+zstd binary |
| Ruby | `ruby/flow_test/` | `codetracer-pure-ruby-recorder` | JSON |

### MCR Recordings

| Platform | Directory | Device | Format |
|----------|-----------|--------|--------|
| macOS ARM64 | `mcr/macos-arm64/` | Apple Silicon Mac (M1) | `.ct` (CTFS) |
| Linux x86_64 | `mcr/linux-x86_64/` | Linux AMD64 (ct-mcr interpose) | `.ct` (CTFS) |
| Android ARM64 | `mcr/android-arm64/` | Samsung Galaxy S24 Ultra | `.ct` (CTFS) |
| iOS ARM64 | `mcr/ios-arm64/` | iPhone 17 Pro simulator | `.ct` (CTFS) |
| Windows x86_64 | `mcr/windows-x86_64/` | Windows 11 x64 (ct-mcr interpose) | `.ct` (CTFS) |
| Linux ARM64 | `mcr/linux-arm64/` | Linux ARM64 (ct-mcr interpose) | `.ct` (CTFS) |

MCR recordings are stored **without embedded binaries**. The recorded
program's binary is stored separately in a `binaries/` subdirectory.
This allows tests to exercise both scenarios:

1. **Replay with embedded binary** — tests embed the binary from `binaries/`
   into the trace via filemap, then verify the debugserver can load it.
2. **Replay after deleting binaries** — tests delete the original binary,
   verify the debugserver can still replay from the embedded copy in the trace.

#### Portable traces for GUI E2E tests

Each platform should produce **two** trace files:

1. **`trace.ct`** — raw MCR recording (no embedded binaries). Used by
   emulator unit tests and debugserver integration tests.
2. **`trace-portable.ct`** — enriched portable trace with embedded
   binaries, debug symbols, and source file references. Used by browser
   GUI E2E tests (via `ct host --trace-path`) and cross-platform replay.

The portable trace is created by running `ct-mcr export --portable` on
the raw trace. The `regenerate.sh` script on each platform should produce
both files. See `mcr/linux-x86_64/regenerate.sh` for the reference
implementation.

#### TODO: Regenerate portable traces for all platforms

Each platform recording needs a `regenerate.sh` (or `.ps1` on Windows)
that produces both `trace.ct` and `trace-portable.ct`. Status:

| Platform | `regenerate.sh` | `trace.ct` | `trace-portable.ct` | Notes |
|----------|----------------|------------|---------------------|-------|
| linux-x86_64 | done | done | done | Reference implementation |
| macos-arm64 | done | done (synthetic) | TODO | Run on Apple Silicon Mac to regenerate |
| windows-x86_64 | done (.ps1) | done | done | — |
| android-arm64 | done | done | TODO | Run with connected device to regenerate |
| ios-arm64 | done | done | TODO | Run with Xcode + simulator to regenerate |
| linux-arm64 | TODO | TODO | TODO | Run on ARM64 Linux host |

To regenerate a platform (example for Linux x86_64):
```bash
direnv exec ../codetracer bash mcr/linux-x86_64/regenerate.sh
```

#### TODO: Add portable trace export to all regeneration scripts

All platform `regenerate.sh` scripts should produce both `trace.ct` (raw)
and `trace-portable.ct` (enriched via `ct-mcr export --portable`).
See `mcr/linux-x86_64/regenerate.sh` for the reference implementation.
## Standard Recordings

All standard test programs compute the same values: `calculate_sum(10, 32)` = 483,
`sum_with_for(9)` = 45, `sum_with_while(9)` = 45.

### Source programs

The `programs/` directory contains source programs used to create recordings:

- `programs/ct_fixture_prog.c` — shared cross-platform C source for MCR platform recordings using local recording (uses `#ifdef _WIN32` for platform-specific I/O and threading)
- `programs/ctsp_client.c` — shared CTSP network client source for MCR mobile recordings (Android, iOS)
- `programs/python_flow_test.py` — Python flow test
- `programs/ruby_flow_test.rb` — Ruby flow test

The RR-based recordings (Rust, C, Go, Nim) use test programs from the
`codetracer` repo at `src/db-backend/test-programs/<lang>/`.

### How recordings were created

#### RR recordings (Rust, C, Go, Nim)

Each RR recording was built and recorded using `ct-rr-support` from the
`codetracer-rr-backend` repo:

```bash
# Build (from codetracer repo root, in nix dev shell)
ct-rr-support build src/db-backend/test-programs/rust/rust_flow_test.rs /tmp/rust_flow_test
ct-rr-support build src/db-backend/test-programs/c/c_flow_test.c /tmp/c_flow_test
ct-rr-support build src/db-backend/test-programs/go/go_flow_program.go /tmp/go_flow_program
ct-rr-support build src/db-backend/test-programs/nim/nim_flow_test.nim /tmp/nim_flow_test

# Record
ct-rr-support record -o rust/flow_test /tmp/rust_flow_test
ct-rr-support record -o c/flow_test /tmp/c_flow_test
ct-rr-support record -o go/flow_test /tmp/go_flow_program
ct-rr-support record -o nim/flow_test /tmp/nim_flow_test
```

#### Python recording

```bash
codetracer-python-recorder --trace-dir python/flow_test --format binary programs/python_flow_test.py
```

#### Ruby recording

```bash
ruby path/to/codetracer-pure-ruby-recorder -o ruby/flow_test programs/ruby_flow_test.rb
```

#### MCR recordings

Each MCR platform has its own `README.md` and regeneration script. For Linux x86_64:

```bash
# From repo root, inside the codetracer nix dev shell:
direnv exec ../codetracer bash mcr/linux-x86_64/regenerate.sh
```

For macOS ARM64:

```bash
direnv exec ../codetracer bash mcr/macos-arm64/regenerate.sh
```

For Android ARM64 (requires connected phone):

```bash
direnv exec ../codetracer bash mcr/android-arm64/regenerate.sh
```

For iOS ARM64 (requires Xcode with iOS simulator):

```bash
direnv exec ../codetracer bash mcr/ios-arm64/regenerate.sh
```

For Linux ARM64 (must be run on an ARM64 host):

```bash
direnv exec ../codetracer bash mcr/linux-arm64/regenerate.sh
```
For Windows x86_64:

```powershell
# From repo root, in a VS Developer PowerShell:
.\mcr\windows-x86_64\regenerate.ps1
```

See each recording's own `README.md` for platform-specific details.

## RR trace folder structure

Each RR recording follows the standard CodeTracer trace folder layout:

```
<lang>/flow_test/
  rr/                        # RR trace data (packed for portability)
  files/                     # Copied source files (absolute paths mirrored)
  trace_db_metadata.json     # Extended metadata from ct-rr-support
  trace_paths.json           # Source file paths from DWARF
  symbols.json               # Extracted symbols
```

## MCR recording structure

```
programs/
  ct_fixture_prog.c            # Shared source for MCR recordings
mcr/<platform>/
  trace.ct                       # Raw CTFS container (no embedded binaries)
  trace-portable.ct              # Enriched trace (binaries + debug symbols)
  binaries/                      # Compiled program binary for this platform
    ct_fixture_prog              # Mach-O / ELF / PE binary
  source.c                       # Symlink to ../../programs/ct_fixture_prog.c
  regenerate.sh / regenerate.ps1 # Script to build + record + export portable
  README.md                      # Platform-specific details
```

## Usage in tests

This repo is intended to be used as a git submodule in the `codetracer` repo:

```bash
git submodule add https://github.com/metacraft-labs/codetracer-example-recordings.git examples/recordings
```

Then tests can reference recordings at `examples/recordings/<lang>/flow_test/`
or `examples/recordings/mcr/<platform>/`.

## Regenerating recordings

To regenerate all recordings, enter the codetracer nix dev shell and re-run the
commands listed above, pointing the output directories back into this repo.
Commit and force-push to update.

## Git LFS

Large binary files (RR trace data, packed binaries) are tracked with Git LFS.
Make sure `git-lfs` is installed before cloning:

```bash
git lfs install
git clone https://github.com/metacraft-labs/codetracer-example-recordings.git
```
