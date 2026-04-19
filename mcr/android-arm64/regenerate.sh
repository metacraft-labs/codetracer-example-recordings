#!/usr/bin/env bash
# Regenerate the Android ARM64 MCR recording fixture.
#
# Prerequisites:
#   - Android phone connected via USB (adb devices shows it)
#   - Android NDK installed ($ANDROID_NDK_HOME or auto-detected)
#   - Nix dev shell from codetracer-native-recorder (for building stream-receiver)
#
# This script:
#   1. Cross-compiles the CTSP client for Android ARM64 using NDK clang
#   2. Builds the stream-receiver helper on the Mac
#   3. Pushes the binary to the phone, runs it, and receives the trace
#
# Run from the codetracer-example-recordings repo root:
#   direnv exec ../codetracer-native-recorder bash mcr/android-arm64/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" && pwd)}"

SOURCE="$REPO_ROOT/programs/ctsp_client.c"
BINARY="$SCRIPT_DIR/binaries/android_ctsp_client"
TRACE="$SCRIPT_DIR/trace.ct"

CTSP_PORT=14290
DEVICE_BINARY_PATH="/data/local/tmp/android_ctsp_client"

RECEIVER_PID=""
CLEANUP_DONE=false
DEVICE_ID=""

cleanup() {
  if $CLEANUP_DONE; then return; fi
  CLEANUP_DONE=true

  echo ""
  echo ">>> Cleaning up..."

  if [ -n "$RECEIVER_PID" ] && kill -0 "$RECEIVER_PID" 2>/dev/null; then
    kill "$RECEIVER_PID" 2>/dev/null || true
    wait "$RECEIVER_PID" 2>/dev/null || true
  fi

  if [ -n "$DEVICE_ID" ]; then
    adb -s "$DEVICE_ID" reverse --remove tcp:$CTSP_PORT 2>/dev/null || true
    adb -s "$DEVICE_ID" shell rm -f "$DEVICE_BINARY_PATH" 2>/dev/null || true
  fi

  echo "  Cleanup done."
}
trap cleanup EXIT

echo "=== Regenerating Android ARM64 MCR fixture ==="
echo "  Source: $SOURCE"
echo "  Binary: $BINARY"
echo "  Trace:  $TRACE"
echo ""

# Step 1: Detect Android device
echo ">>> Detecting Android device..."

DEVICE_LINE=$(adb devices | grep -v "^List" | grep -v "^$" | head -1)
if [ -z "$DEVICE_LINE" ]; then
  echo "ERROR: no Android device connected"
  exit 1
fi

DEVICE_ID=$(echo "$DEVICE_LINE" | awk '{print $1}')
DEVICE_MODEL=$(adb -s "$DEVICE_ID" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "unknown")
DEVICE_ARCH=$(adb -s "$DEVICE_ID" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r' || echo "unknown")
echo "  Device: $DEVICE_ID ($DEVICE_MODEL, $DEVICE_ARCH)"
echo ""

# Step 2: Find NDK clang
echo ">>> Locating Android NDK..."

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  for dir in ~/Library/Android/sdk/ndk/* ~/Android/Sdk/ndk/* /opt/android-ndk*; do
    if [ -d "$dir" ] && [ -f "$dir/build/cmake/android.toolchain.cmake" ]; then
      ANDROID_NDK_HOME="$dir"
      break
    fi
  done
fi

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  echo "ERROR: ANDROID_NDK_HOME not set and NDK not found"
  exit 1
fi

NDK_PREBUILT="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"
HOST_TAG="darwin-x86_64"
if [ ! -d "$NDK_PREBUILT/$HOST_TAG" ]; then
  HOST_TAG="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
fi

NDK_CLANG=""
for api in 34 33 31 30 28 24; do
  CANDIDATE="$NDK_PREBUILT/$HOST_TAG/bin/aarch64-linux-android${api}-clang"
  if [ -x "$CANDIDATE" ]; then
    NDK_CLANG="$CANDIDATE"
    break
  fi
done

if [ -z "$NDK_CLANG" ]; then
  NDK_CLANG=$(find "$ANDROID_NDK_HOME" -name "aarch64-linux-android*-clang" -not -name "*.cmd" 2>/dev/null | sort -r | head -1)
fi

if [ -z "$NDK_CLANG" ] || [ ! -x "$NDK_CLANG" ]; then
  echo "ERROR: NDK clang for aarch64 not found in $ANDROID_NDK_HOME"
  exit 1
fi

echo "  NDK clang: $NDK_CLANG"
echo ""

# Step 3: Cross-compile CTSP client
echo ">>> Cross-compiling CTSP client for Android ARM64..."
mkdir -p "$SCRIPT_DIR/binaries"
"$NDK_CLANG" -Wall -Wextra -Werror -O2 -static -o "$BINARY" "$SOURCE"
echo "  $(file "$BINARY")"
echo ""

# Step 4: Build stream-receiver helper
echo ">>> Building stream-receiver helper (Nim)..."

RECEIVER_SRC="$NATIVE_RECORDER/ct_cooperative/tests/android_stream_receiver_helper.nim"
RECEIVER_BIN="$SCRIPT_DIR/binaries/stream_receiver_helper"

direnv exec "$NATIVE_RECORDER" nim c \
  -o:"$RECEIVER_BIN" \
  --threads:on \
  "$RECEIVER_SRC"
echo ""

# Step 5: Set up adb reverse and start receiver
echo ">>> Setting up adb reverse port forwarding..."
adb -s "$DEVICE_ID" reverse tcp:$CTSP_PORT tcp:$CTSP_PORT

rm -f "$TRACE"
"$RECEIVER_BIN" "$CTSP_PORT" "$TRACE" &
RECEIVER_PID=$!
sleep 1

if ! kill -0 "$RECEIVER_PID" 2>/dev/null; then
  echo "ERROR: stream-receiver died immediately"
  RECEIVER_PID=""
  exit 1
fi
echo ""

# Step 6: Push and run on phone
echo ">>> Pushing binary to phone and running..."
adb -s "$DEVICE_ID" push "$BINARY" "$DEVICE_BINARY_PATH"
adb -s "$DEVICE_ID" shell chmod 755 "$DEVICE_BINARY_PATH"

PHONE_OUTPUT=$(adb -s "$DEVICE_ID" shell "$DEVICE_BINARY_PATH" 127.0.0.1 "$CTSP_PORT" 2>&1 || true)
echo "$PHONE_OUTPUT" | sed 's/^/  | /'

if ! echo "$PHONE_OUTPUT" | grep -q "DONE"; then
  echo "ERROR: phone program did not complete successfully"
  exit 1
fi
echo ""

# Step 7: Wait for receiver to finish
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

# Step 8: Verify
TRACE_SIZE=$(wc -c < "$TRACE" | tr -d ' ')
echo "=== Done ==="
echo "  trace.ct: $TRACE_SIZE bytes"
echo "  binary:   $(wc -c < "$BINARY" | tr -d ' ') bytes"
