#!/usr/bin/env bash
# Derive the pre-stamping control `one_write.ct` from `../eme5_predyld/one_write.ct`.
#
# This fixture is NOT a recording.  It is the current eme5_predyld recording
# with exactly two things undone, so that it has the shape a recorder from
# before founding SP stamping wrote:
#   - the `recordcfg` member (the main-stack fact) is dropped;
#   - every `evOsPredyldSyscall` header's ctTid (the raw SP stamp) is set to 0.
# Everything else is copied member for member.  The derivation is
# codetracer-native-recorder's tests/support/prestamp_derivation.nim, run by
# ct_emulator/tests/gen_prestamp_control_fixture.nim; the consuming test,
# test_macos_attribution_refuses_stamps_without_fact, re-derives it and fails
# unless the committed file is byte-identical.
#
# Re-run it whenever eme5_predyld is re-recorded, and commit both together.
# It needs no Mac: the derivation reads and writes CTFS, nothing else.
#
#   bash mcr/macos-arm64/emulator/eme5_predyld_prestamp/derive.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" 2>/dev/null && pwd || true)}"
if [ -z "$NATIVE_RECORDER" ] || [ ! -d "$NATIVE_RECORDER" ]; then
	echo "ERROR: codetracer-native-recorder sibling not found." >&2
	echo "       Set NATIVE_RECORDER=/path/to/codetracer-native-recorder." >&2
	exit 1
fi

SRC="$SCRIPT_DIR/../eme5_predyld/one_write.ct"
DST="$SCRIPT_DIR/one_write.ct"

(
	cd "$NATIVE_RECORDER/ct_emulator"
	repro exec "$NATIVE_RECORDER" -- \
		nim c -r --hints:off tests/gen_prestamp_control_fixture.nim "$SRC" "$DST"
)
