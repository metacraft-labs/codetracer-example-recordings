#!/usr/bin/env bash
# Pre-commit hook: when a commit adds or changes a .ct recording, or the
# verification itself, verify EVERY staged .ct with both trace readers
# (`verify-all-recordings.sh --index`).  A commit that touches neither passes
# at once.
#
# The tools are taken from CT_PRINT, CT_CREDENTIAL_SCAN, CT_MEMBER_NAMES and
# CT_VERIFY_TRACE when all four are set; otherwise they are built from the
# workspace siblings ../codetracer-trace-format-nim and
# ../codetracer-trace-format (`build-verify-tools.sh`) into
# `$(git rev-parse --git-dir)/ct-verify-tools`, rebuilt when either sibling's
# HEAD moves.  With neither, the commit is refused: a recording is not
# committed unchecked.

set -uo pipefail

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO" || exit 2

changed="$(git diff --cached --name-only --diff-filter=ACMRD -- '*.ct' \
	.github/recordings-not-yet-readable.txt .github/scripts/verify-recordings.sh \
	.github/scripts/verify-all-recordings.sh)"
if [ -z "$changed" ]; then
	exit 0
fi

if [ -n "${CT_PRINT:-}" ] && [ -n "${CT_CREDENTIAL_SCAN:-}" ] &&
	[ -n "${CT_MEMBER_NAMES:-}" ] && [ -n "${CT_VERIFY_TRACE:-}" ]; then
	tools=("$CT_PRINT" "$CT_CREDENTIAL_SCAN" "$CT_MEMBER_NAMES" "$CT_VERIFY_TRACE")
else
	NIM_REPO="$REPO/../codetracer-trace-format-nim"
	RUST_REPO="$REPO/../codetracer-trace-format"
	if [ ! -e "$NIM_REPO/.git" ] || [ ! -e "$RUST_REPO/.git" ]; then
		echo "pre-commit: this commit changes recordings, and they are verified with both trace readers." >&2
		echo "  Set CT_PRINT, CT_CREDENTIAL_SCAN, CT_MEMBER_NAMES and CT_VERIFY_TRACE, or check out" >&2
		echo "  codetracer-trace-format-nim and codetracer-trace-format next to this repository." >&2
		exit 1
	fi
	cache="$(cd "$(git rev-parse --git-dir)" && pwd)/ct-verify-tools"
	stamp="$(git -C "$NIM_REPO" rev-parse HEAD) $(git -C "$RUST_REPO" rev-parse HEAD)"
	if [ "$(cat "$cache/stamp" 2>/dev/null)" != "$stamp" ]; then
		echo "pre-commit: building the verify tools (both readers) into $cache" >&2
		bash .github/scripts/build-verify-tools.sh "$cache" "$NIM_REPO" "$RUST_REPO" >&2 || exit 1
		printf '%s\n' "$stamp" >"$cache/stamp"
	fi
	tools=("$cache/ct-print" "$cache/ct-credential-scan" "$cache/ct-member-names" "$cache/codetracer_trace_util")
fi

bash .github/scripts/verify-all-recordings.sh --index "${tools[@]}"
