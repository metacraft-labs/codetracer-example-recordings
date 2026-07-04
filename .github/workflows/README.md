# Fixture regeneration workflows

These workflows regenerate the recording fixtures that require a specific
runner class to produce them: the **device-bound** MCR fixtures under
`mcr/<platform>/`, and the Linux-only **RR language** fixtures under
`<lang>/flow_test/`. The `macos-arm64` MCR fixture is refreshed by a
developer on an Apple Silicon Mac and has no workflow here.

All workflows are **`workflow_dispatch`** (manual). Each has an optional
monthly `schedule` cron that is commented out — enable it per platform if
unattended refresh is wanted (except `android-arm64`, which is physically
device-bound and intentionally manual-only).

| Workflow file | Fixture(s) | Runner it needs | Regen script |
|---|---|---|---|
| `regen-mcr-linux-x86_64.yml` | `mcr/linux-x86_64` | `[self-hosted, nixos]` | `mcr/linux-x86_64/regenerate.sh` |
| `regen-mcr-linux-arm64.yml` | `mcr/linux-arm64` | `[self-hosted, nixos, aarch64-linux]` | `mcr/linux-arm64/regenerate.sh` |
| `regen-mcr-windows-x86_64.yml` | `mcr/windows-x86_64` | `[self-hosted, windows]` (VS Build Tools) | `mcr/windows-x86_64/regenerate.ps1` |
| `regen-mcr-ios-arm64.yml` | `mcr/ios-arm64` | `[self-hosted, macos]` with Xcode + iOS simulator | `mcr/ios-arm64/regenerate.sh` |
| `regen-mcr-android-arm64.yml` | `mcr/android-arm64` | `[self-hosted, android]` with adb device/AVD + NDK | `mcr/android-arm64/regenerate.sh` |
| `regen-rr-language-recordings.yml` | `rust/`, `c/`, `go/`, `nim/` `flow_test/` | `[self-hosted, nixos, x86-64-v2, bare-metal]` (rr needs PMU) | `<lang>/flow_test/regenerate.sh` (matrix) |

## How each job works

1. Mints a short-lived installation token via the **CI Token Provider**
   GitHub App (`actions/create-github-app-token`).
2. Checks out this repo (`lfs: true`, since the traces are Git LFS objects).
3. Clones the sibling repos the regen scripts expect into the adjacent
   layout — `../codetracer` (Nix dev shell: `cc`, `nim`, `ct-mcr`,
   `direnv`) and `../codetracer-native-recorder` (ct-mcr source) — pinned
   to the `codetracer_ref` / `native_recorder_ref` dispatch inputs
   (defaults: `codetracer=dev`, `codetracer-native-recorder=main`).
4. Sets up Nix (Linux/macOS/Android) or the codetracer `windows-diy` env
   (Windows), then runs the platform's regenerate script exactly as
   documented in the repo README
   (`direnv exec ../codetracer bash mcr/<p>/regenerate.sh`, or the
   `.ps1` on Windows).
5. **Result handling — both, to be safe:**
   - Uploads the refreshed `trace.ct` / `trace-portable.ct` / `binaries/`
     as a workflow **artifact** (always).
   - Opens a **pull request** (`peter-evans/create-pull-request`) with the
     refreshed fixtures, using the app token.

The scripts preserve the canonical `--recording-id` pinning contract where
they implement it (see `mcr/macos-arm64/regenerate.sh` and `FIXTURE_IDS.md`);
the workflows do not weaken it — they only invoke the scripts unchanged.

## Caveats

- **android-arm64** — hardest platform. It needs a *real* adb-reachable
  arm64 target: a physical phone on a self-hosted runner, or an arm64
  emulator on an arm64 host. Hosted GitHub runners have no phone, and
  `reactivecircus/android-emulator-runner` on the hosted Linux images only
  offers x86/x86_64 system images (wrong architecture for this fixture).
  The job fails fast if no authorised device is visible to adb.
- **ios-arm64** — records against the iOS *simulator* (arm64-apple-ios-
  simulator), so it needs a macOS runner with Xcode + the iOS simulator
  SDK. The job fails fast if `xcrun simctl` is unavailable.
- **windows-x86_64** — the sibling repos' existing "Windows Tests" workflow
  still uses the hosted `windows-latest` image; this job targets
  `[self-hosted, windows]` because it needs the full ct-mcr toolchain. If
  the self-hosted Windows pool is not yet online, switch `runs-on` to
  `windows-latest` (ensure VS Build Tools are installed).
- **linux-arm64** — like linux-x86_64 but records on an aarch64 Linux host
  (the ct-mcr interpose backend records the host-architecture binary).
  `regen-mcr-linux-arm64.yml` mirrors the x86_64 workflow.
  **Runner-label assumption:** it targets
  `[self-hosted, nixos, aarch64-linux]` — the x86_64 job's
  `[self-hosted, nixos]` plus a Nix-system arch qualifier, by analogy with
  the macOS pool's `aarch64-darwin`. If the arm64 NixOS pool registers
  under a different label, update `runs-on` in that workflow to match.
  The interpose `record` step cannot pin the raw trace's `recording_id`
  (no `--recording-id` on `ct-mcr record`); only the portable export pins
  it. Both ids remain reserved in `FIXTURE_IDS.md`.
- **RR language recordings** (`rust/`, `c/`, `go/`, `nim/`) are Linux-only
  and now script-driven: each `<lang>/flow_test/regenerate.sh` scripts the
  `ct-rr-support build` + `ct-rr-support record` sequence documented in the
  top-level README. `regen-rr-language-recordings.yml` runs them as a
  matrix. **rr prerequisite:** rr replays by counting retired instructions
  via the CPU PMU, so it needs `kernel.perf_event_paranoid <= 1` and real
  PMU access — hosted/nested-virt runners typically lack this, hence the
  `[self-hosted, nixos, x86-64-v2, bare-metal]` target; the job fails fast
  if `perf_event_paranoid > 1`. RR traces carry no canonical UUIDv7
  `recording_id` (their `trace_db_metadata.json` uses an integer `id`, and
  `ct-rr-support` has no `--recording-id`); the canonical ids are pinned
  consumer-side in `fixture_ids.{nim,rs}` + `FIXTURE_IDS.md`.
- **Git LFS + PRs** — the trace files are LFS-tracked (linux-x86_64's
  `trace-portable.ct` is ~90 MB). `peter-evans/create-pull-request` commits
  the working-tree changes; make sure the repo's LFS quota / server allows
  the pushed objects. The artifact upload is the reliable fallback if the
  LFS-backed PR push is problematic.

## PREREQUISITE — CI token-provider registration

Every workflow's app-token step and PR creation depend on this repo being
registered with the **CI Token Provider** GitHub App, exposing:

- `secrets.CI_TOKEN_PROVIDER_APP_ID`
- `secrets.CI_TOKEN_PROVIDER_PRIVATE_KEY`
- `vars.ATTIC_SUBSTITUTER` / `vars.ATTIC_TRUSTED_PUBLIC_KEY` (for Set up Nix)

If `codetracer-example-recordings` is **not yet registered** with the token
provider app (owner `metacraft-labs`), these workflows cannot mint a token
and will fail at the first step. **Infra follow-up:** register this repo
with the CI token-provider app and grant it access to the `codetracer` and
`codetracer-native-recorder` repos, and set the Attic vars — mirroring the
`codetracer` / `codetracer-native-recorder` setup.
