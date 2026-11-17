#!/usr/bin/env bash
# Regenerate the Go rr flow_test recording fixture.
#
# Builds the test program with `ct-native-replay build` and records it with
# `ct-native-replay record` into this directory, producing the CodeTracer rr
# trace-folder layout (rr/, files/, trace.ct, symbols.json, trace_paths.json,
# trace_db_metadata.json).
#
# A recording keeps the paths it was made from (the source, the binary, the
# working and output folders), and rr captures the program's environment. So
# everything happens under the neutral `/tmp/ct-example-recordings-build`, with
# a cleared environment and HOME inside it: no home directory and no shell
# variable reaches the fixture.
#
# The Go runtime reads /proc/self/mountinfo and /proc/self/cgroup at start
# (container-aware GOMAXPROCS), so rr records the host's mount table, home
# directories included, whatever GOMAXPROCS or GODEBUG say. The recording
# therefore runs in a bubblewrap sandbox whose only mounts are /nix, the build
# directory, the codetracer checkouts, /proc, /dev, /sys, /etc, /bin and /usr.
#
# Prerequisites:
#   - Linux host with rr support (`kernel.perf_event_paranoid` <= 1, a PMU the
#     host exposes: bare metal or a VM that passes the counters through).
#   - bubblewrap (`bwrap`) on PATH.
#   - The codetracer nix dev shell, which provides ct-native-replay and the
#     Go toolchain.
#   - The codetracer sibling checkout (source of the test program).
#
# Recording id: rr traces carry no canonical UUIDv7 `recording_id`; the id
# GO_FLOW_TEST_RECORDING_ID below is pinned consumer-side (codetracer/src/common/fixture_ids.nim,
# .../fixture_ids.rs, FIXTURE_IDS.md).
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash go/flow_test/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODETRACER="${CODETRACER:-$(cd "$REPO_ROOT/../codetracer" && pwd)}"

GO_FLOW_TEST_RECORDING_ID="019e3a35-2531-7600-8aaa-43ff10020001"

B=/tmp/ct-example-recordings-build
NR="$(command -v ct-native-replay)"
TOOLPATH="$(dirname "$(command -v go)"):$(dirname "$(command -v gcc)"):$(dirname "$NR"):/usr/bin:/bin"

mkdir -p "$B/home" "$B/cache" "$B/tmp"
cp "$CODETRACER/src/db-backend/test-programs/go/go_flow_program.go" "$B/go_flow_program.go"

echo ">>> Building $B/go_flow_program.go"
(cd "$B" && env -i PATH="$TOOLPATH" HOME="$B/home" XDG_CACHE_HOME="$B/cache" TMPDIR="$B/tmp" \
  LANG=C TZ=UTC GOCACHE="$B/cache/go" GOPATH="$B/home/go" \
  "$NR" build "$B/go_flow_program.go" "$B/go_flow_program")

echo ">>> Recording into $B/out-go"
rm -rf "$B/out-go"
BWRAP="$(command -v bwrap)"
CHECKOUTS="$(cd "$REPO_ROOT/.." && pwd)"
env -i PATH="$(dirname "$NR"):/usr/bin:/bin" HOME="$B/home" TMPDIR="$B/tmp" LANG=C TZ=UTC GOMAXPROCS=2 \
  "$BWRAP" --ro-bind /nix /nix --ro-bind "$CHECKOUTS" "$CHECKOUTS" --bind "$B" "$B" \
  --proc /proc --dev /dev --ro-bind /sys /sys --tmpfs /run --ro-bind /etc /etc \
  --ro-bind /bin /bin --ro-bind /usr /usr --chdir "$B" -- \
  "$NR" record -o "$B/out-go" "$B/go_flow_program"

echo ">>> Installing into $SCRIPT_DIR"
find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 ! -name regenerate.sh -exec rm -rf {} +
cp -a "$B/out-go/." "$SCRIPT_DIR/"
echo "=== Done (recording_id $GO_FLOW_TEST_RECORDING_ID pinned consumer-side) ==="
