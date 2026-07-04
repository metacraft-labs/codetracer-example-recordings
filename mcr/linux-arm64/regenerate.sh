#!/usr/bin/env bash
# Regenerate the Linux ARM64 MCR recording fixture.
#
# Produces TWO outputs:
#   1. trace.ct — raw MCR recording (for emulator unit tests)
#   2. trace-portable.ct — enriched portable trace with binaries,
#      debug symbols, and source files (for GUI E2E tests)
#
# Prerequisites:
#   - Linux ARM64 (aarch64) host
#   - Nix dev shell from codetracer (provides cc, ct, ct-mcr)
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash mcr/linux-arm64/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Locate sibling repos
CODETRACER="${CODETRACER:-$(cd "$REPO_ROOT/../codetracer" && pwd)}"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" && pwd)}"

SOURCE="$REPO_ROOT/programs/ct_fixture_prog.c"
BINARY="$SCRIPT_DIR/binaries/ct_fixture_prog"
TRACE="$SCRIPT_DIR/trace.ct"
PORTABLE="$SCRIPT_DIR/trace-portable.ct"

# Canonical, pinned recording ids. Consumers hardcode these:
#   codetracer/src/common/fixture_ids.nim
#   codetracer/src/db-backend/tests/common/fixture_ids.rs
#   codetracer-example-recordings/FIXTURE_IDS.md
# Keep them in sync there if they ever change.
#
# NOTE on the raw trace id: the Linux interpose backend records via
# `ct-mcr record --use-interpose`, which does NOT (yet) accept a
# `--recording-id` flag to pin the raw container's recording_id — the
# raw MCR container is still a pre-meta.dat v2 container (see
# FIXTURE_IDS.md).  RECORDING_ID below is therefore the *reserved*
# canonical id for the raw trace; it becomes embedded once the recorder
# gains v3 meta.dat support (recorder-sweep #254).  The portable export,
# however, does honor `--recording-id`, so PORTABLE_RECORDING_ID is
# pinned on the `ct-mcr export --portable` step below (matching
# mcr/macos-arm64/regenerate.sh).
RECORDING_ID="019e3a35-2541-7a00-8aaa-43ff20020001"
PORTABLE_RECORDING_ID="019e3a35-2541-7a00-8aaa-43ff20020002"

echo "=== Regenerating Linux ARM64 MCR fixture ==="
echo "  Source: $SOURCE"
echo "  Binary: $BINARY"
echo "  Trace:  $TRACE"
echo "  Portable: $PORTABLE"
echo ""

# Step 1: Compile with debug info
echo ">>> Compiling ct_fixture_prog..."
mkdir -p "$SCRIPT_DIR/binaries"
cc -O0 -g -pthread -o "$BINARY" "$SOURCE"
echo "  $(file "$BINARY")"
echo ""

# Step 2: Find ct-mcr
CT_MCR=""
if [ -x "$NATIVE_RECORDER/ct_cli/ct_cli" ]; then
	CT_MCR="$NATIVE_RECORDER/ct_cli/ct_cli"
elif command -v ct-mcr &>/dev/null; then
	CT_MCR=$(command -v ct-mcr)
fi

if [ -z "$CT_MCR" ]; then
	echo ">>> Building ct-mcr..."
	(cd "$NATIVE_RECORDER" && just build-ct-mcr)
	CT_MCR="$NATIVE_RECORDER/ct_cli/ct_cli"
fi
echo "  ct-mcr: $CT_MCR"
echo ""

# Step 3: Raw MCR recording (for emulator unit tests)
# `record --use-interpose` has no `--recording-id`; see RECORDING_ID note above.
echo ">>> Recording with ct-mcr (raw)..."
rm -f "$TRACE"
"$CT_MCR" record --use-interpose -o "$TRACE" -- "$BINARY"
echo ""

# Step 4: Export as portable trace (for GUI E2E tests)
# Pin the exported recording_id to the reserved canonical value.
echo ">>> Exporting portable trace..."
rm -f "$PORTABLE"
"$CT_MCR" export --portable -v \
	--recording-id "$PORTABLE_RECORDING_ID" -o "$PORTABLE" "$TRACE"
echo ""

# Step 5: Verify
TRACE_SIZE=$(wc -c <"$TRACE" | tr -d ' ')
PORTABLE_SIZE=$(wc -c <"$PORTABLE" | tr -d ' ')
echo "=== Done ==="
echo "  trace.ct:          $TRACE_SIZE bytes (raw, for emulator tests)"
echo "  trace-portable.ct: $PORTABLE_SIZE bytes (enriched, for GUI E2E)"
echo "  binary:            $(wc -c <"$BINARY" | tr -d ' ') bytes"
