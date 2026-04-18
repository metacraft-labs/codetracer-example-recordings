# MCR Cooperative Mode Recording — macOS ARM64

Pre-made cooperative-mode `.ct` recording for DAP integration testing.

## Recording details

- **Platform:** aarch64-apple-macosx
- **Recording mode:** cooperative
- **Tick source:** compiler
- **Program:** source.c (compiled test program)

## What the program does

1. Pure computation: `calculate_sum`, `sum_with_for`, `sum_with_while` (tick generation)
2. Syscall I/O: `open`/`read`/`close` on `/dev/null` (event recording)
3. Multi-threading: 3 worker threads doing computation + I/O (thread support)

## How it was generated

```bash
cd ~/metacraft/codetracer-native-recorder
./ct_cooperative/tests/generate_fixtures.sh
```

The fixture generator compiles `source.c` with cooperative-mode instrumentation,
runs it under MCR cooperative recording, and copies the resulting `.ct` trace here.

If no real recording infrastructure is available, the generator creates a synthetic
`.ct` trace with the correct metadata and representative event/register/memory data.

## Usage

Used by `ct_cooperative/tests/test_dap_phone_recording.nim` as a fallback fixture
when no live phone (Android/iOS) is available for recording.
