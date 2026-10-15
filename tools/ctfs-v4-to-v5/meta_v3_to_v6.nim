## One-off upgrade: a container's `meta.dat` from schema version 3 to 6.
##
## WHY.  The five `mcr/macos-arm64/emulator/` recordings carry a version-3
## `meta.dat`, and every reader refuses any version but 6 (internal-files.md
## "Metadata (meta.dat)", Version History).  The owner decided on 2026-10-05
## to convert, with the reader kept strict, provided every field the newer
## versions add can be derived from the recording without guessing.  Each
## version, and what it needs here:
##
##   v4 (2026-09-08) changed how the line-only `global_position_index` of a
##        STEP is packed — data in step streams, not in `meta.dat`.  These
##        recordings are native MCR event traces: they have no step stream
##        (no `steps.dat` / call stream member), so nothing carries the
##        changed packing.  `upgradeMetaDatV3` checks that and refuses a
##        container that has one, rather than assume.
##   v5 (2026-09-10) inserted `flags_ext` (written only when set; its one
##        bit, source reload, postdates v3, so a v3 recording has none set).
##   v6 (2026-10-01) made `flags_ext` always present — 0 here, by v5's rule —
##        and moved the path list out of `meta.dat` into `paths.dat`, the
##        trace's interning table of source paths.  The v3 list is in the
##        file, in path-id order, so `paths.dat` is written from it with the
##        current writer, one plain record per path (the column-aware form is
##        only for a trace that sets `FLAG_HAS_COLUMN_AWARE_STEPS`, which a v3
##        `meta.dat` has no bit for).  `paths.dat` is one of the four
##        interning tables, which a trace carries all four or none
##        (internal-files.md "Interning Tables"), so it is written as the
##        current native recorder writes it: `initTraceInterningTables`, with
##        `funcs`, `types` and `varnames` empty — a native recording interns
##        no function, type or variable name, and `meta.dat` bit 12 stays
##        clear, as that recorder leaves it.  An empty list writes none of the
##        four, as a current recorder with no source paths writes none.
##
## MEMBER NAMES.  The macOS recorder stored its seed and sidecar members as
## `t_start.*` / `cp0.predyld.syscalls`, and its event log as
## `event_log.dat` / `event_log.idx`; `_` is outside the CTFS name alphabet
## and several names exceed 12 characters, so the containers hold LOSSY keys.
## Recorder `e16f18457` (2026-10-04) renamed the seed and sidecar members in
## the writer and every reader (`t_start.mem` -> `tstart.mem`, ...), and
## recorder `40aa129e` (the same day) left `eventlog.dat` / `eventlog.idx` as
## the only event-log names any reader opens.  The renames are reproduced here
## exactly: a member is renamed iff its stored key equals the key the old
## writer computed for an old name in that table (the keys of the table's
## names are pairwise distinct, so the match is exact).  The bytes are not
## touched.
##
## Every other byte of `meta.dat` — the strings before the path list and the
## whole MCR / replay-launch / layout / filter tail — is copied unchanged, and
## every other member of the container is copied unchanged, in the same order.
## The result is checked through the CURRENT readers: `readMetaDat` must
## accept it with every field equal to the version-3 decode, the native-bundle
## reader `ct-print` uses must open it, the four interning tables must be
## present with `paths.dat` reading back the version-3 list and the other three
## empty, and every other member must be byte-identical.
##
## Since codetracer-trace-format-nim `20ba929` (2026-10-12) the current
## readers accept only `meta.dat` version 7.  Version 7 changes no byte of the
## version-6 header or body (it assigns new `EventLogKind` values only), so the
## version-6 result is read through them as the version-7 container
## `../meta-v6-to-v7` makes of it, which differs in the version byte alone and
## which that tool verifies.  The tool still writes version 6: the third step
## of the chain, `meta_v6_to_v7`, is a separate one.

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import results
import codetracer_ctfs/[types, base40, container]
import codetracer_trace_writer/[meta_dat, interning_table, varint]
import native_decoder
import ./member_renames

export member_renames
import "../meta-v6-to-v7/meta_v6_to_v7"

type
  MetaV3* = object
    flags*: uint16
    recordingId*, program*, workdir*, recorderId*: string
    args*: seq[string]
    paths*: seq[string]
    tail*: seq[byte]          ## everything after the path list, verbatim
    head*: seq[byte]          ## the strings recording_id .. recorder_id

proc readVarint(d: openArray[byte], p: var int): Result[uint64, string] =
  var r = 0'u64
  var s = 0
  while true:
    if p >= d.len: return err("meta.dat ends inside a varint")
    if s > 63: return err("meta.dat varint longer than 64 bits")
    let b = d[p]
    inc p
    r = r or (uint64(b and 0x7f) shl s)
    if (b and 0x80) == 0: break
    s += 7
  ok(r)

proc readStr(d: openArray[byte], p: var int): Result[string, string] =
  let n = int(?readVarint(d, p))
  if n < 0 or p + n > d.len: return err("meta.dat string runs past its end")
  var s = newString(n)
  for i in 0 ..< n: s[i] = char(d[p + i])
  p += n
  ok(s)

proc parseMetaV3*(d: openArray[byte]): Result[MetaV3, string] =
  if d.len < 8 or d[0] != byte('C') or d[1] != byte('T') or
     d[2] != byte('M') or d[3] != byte('D'):
    return err("meta.dat: bad magic")
  let version = uint16(d[4]) or (uint16(d[5]) shl 8)
  if version != 3:
    return err("meta.dat schema version is " & $version & ", not 3")
  var m = MetaV3(flags: uint16(d[6]) or (uint16(d[7]) shl 8))
  var p = 8
  let headStart = p
  m.recordingId = ?readStr(d, p)
  m.program = ?readStr(d, p)
  let argc = int(?readVarint(d, p))
  for i in 0 ..< argc: m.args.add(?readStr(d, p))
  m.workdir = ?readStr(d, p)
  m.recorderId = ?readStr(d, p)
  for i in headStart ..< p: m.head.add d[i]
  let pathc = int(?readVarint(d, p))
  for i in 0 ..< pathc: m.paths.add(?readStr(d, p))
  for i in p ..< d.len: m.tail.add d[i]
  ok(m)

proc metaV6Bytes*(m: MetaV3): seq[byte] =
  ## The version-6 `meta.dat` holding exactly `m`'s fields.
  result = @[byte('C'), byte('T'), byte('M'), byte('D'), 6'u8, 0'u8,
             byte(m.flags and 0xff), byte(m.flags shr 8),
             0'u8, 0'u8, 0'u8, 0'u8]   # flags_ext = 0 (see the module note)
  result.add m.head
  result.add m.tail

proc memberNames(data: openArray[byte], maxRoot: uint32): seq[string] =
  for i in 0 ..< int(maxRoot):
    let enc = readU64LE(data, HeaderSize + ExtHeaderSize + i * FileEntrySize + 16)
    if enc != 0: result.add base40Decode(enc)

proc upgradeMetaDatV3*(data: openArray[byte]): Result[seq[byte], string] =
  ## A version-5 container whose `meta.dat` is schema 3 -> the same container
  ## with a schema-6 `meta.dat` (and the four interning tables, holding the
  ## v3 path list, when that list is not empty), verified as the module note
  ## says.
  if data.len < 16 or data[5] != CtfsVersion:
    return err("not a CTFS version-" & $CtfsVersion & " container")
  let bs = readU32LE(data, 8)
  let maxRoot = readU32LE(data, 12)
  let names = memberNames(data, maxRoot)
  # The version first: a container already upgraded is refused for that.
  block:
    let mb = readInternalFile(data, "meta.dat", bs, maxRoot)
    if mb.isErr: return err("meta.dat: " & mb.error)
    discard ?parseMetaV3(mb.get)
  for n in names:
    if n in InterningTableMembers:
      return err("the container already carries " & n & "; a version-3 " &
                 "meta.dat holds the path list itself")
    if n == "steps.dat" or n == "calls.dat":
      return err("the container carries a step stream (" & n & "), whose " &
                 "line-only positions version 4 re-packed; this upgrade does " &
                 "not re-pack them, so it refuses rather than guess")
  var members: seq[(string, seq[byte])] = @[]
  for n in names:
    let b = readInternalFile(data, n, bs, maxRoot)
    if b.isErr: return err("member " & n & ": " & b.error)
    members.add((n, b.get))
  var metaIdx = -1
  for i, (n, _) in members:
    if n == "meta.dat": metaIdx = i
  if metaIdx < 0: return err("the container has no meta.dat")
  let m = ?parseMetaV3(members[metaIdx][1])
  let v6 = metaV6Bytes(m)

  var keys: seq[uint64] = @[]
  for i in 0 ..< int(maxRoot):
    let enc = readU64LE(data, HeaderSize + ExtHeaderSize + i * FileEntrySize + 16)
    if enc != 0: keys.add enc
  var outNames: seq[string] = @[]
  for i, (n, _) in members:
    let r = renamedMember(keys[i])
    if r.len > 0:
      if not base40Encodable(r): return err("rename target " & r & " is not storable")
      for (m2, _) in members:
        if m2 == r: return err("the container already has " & r)
      outNames.add r
    else:
      outNames.add n

  var dst = createCtfs(bs, maxRoot, CtfsEncryptionMethod(data[6]), data[7])
  for i, (n, b) in members:
    var f = ?dst.addFile(outNames[i])
    let bytes = if n == "meta.dat": v6 else: b
    if bytes.len > 0: ?dst.writeToFile(f, bytes)
  if m.paths.len > 0:
    var tables = ?initTraceInterningTables(dst)
    for i, path in m.paths:
      let id = ?ensurePathId(dst, tables, path)
      if id != uint64(i):
        return err("path " & path & " was interned as id " & $id & ", not " &
                   $i & ": the v3 list repeats a path, so its ids cannot be " &
                   "kept")
  let output = ?finishCtfs(dst)

  # Verify through the current readers, which read version 7 only: the
  # result's meta.dat is read as the version-7 container of the same
  # recording (see the module note).
  let mr = readInternalFile(output, "meta.dat", bs, maxRoot)
  if mr.isErr: return err("meta.dat does not read back: " & mr.error)
  if mr.get != v6: return err("meta.dat does not read back as written")
  let asV7 = upgradeMetaDatV6(output)
  if asV7.isErr: return err("the version-7 view of the result: " & asV7.error)
  let mr7 = readInternalFile(asV7.get, "meta.dat", bs, maxRoot)
  if mr7.isErr: return err("meta.dat does not read back: " & mr7.error)
  let parsed = readMetaDat(mr7.get)
  if parsed.isErr: return err("readMetaDat refuses the result: " & parsed.error)
  let c = parsed.get
  if c.version != 7 or c.recordingId != m.recordingId or
     c.program != m.program or c.args != m.args or c.workdir != m.workdir or
     c.recorderId != m.recorderId:
    return err("readMetaDat reads back different fields")
  # The whole recording, as `ct-print` opens a native bundle.
  let bundle = detectNativeBundle(asV7.get)
  if bundle.isErr: return err("the native-bundle reader refuses the result: " &
                              bundle.error)
  let partialSet = interningSetRefusal(output, maxRoot)
  if partialSet.len > 0:
    return err(partialSet)
  if m.paths.len > 0:
    for table in ["funcs", "types", "varnames"]:
      let t = initInterningTableReader(output, table, bs, maxRoot)
      if t.isErr: return err(table & ".dat does not open: " & t.error)
      if t.get.count != 0:
        return err(table & ".dat holds " & $t.get.count & " records, not 0")
    let r = initInterningTableReader(output, "paths", bs, maxRoot)
    if r.isErr: return err("paths.dat does not open: " & r.error)
    if r.get.count != uint64(m.paths.len):
      return err("paths.dat holds " & $r.get.count & " paths, not " &
                 $m.paths.len)
    for i, path in m.paths:
      let got = r.get.readById(uint64(i))
      if got.isErr or got.get != path:
        return err("paths.dat path " & $i & " reads back differently")
  for i, (n, b) in members:
    if n == "meta.dat": continue
    let got = readInternalFile(output, outNames[i], bs, maxRoot)
    if got.isErr or got.get != b:
      return err("member " & outNames[i] & " is not byte-identical after " &
                 "the upgrade")
  ok(output)

when isMainModule:
  import std/os
  proc main(): int =
    let args = commandLineParams()
    if args.len != 2:
      stderr.writeLine "usage: meta_v3_to_v6 <in.ct> <out.ct>"
      return 2
    let input = readCtfsFromFile(args[0])
    if input.isErr:
      stderr.writeLine input.error
      return 1
    let output = upgradeMetaDatV3(input.get)
    if output.isErr:
      stderr.writeLine args[0] & ": " & output.error
      return 1
    let tmp = args[1] & ".v6-tmp"
    try:
      writeFile(tmp, output.get)
      moveFile(tmp, args[1])
    except CatchableError as e:
      stderr.writeLine "cannot write " & args[1] & ": " & e.msg
      return 1
    echo args[0], " -> ", args[1], ": meta.dat v3 -> v6"
    0
  quit(main())
