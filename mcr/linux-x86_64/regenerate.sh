#!/usr/bin/env bash
# Regenerate the Linux x86_64 MCR recording fixture.
#
# Produces TWO outputs:
#   1. trace.ct — raw MCR recording (for emulator unit tests)
#   2. trace-portable.ct — enriched portable trace with binaries,
#      debug symbols, and source files (for GUI E2E tests)
#
# Prerequisites:
#   - Linux x86_64 host
#   - Nix dev shell from codetracer (provides cc, ct, ct-mcr)
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash mcr/linux-x86_64/regenerate.sh

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

# Canonical, pinned recording id of the portable export. Consumers hardcode it:
#   codetracer/src/common/fixture_ids.nim
#   codetracer/src/db-backend/tests/common/fixture_ids.rs
#   codetracer-example-recordings/FIXTURE_IDS.md
# `ct-mcr record` has no option to pin the raw trace's id.
PORTABLE_RECORDING_ID="019e3a35-2540-7a00-8aaa-43ff20010002"

echo "=== Regenerating Linux x86_64 MCR fixture ==="
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
#
# `--attach=premain`: the emulator replay that consumes these fixtures starts
# from the `main` boundary that mode records (`cp0.regs` + `cp0.mem`), and
# refuses an `instruction0` recording (the Linux default, which starts at the
# execve-stop) by name.
#
# `env -i`: the recording captures the program's environment, so it is made
# with only what the program needs. Recording from a CI job or a developer
# shell otherwise publishes that shell's tokens in the fixture.
echo ">>> Recording with ct-mcr (raw)..."
rm -f "$TRACE"
env -i PATH=/usr/bin:/bin HOME=/nonexistent LANG=C TZ=UTC \
	${CT_LICENSE_DEV_NO_FFI:+CT_LICENSE_DEV_NO_FFI="$CT_LICENSE_DEV_NO_FFI"} \
	${CODETRACER_LICENSE_FILE:+CODETRACER_LICENSE_FILE="$CODETRACER_LICENSE_FILE"} \
	"$CT_MCR" record --attach=premain -o "$TRACE" -- "$BINARY"
echo ""

# Step 4: Export as portable trace (for GUI E2E tests)
echo ">>> Exporting portable trace..."
rm -f "$PORTABLE"
"$CT_MCR" export --portable -v --recording-id "$PORTABLE_RECORDING_ID" -o "$PORTABLE" "$TRACE"
echo ""

# Step 5: Verify
TRACE_SIZE=$(wc -c <"$TRACE" | tr -d ' ')
PORTABLE_SIZE=$(wc -c <"$PORTABLE" | tr -d ' ')
echo "=== Done ==="
echo "  trace.ct:          $TRACE_SIZE bytes (raw, for emulator tests)"
echo "  trace-portable.ct: $PORTABLE_SIZE bytes (enriched, for GUI E2E)"
echo "  binary:            $(wc -c <"$BINARY" | tr -d ' ') bytes"
