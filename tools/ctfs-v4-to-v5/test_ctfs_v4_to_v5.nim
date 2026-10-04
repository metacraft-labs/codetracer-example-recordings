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
## The same table is then checked against the committed, converted fixture, so
## a later edit to that file that changes any member fails here too.
##
## Run:  nim c -r --path:<codetracer-trace-format-nim>/src test_ctfs_v4_to_v5.nim
## (needs nimcrypto, which codetracer-trace-format-nim's environment carries).

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[os, strutils, unittest]
import results, nimcrypto/sha2
import codetracer_ctfs/[types, base40, container]
import ./ctfs_v4_to_v5

const
  here = currentSourcePath().parentDir
  v4Input = here / "testdata" / "null_main.v4.ct"
  convertedFixture = here / ".." / ".." / "mcr" / "macos-arm64" / "emulator" /
    "eme5" / "null_main.ct"

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

  test "the committed fixture is that conversion":
    checkMembers(readCtfsFromFile(convertedFixture).get)

  test "a container that is not version 4 is refused, naming its version":
    let v5 = convertV4ToV5(readCtfsFromFile(v4Input).get).get
    let again = convertV4ToV5(v5)
    check again.isErr
    check "version is 5" in again.error
