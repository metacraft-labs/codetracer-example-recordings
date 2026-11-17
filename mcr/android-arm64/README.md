# MCR Recording: Android ARM64

A real cooperative recording made on an arm64 Android emulator (android-34,
google_apis) running on an Apple Silicon Mac. Replay on a Linux host waits on
cross-ISA arm64 replay (PLAT-73); the events and the entry snapshot are real.

## How it was recorded

`regenerate.sh` drives codetracer-native-recorder's
`ct_cooperative/tests/record_android_emu_fixture.sh`. It links the program
`ct_cooperative/tests/fixtures/cooperative_fixture.c` (in that repository)
against `libct_cooperative_android.a`, boots an arm64 emulator (the flake's
`android-emulator-sdk` package), runs the program there and records its system
calls over `adb reverse` to the host's stream receiver, which writes the CTFS
container. The recording carries the program's entry snapshot (`cp0.regs`,
`cp0.mem`, `cp0.tpidr`) beside its 7 events, and `platform.bin` describes the
recording device (Linux, aarch64), not the Mac that received the stream.

No home directory reaches the fixture; the driver fails if one does.

This replaces the earlier flow (a synthetic CTSP client on a USB-attached
phone, since removed, whose traces held no events).

## Contents

| File | Description |
|------|-------------|
| `trace.ct` | The raw cooperative recording: 7 events and the entry snapshot. |
| `trace-portable.ct` | The portable export with the binary bundled; its DWARF is inside the ELF. Pinned id `019e3a35-2544-7a00-8aaa-43ff20050002`. |
| `binaries/android_emu_cooperative_fixture` | The recorded program (arm64 ELF, Android). |
| `regenerate.sh` | Builds the program, records it and exports the portable trace. |

## How to regenerate

```bash
# On an Apple Silicon Mac, with codetracer-native-recorder (agents 9d4c12506 or
# later) and codetracer-trace-format-nim (2e29ce4 or later) beside this repository:
(cd ../codetracer-native-recorder &&
  nix develop --command bash ../codetracer-example-recordings/mcr/android-arm64/regenerate.sh)
```

## Usage in tests

Read by DAP and portable-trace tests as the Android arm64 fixture. Tests that
only read the container's members run on any host; replaying it on Linux needs
cross-ISA arm64 replay (PLAT-73).
