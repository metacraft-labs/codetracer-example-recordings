#!/usr/bin/env bash
# Clone the two trace-format repositories at the revisions codetracer pins,
# next to this checkout, for `build-verify-tools.sh`:
#
#   <parent-dir>/codetracer-trace-format-nim   (the Nim reader, ct-print)
#   <parent-dir>/codetracer-trace-format       (the Rust readers)
#
# Usage:
#   provision-readers.sh <codetracer-ref> <parent-dir>
#
# The revisions are the ones codetracer's committed repro.lock names at
# <codetracer-ref>: the readers codetracer opens these recordings with. Both
# repositories are public, so no token is needed. Writes
# `<parent-dir>/reader-pins.txt`.

set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <codetracer-ref> <parent-dir>" >&2
	exit 2
fi
CODETRACER_REF="$1"
mkdir -p "$2"
PARENT="$(cd "$2" && pwd)"
ORG_URL="https://github.com/metacraft-labs"

if printf '%s' "$CODETRACER_REF" | grep -Eq '^[0-9a-f]{40}$'; then
	CODETRACER_SHA="$CODETRACER_REF"
else
	CODETRACER_SHA="$(git ls-remote "$ORG_URL/codetracer" "refs/heads/$CODETRACER_REF" "refs/tags/$CODETRACER_REF" | head -1 | cut -f1)"
fi
if [ -z "$CODETRACER_SHA" ]; then
	echo "error: codetracer has no branch or tag named '$CODETRACER_REF'" >&2
	exit 1
fi
LOCK="$(mktemp)"
trap 'rm -f "$LOCK"' EXIT
curl -fsSL -o "$LOCK" "https://raw.githubusercontent.com/metacraft-labs/codetracer/$CODETRACER_SHA/repro.lock"

PINS="$PARENT/reader-pins.txt"
echo "codetracer=$CODETRACER_SHA" >"$PINS"
for repo in codetracer-trace-format-nim codetracer-trace-format; do
	sha="$(grep -o "{ name = \"$repo\", path = [^}]*}" "$LOCK" |
		grep -o 'revision = "[0-9a-f]*"' | head -1 | cut -d'"' -f2 || true)"
	if [ -z "$sha" ]; then
		echo "error: codetracer@$CODETRACER_SHA repro.lock pins no $repo revision" >&2
		exit 1
	fi
	dir="$PARENT/$repo"
	if [ ! -d "$dir/.git" ]; then
		rm -rf "$dir"
		git init -q "$dir"
		git -C "$dir" remote add origin "$ORG_URL/$repo"
	fi
	git -C "$dir" fetch -q --depth 1 origin "$sha"
	git -C "$dir" checkout -q --force --detach FETCH_HEAD
	git -C "$dir" clean -q -ffdx
	echo "  $repo @ $sha"
	echo "$repo=$sha" >>"$PINS"
done
echo "Pins written to $PINS"
