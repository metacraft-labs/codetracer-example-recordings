#!/usr/bin/env bash
# Regenerate the iOS ARM64 MCR recording fixture: a real cooperative recording
# made in the iOS simulator.
#
# Produces:
#   1. trace.ct          — the raw cooperative recording (for emulator tests)
#   2. trace-portable.ct — the portable export with the binary (for GUI E2E)
#   3. binaries/ios_sim_cooperative_fixture (+ .dSYM) — the recorded program
#
# The recording comes from codetracer-native-recorder's
# ct_cooperative/tests/record_ios_sim_fixture.sh: it links
# ct_cooperative/tests/fixtures/ios_sim_cooperative_fixture.c against
# libct_cooperative_sim.a, runs it in a simulator with `simctl spawn`, and
# records its syscalls over the network to the host's stream receiver. (The
# fixture used to come from a synthetic CTSP client (since removed) whose
# placeholder blobs no reader decodes; its traces held no events.)
#
# Prerequisites:
#   - macOS with Xcode and an iOS simulator runtime (one is booted if none is)
#   - codetracer-native-recorder beside this repository, at a revision that
#     carries record_ios_sim_fixture.sh (agents 400f39fd6 or later)
#
# Run from that repository's dev shell:
#   (cd ../codetracer-native-recorder &&
#     nix develop --command bash ../codetracer-example-recordings/mcr/ios-arm64/regenerate.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" && pwd)}"

TRACE="$SCRIPT_DIR/trace.ct"
PORTABLE="$SCRIPT_DIR/trace-portable.ct"
PROGRAM="ios_sim_cooperative_fixture"
BINARY="$SCRIPT_DIR/binaries/$PROGRAM"
DRIVER="$NATIVE_RECORDER/ct_cooperative/tests/record_ios_sim_fixture.sh"

# Canonical, pinned recording id of the portable export. Consumers hardcode it:
#   codetracer/src/common/fixture_ids.nim
#   codetracer/src/db-backend/tests/common/fixture_ids.rs
#   codetracer-example-recordings/FIXTURE_IDS.md
# The raw trace.ct is written by the stream receiver, which mints its own id.
PORTABLE_RECORDING_ID="019e3a35-2543-7a00-8aaa-43ff20040002"

if [ ! -f "$DRIVER" ]; then
	echo "ERROR: $DRIVER not found; codetracer-native-recorder must be at agents 400f39fd6 or later" >&2
	exit 1
fi

echo "=== Regenerating iOS ARM64 MCR fixture ==="

# ct-mcr: the driver checks the trace with it, and the export below uses it.
CT_MCR="${CT_MCR:-}"
if [ -z "$CT_MCR" ] && [ -x "$NATIVE_RECORDER/ct_cli/ct_cli" ]; then
	CT_MCR="$NATIVE_RECORDER/ct_cli/ct_cli"
fi
if [ -z "$CT_MCR" ]; then
	echo ">>> Building ct-mcr..."
	(cd "$NATIVE_RECORDER" && just build-ct-mcr)
	CT_MCR="$NATIVE_RECORDER/ct_cli/ct_cli"
fi
export CT_MCR
echo "  ct-mcr: $CT_MCR"

echo ">>> Recording in the iOS simulator..."
rm -f "$TRACE" "$PORTABLE"
bash "$DRIVER" "$TRACE"
# The driver leaves the recorded binary and its .dSYM beside the trace.
mkdir -p "$SCRIPT_DIR/binaries"
mv -f "$SCRIPT_DIR/$PROGRAM" "$BINARY"
rm -rf "$BINARY.dSYM"
mv -f "$SCRIPT_DIR/$PROGRAM.dSYM" "$BINARY.dSYM"

echo ">>> Exporting portable trace..."
# The trace names its program by basename; the export finds it in binaries/.
(cd "$SCRIPT_DIR/binaries" && "$CT_MCR" export --portable -v \
	--recording-id "$PORTABLE_RECORDING_ID" -o "$PORTABLE" "$TRACE")

echo "=== Done ==="
echo "  trace.ct:          $(wc -c <"$TRACE" | tr -d ' ') bytes (raw, for emulator tests)"
echo "  trace-portable.ct: $(wc -c <"$PORTABLE" | tr -d ' ') bytes (portable, for GUI E2E)"
echo "  binary:            $(wc -c <"$BINARY" | tr -d ' ') bytes"
"$CT_MCR" trace info "$PORTABLE" | sed -n 's/^\(program\|events\|threads\): /  \1: /p'
