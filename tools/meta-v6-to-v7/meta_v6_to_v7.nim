## Upgrade a container's `meta.dat` from schema version 6 to 7, in place.
##
## WHY.  Version 7 (internal-files.md "Metadata (meta.dat)", Version History)
## changes no byte of the header or body: it allocates the `EventLogKind`
## values 14-23 that `events.dat` may carry (trace-events.md "EventLogKind
## (u8 enum)"), and moves the version so that a version-6 reader refuses a
## version-7 trace at open.  A version-6 recording carries only kinds 0-13,
## which keep their meaning at version 7, so the version-7 container of the
## same recording differs from it in exactly one byte: the low byte of
## `meta.dat`'s version field.  Every reader refuses any version but 7, so a
## committed version-6 fixture that cannot be re-recorded where it is used
## (a recording made on another OS, or by a recorder the consumer does not
## build) is upgraded with this tool instead.
##
## WHAT.  The byte at `meta.dat` offset 4 is rewritten from 6 to 7 at its
## place in the file; nothing else is written.  The tool refuses a container
## that is not CTFS version 5, whose image is not the file's bytes (a
## whole-file compressed container), whose `meta.dat` is not version 6, or
## whose `events.dat` carries a kind outside 0-13.  The result is checked
## through the CURRENT readers: `meta.dat` must read back as the input's with
## only the version byte changed and `readMetaDat` must accept it, the file
## must differ from the input in that one byte (so every other member is
## byte-identical), the container must carry all four interning tables or
## none of them, and for a split-stream trace (one with `steps.dat`) the
## trace reader must open it and read every `events.dat` record.  A native
## (MCR) bundle carries no `events.dat`; one that carries it without
## `steps.dat` is refused, since its kinds cannot be checked here.
##
## A new recording is written as version 7 by its recorder.  Do not use this
## tool for one.

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import results
import codetracer_ctfs/[types, container]
import codetracer_trace_writer/[meta_dat, new_trace_reader]
import codetracer_trace_types

const
  MetaVersionOffset = 4

proc upgradeMetaDatV6*(data: openArray[byte]): Result[seq[byte], string] =
  ## A version-5 container whose `meta.dat` is schema 6 -> the same bytes with
  ## the schema byte set to 7, verified as the module note says.
  if data.len < 16 or data[5] != CtfsVersion:
    return err("not a CTFS version-" & $CtfsVersion & " container")
  let bs = readU32LE(data, 8)
  let maxRoot = readU32LE(data, 12)

  let runs = ?locateMember(data, "meta.dat", bs, maxRoot)
  if runs.len == 0 or runs[0].len <= MetaVersionOffset + 1:
    return err("meta.dat is too short to carry a version")
  let at = runs[0].at + MetaVersionOffset
  let before = ?readInternalFile(data, "meta.dat", bs, maxRoot)
  if data[at] != 6'u8 or data[at + 1] != 0'u8 or
      before[MetaVersionOffset] != 6'u8:
    return err("meta.dat is schema version " &
      $(uint16(before[MetaVersionOffset]) or
        (uint16(before[MetaVersionOffset + 1]) shl 8)) & ", not 6")

  var output = newSeq[byte](data.len)
  if data.len > 0:
    copyMem(addr output[0], unsafeAddr data[0], data.len)
  output[at] = 7'u8

  # Verify through the current readers.
  let after = ?readInternalFile(output, "meta.dat", bs, maxRoot)
  var expect = before
  expect[MetaVersionOffset] = 7'u8
  if after != expect:
    return err("meta.dat reads back with more than its version changed")
  let parsed = readMetaDat(after)
  if parsed.isErr: return err("readMetaDat refuses the result: " & parsed.error)
  if parsed.get.version != 7:
    return err("readMetaDat reads version " & $parsed.get.version)
  # The output is the input with one byte changed, and that byte lies in
  # meta.dat: every other member is byte-identical by construction.
  var changed = 0
  for i in 0 ..< data.len:
    if data[i] != output[i]: inc changed
  if changed != 1:
    return err("the upgrade changed " & $changed & " bytes, not 1")
  # The interning tables are carried all four or none (`internal-files.md`
  # "Interning Tables"). A native bundle is not opened by the trace reader
  # below, so the set is checked here, with the writer's and readers' check.
  let partialSet = interningSetRefusal(output, maxRoot)
  if partialSet.len > 0:
    return err(partialSet)
  if hasInternalFile(output, "steps.dat", maxRoot):
    # A split-stream trace: the trace reader must open it and read every
    # event, and a version-6 recording carries kinds 0-13 only.
    var opened = openNewTraceFromBytes(output)
    if opened.isErr:
      return err("the current trace reader refuses the result: " & opened.error)
    var r = opened.get
    let n = ?r.ioEventCount()
    for i in 0'u64 ..< n:
      let ev = ?r.ioEvent(i)
      if ord(ev.kind) > ord(elkEvmEvent):
        return err("events.dat record " & $i & " carries kind " &
          $ord(ev.kind) & ", which version 6 does not assign")
  elif hasInternalFile(output, "events.dat", maxRoot):
    return err("the container carries events.dat but no steps.dat; this " &
      "tool cannot check its kinds")
  ok(output)

when isMainModule:
  import std/os

  proc main(): int =
    let args = commandLineParams()
    if args.len != 2:
      stderr.writeLine "usage: meta_v6_to_v7 <in.ct> <out.ct>"
      return 2
    let raw =
      try: readFile(args[0])
      except CatchableError as e:
        stderr.writeLine "cannot read " & args[0] & ": " & e.msg
        return 1
    let input = readCtfsFromFile(args[0])
    if input.isErr:
      stderr.writeLine input.error
      return 1
    if input.get != cast[seq[byte]](raw):
      stderr.writeLine args[0] & ": the container image is not the file's " &
        "bytes (whole-file compression); this tool patches the file in place " &
        "and does not handle it"
      return 1
    let output = upgradeMetaDatV6(input.get)
    if output.isErr:
      stderr.writeLine args[0] & ": " & output.error
      return 1
    let tmp = args[1] & ".v7-tmp"
    try:
      writeFile(tmp, output.get)
      moveFile(tmp, args[1])
    except CatchableError as e:
      stderr.writeLine "cannot write " & args[1] & ": " & e.msg
      return 1
    echo args[0], " -> ", args[1], ": meta.dat v6 -> v7"
    0
  quit(main())
