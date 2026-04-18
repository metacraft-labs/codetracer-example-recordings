# MCR Recording: Linux x86_64

Pre-made `.ct` recording from a Linux x86_64 machine for DAP integration testing.

## Recording details

- **Platform:** x86_64-linux-gnu
- **Recording mode:** hook (interpose)
- **Tick source:** none (interpose-based event capture)
- **Program:** `ct_fixture_prog` (compiled from `programs/ct_fixture_prog.c`)
- **Threads:** 4 (1 main + 3 workers)
- **Events:** 48 total
- **Embedded binaries:** none (stored separately in `binaries/`)

## Files

| File | Description |
|------|-------------|
| `trace.ct` | CTFS container with event streams, recorded via `ct-mcr record --use-interpose`. Does NOT contain embedded binaries or filemap. |
| `binaries/ct_fixture_prog` | x86_64 ELF executable compiled from `programs/ct_fixture_prog.c` with `-g -O0`. |
| `source.c` | Symlink to `../../programs/ct_fixture_prog.c` (shared source). |
| `regenerate.sh` | Script to rebuild the binary and re-record the trace. |

## What the program does

1. **Pure computation:** `calculate_sum`, `sum_with_for`, `sum_with_while`
   generate events via interpose hooks.
2. **Syscall I/O:** `open`/`read`/`close` on `/dev/null` generate syscall
   events in the event stream.
3. **Multi-threading:** 3 worker threads each perform computation and I/O,
   producing per-thread event streams.

## How to regenerate

```bash
# From the codetracer-example-recordings repo root, inside the
# codetracer-native-recorder nix dev shell:
direnv exec ../codetracer-native-recorder bash mcr/linux-x86_64/regenerate.sh

# Or step by step:
cc -O0 -g -pthread -o mcr/linux-x86_64/binaries/ct_fixture_prog programs/ct_fixture_prog.c
ct-mcr record --use-interpose -o mcr/linux-x86_64/trace.ct -- mcr/linux-x86_64/binaries/ct_fixture_prog
```

## Usage in tests

Used by DAP integration tests as a fixture for Linux x86_64 replay.

Tests can:
1. Load `trace.ct` directly for DAP inspection (metadata, events, registers).
2. Read the binary from `binaries/ct_fixture_prog` and embed it into a copy of
   the trace to test binary-aware replay.
3. Verify that replay works both with and without the original binary present.
