# MCR visual recording: gl_scene (Linux x86_64)

The recording codetracer's Visual Replay suites open: the desktop's capture
(`plat59-visual-replay-capture.spec.ts`), the terminal's and the GPUI
window's PLAT-59 suites, and the `visual-recording` scenario stage. codetracer
reaches it through its `examples/recordings` submodule, so every host and CI
job opens the same recording, at the commit codetracer pins, and an answer
captured from it holds on all of them.

A recording made on each host would not: its GEIDs count every call the
process made, and those depend on the host's libraries. The answers in
codetracer's `src/tests/visual/answers/plat59-visual-replay.electron.json`
name the commit of this repository they were captured from.

## Recording details

- **Program:** `gl/gl_scene.c` from codetracer-native-test-programs: 60
  frames of a 256x256 framebuffer, four solid quads per frame (one draw call
  each), every quad's colour a function of (frame, quadrant).
- **Recorder:** `ct-mcr record --interpose`, the only attach on Linux that
  captures GL. The debug server refuses it (no stage-0 boundary), so the
  front-ends open it with their Visual Replay panes only.
- **GL:** Mesa llvmpipe, surfaceless EGL (`LIBGL_ALWAYS_SOFTWARE=1`,
  `EGL_PLATFORM=surfaceless`, one llvmpipe thread).
- **Environment:** scrubbed. The program starts from `env -i` with only the
  variables above, a scratch `HOME` / `TMPDIR` / XDG directories and the dev
  shell's library path, so the recording carries nothing of the shell that
  made it.

## Files

| File              | Description                                                                  |
| ----------------- | ---------------------------------------------------------------------------- |
| `trace.ct`        | The raw MCR recording.                                                       |
| `gfx_stream/`     | Its graphics stream, extracted (`ct-mcr extract-gfx --ctfs-visual-streams`). |
| `gfx_stream.ctfs` | The same stream as the CTFS container the player reads.                      |
| `trace.ct.*`      | The recorder's sidecars.                                                     |
| `regenerate.sh`   | Re-records all of the above.                                                 |

Opening the recording writes beside it (`ct` rewrites `trace.ct` and
`paths.json` when it imports one), so codetracer's suites open a scratch copy
and never this directory.

## How to regenerate

```bash
nix develop ../codetracer-visual-replay --command \
  bash mcr/linux-x86_64/visual-gl-scene/regenerate.sh
```

Then verify it, commit it, move codetracer's `examples/recordings` gitlink to
the commit, and re-capture the answers made from it in codetracer
(`just plat59-capture-electron`).
