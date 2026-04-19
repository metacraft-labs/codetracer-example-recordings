#!/usr/bin/env bash
# Regenerate the macOS ARM64 MCR recording fixture.
#
# Prerequisites:
#   - macOS on Apple Silicon (ARM64)
#   - Nix dev shell from codetracer-native-recorder (provides cc, nim)
#
# This script:
#   1. Compiles the shared ct_fixture_prog source into an ARM64 Mach-O binary
#   2. Records it with the cooperative-mode fixture generator to produce trace.ct
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer-native-recorder bash mcr/macos-arm64/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" && pwd)}"

SOURCE="$REPO_ROOT/programs/ct_fixture_prog.c"
BINARY="$SCRIPT_DIR/binaries/ct_fixture_prog"
TRACE="$SCRIPT_DIR/trace.ct"

FIXTURE_GEN="$NATIVE_RECORDER/ct_cooperative/tests/generate_recording_fixture.nim"

echo "=== Regenerating macOS ARM64 MCR fixture ==="
echo "  Source: $SOURCE"
echo "  Binary: $BINARY"
echo "  Trace:  $TRACE"
echo ""

# Step 1: Compile
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

# Step 3: Verify
TRACE_SIZE=$(wc -c < "$TRACE" | tr -d ' ')
echo "=== Done ==="
echo "  trace.ct: $TRACE_SIZE bytes"
echo "  binary:   $(wc -c < "$BINARY" | tr -d ' ') bytes"
