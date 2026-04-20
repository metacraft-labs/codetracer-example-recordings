#!/usr/bin/env bash
# Regenerate the macOS ARM64 MCR recording fixture.
#
# Produces TWO outputs:
#   1. trace.ct — raw cooperative-mode recording (for emulator unit tests)
#   2. trace-portable.ct — enriched portable trace with binaries,
#      debug symbols, and source files (for GUI E2E tests)
#
# Prerequisites:
#   - macOS on Apple Silicon (ARM64)
#   - Nix dev shell from codetracer (provides cc, ct-mcr, nim)
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash mcr/macos-arm64/regenerate.sh

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

FIXTURE_GEN="$NATIVE_RECORDER/ct_cooperative/tests/generate_recording_fixture.nim"

echo "=== Regenerating macOS ARM64 MCR fixture ==="
echo "  Source: $SOURCE"
echo "  Binary: $BINARY"
echo "  Trace:  $TRACE"
echo "  Portable: $PORTABLE"
echo ""

# Step 1: Compile with debug info
echo ">>> Compiling ct_fixture_prog..."
mkdir -p "$SCRIPT_DIR/binaries"
cc -O0 -g -lpthread -o "$BINARY" "$SOURCE"
echo "  $(file "$BINARY")"
echo ""

# Step 2: Record (cooperative mode via fixture generator)
echo ">>> Recording with cooperative-mode fixture generator..."
rm -f "$TRACE"
(cd "$NATIVE_RECORDER" && nim c -r "$FIXTURE_GEN" -- \
  --output="$TRACE" \
  --program="$BINARY")
echo ""

# Step 3: Find ct-mcr
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

# Step 4: Export as portable trace (for GUI E2E tests)
echo ">>> Exporting portable trace..."
rm -f "$PORTABLE"
"$CT_MCR" export --portable -v -o "$PORTABLE" "$TRACE"
echo ""

# Step 5: Verify
TRACE_SIZE=$(wc -c < "$TRACE" | tr -d ' ')
PORTABLE_SIZE=$(wc -c < "$PORTABLE" | tr -d ' ')
echo "=== Done ==="
echo "  trace.ct:          $TRACE_SIZE bytes (raw, for emulator tests)"
echo "  trace-portable.ct: $PORTABLE_SIZE bytes (enriched, for GUI E2E)"
echo "  binary:            $(wc -c < "$BINARY" | tr -d ' ') bytes"
