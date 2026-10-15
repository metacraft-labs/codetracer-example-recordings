#!/usr/bin/env bash
# Verify EVERY committed .ct recording with both trace readers.
#
# Usage:
#   verify-all-recordings.sh [--index] <ct-print> <ct-credential-scan> <ct-member-names> <ct-verify-trace>
#
#   --index   check the files as staged (`git ls-files` and the index's
#             contents), not the working tree: what the commit being made
#             will hold.  The pre-commit hook passes it.
#
# Each file not listed in `.github/recordings-not-yet-readable.txt` goes
# through `verify-recordings.sh` with all four tools, the Rust reader
# included (no `-`).  A listed file must exist and be refused by BOTH
# `ct-print --summary` and `<ct-verify-trace> verify-trace`, each naming the
# container version; a listed file that either reader opens fails, so the
# line is removed once the file is re-recorded.
#
# Run by the pre-commit hook (`pre-commit-verify-recordings.sh`) and the
# `verify-recordings` workflow, on every change, so no recording reaches the
# repository unless both readers open it.  Exits non-zero on any failure.

set -uo pipefail

FROM_INDEX=false
if [ "${1:-}" = "--index" ]; then
	FROM_INDEX=true
	shift
fi
if [ "$#" -ne 4 ]; then
	echo "usage: $0 [--index] <ct-print> <ct-credential-scan> <ct-member-names> <ct-verify-trace>" >&2
	exit 2
fi
abs() { (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd)" "$(basename "$1")"); }
CT_PRINT="$(abs "$1")"
CREDENTIAL_SCAN="$(abs "$2")"
MEMBER_NAMES="$(abs "$3")"
VERIFY_TRACE="$(abs "$4")"
for tool in "$CT_PRINT" "$CREDENTIAL_SCAN" "$MEMBER_NAMES" "$VERIFY_TRACE"; do
	if [ ! -x "$tool" ]; then
		echo "error: $tool is not an executable" >&2
		exit 2
	fi
done

REPO="$(git rev-parse --show-toplevel)"
cd "$REPO" || exit 2
VERIFY="$REPO/.github/scripts/verify-recordings.sh"
EXCEPTIONS="$REPO/.github/recordings-not-yet-readable.txt"

ROOT="$REPO"
SCRATCH=""
if $FROM_INDEX; then
	SCRATCH="$(mktemp -d)"
	trap 'rm -rf "$SCRATCH"' EXIT
	git ls-files -z -- '*.ct' | git checkout-index -z --stdin --prefix="$SCRATCH/"
	ROOT="$SCRATCH"
fi

listed_reason() {
	grep -v '^#' "$EXCEPTIONS" | awk -F '\t' -v p="$1" '$1 == p { print $2; exit }'
}

failed=0
readable=()
excepted=0
while IFS= read -r -d '' path; do
	reason="$(listed_reason "$path")"
	if [ -z "$reason" ]; then
		readable+=("$path")
		continue
	fi
	excepted=$((excepted + 1))
	nim_out="$("$CT_PRINT" --summary "$ROOT/$path" 2>&1)"
	nim_rc=$?
	rust_out="$("$VERIFY_TRACE" verify-trace "$ROOT/$path" 2>&1)"
	rust_rc=$?
	if [ "$nim_rc" -eq 0 ] || [ "$rust_rc" -eq 0 ]; then
		echo "FAIL $path: opens now (ct-print=$nim_rc rust=$rust_rc); remove it from .github/recordings-not-yet-readable.txt (listed as: $reason)"
		failed=1
	elif ! printf '%s' "$nim_out" | grep -q 'CTFS container version' ||
		! printf '%s' "$rust_out" | grep -q 'unsupported CTFS container version'; then
		echo "FAIL $path: listed as unreadable for its container version ($reason), but refused otherwise:"
		printf '%s\n' "$nim_out" | head -3 | sed 's/^/       ct-print: /'
		printf '%s\n' "$rust_out" | head -3 | sed 's/^/       rust: /'
		failed=1
	else
		echo "OK   $path: refused by both readers for its container version, as listed ($reason)"
	fi
done < <(git ls-files -z -- '*.ct')

# Every listed file must still be committed.
while IFS="$(printf '\t')" read -r path _; do
	case "$path" in '' | '#'*) continue ;; esac
	if [ -z "$(git ls-files -- "$path")" ]; then
		echo "FAIL $path: listed in .github/recordings-not-yet-readable.txt but not committed; remove the line"
		failed=1
	fi
done <"$EXCEPTIONS"

if [ "${#readable[@]}" -eq 0 ]; then
	echo "FAIL: no committed recording to verify"
	exit 1
fi
(cd "$ROOT" && bash "$VERIFY" "$CT_PRINT" "$CREDENTIAL_SCAN" "$MEMBER_NAMES" "$VERIFY_TRACE" "${readable[@]}") || failed=1

echo "${#readable[@]} recordings checked with both readers; $excepted listed as not yet readable"
exit "$failed"
