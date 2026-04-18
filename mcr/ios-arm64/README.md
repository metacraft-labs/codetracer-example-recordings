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
| `source.c` | CTSP client source code |

## Device info

- Simulator: iPhone 17 Pro (494EE9B4-51A3-4AEE-91C1-FA7E68CEB5DE)
- OS: iOS 26.2 (simulator)
- Architecture: arm64

## Regeneration

```bash
cd codetracer-native-recorder

# Compile for iOS simulator
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun --sdk iphonesimulator clang \
  -target arm64-apple-ios18.0-simulator -O0 -g \
  -o ios_ctsp_client ct_cooperative/tests/android_ctsp_client.c

# Start receiver, spawn on simulator
stream_receiver 14292 trace.ct &
xcrun simctl spawn <UDID> ./ios_ctsp_client 127.0.0.1 14292
```

Requires Xcode with iOS simulator runtime installed.
