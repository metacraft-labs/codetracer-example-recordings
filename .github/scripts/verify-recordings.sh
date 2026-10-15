#!/usr/bin/env bash
# Check that each .ct recording is in the format current readers accept, that
# BOTH trace readers open it (the Nim `ct-print` and the Rust
# `codetracer_trace_util verify-trace`), that it carries no credential, and
# that every member is stored under a storable name.
#
# Usage:
#   verify-recordings.sh <ct-print> <ct-credential-scan> <ct-member-names> <ct-verify-trace> <file.ct> [<file.ct> ...]
#
#   <ct-verify-trace> is the codetracer_trace_util binary built from
#   codetracer-trace-format; it is run as `<ct-verify-trace> verify-trace <file>`.
#   A literal `-` skips the Rust reader. Only the device-bound regeneration
#   jobs pass it, on runners that cannot build the Rust reader; their output
#   is committed through a change that `verify-all-recordings.sh` checks with
#   both readers (the pre-commit hook and the `verify-recordings` workflow).
#   The verdict line then says `rust=NOT-RUN`.
#
# For every file, six checks, all reported before the verdict:
#   container   byte 5 of the CTFS header is the container version; must be 5
#   meta.dat    the u16 after the first `CTMD` magic is the meta.dat schema;
#               must be 7 (the version every reader at the pinned trace format
#               reads; codetracer-trace-format-nim MetaDatVersion)
#   ct-print    `ct-print --summary <file>` must exit 0.  ct-print refuses any
#               other container version or meta.dat schema by itself, so this
#               also decodes what the first two checks only read off the bytes.
#   rust        `<ct-verify-trace> verify-trace <file>` must exit 0: the Rust
#               readers open the container, read every member, decode
#               `meta.dat`, and open the interning tables and every stream.
#               The two readers are checked separately because each has
#               accepted what the other refuses: a container with `paths.dat`
#               but not the other three interning tables passed ct-print and
#               was refused by the Rust readers.
#   credentials `ct-credential-scan <file>` (ct_credential_scan.nim) must find
#               no token, authorization header or private key in the raw bytes,
#               in any member, or in any zstd frame inside them.  A recording
#               captures the recorded process's environment, so one made in a
#               CI job or a developer shell publishes its tokens unless it was
#               made under a scrubbed environment.
#   members     `ct-member-names <file>` (ct_member_names.nim) must find every
#               member stored under a storable CTFS name: at most 12 characters
#               from `\0 0-9 a-z . / -` (trace-format spec, ctfs-container.md
#               §3).  A writer given any other name stores a lossy key that
#               ct-print and codetracer's reader cannot find by name.
#
# Prints one line per file and exits non-zero if any file fails any check.
# Runs under bash 3.2 (macOS) and Git Bash (Windows).

set -uo pipefail

EXPECT_CONTAINER=5
EXPECT_META=7

if [ "$#" -lt 5 ]; then
	echo "usage: $0 <ct-print> <ct-credential-scan> <ct-member-names> <ct-verify-trace|-> <file.ct> [<file.ct> ...]" >&2
	exit 2
fi

CT_PRINT="$1"
CREDENTIAL_SCAN="$2"
MEMBER_NAMES="$3"
VERIFY_TRACE="$4"
shift 4

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

	rust_out=""
	rust_rc=0
	if [ "$VERIFY_TRACE" != "-" ]; then
		rust_out="$("$VERIFY_TRACE" verify-trace "$f" 2>&1)"
		rust_rc=$?
	fi

	scan_out="$("$CREDENTIAL_SCAN" "$f" 2>&1)"
	scan_rc=$?
	names_out="$("$MEMBER_NAMES" "$f" 2>&1)"
	names_rc=$?

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
	if [ "$rust_rc" -ne 0 ]; then
		problems="$problems rust-exit=$rust_rc"
	fi
	if [ "$scan_rc" -ne 0 ]; then
		problems="$problems credentials=$([ "$scan_rc" -eq 1 ] && echo FOUND || echo "scan-error($scan_rc)")"
	fi
	if [ "$names_rc" -ne 0 ]; then
		problems="$problems members=$([ "$names_rc" -eq 1 ] && echo UNSTORABLE || echo "check-error($names_rc)")"
	fi
	if [ -n "$problems" ]; then
		verdict="FAIL"
		failed=1
	fi

	rust_word="$rust_rc"
	if [ "$VERIFY_TRACE" = "-" ]; then
		rust_word="NOT-RUN"
	fi
	echo "$verdict $f: container=$container meta.dat=$meta ct-print=$print_rc rust=$rust_word credentials=$([ "$scan_rc" -eq 0 ] && echo none || echo FOUND) members=$([ "$names_rc" -eq 0 ] && echo storable || echo UNSTORABLE) size=$(wc -c <"$f" | tr -d ' ')${problems:+ --$problems}"
	if [ "$print_rc" -ne 0 ]; then
		printf '%s\n' "$print_out" | head -5 | sed 's/^/       ct-print: /'
	fi
	if [ "$rust_rc" -ne 0 ]; then
		printf '%s\n' "$rust_out" | head -5 | sed 's/^/       rust: /'
	fi
	if [ "$scan_rc" -ne 0 ]; then
		printf '%s\n' "$scan_out" | head -20 | sed 's/^/       credentials: /'
	fi
	printf '%s\n' "$names_out" | head -5 | sed 's/^/       members: /'
done

exit "$failed"
