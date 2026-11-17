#!/usr/bin/env bash
# Regenerate the C rr flow_test recording fixture.
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
# Prerequisites:
#   - Linux host with rr support (`kernel.perf_event_paranoid` <= 1, a PMU the
#     host exposes: bare metal or a VM that passes the counters through).
#   - The codetracer nix dev shell, which provides ct-native-replay and the
#     C toolchain.
#   - The codetracer sibling checkout (source of the test program).
#
# Recording id: rr traces carry no canonical UUIDv7 `recording_id`; the id
# C_FLOW_TEST_RECORDING_ID below is pinned consumer-side (codetracer/src/common/fixture_ids.nim,
# .../fixture_ids.rs, FIXTURE_IDS.md).
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash c/flow_test/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODETRACER="${CODETRACER:-$(cd "$REPO_ROOT/../codetracer" && pwd)}"

C_FLOW_TEST_RECORDING_ID="019e3a35-2530-7c00-8aaa-43ff10010001"

B=/tmp/ct-example-recordings-build
NR="$(command -v ct-native-replay)"
TOOLPATH="$(dirname "$(command -v gcc)"):$(dirname "$(command -v gcc)"):$(dirname "$NR"):/usr/bin:/bin"

mkdir -p "$B/home" "$B/cache" "$B/tmp"
cp "$CODETRACER/src/db-backend/test-programs/c/c_flow_test.c" "$B/c_flow_test.c"

echo ">>> Building $B/c_flow_test.c"
(cd "$B" && env -i PATH="$TOOLPATH" HOME="$B/home" XDG_CACHE_HOME="$B/cache" TMPDIR="$B/tmp" \
  LANG=C TZ=UTC GOCACHE="$B/cache/go" GOPATH="$B/home/go" \
  "$NR" build "$B/c_flow_test.c" "$B/c_flow_test")

echo ">>> Recording into $B/out-c"
rm -rf "$B/out-c"
(cd "$B" && env -i PATH="$(dirname "$NR"):/usr/bin:/bin" HOME="$B/home" TMPDIR="$B/tmp" \
  LANG=C TZ=UTC "$NR" record -o "$B/out-c" "$B/c_flow_test")

echo ">>> Installing into $SCRIPT_DIR"
find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 ! -name regenerate.sh -exec rm -rf {} +
cp -a "$B/out-c/." "$SCRIPT_DIR/"
echo "=== Done (recording_id $C_FLOW_TEST_RECORDING_ID pinned consumer-side) ==="
