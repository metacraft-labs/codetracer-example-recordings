# MCR Recording: Android ARM64

Recording from a Samsung Galaxy S24 Ultra (SM-S928B), Android 16, ARM64.

## How it was recorded

A pure C CTSP client was cross-compiled with Android NDK clang
(`aarch64-linux-android34-clang`), pushed to the phone via `adb push`,
and executed via `adb shell`. The client connects to a stream-receiver
running on the developer machine over TCP (via `adb reverse`), sends
CTSP EVENT_BATCH messages, and the receiver assembles them into a CTFS
`.ct` trace file.

## Contents

| File | Description |
|------|-------------|
| `trace.ct` | Raw CTFS recording (10 EVENT_BATCH messages, 50 events, no embedded binaries). For emulator unit tests. |
| `trace-portable.ct` | Enriched portable trace with embedded binaries and debug symbols. For GUI E2E tests via `ct host --trace-path`. |
| `binaries/android_ctsp_client` | ARM64 ELF static binary (cross-compiled with NDK) |
| `source.c` | Symlink to `../../programs/ctsp_client.c` (shared CTSP client source). |
| `regenerate.sh` | Script to rebuild the binary, record the trace, and export the portable trace. |

## Device info

- Model: SM-S928B (Samsung Galaxy S24 Ultra)
- OS: Android 16, SDK 36
- ABI: arm64-v8a
- CPU: aarch64

## How to regenerate

```bash
# From the codetracer-example-recordings repo root, inside the codetracer nix dev shell:
direnv exec ../codetracer bash mcr/android-arm64/regenerate.sh
```

Requires an Android phone connected via USB with `adb` access and
Android NDK installed (`$ANDROID_NDK_HOME` or auto-detected).

This produces both `trace.ct` (raw) and `trace-portable.ct` (enriched).

## Usage in tests

Used by DAP integration tests as a fixture for Android ARM64 replay.

Tests can:
1. Load `trace.ct` directly for DAP inspection (metadata, events, registers).
2. Read the binary from `binaries/android_ctsp_client` and embed it into a copy of
   the trace to test binary-aware replay.
3. Verify that replay works both with and without the original binary present.
