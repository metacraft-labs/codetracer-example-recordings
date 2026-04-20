#!/usr/bin/env bash
# Regenerate the iOS ARM64 MCR recording fixture.
#
# Produces TWO outputs:
#   1. trace.ct — raw CTSP recording (for emulator unit tests)
#   2. trace-portable.ct — enriched portable trace with binaries,
#      debug symbols, and source files (for GUI E2E tests)
#
# Prerequisites:
#   - macOS with Xcode (provides xcrun, simctl, iOS simulator SDK)
#   - A booted iOS simulator (or one will be booted automatically)
#   - Nix dev shell from codetracer (provides nim, ct-mcr)
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer bash mcr/ios-arm64/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Locate sibling repos
CODETRACER="${CODETRACER:-$(cd "$REPO_ROOT/../codetracer" && pwd)}"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" && pwd)}"

SOURCE="$REPO_ROOT/programs/ctsp_client.c"
BINARY="$SCRIPT_DIR/binaries/ios_ctsp_client"
TRACE="$SCRIPT_DIR/trace.ct"
PORTABLE="$SCRIPT_DIR/trace-portable.ct"

CTSP_PORT=14292

RECEIVER_PID=""
CLEANUP_DONE=false

cleanup() {
  if $CLEANUP_DONE; then return; fi
  CLEANUP_DONE=true

  echo ""
  echo ">>> Cleaning up..."

  if [ -n "$RECEIVER_PID" ] && kill -0 "$RECEIVER_PID" 2>/dev/null; then
    kill "$RECEIVER_PID" 2>/dev/null || true
    wait "$RECEIVER_PID" 2>/dev/null || true
  fi

  echo "  Cleanup done."
}
trap cleanup EXIT

echo "=== Regenerating iOS ARM64 MCR fixture ==="
echo "  Source: $SOURCE"
echo "  Binary: $BINARY"
echo "  Trace:  $TRACE"
echo "  Portable: $PORTABLE"
echo ""

# Step 1: Find a booted iOS simulator
echo ">>> Detecting iOS simulator..."

SIM_UDID=$(xcrun simctl list devices booted -j 2>/dev/null \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for runtime, devs in data.get('devices', {}).items():
    for d in devs:
        if d.get('state') == 'Booted':
            print(d['udid'])
            sys.exit(0)
sys.exit(1)
" 2>/dev/null || true)

if [ -z "$SIM_UDID" ]; then
  echo "  No booted simulator found, looking for available simulators..."
  # Find and boot the first available iPhone simulator
  SIM_UDID=$(xcrun simctl list devices available -j 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for runtime, devs in data.get('devices', {}).items():
    if 'iOS' not in runtime:
        continue
    for d in devs:
        if d.get('isAvailable', False) and 'iPhone' in d.get('name', ''):
            print(d['udid'])
            sys.exit(0)
sys.exit(1)
" 2>/dev/null || true)

  if [ -z "$SIM_UDID" ]; then
    echo "ERROR: no available iPhone simulator found"
    exit 1
  fi

  echo "  Booting simulator $SIM_UDID..."
  xcrun simctl boot "$SIM_UDID"
  sleep 3
fi

SIM_NAME=$(xcrun simctl list devices -j 2>/dev/null \
  | python3 -c "
import sys, json
udid = '$SIM_UDID'
data = json.load(sys.stdin)
for runtime, devs in data.get('devices', {}).items():
    for d in devs:
        if d['udid'] == udid:
            print(d['name'])
            sys.exit(0)
" 2>/dev/null || echo "unknown")

echo "  Simulator: $SIM_NAME ($SIM_UDID)"
echo ""

# Step 2: Compile for iOS simulator
echo ">>> Compiling CTSP client for iOS simulator..."
mkdir -p "$SCRIPT_DIR/binaries"

SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
XCODE_CLANG=$(xcrun --sdk iphonesimulator -f clang)

"$XCODE_CLANG" \
  -target arm64-apple-ios18.0-simulator \
  -isysroot "$SDK_PATH" \
  -O0 -g \
  -o "$BINARY" "$SOURCE"

echo "  $(file "$BINARY")"
echo ""

# Step 3: Build stream-receiver helper
echo ">>> Building stream-receiver helper (Nim)..."

RECEIVER_SRC="$NATIVE_RECORDER/ct_cooperative/tests/android_stream_receiver_helper.nim"
RECEIVER_BIN="$SCRIPT_DIR/binaries/stream_receiver_helper"

direnv exec "$NATIVE_RECORDER" nim c \
  -o:"$RECEIVER_BIN" \
  --threads:on \
  "$RECEIVER_SRC"
echo ""

# Step 4: Start receiver and spawn on simulator
echo ">>> Starting stream-receiver and spawning on simulator..."

rm -f "$TRACE"
"$RECEIVER_BIN" "$CTSP_PORT" "$TRACE" &
RECEIVER_PID=$!
sleep 1

if ! kill -0 "$RECEIVER_PID" 2>/dev/null; then
  echo "ERROR: stream-receiver died immediately"
  RECEIVER_PID=""
  exit 1
fi

# simctl spawn requires the binary to be accessible to the simulator
xcrun simctl spawn "$SIM_UDID" "$BINARY" 127.0.0.1 "$CTSP_PORT"
echo ""

# Step 5: Wait for receiver to finish
echo ">>> Waiting for trace file..."
for i in $(seq 1 10); do
  if ! kill -0 "$RECEIVER_PID" 2>/dev/null; then
    break
  fi
  if [ "$i" -eq 10 ]; then
    kill "$RECEIVER_PID" 2>/dev/null || true
  fi
  sleep 1
done
wait "$RECEIVER_PID" 2>/dev/null || true
RECEIVER_PID=""

# Remove the temporary receiver binary
rm -f "$RECEIVER_BIN"

if [ ! -f "$TRACE" ]; then
  echo "ERROR: trace file not produced"
  exit 1
fi

# Step 6: Find ct-mcr
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

# Step 7: Export as portable trace (for GUI E2E tests)
echo ">>> Exporting portable trace..."
rm -f "$PORTABLE"
"$CT_MCR" export --portable -v -o "$PORTABLE" "$TRACE"
echo ""

# Step 8: Verify
TRACE_SIZE=$(wc -c < "$TRACE" | tr -d ' ')
PORTABLE_SIZE=$(wc -c < "$PORTABLE" | tr -d ' ')
echo "=== Done ==="
echo "  trace.ct:          $TRACE_SIZE bytes (raw, for emulator tests)"
echo "  trace-portable.ct: $PORTABLE_SIZE bytes (enriched, for GUI E2E)"
echo "  binary:            $(wc -c < "$BINARY" | tr -d ' ') bytes"
