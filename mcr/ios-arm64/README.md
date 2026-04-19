# MCR Recording: iOS ARM64

Recording from an iPhone 17 Pro simulator (iOS 26.2), ARM64.

## How it was recorded

A pure C CTSP client was cross-compiled with Xcode clang for the iOS
simulator target (`arm64-apple-ios18.0-simulator`), then executed inside
the simulator via `xcrun simctl spawn`. The client connects to a
stream-receiver running on the Mac over localhost TCP, sends CTSP
EVENT_BATCH messages, and the receiver assembles them into a CTFS
`.ct` trace file.

## Contents

| File | Description |
|------|-------------|
| `trace.ct` | CTFS recording (10 EVENT_BATCH messages, 50 events, no embedded binaries) |
| `binaries/ios_ctsp_client` | ARM64 Mach-O executable (iOS simulator target) |
| `source.c` | Symlink to `../../programs/ctsp_client.c` (shared CTSP client source). |
| `regenerate.sh` | Script to rebuild the binary and re-record the trace. |

## Device info

- Simulator: iPhone 17 Pro (494EE9B4-51A3-4AEE-91C1-FA7E68CEB5DE)
- OS: iOS 26.2 (simulator)
- Architecture: arm64

## How to regenerate

```bash
# From the codetracer-example-recordings repo root, inside the
# codetracer-native-recorder nix dev shell:
direnv exec ../codetracer-native-recorder bash mcr/ios-arm64/regenerate.sh
```

Requires Xcode with iOS simulator runtime installed.

## Usage in tests

Used by DAP integration tests as a fixture for iOS ARM64 replay.

Tests can:
1. Load `trace.ct` directly for DAP inspection (metadata, events, registers).
2. Read the binary from `binaries/ios_ctsp_client` and embed it into a copy of
   the trace to test binary-aware replay.
3. Verify that replay works both with and without the original binary present.
