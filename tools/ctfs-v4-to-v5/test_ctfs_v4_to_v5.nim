## Converting a real version-4 recording leaves every member byte-identical.
##
## No mocks: the input is a real recording and both readers are real.
##
## `testdata/null_main.v4.ct` is the version-4 `mcr/macos-arm64/emulator/eme5/
## null_main.ct` exactly as it was committed before conversion (sha256
## d84ddbad…ae89, at `b104a99`). The expected member table below was NOT
## produced by the converter: it was computed by codetracer-trace-format-nim at
## `86ca226^` — the last revision whose own reader read version 4 — so it checks
## the vendored version-4 walk as well as the version-5 write. Each member is
## read back through the CURRENT reader (the one the suites use) and compared by
## length and sha256, in root-slot order.
##
## `meta_v3_to_v6.nim` is tested on the same recording: its `meta.dat` must be
## accepted by the current `readMetaDat` with the version-3 fields (pinned
## below), the four interning tables must all be there (internal-files.md
## "Interning Tables": all four or none) with `paths.dat` holding the
## version-3 path list and the other three empty, every other member must
## still match the table, and the member renames of recorders `e16f18457` and
## `40aa129e` must map each old lossy key to its storable name.
##
## `testdata/one_puts.v4.ct` is the version-4 `eme5/one_puts.ct` as committed
## at `50d4a69` (sha256 pinned below, taken from git, not from the tool). It
## stores its event log under the lossy keys of `event_log.dat` /
## `event_log.idx`, which the current writer cannot store, so its chain also
## covers the renames; its committed fixture is pinned the same way.  The committed fixture
## must be exactly v4 -> v5 -> meta v6 -> meta v7 of the kept original, byte
## for byte, so a later edit to that file fails here too.  The last step is
## `../meta-v6-to-v7` (codetracer-trace-format-nim `20ba929`, after which the
## current readers read `meta.dat` version 7 only); a version-6 `meta.dat` is
## read through them as that step's output, which differs in its version byte
## alone.
##
## `eme_m9c_2006/one_write.ct` went through the same chain before
## `member_renames.nim` carried all of `40aa129e`'s renames, and kept its
## record configuration under `recordcfg.bin`'s lossy key.  Its version-4
## original is not kept, so the regenerated fixture is pinned to that first
## conversion with the one key renamed, and every committed macOS fixture is
## checked for a member left under an old key.
##
## Run:  nim c -r --path:<codetracer-trace-format-nim>/src test_ctfs_v4_to_v5.nim
## (needs nimcrypto, which codetracer-trace-format-nim's environment carries).

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[options, os, strutils, unittest]
import results, nimcrypto/sha2
import codetracer_ctfs/[types, base40, container]
import codetracer_trace_writer/[meta_dat, interning_table]
import native_decoder
import ./ctfs_v4_to_v5
import ./meta_v3_to_v6
import "../meta-v6-to-v7/meta_v6_to_v7"

const
  here = currentSourcePath().parentDir
  v4Input = here / "testdata" / "null_main.v4.ct"
  convertedFixture = here / ".." / ".." / "mcr" / "macos-arm64" / "emulator" /
    "eme5" / "null_main.ct"
  onePutsV4 = here / "testdata" / "one_puts.v4.ct"
  # `git show 50d4a69:mcr/macos-arm64/emulator/eme5/one_puts.ct | sha256sum`
  onePutsV4Sha256 =
    "4F95B08536F64769DE9CFE851C2D80A5C7739594A561412E045168B2A4EC4A66"
  onePutsFixture = here / ".." / ".." / "mcr" / "macos-arm64" / "emulator" /
    "eme5" / "one_puts.ct"
  m9cFixture = here / ".." / ".." / "mcr" / "macos-arm64" / "emulator" /
    "eme_m9c_2006" / "one_write.ct"
  # `git show 76e71a4^:mcr/macos-arm64/emulator/eme_m9c_2006/one_write.ct |
  # sha256sum`: the version-6 file the first conversion made, with the record
  # configuration still under the lossy key of `recordcfg.bin`.
  m9cV6Sha256 =
    "c02ddc8910bf3e868ceee816040e888e34fe9f01909c804ca0c4e1232c1a7f8c"

  # name, length, sha256 — from the `86ca226^` reader, in root-slot order.
  expected = [
    ("meta.dat", 251,
      "75DE4DE81256690A10164227B1C8F2008F965DC4143C3A11B65D00E678CC4939"),
    ("platform.bin", 35,
      "E329224D13F9224662FB549734B62FEBEC536BDC01B8810681D6AF2F64B7BA09"),
    ("dsc.bin", 38,
      "9434A760F6B9FFA0DD3121B13225B79874E6D1C3CFBEDBCE5D6B4422506361A5"),
    ("debug.dat", 17144,
      "CDB33DEBD19E8BA944F718808DB0F4ACC0E89E23F773815F4B1286207FA574CB"),
    ("cp0.regs", 280,
      "36B7F91065E4E91DC16EA3D1676BED9DE1587DA8CC4DEEACE091CFB8754C3065"),
    ("cp0.mem", 311360,
      "3541D4C33F97F3294BCBCE66752EF4CB69BAF0938D92A98608AE6AEA092379C3"),
    ("t00000000000", 1307,
      "C383968D2E50A6DF19806E4AA5F7065A35FEC4504F3DEC96EC86D68EBC0A16CE"),
    ("paths.json", 47,
      "C99F34D76DE59254A627DBFA1CF0505611696BDC5C682E2FA32501F2D3FA1BD2"),
  ]

template checkMembers(image: seq[byte]) =
  ## Version 5, the expected members in slot order and nothing else, each
  ## read through the current reader with the expected length and digest.
  ## A template, not a proc: `check` marks the enclosing `test` failed only
  ## when it expands inside it (from a proc the test still prints [OK]).
  let data = image
  check data[5] == CtfsVersion
  let blockSize = readU32LE(data, 8)
  let maxRoot = readU32LE(data, 12)
  check blockSize == 4096'u32
  check maxRoot == 128'u32
  var names: seq[string]
  for i in 0 ..< int(maxRoot):
    let encoded = readU64LE(data, HeaderSize + ExtHeaderSize + i * FileEntrySize + 16)
    if encoded != 0:
      names.add base40Decode(encoded)
  var wantNames: seq[string]
  for (name, _, _) in expected:
    wantNames.add name
  check names == wantNames
  for (name, length, digest) in expected:
    let got = readInternalFile(data, name, blockSize, maxRoot)
    check got.isOk
    if got.isOk:
      check got.get.len == length
      check $sha256.digest(got.get) == digest

template checkMembersExceptMeta(image: seq[byte]) =
  ## Every member but `meta.dat` against the `86ca226^` table, by name.
  let data = image
  for (name, length, digest) in expected:
    if name == "meta.dat": continue
    let got = readInternalFile(data, name, 4096, 128)
    check got.isOk
    if got.isOk:
      check got.get.len == length
      check $sha256.digest(got.get) == digest

suite "ctfs v4 -> v5":
  test "the v4 walk reads the members the 86ca226^ reader read":
    let src = readV4Members(readCtfsFromFile(v4Input).get)
    check src.isOk
    check src.get.members.len == expected.len
    for i, (name, length, digest) in expected:
      check src.get.members[i].name == name
      check src.get.members[i].bytes.len == length
      check $sha256.digest(src.get.members[i].bytes) == digest

  test "converting a recording keeps every member byte-identical":
    let output = convertV4ToV5(readCtfsFromFile(v4Input).get)
    check output.isOk
    if output.isOk:
      checkMembers(output.get)

  test "meta.dat v3 -> v6 keeps every field and moves the path list":
    let v5 = convertV4ToV5(readCtfsFromFile(v4Input).get).get
    let up = upgradeMetaDatV3(v5)
    check up.isOk
    if up.isOk:
      let data = up.get
      let raw = readInternalFile(data, "meta.dat", 4096, 128).get
      check raw[4] == 6'u8 and raw[5] == 0'u8
      # The current reader reads version 7 only: read the version-7 view.
      let asV7 = upgradeMetaDatV6(data)
      check asV7.isOk
      let meta = readMetaDat(readInternalFile(asV7.get, "meta.dat", 4096,
                                              128).get)
      check meta.isOk
      if meta.isOk:
        check meta.get.version == 7
        check meta.get.recordingId == "019f2f59-f478-7c60-800f-91c100c55cca"
        check meta.get.program == "/tmp/eme5rec/null_main"
        check meta.get.recorderId == "mcr-interpose"
        check meta.get.mcrFields.isSome
      check detectNativeBundle(asV7.get).isOk
      check interningSetRefusal(data, 128) == ""
      for table in ["funcs", "types", "varnames"]:
        let t = initInterningTableReader(data, table, 4096, 128)
        check t.isOk
        if t.isOk:
          check t.get.count == 0
      let paths = initInterningTableReader(data, "paths", 4096, 128)
      check paths.isOk
      if paths.isOk:
        check paths.get.count == 1
        check paths.get.readById(0).get ==
          "ct_emulator/tests/fixtures/eme5/null_main.c"
      for (name, length, digest) in expected:
        if name == "meta.dat": continue
        let got = readInternalFile(data, name, 4096, 128)
        check got.isOk
        if got.isOk:
          check got.get.len == length
          check $sha256.digest(got.get) == digest
      # It is not version 3 any more: a second upgrade is refused by name.
      let again = upgradeMetaDatV3(data)
      check again.isErr
      check "not 3" in again.error

  test "the e16f18457 and 40aa129e renames map each old lossy key to its storable name":
    for (old, new) in MemberRenames:
      check not base40Encodable(old)
      check base40Encodable(new)
      check renamedMember(base40Encode(old)) == new
      check renamedMember(base40Encode(new)) == ""
    var keys: seq[uint64]
    for (old, _) in MemberRenames: keys.add base40Encode(old)
    for i in 0 ..< keys.len:
      for j in i + 1 ..< keys.len:
        check keys[i] != keys[j]

  test "no committed macOS fixture keeps a member under a renamed recorder key":
    # Only the two `eme5` recordings are pinned to a kept original (below), so
    # the others are checked by what the chain must have made of them: every
    # member under the name current readers open.  A member left under an
    # old key is not an error anywhere; its readers find nothing and fall
    # back.  `eme_m9c_2006` kept `recordcfg.bin`'s key that way, and with
    # no record configuration its strong-kernel replay routed founding events
    # by raw stack pointer.
    let root = here / ".." / ".." / "mcr" / "macos-arm64" / "emulator"
    var containers = 0
    for path in walkDirRec(root):
      if not path.endsWith(".ct"): continue
      containers += 1
      let data = readCtfsFromFile(path).get
      let maxRoot = readU32LE(data, 12)
      for i in 0 ..< int(maxRoot):
        let key = readU64LE(data, HeaderSize + ExtHeaderSize + i * FileEntrySize + 16)
        if key == 0: continue
        let renamed = renamedMember(key)
        if renamed.len > 0:
          checkpoint path.relativePath(root) & ": member " & base40Decode(key) &
            " is stored under an old key; readers open " & renamed
        check renamed.len == 0
    # Six recordings, so a walk that finds nothing cannot pass.
    check containers == 6

  test "the committed fixture is exactly that conversion, then meta v6 -> v7":
    let v5 = convertV4ToV5(readCtfsFromFile(v4Input).get).get
    let up = upgradeMetaDatV3(v5)
    check up.isOk
    if up.isOk:
      let v7 = upgradeMetaDatV6(up.get)
      check v7.isOk
      if v7.isOk:
        check readCtfsFromFile(convertedFixture).get == v7.get
        checkMembersExceptMeta(v7.get)

  test "one_puts: the kept original is the version-4 file committed at 50d4a69":
    check $sha256.digest(readCtfsFromFile(onePutsV4).get) == onePutsV4Sha256

  test "one_puts: the event log is renamed and every other member kept":
    let src = readV4Members(readCtfsFromFile(onePutsV4).get)
    check src.isOk
    if src.isOk:
      var keys: seq[uint64]
      for m in src.get.members: keys.add m.key
      check base40Encode("event_log.dat") in keys
      check base40Encode("event_log.idx") in keys
      let v5 = convertV4ToV5(readCtfsFromFile(onePutsV4).get)
      check v5.isOk
      if v5.isOk:
        for m in src.get.members:
          let renamed = renamedMember(m.key)
          let name = if renamed.len > 0: renamed else: m.name
          let got = readInternalFile(v5.get, name, src.get.blockSize,
                                     src.get.maxRootEntries)
          check got.isOk
          if got.isOk:
            check got.get == m.bytes
        check readInternalFile(v5.get, "eventlog.dat", 4096, 128).isOk
        check readInternalFile(v5.get, "eventlog.idx", 4096, 128).isOk

  test "one_puts: the committed fixture is exactly the v4 -> v7 chain":
    let v5 = convertV4ToV5(readCtfsFromFile(onePutsV4).get)
    check v5.isOk
    if v5.isOk:
      let up = upgradeMetaDatV3(v5.get)
      check up.isOk
      if up.isOk:
        check interningSetRefusal(up.get, 128) == ""
        let v7 = upgradeMetaDatV6(up.get)
        check v7.isOk
        if v7.isOk:
          check readCtfsFromFile(onePutsFixture).get == v7.get
          check detectNativeBundle(v7.get).isOk

  test "eme_m9c_2006: the fixture is its first conversion with recordcfg renamed":
    # Its version-4 original (29 MB) is not kept here, so the regenerated
    # fixture is pinned to the conversion committed before it: setting the
    # `recordcfg` key back to `recordcfg.bin`'s lossy key and `meta.dat`'s
    # version byte back to 6 must give that file exactly.  Every other byte,
    # every member's included, is then the first conversion's.
    var data = readCtfsFromFile(m9cFixture).get
    let blockSize = readU32LE(data, 8)
    let maxRoot = readU32LE(data, 12)
    var slots: seq[int]
    for i in 0 ..< int(maxRoot):
      let at = HeaderSize + ExtHeaderSize + i * FileEntrySize + 16
      if readU64LE(data, at) == base40Encode("recordcfg"): slots.add at
    check slots.len == 1
    check renamedMember(base40Encode("recordcfg.bin")) == "recordcfg"
    if slots.len == 1:
      let old = base40Encode("recordcfg.bin")
      for b in 0 ..< 8:
        data[slots[0] + b] = byte((old shr (8 * b)) and 0xFF)
      let meta = locateMember(data, "meta.dat", blockSize, maxRoot)
      check meta.isOk
      if meta.isOk:
        check data[meta.get[0].at + 4] == 7'u8
        data[meta.get[0].at + 4] = 6
        check toLowerAscii($sha256.digest(data)) == m9cV6Sha256

  test "a container that is not version 4 is refused, naming its version":
    let v5 = convertV4ToV5(readCtfsFromFile(v4Input).get).get
    let again = convertV4ToV5(v5)
    check again.isErr
    check "version is 5" in again.error
