#!/usr/bin/env bash
# Regenerate the macOS ARM64 MCR *emulator* fixtures.
#
# These are DEVICE-BOUND recordings.  They can only be produced on an Apple
# Silicon Mac with:
#   - SIP DISABLED (`csrutil status` must say disabled) — the injected record
#     path PC-hijacks a suspended child pre-dyld;
#   - an ad-hoc-signed recorder carrying `com.apple.security.cs.debugger` and
#     `com.apple.private.thread-set-state` (the committed drivers self-sign and
#     re-exec);
#   - a QUIET HOST.  Concurrent recording tests SIGKILL each other — do not run
#     this while any other recorder/replay suite is running.
#
# Re-recording MOVES the characterization numbers the recorder repo's tests pin
# (instruction counts, stop PCs, geids, svc tables).  That is expected when a
# fixture legitimately gets richer and a REGRESSION when behaviour changed; each
# fixture's `<name>.info.txt` records what the numbers were.  Classify every
# moved value before re-pinning it.
#
# Run from anywhere:
#   bash mcr/macos-arm64/emulator/regenerate.sh [<fixture> ...]
# With no arguments it regenerates every fixture that has a committed driver.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" 2>/dev/null && pwd || true)}"
if [ -z "$NATIVE_RECORDER" ] || [ ! -d "$NATIVE_RECORDER" ]; then
	echo "ERROR: codetracer-native-recorder sibling not found." >&2
	echo "       Set NATIVE_RECORDER=/path/to/codetracer-native-recorder." >&2
	exit 1
fi

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
	echo "ERROR: these fixtures are macOS arm64 recordings; this host is $(uname -s)/$(uname -m)." >&2
	exit 1
fi

if ! csrutil status 2>/dev/null | grep -qi disabled; then
	echo "ERROR: SIP is enabled. The injected record path cannot run here." >&2
	echo "       Disable SIP (recovery mode: 'csrutil disable') and retry." >&2
	exit 1
fi

# The drivers write straight into this directory.
export CT_EXAMPLE_RECORDINGS="$REPO_ROOT"

run_driver() {
	# $1 = fixture name, $2 = driver path relative to the recorder repo root
	local fixture="$1" driver="$2"
	echo ">>> $fixture — $driver"
	(
		cd "$NATIVE_RECORDER/ct_cli"
		CT_REC_INSTALL_FIXTURE=1 direnv exec "$NATIVE_RECORDER" \
			nim c -r "${driver#ct_cli/}"
	)
	echo ""
}

regen_one() {
	case "$1" in
	eme5_inject)
		run_driver eme5_inject ct_cli/tests/record_macos_eme5_inject.nim
		;;
	eme_m9c_2006)
		run_driver eme_m9c_2006 ct_cli/tests/record_macos_eme_m9c_2006.nim
		;;
	eme5)
		# Recorded with the plain interpose recorder:
		#   ct_cli record -o <out>.ct -- <victim>
		# for each of programs/mcr_null_main.c and programs/mcr_one_puts.c.
		# No committed driver yet — fail loudly rather than pretend.
		echo "ERROR: 'eme5' has no committed re-record driver." >&2
		echo "       It was produced with: ct_cli record -o <out>.ct -- <victim>" >&2
		echo "       over programs/mcr_null_main.c and programs/mcr_one_puts.c." >&2
		echo "       Add ct_cli/tests/record_macos_eme5.nim before regenerating." >&2
		exit 1
		;;
	eme5_predyld)
		echo "ERROR: 'eme5_predyld' has no committed re-record driver." >&2
		echo "       It was produced via the inject path with" >&2
		echo "       CT_STAGE0_INCHILD_SETUP=1 (M-EME-T0 Stage 2c/3b); the closest" >&2
		echo "       committed exerciser is" >&2
		echo "       ct_cli/tests/test_macos_stage2c_inchild_setup_installer.nim." >&2
		echo "       Add ct_cli/tests/record_macos_eme5_predyld.nim first." >&2
		exit 1
		;;
	eme_ete_2006)
		echo "ERROR: 'eme_ete_2006' is NOT reproducible from the repo." >&2
		echo "       It was recorded by ct_cli/src/zz_rec_m9c_ow.nim, a scratch" >&2
		echo "       driver that no longer exists. The full recording (including" >&2
		echo "       the 148 MB .trace.ete) lives at ~/mcr-hwtrace/eme_ete_2006/." >&2
		echo "       Treat this fixture as ARCHIVAL." >&2
		exit 1
		;;
	*)
		echo "ERROR: unknown fixture '$1'." >&2
		echo "       Known: eme5 eme5_inject eme5_predyld eme_ete_2006 eme_m9c_2006" >&2
		exit 1
		;;
	esac
}

if [ "$#" -gt 0 ]; then
	for f in "$@"; do regen_one "$f"; done
else
	# Every fixture that HAS a committed driver.
	regen_one eme5_inject
	regen_one eme_m9c_2006
	echo "NOTE: eme5, eme5_predyld and eme_ete_2006 were skipped — they have no"
	echo "      committed driver. Name one explicitly to see what it would take."
fi

echo "=== Done ==="
for d in "$SCRIPT_DIR"/*/; do
	for ct in "$d"*.ct; do
		[ -e "$ct" ] || continue
		echo "  $(printf '%10s' "$(wc -c <"$ct" | tr -d ' ')")  ${ct#"$SCRIPT_DIR"/}"
	done
done
