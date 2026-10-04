## One-off converter: a version-4 CTFS container to version 5, members unchanged.
##
## WHY THIS EXISTS. codetracer-trace-format-nim `86ca226` (2026-10-01) made the
## container version 5 — a member of at most one block is stored DIRECT, a
## never-written member owns no block — and made every reader refuse every
## other version, naming it. The five recordings under
## `mcr/macos-arm64/emulator/` were written as version 4 by a SIP-disabled Mac
## that is not available to re-record them, so the suites that replay them
## stopped at the version check. The owner chose conversion over re-recording
## (2026-10-04): read each member with the version-4 reader, write it unchanged
## with the current writer.
##
## WHAT IT DOES. `readV4Members` is the version-4 member walk, vendored from
## `src/codetracer_ctfs/container.nim` at `86ca226^` (`readInternalFile`) so the
## converter does not depend on a reader the library no longer has. It returns
## every root entry in slot order. `convertV4ToV5` writes those members, in the
## same order and under the same names, into a container created by the CURRENT
## writer with the source's block size, root-entry count, encryption byte and
## shard count. It then reads every member back through the CURRENT reader and
## refuses the result unless each one is byte-identical to what the version-4
## walk produced. Member bytes are never interpreted: a member that is itself
## versioned (`meta.dat`, an event stream) keeps the version it was written with.
##
## Usage:  ctfs_v4_to_v5 <in.ct> <out.ct>     (in == out converts in place)
##
## Build:  nim c --path:<codetracer-trace-format-nim>/src ctfs_v4_to_v5.nim

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/os
import results
import codetracer_ctfs/[types, base40, container]

const V4Version = 4'u8

type
  V4Member* = object
    name*: string
    bytes*: seq[byte]

  V4Container* = object
    blockSize*: uint32
    maxRootEntries*: uint32
    encryption*: uint8
    maxShards*: uint8
    members*: seq[V4Member]

proc readV4MemberBytes(data: openArray[byte], name: string,
    fileSize, mapBlock: uint64, blockSize: uint32): Result[seq[byte], string] =
  ## The version-4 walk: every non-empty member has a mapping block, level 1
  ## holds `usable` data pointers and a chain pointer in its last slot, level
  ## `n` holds `usable^n` blocks reached through `n - 1` descents. Bounds are
  ## floored to whole blocks on all three paths (root, mapping, data), as the
  ## version-4 reader did.
  if fileSize == 0:
    return ok(newSeq[byte](0))
  let wholeBlocks = uint64(data.len div int(blockSize))
  if mapBlock == 0'u64 or mapBlock >= wholeBlocks:
    return err("member " & name & ": mapping root block " & $mapBlock &
      " is out of bounds")

  var fileBytes = newSeq[byte](int(fileSize))
  let usable = uint64(blockSize) div 8 - 1
  var remaining = int(fileSize)
  var destPos = 0
  var blockIdx: uint64 = 0

  while remaining > 0:
    var idx = blockIdx
    var currentLevelBlock = mapBlock
    var level: uint32 = 1
    block findLevel:
      while true:
        var cap: uint64 = 1
        for l in 0'u32 ..< level:
          cap = cap * usable
        if idx < cap:
          break findLevel
        idx -= cap
        level += 1
        if level > MaxChainLevels:
          return err("member " & name & ": block index too large for mapping")
        let chainOff = int(currentLevelBlock) * int(blockSize) + int(usable) * 8
        if chainOff + 8 > data.len:
          return err("member " & name & ": chain pointer out of bounds")
        let chainPtr = readU64LE(data, chainOff)
        if chainPtr == 0 or chainPtr >= wholeBlocks:
          return err("member " & name & ": chain pointer at level " & $level &
            " names block " & $chainPtr)
        currentLevelBlock = chainPtr

    var navBlock = currentLevelBlock
    var navLevel = level
    var navIdx = idx
    while navLevel > 1:
      var subCap: uint64 = 1
      for l in 0'u32 ..< (navLevel - 1):
        subCap = subCap * usable
      let childOff = int(navBlock) * int(blockSize) + int(navIdx div subCap) * 8
      if childOff + 8 > data.len:
        return err("member " & name & ": child pointer out of bounds")
      let childBlock = readU64LE(data, childOff)
      if childBlock == 0 or childBlock >= wholeBlocks:
        return err("member " & name & ": child pointer at level " &
          $navLevel & " names block " & $childBlock)
      navBlock = childBlock
      navIdx = navIdx mod subCap
      navLevel -= 1

    let ptrOff = int(navBlock) * int(blockSize) + int(navIdx) * 8
    if ptrOff + 8 > data.len:
      return err("member " & name & ": data block pointer out of bounds")
    let dataBlock = readU64LE(data, ptrOff)
    if dataBlock == 0 or dataBlock >= wholeBlocks:
      return err("member " & name & ": data block " & $blockIdx &
        " is block " & $dataBlock)
    let blockOff = int(dataBlock) * int(blockSize)
    let toCopy = min(remaining, int(blockSize))
    for i in 0 ..< toCopy:
      fileBytes[destPos + i] = data[blockOff + i]
    destPos += toCopy
    remaining -= toCopy
    blockIdx += 1

  ok(fileBytes)

proc readV4Members*(data: openArray[byte]): Result[V4Container, string] =
  ## Every member of a version-4 container, in root-slot order.
  ##
  ## Refuses anything that is not version 4, and a root directory whose used
  ## slots are not contiguous from slot 0: the current writer fills the first
  ## free slot, so a gap could not be reproduced and member order would change.
  if data.len < HeaderSize + ExtHeaderSize or not hasCtfsMagic(data):
    return err("not a CTFS container")
  if data[5] != V4Version:
    return err("container version is " & $data[5] & ", not 4")
  var c = V4Container(
    blockSize: readU32LE(data, 8),
    maxRootEntries: readU32LE(data, 12),
    encryption: data[6],
    maxShards: data[7])
  if c.blockSize == 0 or c.blockSize mod 8 != 0:
    return err("block size " & $c.blockSize & " is not a positive multiple of 8")
  var sawEmpty = false
  for i in 0 ..< int(c.maxRootEntries):
    let off = HeaderSize + ExtHeaderSize + i * FileEntrySize
    if off + FileEntrySize > data.len:
      return err("root entry " & $i & " lies past the end of the container")
    let size = readU64LE(data, off)
    let mapBlock = readU64LE(data, off + 8)
    let encoded = readU64LE(data, off + 16)
    if encoded == 0:
      if size != 0 or mapBlock != 0:
        return err("root entry " & $i & " has no name but size " & $size &
          " and mapping block " & $mapBlock)
      sawEmpty = true
      continue
    if sawEmpty:
      return err("root entry " & $i & " follows an empty slot; the current " &
        "writer cannot reproduce a gap in the root directory")
    let name = base40Decode(encoded)
    if base40Encode(name) != encoded:
      return err("root entry " & $i & ": name 0x" & $encoded &
        " does not survive a base40 round trip")
    let bytes = ?readV4MemberBytes(data, name, size, mapBlock, c.blockSize)
    c.members.add V4Member(name: name, bytes: bytes)
  ok(c)

proc convertV4ToV5*(data: openArray[byte]): Result[seq[byte], string] =
  ## A version-5 container holding exactly the version-4 container's members,
  ## verified member by member through the current reader.
  let src = ?readV4Members(data)
  if src.encryption > uint8(high(CtfsEncryptionMethod)):
    return err("unknown encryption method " & $src.encryption)
  var dst = createCtfs(src.blockSize, src.maxRootEntries,
    CtfsEncryptionMethod(src.encryption), src.maxShards)
  for m in src.members:
    var f = ?dst.addFile(m.name)
    if m.bytes.len > 0:
      ?dst.writeToFile(f, m.bytes)
  let output = dst.toBytes()

  # Read back through the CURRENT reader — the one the suites use.
  for m in src.members:
    let back = readInternalFile(output, m.name, src.blockSize,
      src.maxRootEntries)
    if back.isErr:
      return err("member " & m.name & " does not read back: " & back.error)
    if back.get != m.bytes:
      return err("member " & m.name & " reads back different bytes (" &
        $back.get.len & " vs " & $m.bytes.len & ")")
  ok(output)

when isMainModule:
  proc main(): int =
    let args = commandLineParams()
    if args.len != 2:
      stderr.writeLine "usage: ctfs_v4_to_v5 <in.ct> <out.ct>"
      return 2
    let input = readCtfsFromFile(args[0])
    if input.isErr:
      stderr.writeLine input.error
      return 1
    let output = convertV4ToV5(input.get)
    if output.isErr:
      stderr.writeLine args[0] & ": " & output.error
      return 1
    # Write beside the target and rename, so an in-place conversion that
    # fails half-way never leaves a truncated recording.
    let tmp = args[1] & ".v5-tmp"
    try:
      writeFile(tmp, output.get)
      moveFile(tmp, args[1])
    except CatchableError as e:
      stderr.writeLine "cannot write " & args[1] & ": " & e.msg
      return 1
    echo args[0], " -> ", args[1], ": ", output.get.len, " bytes"
    0

  quit(main())
