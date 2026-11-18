#!/usr/bin/env bash
# Regenerate the Nim rr flow_test recording fixture.
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
#   - The codetracer nix dev shell, which provides ct-native-replay and gcc.
#     Nim is stock Nim, built with `nix` from codetracer's nixpkgs pin (see
#     NIM_BIN below), not the dev shell's `nim`.
#   - The codetracer sibling checkout (source of the test program).
#
# Recording id: rr traces carry no canonical UUIDv7 `recording_id`; the id
# NIM_FLOW_TEST_RECORDING_ID below is pinned consumer-side (codetracer/src/common/fixture_ids.nim,
# .../fixture_ids.rs, FIXTURE_IDS.md).
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash nim/flow_test/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODETRACER="${CODETRACER:-$(cd "$REPO_ROOT/../codetracer" && pwd)}"

NIM_FLOW_TEST_RECORDING_ID="019e3a35-2533-7e00-8aaa-43ff10040001"

B=/tmp/ct-example-recordings-build
NR="$(command -v ct-native-replay)"

# The fixture is built with STOCK Nim, not the `nim` the codetracer dev shell
# puts first on PATH. That one is CodeTracer's Nim fork, whose C backend no
# longer writes `#line` directives: it maps C to Nim through `<file>.c.map`
# side files instead. Without directives the binary's DWARF names only the
# generated C, so the recording bundles no Nim source, reports its language
# as C, and the consumers that read the bundled C's directives
# (codetracer's test_nim_c_producer, the TUI/GPUI Generated C Source tests)
# find none. Stock Nim with `--debugger:native` writes them. The default is
# the `nim-unwrapped` of codetracer's own nixpkgs pin, so the compiler is
# pinned by the consumer's flake.lock; NIM_BIN (a directory holding `nim`)
# overrides it.
NIM_BIN="${NIM_BIN:-$(nix build --no-link --print-out-paths --inputs-from "$CODETRACER" nixpkgs#nim-unwrapped)/bin}"
TOOLPATH="$NIM_BIN:$(dirname "$(command -v gcc)"):$(dirname "$NR"):/usr/bin:/bin"

mkdir -p "$B/home" "$B/cache" "$B/tmp"
# Start from an empty nimcache: the #line check below reads it, and C left by
# an earlier run (made with another compiler) would satisfy or fail it falsely.
rm -rf "$B/cache/nim/nim_flow_test_d"
cp "$CODETRACER/src/db-backend/test-programs/nim/nim_flow_test.nim" "$B/nim_flow_test.nim"

echo ">>> Building $B/nim_flow_test.nim"
(cd "$B" && env -i PATH="$TOOLPATH" HOME="$B/home" XDG_CACHE_HOME="$B/cache" TMPDIR="$B/tmp" \
  LANG=C TZ=UTC GOCACHE="$B/cache/go" GOPATH="$B/home/go" \
  "$NR" build "$B/nim_flow_test.nim" "$B/nim_flow_test")

# The fork's version banner is indistinguishable from stock Nim's, so check
# the output instead: the generated C must carry `#line` directives. (Stock
# Nim rot13-encodes its nimcache file names — `@mnim_flow_test.nim.c` is
# written as `@zavz_sybj_grfg.nim.c` — so match any generated C file.)
if ! grep -qs '^#line ' "$B"/cache/nim/nim_flow_test_d/*.nim.c; then
  echo "error: the generated C has no #line directives ($NIM_BIN/nim is not stock Nim?)" >&2
  exit 1
fi

echo ">>> Recording into $B/out-nim"
rm -rf "$B/out-nim"
(cd "$B" && env -i PATH="$(dirname "$NR"):/usr/bin:/bin" HOME="$B/home" TMPDIR="$B/tmp" \
  LANG=C TZ=UTC "$NR" record -o "$B/out-nim" "$B/nim_flow_test")

echo ">>> Installing into $SCRIPT_DIR"
find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 ! -name regenerate.sh -exec rm -rf {} +
cp -a "$B/out-nim/." "$SCRIPT_DIR/"
echo "=== Done (recording_id $NIM_FLOW_TEST_RECORDING_ID pinned consumer-side) ==="
