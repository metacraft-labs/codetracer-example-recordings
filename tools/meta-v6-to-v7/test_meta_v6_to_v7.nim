## `upgradeMetaDatV6` turns a version-6 container into exactly the bytes the
## current writer produces for the same recording: a recording is written at
## version 7, its `meta.dat` version byte is set back to 6 in place (the
## version-6 writer's output for it, since version 7 changed no other byte),
## and the upgrade must give back the original file, byte for byte.  It
## refuses a container already at version 7 and a version-6 container whose
## `events.dat` carries a kind version 6 does not assign.  No mocks: the real
## writer, the real readers, real files.

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[os, strutils]
import results
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

removeDir(dir)
