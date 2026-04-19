# MCR Recording: macOS ARM64

Pre-made `.ct` recording from an Apple Silicon Mac (M1) for DAP integration testing.

## Recording details

- **Platform:** aarch64-apple-macosx
- **Recording mode:** cooperative
- **Tick source:** compiler
- **Program:** `ct_fixture_prog` (compiled from `programs/ct_fixture_prog.c`)
- **Threads:** 4 (1 main + 3 workers)
- **Events:** 25 total
- **Checkpoints:** 1
- **Embedded binaries:** none (stored separately in `binaries/`)

## Files

| File | Description |
|------|-------------|
| `trace.ct` | CTFS container with event streams, memory snapshot, register checkpoint, and checkpoint index. Does NOT contain embedded binaries or filemap. |
| `binaries/ct_fixture_prog` | ARM64 Mach-O executable compiled from `programs/ct_fixture_prog.c` with `-g -O0`. |
| `source.c` | Symlink to `../../programs/ct_fixture_prog.c` (shared source). |
| `regenerate.sh` | Script to rebuild the binary and re-record the trace. |

## What the program does

1. **Pure computation:** `calculate_sum`, `sum_with_for`, `sum_with_while`
   generate ticks from compiler instrumentation.
2. **Syscall I/O:** `open`/`read`/`close` on `/dev/null` generate syscall
   events in the event stream.
3. **Multi-threading:** 3 worker threads each perform computation and I/O,
   producing per-thread event streams.

## Trace contents

The `.ct` trace contains:

- **Thread 1 (main):** 10 events -- 7 computation ticks + 3 syscall events
- **Thread 2 (worker 1):** 5 events -- 3 computation + 2 syscall
- **Thread 3 (worker 2):** 5 events -- 3 computation + 2 syscall
- **Thread 4 (worker 3):** 5 events -- 3 computation + 2 syscall
- **Memory snapshot** (`cp0.mem`): 32 bytes at `0x16F600000` containing local
  variable values (`s1=483`, `s2=45`, `s3=45`, `bytes=0`, `final_sum=573`).
- **Register checkpoint** (`cp0.regs`): 34 ARM64 registers for thread 1
  (x0-x30, PC, SP, plus one reserved slot).
- **Checkpoint index:** 1 entry at offset 0.

## How to regenerate

```bash
# From the codetracer-example-recordings repo root, inside the
# codetracer-native-recorder nix dev shell:
direnv exec ../codetracer-native-recorder bash mcr/macos-arm64/regenerate.sh

# Or step by step:
cc -O0 -g -lpthread -o mcr/macos-arm64/binaries/ct_fixture_prog programs/ct_fixture_prog.c
cd ../codetracer-native-recorder
nim c -r ct_cooperative/tests/generate_recording_fixture.nim -- \
  --output=~/metacraft/codetracer-example-recordings/mcr/macos-arm64/trace.ct \
  --program=~/metacraft/codetracer-example-recordings/mcr/macos-arm64/binaries/ct_fixture_prog
```

## Usage in tests

Used by `ct_cooperative/tests/test_dap_cooperative_trace.nim` and
`test_dap_phone_recording.nim` as a fixture when no live device is available.

Tests can:
1. Load `trace.ct` directly for DAP inspection (metadata, events, registers).
2. Read the binary from `binaries/ct_fixture_prog` and embed it into a copy of
   the trace to test binary-aware replay.
3. Verify that replay works both with and without the original binary present.
