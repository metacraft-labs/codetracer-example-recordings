# MCR Recording: iOS ARM64

A real cooperative recording made in an iOS simulator (iOS 26.5, arm64) on an
Apple Silicon Mac. Replay on a Linux host waits on cross-ISA arm64 replay
(PLAT-73); the events and the entry snapshot are real.

## How it was recorded

`regenerate.sh` drives codetracer-native-recorder's
`ct_cooperative/tests/record_ios_sim_fixture.sh`. It links the program
`ct_cooperative/tests/fixtures/ios_sim_cooperative_fixture.c` (in that
repository) against `libct_cooperative_sim.a`, runs it in a simulator with
`xcrun simctl spawn`, and records its system calls over the network to the
host's stream receiver, which writes the CTFS container. The receiver stores
the program's entry snapshot (`cp0.regs`, `cp0.mem`) beside the 7 events
(open, write, close, open, read, close, write).

The driver records in a private simulator device set and builds against a copy
of the nimble packages, so no home directory reaches the fixture; it fails if
one does.

This replaces the earlier synthetic flow (a synthetic CTSP client, since removed,
whose placeholder blobs no reader decoded; its traces held no events).

## Contents

| File | Description |
|------|-------------|
| `trace.ct` | The raw cooperative recording: 7 events and the entry snapshot. |
| `trace-portable.ct` | The portable export, with the binary and its `.dSYM` bundled (`debug symbols: 1`). Pinned id `019e3a35-2543-7a00-8aaa-43ff20040002`. |
| `binaries/ios_sim_cooperative_fixture` | The recorded program (arm64 Mach-O, iOS simulator), with its `.dSYM`. |
| `regenerate.sh` | Builds the program, records it and exports the portable trace. |

## How to regenerate

```bash
# On an Apple Silicon Mac with Xcode and an iOS simulator runtime, with
# codetracer-native-recorder (agents be0b06d5e or later) beside this repository:
(cd ../codetracer-native-recorder &&
  nix develop --command bash ../codetracer-example-recordings/mcr/ios-arm64/regenerate.sh)
```

## Usage in tests

Read by DAP and portable-trace tests as the iOS arm64 fixture. Tests that only
read the container's members (metadata, events, the bundled binary) run on any
host; replaying it on Linux needs cross-ISA arm64 replay (PLAT-73).
