#!/usr/bin/env bash
# Check that each .ct recording is in the format current readers accept, and
# that ct-print can open it.
#
# Usage:
#   verify-recordings.sh <ct-print> <file.ct> [<file.ct> ...]
#
# For every file, three checks, all reported before the verdict:
#   container   byte 5 of the CTFS header is the container version; must be 5
#   meta.dat    the u16 after the first `CTMD` magic is the meta.dat schema;
#               must be 6
#   ct-print    `ct-print --summary <file>` must exit 0.  ct-print refuses any
#               other container version or meta.dat schema by itself, so this
#               also decodes what the first two checks only read off the bytes.
#
# Prints one line per file and exits non-zero if any file fails any check.
# Runs under bash 3.2 (macOS) and Git Bash (Windows).

set -uo pipefail

EXPECT_CONTAINER=5
EXPECT_META=6

if [ "$#" -lt 2 ]; then
	echo "usage: $0 <ct-print> <file.ct> [<file.ct> ...]" >&2
	exit 2
fi

CT_PRINT="$1"
shift

failed=0
for f in "$@"; do
	if [ ! -f "$f" ]; then
		echo "FAIL $f: missing"
		failed=1
		continue
	fi

	container="$(od -A n -t u1 -j 5 -N 1 "$f" | tr -d ' ')"

	meta="none"
	off="$(LC_ALL=C grep -obUa 'CTMD' "$f" | head -1 | cut -d: -f1)"
	if [ -n "$off" ]; then
		meta="$(od -A n -t u2 -j $((off + 4)) -N 2 "$f" | tr -d ' ')"
	fi

	print_out="$("$CT_PRINT" --summary "$f" 2>&1)"
	print_rc=$?

	verdict="OK  "
	problems=""
	if [ "$container" != "$EXPECT_CONTAINER" ]; then
		problems="$problems container=$container(want $EXPECT_CONTAINER)"
	fi
	if [ "$meta" != "$EXPECT_META" ]; then
		problems="$problems meta.dat=$meta(want $EXPECT_META)"
	fi
	if [ "$print_rc" -ne 0 ]; then
		problems="$problems ct-print-exit=$print_rc"
	fi
	if [ -n "$problems" ]; then
		verdict="FAIL"
		failed=1
	fi

	echo "$verdict $f: container=$container meta.dat=$meta ct-print=$print_rc size=$(wc -c <"$f" | tr -d ' ')${problems:+ --$problems}"
	if [ "$print_rc" -ne 0 ]; then
		printf '%s\n' "$print_out" | head -5 | sed 's/^/       ct-print: /'
	fi
done

exit "$failed"
