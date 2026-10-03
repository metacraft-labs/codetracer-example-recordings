#!/usr/bin/env bash
# Clone the native recorder, and the sibling repos it builds against, at the
# revisions codetracer pins, side by side in the layout the regenerate scripts
# expect (`<parent>/codetracer-native-recorder`, `<parent>/codetracer-trace-format-nim`, ...).
#
# Usage:
#   provision-recorder.sh <codetracer-ref> <parent-dir> [--with-codetracer]
#
#   <codetracer-ref>   branch, tag or SHA of metacraft-labs/codetracer whose
#                      committed repro.lock names the recorder revision
#   <parent-dir>       directory the repos are cloned into (normally the parent
#                      of this repository's checkout)
#   --with-codetracer  also clone codetracer itself at <codetracer-ref>, without
#                      submodules (the Windows job needs its env.ps1)
#
# Where each revision comes from:
#   codetracer-native-recorder   codetracer's repro.lock
#   every other sibling          codetracer's repro.lock when it pins the repo,
#                                otherwise the recorder's own repro.lock
# A sibling pinned by neither lock fails the run: building it from a branch tip
# would not be the revision anybody recorded against.
#
# Runs under bash 3.2 (macOS) and Git Bash (Windows): no associative arrays,
# no mapfile.  Every repository involved is public, so no credential is used.
#
# Writes `<parent-dir>/recorder-pins.txt`, and the same pins to $GITHUB_OUTPUT
# when that is set.

set -euo pipefail

if [ "$#" -lt 2 ]; then
	echo "usage: $0 <codetracer-ref> <parent-dir> [--with-codetracer]" >&2
	exit 2
fi

CODETRACER_REF="$1"
PARENT="$2"
WITH_CODETRACER=false
if [ "${3:-}" = "--with-codetracer" ]; then
	WITH_CODETRACER=true
fi

ORG_URL="https://github.com/metacraft-labs"
SIBLINGS="codetracer-trace-format-nim codetracer-visual-replay nim-stackable-hooks"

mkdir -p "$PARENT"
PARENT="$(cd "$PARENT" && pwd)"

# A full 40-hex SHA is used as-is; anything else is resolved on the remote.
resolve_ref() {
	local repo="$1" ref="$2" sha
	if printf '%s' "$ref" | grep -Eq '^[0-9a-f]{40}$'; then
		printf '%s\n' "$ref"
		return
	fi
	sha="$(git ls-remote "$ORG_URL/$repo" "refs/heads/$ref" "refs/tags/$ref" | head -1 | cut -f1)"
	if [ -z "$sha" ]; then
		echo "error: $repo has no branch or tag named '$ref'" >&2
		exit 1
	fi
	printf '%s\n' "$sha"
}

# Print the `revision` the lock file records for repo NAME, or nothing.
lock_rev() {
	local lock="$1" name="$2"
	grep -o "{ name = \"$name\", path = [^}]*}" "$lock" |
		grep -o 'revision = "[0-9a-f]*"' | head -1 | cut -d'"' -f2 || true
}

# Check out REPO at exactly SHA in DIR, reusing an existing clone (the
# persistent self-hosted runners keep the parent directory between runs) but
# leaving nothing behind from a previous run.
clone_at() {
	local repo="$1" sha="$2" dir="$3"
	if [ ! -d "$dir/.git" ]; then
		rm -rf "$dir"
		git init -q "$dir"
		git -C "$dir" remote add origin "$ORG_URL/$repo"
	fi
	git -C "$dir" fetch -q --depth 1 origin "$sha"
	git -C "$dir" checkout -q --force --detach FETCH_HEAD
	git -C "$dir" clean -q -ffdx
	local got
	got="$(git -C "$dir" rev-parse HEAD)"
	if [ "$got" != "$sha" ]; then
		echo "error: $repo checked out $got, expected $sha" >&2
		exit 1
	fi
	echo "  $repo @ $sha"
}

CODETRACER_SHA="$(resolve_ref codetracer "$CODETRACER_REF")"
echo "codetracer $CODETRACER_REF -> $CODETRACER_SHA"

LOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$LOCK_DIR"' EXIT
curl -fsSL -o "$LOCK_DIR/codetracer.lock" \
	"https://raw.githubusercontent.com/metacraft-labs/codetracer/$CODETRACER_SHA/repro.lock"

RECORDER_SHA="$(lock_rev "$LOCK_DIR/codetracer.lock" codetracer-native-recorder)"
if [ -z "$RECORDER_SHA" ]; then
	echo "error: codetracer@$CODETRACER_SHA repro.lock pins no codetracer-native-recorder revision" >&2
	exit 1
fi

echo "Cloning into $PARENT:"
if $WITH_CODETRACER; then
	clone_at codetracer "$CODETRACER_SHA" "$PARENT/codetracer"
fi
clone_at codetracer-native-recorder "$RECORDER_SHA" "$PARENT/codetracer-native-recorder"
RECORDER_LOCK="$PARENT/codetracer-native-recorder/repro.lock"

PINS="$PARENT/recorder-pins.txt"
{
	echo "codetracer=$CODETRACER_SHA"
	echo "codetracer-native-recorder=$RECORDER_SHA"
} >"$PINS"

for sib in $SIBLINGS; do
	from_ct="$(lock_rev "$LOCK_DIR/codetracer.lock" "$sib")"
	from_rec="$(lock_rev "$RECORDER_LOCK" "$sib")"
	if [ -n "$from_ct" ] && [ -n "$from_rec" ] && [ "$from_ct" != "$from_rec" ]; then
		echo "note: $sib: codetracer pins $from_ct, the recorder's lock pins $from_rec; using codetracer's"
	fi
	sha="${from_ct:-$from_rec}"
	if [ -z "$sha" ]; then
		echo "error: neither codetracer's nor the recorder's repro.lock pins $sib" >&2
		exit 1
	fi
	clone_at "$sib" "$sha" "$PARENT/$sib"
	echo "$sib=$sha" >>"$PINS"
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	sed 's/-/_/g; s/^codetracer_native_recorder=/recorder=/' "$PINS" >>"$GITHUB_OUTPUT"
fi
echo "Pins written to $PINS"
