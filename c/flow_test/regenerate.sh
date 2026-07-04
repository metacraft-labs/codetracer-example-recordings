#!/usr/bin/env bash
# Regenerate the C RR flow_test recording fixture.
#
# Scripted form of the manual command sequence documented in the repo
# README ("RR recordings (Rust, C, Go, Nim)").  Builds the test program
# with `ct-rr-support` and records it into this directory, producing the
# standard CodeTracer RR trace-folder layout (rr/, files/, symbols.json,
# trace_paths.json, trace_db_metadata.json).
#
# Prerequisites:
#   - Linux host with rr support.  rr needs hardware performance counters:
#       * `kernel.perf_event_paranoid` <= 1
#         (`sudo sysctl kernel.perf_event_paranoid=1`)
#       * on bare metal / a VM that exposes the PMU; most cloud CI VMs and
#         nested virtualisation do NOT expose the counters rr requires.
#   - Nix dev shell from codetracer (provides `ct-rr-support`).
#   - The codetracer sibling checkout (source of the test programs).
#
# Recording id: RR traces store their metadata in `trace_db_metadata.json`
# with an integer `id` field — they do NOT carry a canonical UUIDv7
# `recording_id`, and `ct-rr-support` has no `--recording-id` flag.  The
# canonical id C_FLOW_TEST_RECORDING_ID below is pinned consumer-side
# (codetracer/src/common/fixture_ids.nim, .../fixture_ids.rs,
# codetracer-example-recordings/FIXTURE_IDS.md).  It is recorded here only
# for reference; it becomes embedded once the RR recorder gains v3
# `meta.dat` support (recorder-sweep #254).
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash c/flow_test/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Locate the codetracer sibling repo (source of the RR test programs).
CODETRACER="${CODETRACER:-$(cd "$REPO_ROOT/../codetracer" && pwd)}"

# Pinned canonical recording id (reference only — see header note).
C_FLOW_TEST_RECORDING_ID="019e3a35-2530-7c00-8aaa-43ff10010001"

SOURCE="$CODETRACER/src/db-backend/test-programs/c/c_flow_test.c"
BUILT="/tmp/c_flow_test"
OUT_DIR="$SCRIPT_DIR"

echo "=== Regenerating C RR flow_test fixture ==="
echo "  Source:       $SOURCE"
echo "  Built binary: $BUILT"
echo "  Output dir:   $OUT_DIR"
echo "  recording_id: $C_FLOW_TEST_RECORDING_ID (pinned consumer-side)"
echo ""

echo ">>> Building with ct-rr-support..."
ct-rr-support build "$SOURCE" "$BUILT"
echo ""

echo ">>> Recording with ct-rr-support..."
ct-rr-support record -o "$OUT_DIR" "$BUILT"
echo ""

echo "=== Done ==="
echo "  Trace folder: $OUT_DIR"
