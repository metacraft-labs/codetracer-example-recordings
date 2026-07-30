# MCR Emulator Fixtures: macOS ARM64

Real `.ct` recordings of tiny victim programs on an Apple Silicon Mac, used by
the **arm64 emulator replay** and **lockstep-diff** suites in
[`codetracer-native-recorder`](https://github.com/metacraft-labs/codetracer-native-recorder).

They are a different family from the `mcr/<platform>/trace.ct` fixtures one
level up: those are *one recording per platform* for DAP/GUI integration tests,
these are *several recordings of the same platform* that pin how far the
emulator gets through a real macOS bring-up and where it honestly stops. Each
directory is one recorder CONFIGURATION, not one program — that is why three of
them record the same `one_write` victim.

## Fixtures

| Directory | Victim | Recorded via | What it pins |
|---|---|---|---|
| `eme5/` | `null_main`, `one_puts` | `ct_cli record` (interpose) | Trace ingest, decode cascade, shared-cache + stack provisioning, the pass-1 boundary |
| `eme5_inject/` | `one_write` | `ct_cli record --experimental-no-sip-mode` + `CT_STAGE0_INCHILD_SETUP=0` | The cp0-seeded T0 (`__dyld_start`) inject seed; **the no-founding-stream fallback path** — the only fixture that reaches an `svc` with `predyldRecordCount == 0`. Since founding capture became the record default (2026-07-29) the founding-free shape is an explicit opt-out, and the fallback serves only pre-promotion recordings |
| `eme5_predyld/` | `one_write` | inject + `CT_STAGE0_INCHILD_SETUP=1` (now also the default), lean interpose dylib | The in-child pre-dyld installer, T0 disk re-derivation, and founding svcs SERVED from the recording at scale: 1945 events consumed, 1898 founding serves, 74 out-param copyouts |
| `eme_m9c_2006/` | `one_write` | inject + M9c + `CT_ARC4_HOOK=1` | Whole-program svc capture via the reach-independent detour tier; the cache-dyld re-arm; the current replay frontier |

`eme_ete_2006/` (inject + M9c + `CT_PREDYLD_ETE=1`) was **retired** on
2026-07-28. It had no code consumer, no committed driver, and was not
reproducible from the repo — its scratch driver `zz_rec_m9c_ow.nim` exists in no
tree. Keeping a fixture nothing reads and nothing can regenerate only costs
review attention. The full recording, including the 148 MB `.trace.ete` that was
never bundled here, lives under `~/mcr-hwtrace/eme_ete_2006/`.

## Files in each directory

| File | Description |
|---|---|
| `<name>.ct` | The CTFS container. This is the recording. |
| `<name>.c` | Symlink to the shared victim source in `../../../../programs/`. |
| `<name>.events.txt` | Human-readable event histogram, asserted against the live decode by `test_macos_trace_ingest`. |
| `<name>.info.txt` | The fixture's own characterization note: how it was recorded, what the numbers were, and where replay stops. Read this first. |
| `<name>.ct.head.json` | Recording head (event count / geid watermark). |
| `<name>.ct.predyld` | Founding pre-dyld svc dump + the parent's install note. |
| `<name>.ct.loadtrap` | M7 image-load-trap sequence (base, size, in load order). |
| `<name>.ct.m9images` | M9 svc-issuing image list (`:detour` = the §1A.9 tier-2 patch). |
| `<name>.ct.wpband.N` | M9c whole-program svc bands. |
| `<name>.ct.arc4buf` | arc4/CPRNG capture buffer VAs. |

Sidecars are per-fixture — a directory only carries the ones its recording
configuration produces. Some sidecars are read off disk by the replay path
(`.arc4buf`, `.loadtrap`); the rest are provenance.

Deliberately **not** bundled, because they are far too large for a non-LFS
repository:

- `eme_ete_2006/one_write.ct.trace.ete` — the raw 148 MB Apple-ETE packet stream.
- `eme_m9c_2006/one_write.ct.wpband.{1,2}` — 4.6 MB / 13 MB whole-program bands
  (their event stream is already drained into the `.ct`).

Both live durably outside this repo under `~/mcr-hwtrace/`; the fixtures replay
without them.

## Usage in tests

Consumers resolve this directory through the recorder repo's shared helper,
`tests/support/example_recordings.nim`:

```nim
import example_recordings
let fixture = mcrEmulatorFixture("eme5_inject", "one_write.ct")
```

which searches, in order:

1. `$CT_EXAMPLE_RECORDINGS`
2. `../codetracer-example-recordings` (workspace sibling)
3. `~/metacraft/codetracer-example-recordings`

and **hard-fails with a clear message** if none of them exists. It never skips
silently — a missing fixture repo is a setup error, not a reason to report a
green suite.

## Regenerating

```bash
# From the codetracer-example-recordings repo root, on an Apple Silicon Mac
# with SIP disabled:
bash mcr/macos-arm64/emulator/regenerate.sh            # all reproducible fixtures
bash mcr/macos-arm64/emulator/regenerate.sh eme5_inject # just one
```

Read `regenerate.sh`'s header first: these are **device-bound** recordings that
need SIP off and an entitled recorder, they must run on a QUIET host (concurrent
recording tests SIGKILL each other), and `eme_ete_2006` is **not** reproducible
from the repo — its scratch driver no longer exists.

Re-recording moves the characterization numbers pinned in the recorder repo's
tests. That is expected when the fixture legitimately gets richer, and a
regression when behaviour changed; each fixture's `.info.txt` records what the
numbers were and why.

## `.founding_merkle.rec` — the memory-axis pairing baseline

`eme_m9c_2006` carries `one_write.ct.founding_merkle.rec`: the record-side
whole-address-space page-fingerprint ROOTS, taken cross-task by the recorder
parent at the two holds the M9c capture provides (the CDRV rendezvous and
quiescence). The emulator emits the same shape per founding cursor, and the two
pair by common VA — without this sidecar the emulator's roots have nothing to
compare against and the memory axis returns no verdict at all.

Only the roots (two lines) are bundled. The per-page detail
(`.founding_merkle.rec.pages`) is **188 MB** — the §1A.9 comparison puts the whole
dyld shared cache in scope, so the walk covers ~1.56 million pages per hold — and
lives with the full recording under `~/mcr-hwtrace/eme_m9c_2006_merkle/`. A
localization drill needs it; a verdict does not.

Recorded automatically: `CT_MEM_MERKLE_FOUNDING` is armed by default in
`ct_cli/tests/record_macos_eme_m9c_2006.nim`, so `regenerate.sh` reproduces the
sidecar. `CT_MEM_MERKLE_FOUNDING=0` opts out.
