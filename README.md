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
| Android ARM64 | `mcr/android-arm64/` | Samsung Galaxy S24 Ultra | `.ct` (CTFS) |
| iOS ARM64 | `mcr/ios-arm64/` | iPhone 17 Pro simulator | `.ct` (CTFS) |

MCR recordings are stored **without embedded binaries**. The recorded
program's binary is stored separately in a `binaries/` subdirectory.
This allows tests to exercise both scenarios:

1. **Replay with embedded binary** — tests embed the binary from `binaries/`
   into the trace via filemap, then verify the debugserver can load it.
2. **Replay after deleting binaries** — tests delete the original binary,
   verify the debugserver can still replay from the embedded copy in the trace.

#### TODO: Additional platforms

The following platform recordings are planned but not yet captured:

- `mcr/linux-x86_64/` — recording from Linux x86_64
- `mcr/linux-arm64/` — recording from Linux ARM64
- `mcr/windows-x86_64/` — recording from Windows x86_64

## Standard Recordings

All standard test programs compute the same values: `calculate_sum(10, 32)` = 94,
`sum_with_for(9)` = 45, `sum_with_while(9)` = 45.

### Source programs

The `programs/` directory contains the Python and Ruby source programs used to
create their respective recordings. The RR-based recordings (Rust, C, Go, Nim)
use test programs from the `codetracer` repo at
`src/db-backend/test-programs/<lang>/`.

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

See each recording's own `README.md` for regeneration instructions.

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

## MCR cooperative recording structure

```
mcr/<platform>/
  trace.ct                   # CTFS container (no embedded binaries)
  binaries/                  # Compiled program binary for this platform
    <program>                # Mach-O / ELF / PE binary
  source.c                   # Source code of the recorded program
  README.md                  # Platform-specific details
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
