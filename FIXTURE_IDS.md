# Fixture Recording IDs

Canonical UUIDv7 `recording_id` constants for every committed example
recording in this repository. Defined by **M-REC-12** of the Recording-Identifier
Migration (see
[`codetracer-specs/Refactoring-Plans/Recording-Identifier-Migration.md`](https://github.com/metacraft-labs/codetracer-specs)
§6.10 and §8).

## Why pin the IDs

Pre-1.0 we replaced the integer `trace_id` counter with a UUIDv7
`recording_id` minted by the recorder at record-start (M-REC-1). For test
fixtures the natural reproducibility property is "the same fixture has the
same id across machines, runs, and CI invocations" — so every committed
fixture is assigned a **stable, well-known** UUIDv7 here. Tests reference
these constants directly instead of generating fresh UUIDs at setup time.

The embedded UUIDv7 millisecond timestamp is **fictional** — set to
`2026-05-18T08:30:22Z` (the day M-REC-1 landed) plus a 1 ms offset per
fixture so they lex-sort in the order the fixtures were introduced. The
honest creation time of each fixture lives in this repository's git history
and (when the recorder is migrated to write `meta.dat` v3) in each
recording's `recorded_at` field.

## Canonical IDs

### Language-flow fixtures (`<lang>/flow_test/`)

| Fixture path                      | `recording_id`                           | Recorder                            | Notes                                                                                                                                                |
| --------------------------------- | ---------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `c/flow_test/`                    | `019e3a35-2530-7c00-8aaa-43ff10010001`   | `ct-rr-support` (RR)                | Pre-M-REC-1 metadata; RR-backend fixture. Tracked by recorder-sweep #254 — regeneration awaits the RR recorder's v3 `meta.dat` writer.               |
| `go/flow_test/`                   | `019e3a35-2531-7600-8aaa-43ff10020001`   | `ct-rr-support` (RR)                | Pre-M-REC-1 metadata; same blocker as `c/flow_test/`.                                                                                                |
| `javascript/flow_test/`           | `019e3a35-2532-7100-8aaa-43ff10030001`   | `codetracer-js-recorder`            | Lives in the **submodule** (`codetracer/examples/recordings/`, pin `c59c52d`), not in this sibling repo's tree. Same recorder-sweep #254 dependency. |
| `nim/flow_test/`                  | `019e3a35-2533-7e00-8aaa-43ff10040001`   | `ct-rr-support` (RR)                | Pre-M-REC-1 metadata; same blocker as `c/flow_test/`.                                                                                                |
| `python/flow_test/`               | `019e3a35-2534-7000-8aaa-43ff10050001`   | `codetracer-python-recorder`        | Pre-M-REC-1 metadata (`trace.bin` + `trace_metadata.json`); recorder-sweep #254.                                                                     |
| `ruby/flow_test/`                 | `019e3a35-2535-7b00-8aaa-43ff10060001`   | `codetracer-pure-ruby-recorder`     | Pre-M-REC-1 metadata (`trace.json` + `trace_metadata.json`); recorder-sweep #254.                                                                    |
| `rust/flow_test/`                 | `019e3a35-2536-7900-8aaa-43ff10070001`   | `ct-rr-support` (RR)                | Pre-M-REC-1 metadata; same blocker as `c/flow_test/`.                                                                                                |

### MCR portable-trace fixtures (`mcr/<platform>/`)

Each MCR platform fixture ships two `.ct` files: `trace.ct` (raw recording,
no embedded binaries) and `trace-portable.ct` (enriched with binaries and
debug symbols). Each gets its own `recording_id`; they are distinct
recordings.

| Fixture path                                 | `recording_id`                           | Notes                                                                                                                                                  |
| -------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `mcr/linux-x86_64/trace.ct`                  | `019e3a35-2540-7a00-8aaa-43ff20010001`   | Raw MCR trace from `ct-mcr` interpose hook. **Pre-meta.dat container** — carries JSON header `"version":"2"`. Will switch to v3 `meta.dat` on regen.   |
| `mcr/linux-x86_64/trace-portable.ct`         | `019e3a35-2540-7a00-8aaa-43ff20010002`   | Portable export of the linux-x86_64 raw trace. Same pre-meta.dat blocker.                                                                              |
| `mcr/linux-arm64/trace.ct`                   | `019e3a35-2541-7a00-8aaa-43ff20020001`   | **Pending first CI generation** — `mcr/linux-arm64/regenerate.sh` + `regen-mcr-linux-arm64.yml` exist; awaits a run on an aarch64 Linux host. Raw id embeds once the recorder gains v3 `meta.dat` (interpose `record` has no `--recording-id`). |
| `mcr/linux-arm64/trace-portable.ct`          | `019e3a35-2541-7a00-8aaa-43ff20020002`   | **Pending first CI generation** — pinned on the `ct-mcr export --portable --recording-id` step in `regenerate.sh`.                                     |
| `mcr/macos-arm64/trace.ct`                   | `019e3a35-2542-7a00-8aaa-43ff20030001`   | Apple Silicon M1 recording; pre-meta.dat blocker.                                                                                                      |
| `mcr/macos-arm64/trace-portable.ct`          | `019e3a35-2542-7a00-8aaa-43ff20030002`   | Portable export of the macOS ARM64 raw trace.                                                                                                          |
| `mcr/ios-arm64/trace.ct`                     | `019e3a35-2543-7a00-8aaa-43ff20040001`   | iPhone 17 Pro simulator recording; pre-meta.dat blocker.                                                                                               |
| `mcr/ios-arm64/trace-portable.ct`            | `019e3a35-2543-7a00-8aaa-43ff20040002`   | Portable export of the iOS ARM64 raw trace.                                                                                                            |
| `mcr/android-arm64/trace.ct`                 | `019e3a35-2544-7a00-8aaa-43ff20050001`   | Samsung Galaxy S24 Ultra recording; pre-meta.dat blocker.                                                                                              |
| `mcr/android-arm64/trace-portable.ct`        | `019e3a35-2544-7a00-8aaa-43ff20050002`   | Portable export of the Android ARM64 raw trace.                                                                                                        |
| `mcr/windows-x86_64/trace.ct`                | `019e3a35-2545-7a00-8aaa-43ff20060001`   | Windows 11 x64 recording (interpose); pre-meta.dat blocker.                                                                                            |
| `mcr/windows-x86_64/trace-portable.ct`       | `019e3a35-2545-7a00-8aaa-43ff20060002`   | Portable export of the Windows x86_64 raw trace.                                                                                                       |

## Test-side mirrors

Two source-tree mirrors of this table are kept in lockstep — change one,
change all three:

- **Rust:**
  [`codetracer/src/db-backend/tests/common/fixture_ids.rs`](https://github.com/metacraft-labs/codetracer/blob/main/src/db-backend/tests/common/fixture_ids.rs)
  — re-exports each ID as a `pub const &str`.
- **Nim:**
  [`codetracer/src/common/fixture_ids.nim`](https://github.com/metacraft-labs/codetracer/blob/main/src/common/fixture_ids.nim)
  — re-exports each ID as a `const string*`.

Both modules import the table by value (no runtime parse step); the
canonical authority is this Markdown file.

## How regeneration interacts with the recorder sweep

The recorders that produced these fixtures (RR-backend, the pure-Ruby
recorder, the Python recorder, `ct-mcr`) still emit the **pre-M-REC-1
metadata layout** — either the legacy
`trace.bin`/`trace.json`+`trace_metadata.json`+`trace_paths.json` triplet,
or the legacy JSON header inside `.ct` containers. The db-backend reader
rejects those now (M-REC-1.5 made v3 `meta.dat` the only supported form).

Until each recorder is migrated to write the v3 `meta.dat` block (tracked
as **recorder-sweep #254**, a parallel initiative to this migration),
regenerating these fixtures with their current recorders produces traces
that still fail to load. Two paths forward:

1. **Recommended:** wait for recorder-sweep #254 to land per-recorder v3
   support, then run each fixture's `regenerate.sh` (where present) under
   the migrated recorder. The IDs in this file remain pinned.
2. **Fallback (per-fixture, opt-in):** write a small migration utility
   that opens an existing `.ct` container, replaces the JSON header with a
   v3 `meta.dat` block carrying the canonical id from this table, and
   re-seals the container. This avoids re-running the recorder but is
   deliberately scoped to "translate the metadata block" — it doesn't fix
   anything else inside the container.

Either way, the ids in this table never change.

## Adding a new fixture

1. Pick the next unused millisecond offset in the appropriate range
   (language fixtures live in the `019e3a35-25{30..3f}` band; MCR fixtures
   live in the `019e3a35-25{40..4f}` band).
2. Pick a low-entropy 16-character `XXXXXXXXXXXX` suffix that encodes the
   fixture's role (the existing entries use `43ff` as a prefix and embed a
   short numeric tag — see the linux-x86_64 entry for the convention).
3. Validate that the resulting string is a canonical UUIDv7:
   - 36 characters total, lowercase hex + four hyphens at positions
     8/13/18/23.
   - Position 14 must be `7` (version nibble).
   - Position 19 must be one of `8`/`9`/`a`/`b` (variant nibble).
4. Append the row to the table above **and** to both
   `fixture_ids.{rs,nim}` mirrors.
