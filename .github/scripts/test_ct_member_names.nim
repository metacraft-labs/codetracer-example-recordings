## Test for ct-member-names: a container whose members all have storable
## names passes; one that carries a member under a lossy key fails, naming it;
## a file that is no container is an error.
##
## Usage:
##   test_ct_member_names <path-to-ct-member-names>
##
## No mocks: the containers are written with the real CTFS writer
## (codetracer_ctfs/container), and the checker is the built binary, run as a
## process exactly as verify-recordings.sh runs it.  The lossy key is planted
## by overwriting a written member's key in the root directory with the key a
## lossy writer stored for `cp.vdso_time.bin` (`cp.vdso` NUL `time`), so the
## test does not depend on the writer still accepting such a name.
##
## Build against codetracer-trace-format-nim:
##   nim c -d:release -p:<codetracer-trace-format-nim>/src -o:test_ct_member_names test_ct_member_names.nim

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]
import std/[os, osproc, strutils]
import results
import codetracer_ctfs/[container, base40, types]

proc bytesOf(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

proc writeContainer(path: string, members: openArray[(string, string)]) =
  var c = createCtfs()
  for (name, body) in members:
    var f = c.addFile(name).get()
    doAssert c.writeToFile(f, bytesOf(body)).isOk
  doAssert c.writeCtfsToFile(path).isOk

proc lossyKey(name: string): uint64 =
  ## The key a writer that does not check its names stores for `name`: a
  ## character outside the alphabet becomes the padding index, and everything
  ## past the 12th is dropped.
  const alphabet = "\x000123456789abcdefghijklmnopqrstuvwxyz./-"
  var mult = 1'u64
  for i in 0 ..< min(name.len, 12):
    let idx = alphabet.find(name[i])
    result += uint64(max(idx, 0)) * mult
    mult *= 40

proc plantKey(path, storedName: string, key: uint64) =
  ## Overwrite the root-directory key of the member stored as `storedName`.
  var data = readFile(path)
  let want = base40Encode(storedName)
  var off = HeaderSize + ExtHeaderSize
  while off + FileEntrySize <= data.len:
    var k = 0'u64
    for b in 0 ..< 8: k = k or (uint64(byte(data[off + 16 + b])) shl (8 * b))
    if k == want:
      for b in 0 ..< 8: data[off + 16 + b] = char((key shr (8 * b)) and 0xff)
      writeFile(path, data)
      return
    off += FileEntrySize
  doAssert false, "no root entry named " & storedName

proc main(): int =
  if paramCount() != 1:
    stderr.writeLine("usage: test_ct_member_names <path-to-ct-member-names>")
    return 2
  let checker = paramStr(1)
  let dir = getTempDir() / "test_ct_member_names_" & $getCurrentProcessId()
  createDir(dir)
  defer: removeDir(dir)
  var failures = 0
  template expect(cond: bool, what: string) =
    if cond: echo "  ok   " & what
    else:
      echo "  FAIL " & what
      inc failures

  let good = dir / "good.ct"
  writeContainer(good, [("meta.dat", "m"), ("recordcfg", "r"),
                        ("cp.vtime.bin", "v"), ("t00000000000", "t")])
  let (goodOut, goodRc) = execCmdEx(checker.quoteShell & " " & good.quoteShell)
  expect(goodRc == 0, "a container of storable names passes (rc " & $goodRc & ")")
  expect("\"cp.vtime.bin\"" in goodOut, "its member names are listed")

  let bad = dir / "bad.ct"
  writeContainer(bad, [("meta.dat", "m"), ("cp.vtime.bin", "v")])
  plantKey(bad, "cp.vtime.bin", lossyKey("cp.vdso_time.bin"))
  let (badOut, badRc) = execCmdEx(checker.quoteShell & " " & bad.quoteShell)
  expect(badRc == 1, "a member under a lossy key fails (rc " & $badRc & ")")
  expect("cp.vdso\\x00time" in badOut, "the lossy key is named: " & badOut.strip())

  let both = execCmdEx(checker.quoteShell & " " & good.quoteShell & " " &
                       bad.quoteShell)
  expect(both.exitCode == 1, "one bad file among good ones fails the run")

  let junk = dir / "junk.ct"
  writeFile(junk, "not a container")
  let (_, junkRc) = execCmdEx(checker.quoteShell & " " & junk.quoteShell)
  expect(junkRc == 2, "a file that is no container is an error (rc " & $junkRc & ")")

  if failures > 0:
    echo $failures & " check(s) failed"
    return 1
  echo "all checks passed"
  0

quit(main())
