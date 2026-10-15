#!/usr/bin/env bash
# Build the four tools verify-all-recordings.sh needs, from checkouts of the
# two trace-format repositories, into <out-dir>:
#
#   ct-print            the Nim reader      (codetracer-trace-format-nim)
#   ct-credential-scan  .github/scripts/ct_credential_scan.nim, against it
#   ct-member-names     .github/scripts/ct_member_names.nim, against it
#   codetracer_trace_util   the Rust readers  (codetracer-trace-format)
#
# Usage:
#   build-verify-tools.sh <out-dir> [<codetracer-trace-format-nim> <codetracer-trace-format>]
#
# The repositories default to the workspace siblings of this checkout. Each is
# built in its own Nix dev shell (`nix develop`), as the regeneration jobs
# build ct-print; with `nix` absent, the current environment must supply
# `nim`, `cargo` and `capnp`.

set -euo pipefail

if [ "$#" -ne 1 ] && [ "$#" -ne 3 ]; then
	echo "usage: $0 <out-dir> [<codetracer-trace-format-nim> <codetracer-trace-format>]" >&2
	exit 2
fi
REPO="$(git rev-parse --show-toplevel)"
mkdir -p "$1"
OUT="$(cd "$1" && pwd)"
NIM_REPO="$(cd "${2:-$REPO/../codetracer-trace-format-nim}" && pwd)"
RUST_REPO="$(cd "${3:-$REPO/../codetracer-trace-format}" && pwd)"

in_shell() {
	local dir="$1"
	shift
	if command -v nix >/dev/null 2>&1 && [ -f "$dir/flake.nix" ]; then
		(cd "$dir" && nix develop --command bash -c "$*")
	else
		(cd "$dir" && bash -c "$*")
	fi
}

# shellcheck disable=SC2016 # expanded by the inner shell
in_shell "$NIM_REPO" '
	set -euo pipefail
	nim c -d:release --hints:off -p:src -o:"'"$OUT"'/ct-print" src/codetracer_ct_print.nim
	nim c -d:release --hints:off -p:src -o:"'"$OUT"'/ct-credential-scan" "'"$REPO"'/.github/scripts/ct_credential_scan.nim"
	nim c -d:release --hints:off -p:src -o:"'"$OUT"'/ct-member-names" "'"$REPO"'/.github/scripts/ct_member_names.nim"'
# shellcheck disable=SC2016 # expanded by the inner shell
in_shell "$RUST_REPO" '
	set -euo pipefail
	cargo build --release -p codetracer_trace_util
	cp "${CARGO_TARGET_DIR:-target}/release/codetracer_trace_util" "'"$OUT"'/codetracer_trace_util"'
echo "verify tools built in $OUT:"
echo "  ct-print            from $NIM_REPO @ $(git -C "$NIM_REPO" rev-parse --short HEAD)"
echo "  codetracer_trace_util from $RUST_REPO @ $(git -C "$RUST_REPO" rev-parse --short HEAD)"
