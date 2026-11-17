# MCR Recording: macOS ARM64

A real recording of `ct_fixture_prog` on an Apple Silicon Mac, made by the
cooperative recorder (`libct_cooperative`), with its entry snapshot. It is the
macOS case of the cross-platform replay tests: a Linux x86-64 host replays it
in the arm64 emulator.

Until 2026-11-16 the files here were not a recording: `trace.ct` was written
by `ct_cooperative/tests/generate_recording_fixture.nim`, which fabricated its
events and its starting registers and memory. Nothing could replay it.

## Recording details

- **Platform:** arm64-apple-macosx (recorded on macOS 26.5.1, m4)
- **Recording mode:** cooperative; tick source none
- **Program:** `ct_fixture_prog`, from `programs/ct_fixture_prog.c` (as
  `source.c`), built for the cooperative recorder by `ct_fixture_prog_coop.c`
  and started/stopped by `ct_fixture_coop_shim.c`
- **Threads:** 4 (main + 3 workers)
- **Events:** 30. Main thread: 5 rounds of open/read/close on `/dev/null`
  (15 hooked calls). Each worker: thread start, one open/read/close, thread
  end. Every hooked call is an `evOsSyscall` with its return value and data
  (an open's path).
- **Entry snapshot:** `cp0.regs` (the main thread's `arm_thread_state64_t` at
  `main`'s first instruction, 0x100000ca8), `cp0.mem` (the stack from SP up,
  256 KiB below SP as zeros, the executable's writable segments, the pages its
  GOT points at), `cpidx.idx` (one checkpoint). Recorded with ASLR off, so the
  executable's addresses are its file's.
- **Embedded in `trace-portable.ct`:** the executable and its `.dSYM`
  (`ct-mcr export --portable`).

## Files

| File | Description |
|------|-------------|
| `trace.ct` | The recording. Its `recording_id` is minted by the recorder (`ct_recording_init` cannot pin it). |
| `trace-portable.ct` | Its portable export, with the executable and the `.dSYM`; `recording_id` pinned to `019e3a35-2542-7a00-8aaa-43ff20030002`. Used by `ct host` / the desktop and by `ct-mcr debugserver` on other hosts. |
| `binaries/ct_fixture_prog`, `binaries/ct_fixture_prog.dSYM` | The program as recorded, and its debug info. |
| `ct_fixture_prog_coop.c` | The program built for the cooperative recorder: system headers, then `ct_cooperative.h` with `CT_COOPERATIVE_WRAP_LIBC`, then `source.c`. |
| `ct_fixture_coop_shim.c` | Starts the recording in a constructor (`ct_recording_init` / `start` / `capture_entry_snapshot`), stops it at exit. The trace path is `CT_FIXTURE_TRACE`. |
| `noaslr.c` | Runs a program with ASLR disabled (`posix_spawn`'s `_POSIX_SPAWN_DISABLE_ASLR`). |
| `source.c` | Symlink to `../../programs/ct_fixture_prog.c`. |
| `regenerate.sh` | Rebuilds the program and the recorder, records, exports. |

## What a replay on another host does with it

`ct-mcr debugserver trace-portable.ct` on Linux x86-64 serves it from the
arm64 emulator (codetracer-pm `spec/CLI/ct-mcr/debugserver.md`, "A macOS arm64
cooperative recording on another host"): LLDB sees an arm64 process stopped at
`main`'s first instruction with the recorded registers; `b main` / `c` stops
at `source.c:149`; stepping runs `main`, `calculate_sum`, `sum_with_for` and
`sum_with_while`. The first `printf` ends the replay with a named reason: the
cooperative recorder hooks only open/read/write/close and thread creation, so
the recording has nothing that says what `printf` did.

## How to regenerate

On an Apple Silicon Mac, from a scratch copy of this repository with
`codetracer-native-recorder` (and `codetracer-trace-format-nim`) beside it,
ct-mcr built (`just build-ct-mcr`), and nim / a zstd library on `PATH`
(the recorder's dev shell, or set `ZSTD_LIB`):

```bash
bash mcr/macos-arm64/regenerate.sh
```

It builds the recorder and the program under `/tmp` (the files keep their
build paths, and a home directory or `$TMPDIR` would put the account's name
into a public fixture), records under a cleared environment, and exports.
Scan the results for credential-shaped names before committing; `cp0.mem` is
compressed, so scan it decompressed too.

## Usage in tests

- codetracer-native-recorder
  `ct_cli/tests/test_debugserver_cross_isa_macos_arm64_linux.nim`: a real LLDB
  against `ct-mcr debugserver` on Linux x86-64.
- codetracer `replay/portable-macos-recording-replays` and
  `src/tests/gui/tests/cross-platform-replay.spec.ts` (macos-arm64 case):
  `ct host` replays it and the status bar shows `source.c:<line>`.
