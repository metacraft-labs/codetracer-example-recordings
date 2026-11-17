# MCR Recording: Linux ARM64

Pre-made `.ct` recording from a Linux ARM64 (aarch64) machine.

## Recording details

- **Platform:** aarch64-linux-gnu
- **Recording mode:** hook (interpose)
- **Tick source:** none (interpose-based event capture)
- **Program:** `ct_fixture_prog` (compiled from `programs/ct_fixture_prog.c`)
- **Threads:** 4 (1 main + 3 workers)
- **Events:** 48 total

## Files

| File | Description |
|------|-------------|
| `trace.ct` | Raw CTFS container with event streams. No embedded binaries. For emulator unit tests. |
| `trace-portable.ct` | Enriched portable trace with embedded binaries (main binary + ld-linux + libc). For GUI E2E and cross-platform replay tests. |
| `binaries/ct_fixture_prog` | aarch64 ELF executable compiled with `-g -O0`. |
| `source.c` | Symlink to `../../programs/ct_fixture_prog.c`. |
| `regenerate.sh` | Script to rebuild binary, record trace, and export portable version. |

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
# codetracer nix dev shell (which provides cc, ct-mcr, ct).
# Must be run on a Linux ARM64 (aarch64) host — the interpose backend
# records the native binary of the host architecture.
direnv exec ../codetracer bash mcr/linux-arm64/regenerate.sh
```

This produces both `trace.ct` (raw) and `trace-portable.ct` (enriched with
binaries and debug symbols for cross-platform replay).

## Usage in tests

| Trace file | Used for |
|------------|----------|
| `trace.ct` | Emulator unit tests, DAP integration tests, debugserver tests |
| `trace-portable.ct` | Browser GUI E2E tests (via `ct host --trace-path`), cross-platform replay |

The portable trace contains embedded binaries (main executable + dynamic
linker + libc) so it can be replayed on any platform — the emulator loads
the binary from the CTFS container and feeds recorded events.
