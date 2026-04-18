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
| `trace.ct` | CTFS recording (10 EVENT_BATCH messages, 50 events, no embedded binaries) |
| `binaries/android_ctsp_client` | ARM64 ELF static binary (cross-compiled with NDK) |

## Device info

- Model: SM-S928B (Samsung Galaxy S24 Ultra)
- OS: Android 16, SDK 36
- ABI: arm64-v8a
- CPU: aarch64

## Regeneration

```bash
cd codetracer-native-recorder
direnv exec . bash ct_cooperative/tests/test_android_phone_e2e.sh
# Copy trace from ct_cooperative/build/android_e2e_test/android_e2e_test.ct
```

Requires an Android phone connected via USB with `adb` access.
