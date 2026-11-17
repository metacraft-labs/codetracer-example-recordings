#!/usr/bin/env bash
# Regenerate the gl_scene visual recording in this directory.
#
# The recording is made by codetracer's own script, which the Visual Replay
# suites' answers depend on (codetracer
# scripts/record-visual-replay-fixture.sh): gl_scene.c from
# codetracer-native-test-programs, recorded by `ct-mcr record --interpose`
# under a scrubbed environment (no host variables reach the recorded
# program), its gfx stream extracted beside it.
#
# Prerequisites (Linux x86_64):
#   - ../codetracer, ../codetracer-native-recorder (ct_cli built with
#     `just build-ct-mcr`, at the revision codetracer's repro.lock pins) and
#     ../codetracer-native-test-programs beside this repository;
#   - codetracer-visual-replay's dev shell, for a C compiler with EGL and
#     GLES2 and Mesa's EGL vendor.
#
# Run from this repository's root:
#   nix develop ../codetracer-visual-replay --command \
#     bash mcr/linux-x86_64/visual-gl-scene/regenerate.sh
#
# Then verify it (`.github/scripts/verify-all-recordings.sh` and
# `ct_leak_scan`), commit it, move codetracer's `examples/recordings`
# gitlink to the commit, and re-capture the answers made from it in
# codetracer (`just plat59-capture-electron`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CODETRACER="${CODETRACER:-$(cd "$REPO_ROOT/../codetracer" && pwd)}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
bash "$CODETRACER/scripts/record-visual-replay-fixture.sh" "$work/visual-gl-scene"
# The recording and its extracted stream only: what the suites open.
find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 ! -name README.md ! -name regenerate.sh -exec rm -rf {} +
cp -R "$work/visual-gl-scene/." "$SCRIPT_DIR/"
echo "regenerated: $SCRIPT_DIR"
