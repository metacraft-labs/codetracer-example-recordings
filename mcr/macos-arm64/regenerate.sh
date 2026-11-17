#!/usr/bin/env bash
# Regenerate the macOS ARM64 MCR recording fixture: a real recording of
# ct_fixture_prog made by the cooperative recorder, with its entry snapshot.
#
# Produces:
#   binaries/ct_fixture_prog (+ .dSYM)  the program, built for the cooperative recorder
#   trace.ct                            the recording (events + entry snapshot)
#   trace-portable.ct                   its portable export (executable + .dSYM)
#
# Prerequisites: an Apple Silicon Mac; Xcode's clang and dsymutil; nim and a
# zstd library (the codetracer-native-recorder dev shell has both); ct-mcr
# built in ../codetracer-native-recorder/ct_cli (`just build-ct-mcr`), for the
# export.  The recording runs under a cleared environment, because the entry
# snapshot copies the stack, environment strings included.
#
# Run from the codetracer-example-recordings repo root, in a scratch copy:
#   bash mcr/macos-arm64/regenerate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NATIVE_RECORDER="${NATIVE_RECORDER:-$(cd "$REPO_ROOT/../codetracer-native-recorder" && pwd)}"
CT_MCR="${CT_MCR:-$NATIVE_RECORDER/ct_cli/ct_cli}"
COOP="$NATIVE_RECORDER/ct_cooperative"

# The portable export's id is pinned; consumers hardcode it
# (codetracer/src/common/fixture_ids.nim, db-backend tests/common/fixture_ids.rs,
# FIXTURE_IDS.md).  The raw trace's id is minted by the recorder:
# ct_recording_init cannot pin it.
PORTABLE_RECORDING_ID="019e3a35-2542-7a00-8aaa-43ff20030002"

[ "$(uname -s)/$(uname -m)" = "Darwin/arm64" ] || { echo "needs an Apple Silicon Mac" >&2; exit 1; }
[ -x "$CT_MCR" ] || { echo "ct-mcr not found at $CT_MCR (just build-ct-mcr)" >&2; exit 1; }

# Under /tmp, not $TMPDIR: the recording and its export keep the build and
# program paths, and $TMPDIR is a per-user folder (/var/folders/<id>/...).
WORK="$(mktemp -d /tmp/ct-macos-fixture.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# The recorder is built from a copy under $WORK, with the nimble packages
# reached through $WORK too: the archive embeds the source paths it was built
# from (assertion messages, debug info), and a checkout or ~/.nimble under a
# home directory would put the developer's account name into a public fixture.
echo ">>> Building libct_cooperative_macos.a"
TRACE_FORMAT_NIM="${TRACE_FORMAT_NIM:-$(cd "$NATIVE_RECORDER/../codetracer-trace-format-nim" && pwd)}"
mkdir -p "$WORK/src/codetracer-native-recorder" "$WORK/nimble-home"
for pkg in ct_cooperative ct_runtime ct_interpose ct_ringbuf ct_events ct_time_model \
           ct_sync ct_snapshot ct_recorder ct_trace_store; do
  cp -R "$NATIVE_RECORDER/$pkg" "$WORK/src/codetracer-native-recorder/"
done
cp "$NATIVE_RECORDER/config.nims" "$WORK/src/codetracer-native-recorder/"
cp -R "$TRACE_FORMAT_NIM" "$WORK/src/codetracer-trace-format-nim"
# A copy, not a link: Nim resolves a link to its target's path.
mkdir -p "$WORK/nimble-home/.nimble"
cp -R "${NIMBLE_DIR:-$HOME/.nimble}/pkgs2" "$WORK/nimble-home/.nimble/pkgs2"
COOP="$WORK/src/codetracer-native-recorder/ct_cooperative"
rm -rf "$COOP/build"
(cd "$COOP" && CODETRACER_HOST_HOME="$WORK/nimble-home" bash macos_build.sh)

ZSTD_LIB="${ZSTD_LIB:-$(pkg-config --variable=libdir libzstd 2>/dev/null || true)}"
[ -n "$ZSTD_LIB" ] && [ -e "$ZSTD_LIB/libzstd.dylib" ] || { echo "set ZSTD_LIB to a directory with libzstd.dylib" >&2; exit 1; }

echo ">>> Building ct_fixture_prog for the cooperative recorder"
mkdir -p "$WORK/build" "$SCRIPT_DIR/binaries"
# The wrapper includes the program as `source.c`, so its line table names
# source.c, the file a viewer of this fixture is shown.
cp "$REPO_ROOT/programs/ct_fixture_prog.c" "$WORK/build/source.c"
cp "$SCRIPT_DIR/ct_fixture_prog_coop.c" "$SCRIPT_DIR/ct_fixture_coop_shim.c" "$WORK/build/"
# Compiled to objects in $WORK first: a one-step compile-and-link leaves its
# objects in $TMPDIR, and the debug map names them.
(cd "$WORK/build" && /usr/bin/clang -O0 -g -I"$COOP/include" -I. -c \
  ct_fixture_prog_coop.c ct_fixture_coop_shim.c)
(cd "$WORK/build" && /usr/bin/clang -g \
  -o ct_fixture_prog ct_fixture_prog_coop.o ct_fixture_coop_shim.o \
  "$COOP/build/libct_cooperative_macos.a" -L"$ZSTD_LIB" -lzstd \
  -framework Foundation -framework Metal -framework CoreFoundation \
  -framework Security -lobjc -lpthread \
  -Wl,-e,_ct_recording_entry)
(cd "$WORK/build" && /usr/bin/dsymutil ct_fixture_prog)
/usr/bin/clang -O2 -o "$WORK/noaslr" "$SCRIPT_DIR/noaslr.c"

echo ">>> Recording (ASLR off, cleared environment)"
mkdir -p "$WORK/home"
env -i PATH=/usr/bin:/bin HOME="$WORK/home" LANG=C TZ=UTC \
  CT_FIXTURE_TRACE="$WORK/trace.ct" \
  "$WORK/noaslr" "$WORK/build/ct_fixture_prog"

echo ">>> Exporting the portable trace"
(cd "$WORK/build" && CT_LICENSE_DEV_NO_FFI=1 "$CT_MCR" export --portable -v \
  --recording-id "$PORTABLE_RECORDING_ID" -o "$WORK/trace-portable.ct" "$WORK/trace.ct")

rm -rf "$SCRIPT_DIR/binaries/ct_fixture_prog" "$SCRIPT_DIR/binaries/ct_fixture_prog.dSYM"
cp -R "$WORK/build/ct_fixture_prog" "$WORK/build/ct_fixture_prog.dSYM" "$SCRIPT_DIR/binaries/"
cp "$WORK/trace.ct" "$SCRIPT_DIR/trace.ct"
cp "$WORK/trace-portable.ct" "$SCRIPT_DIR/trace-portable.ct"

echo "=== Done ==="
echo "  trace.ct:          $(wc -c < "$SCRIPT_DIR/trace.ct" | tr -d ' ') bytes"
echo "  trace-portable.ct: $(wc -c < "$SCRIPT_DIR/trace-portable.ct" | tr -d ' ') bytes"
echo "Scan both for credential-shaped names before committing:"
echo "  grep -aoE '[A-Z][A-Z0-9_]{2,}=' <file> | sort -u   (cp0.mem is compressed: also scan it decompressed)"
