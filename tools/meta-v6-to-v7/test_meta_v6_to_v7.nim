## `upgradeMetaDatV6` turns a version-6 container into exactly the bytes the
## current writer produces for the same recording: a recording is written at
## version 7, its `meta.dat` version byte is set back to 6 in place (the
## version-6 writer's output for it, since version 7 changed no other byte),
## and the upgrade must give back the original file, byte for byte.  It
## refuses a container already at version 7 and a version-6 container whose
## `events.dat` carries a kind version 6 does not assign.  No mocks: the real
## writer, the real readers, real files.
##
## It also pins the committed fixtures this tool upgraded (`76e71a4`): each
## must be its version-6 recording with the version byte alone changed.  The
## table below holds the sha256 of each file as committed at `76e71a4^`,
## computed by `git show 76e71a4^:<path> | sha256sum`, not by this tool.  The
## test sets the committed file's version byte back to 6 and requires that
## digest, so every member but `meta.dat`'s version is byte-identical to the
## version-6 recording, and it requires the upgrade of that image to give the
## committed file back.  A fixture re-recorded or regenerated later leaves
## this table: `eme5/null_main.ct` and `eme5/one_puts.ct` are pinned by
## `../ctfs-v4-to-v5/test_ctfs_v4_to_v5.nim` as the v4 -> v7 chain of their
## kept originals, whose last step is this tool.

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[os, strutils]
import results, nimcrypto/sha2
import codetracer_ctfs/[types, container]
import codetracer_trace_types
import codetracer_trace_writer/multi_stream_writer
import meta_v6_to_v7

proc record(path: string, kinds: openArray[EventLogKind]): seq[byte] =
  var w = initMultiStreamWriter(path, "upgrade",
    recordingId = "01949fcc-7d92-7e9c-bccc-000000000067").get
  let p = w.registerPath("/src/u.nim").get
  for i, k in kinds:
    doAssert w.registerStep(p, uint64(i + 1), []).isOk
    doAssert w.registerIOEvent(k, cast[seq[byte]]("c" & $i)).isOk
  doAssert w.close().isOk
  cast[seq[byte]](readFile(path))

proc stampedV6(v7: seq[byte]): seq[byte] =
  result = v7
  let bs = readU32LE(v7, 8)
  let maxRoot = readU32LE(v7, 12)
  let runs = locateMember(v7, "meta.dat", bs, maxRoot).get
  doAssert result[runs[0].at + 4] == 7
  result[runs[0].at + 4] = 6

const
  repoRoot = currentSourcePath().parentDir / ".." / ".."
  # path, sha256 of the version-6 file at `76e71a4^`.
  upgradedFixtures = [
    ("javascript/flow_test/trace.ct",
      "a60bffb330724bb79c56565140f9686f57a9dcc648f97847e7b7d4fd529784ec"),
    ("mcr/linux-x86_64/trace-portable.ct",
      "b77546032bfeff400dea340c2ab22375e471e7054db765bc23581d3b8e47e8c8"),
    ("mcr/linux-x86_64/trace.ct",
      "e29225486db5b773197f9d77d93f4dc07a96a0fccf7354b7b7a86d3ca5bce721"),
    ("mcr/macos-arm64/emulator/eme5_inject/one_write.ct",
      "ff799913b7a1579499ceedadaeea6be7d15f4a122f64dd19b41f1f28546f3c56"),
    ("mcr/macos-arm64/emulator/eme5_predyld/one_write.ct",
      "ad326ac2e234a4f68f40ca6c6a2f1936f9557a0cd8fd2b7a9d6b565ac4745a9e"),
    ("mcr/macos-arm64/emulator/eme_m9c_2006/one_write.ct",
      "c02ddc8910bf3e868ceee816040e888e34fe9f01909c804ca0c4e1232c1a7f8c"),
    ("mcr/macos-arm64/trace-portable.ct",
      "97cd0033fd4ac896b1311e5c9c7be46c15a4fa53232407faabbf0e6b566a3fb7"),
    ("mcr/macos-arm64/trace.ct",
      "7cfb12edc051e64f4ae562fa41046a1c2e71efe56814627f93c5fac1ccaaa0e9"),
    ("mcr/windows-x86_64/trace-portable.ct",
      "95e9bb0dc535e097c72df1e0a7e851da0b26707ee0e731a80c306f2e8b2e9917"),
    ("mcr/windows-x86_64/trace.ct",
      "bae4ae5d956a21d63845e28a3e29f8e434a2f8699a962a5fb9b3fe8f795db272"),
    ("ruby/flow_test/trace.ct",
      "2e5de98a8160667c98649bd6d5dc770c9e2ec2cb5c8d5b606c5e167edfd13117"),
  ]

let dir = getTempDir() / ("meta_v6_to_v7_" & $getCurrentProcessId())
createDir(dir)

block a_v6_container_upgrades_to_the_current_writers_bytes:
  let v7 = record(dir / "a.ct", [elkWrite, elkReadFile, elkError, elkEvmEvent])
  let v6 = stampedV6(v7)
  doAssert v6 != v7
  let up = upgradeMetaDatV6(v6)
  doAssert up.isOk, up.error
  doAssert up.get == v7, "the upgrade is not the current writer's container"
  echo "PASS a_v6_container_upgrades_to_the_current_writers_bytes"

block a_v7_container_is_refused:
  let v7 = record(dir / "b.ct", [elkWrite])
  let up = upgradeMetaDatV6(v7)
  doAssert up.isErr and "version 7" in up.error, $up
  echo "PASS a_v7_container_is_refused"

block a_kind_version_6_does_not_assign_is_refused:
  let v6 = stampedV6(record(dir / "c.ct", [elkWrite, elkWriteStderr]))
  let up = upgradeMetaDatV6(v6)
  doAssert up.isErr and "kind 14" in up.error, $up
  echo "PASS a_kind_version_6_does_not_assign_is_refused"

block the_committed_fixtures_are_their_v6_recordings_with_one_byte_changed:
  for (path, v6Digest) in upgradedFixtures:
    let v7 = cast[seq[byte]](readFile(repoRoot / path))
    let v6 = stampedV6(v7)
    doAssert toLowerAscii($sha256.digest(v6)) == v6Digest,
      path & ": with its version byte set back to 6 it is not the version-6 " &
      "recording committed at 76e71a4^"
    let up = upgradeMetaDatV6(v6)
    doAssert up.isOk, path & ": " & up.error
    doAssert up.get == v7, path & ": the upgrade is not the committed file"
  echo "PASS the_committed_fixtures_are_their_v6_recordings_with_one_byte_changed (",
    upgradedFixtures.len, " fixtures)"

removeDir(dir)
