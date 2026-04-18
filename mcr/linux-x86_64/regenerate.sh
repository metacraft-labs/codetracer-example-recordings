#!/usr/bin/env bash
# Regenerate the Linux x86_64 MCR recording fixture.
#
# Prerequisites:
#   - Linux x86_64 host
#   - Nix dev shell from codetracer-native-recorder (provides cc, ct-mcr)
#
# This script:
#   1. Compiles the shared ct_fixture_prog source into an x86_64 ELF binary
#   2. Records it with ct-mcr (interpose mode) to produce trace.ct
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer-native-recorder bash mcr/linux-x86_64/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" && pwd)}"

SOURCE="$REPO_ROOT/programs/ct_fixture_prog.c"
BINARY="$SCRIPT_DIR/binaries/ct_fixture_prog"
TRACE="$SCRIPT_DIR/trace.ct"

CT_MCR="${NATIVE_RECORDER}/ct_cli/ct_cli"

echo "=== Regenerating Linux x86_64 MCR fixture ==="
echo "  Source: $SOURCE"
echo "  Binary: $BINARY"
echo "  Trace:  $TRACE"
echo ""

# Step 1: Compile
echo ">>> Compiling ct_fixture_prog..."
mkdir -p "$SCRIPT_DIR/binaries"
cc -O0 -g -pthread -o "$BINARY" "$SOURCE"
echo "  $(file "$BINARY")"
echo ""

# Step 2: Build ct-mcr if not already built
if [ ! -x "$CT_MCR" ]; then
  echo ">>> Building ct-mcr..."
  (cd "$NATIVE_RECORDER" && just build-ct-mcr)
  echo ""
fi

# Step 3: Record
echo ">>> Recording with ct-mcr..."
rm -f "$TRACE"
"$CT_MCR" record --use-interpose -o "$TRACE" -- "$BINARY"
echo ""

# Step 4: Verify
TRACE_SIZE=$(wc -c < "$TRACE" | tr -d ' ')
echo "=== Done ==="
echo "  trace.ct: $TRACE_SIZE bytes"
echo "  binary:   $(wc -c < "$BINARY" | tr -d ' ') bytes"
