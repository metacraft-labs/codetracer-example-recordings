## Test for ct-leak-scan: plant personal data and source code in CTFS
## containers, in each place a recording can hold them, and require the
## scanner to refuse every one; and pass a clean container carrying the
## look-alikes a publishable recording holds.
##
## Usage:
##   test_ct_leak_scan <path-to-ct-leak-scan>
##
## No mocks: the containers are written with the real CTFS writer
## (codetracer_ctfs/container), and the scanner is the built binary, run as a
## process exactly as the regeneration workflow runs it. Every case passes
## `--no-host-identity`, so the result does not depend on who runs the test.
##
## The planted user name is assembled at run time and is not a real one.
##
## Build against codetracer-trace-format-nim:
##   nim c -d:release -p:<codetracer-trace-format-nim>/src -o:test_ct_leak_scan test_ct_leak_scan.nim

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[os, osproc, strutils]
import results
import codetracer_ctfs/[container, types, zstd_bindings]

let fakeUser = "plant" & "eduser"     # never a real account name
let fakeHost = "PLANTED" & "-HOST-7"

proc bytesOf(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

proc utf16Of(s: string): seq[byte] =
  for c in s:
    result.add(byte(c))
    result.add(0'u8)

proc zstdCompress(data: seq[byte]): seq[byte] =
  let bound = ZSTD_compressBound(csize_t(data.len))
  result = newSeq[byte](int(bound))
  let n = ZSTD_compress(addr result[0], bound, unsafeAddr data[0],
                        csize_t(data.len), 3)
  doAssert ZSTD_isError(n) == 0, "zstd compress failed"
  result.setLen(int(n))

proc noise(n: int, seed: int): seq[byte] =
  ## Deterministic incompressible filler, never printable ASCII, so a member
  ## spans several blocks and its frames do too.
  result = newSeq[byte](n)
  var x = uint32(seed) * 2654435761'u32 + 12345'u32
  for i in 0 ..< n:
    x = x xor (x shl 13); x = x xor (x shr 17); x = x xor (x shl 5)
    result[i] = byte(x and 0x7f) or 0x80

proc containerBytes(members: openArray[(string, seq[byte])]): seq[byte] =
  var c = createCtfs()
  for (name, body) in members:
    var f = c.addFile(name).get()
    doAssert c.writeToFile(f, body).isOk
  c.toBytes()

proc writeContainer(path: string, members: openArray[(string, seq[byte])]) =
  writeFile(path, cast[string](containerBytes(members)))

proc holds(hay, needle: seq[byte]): bool =
  cast[string](hay).find(cast[string](needle)) >= 0

type Case = object
  name: string
  args: seq[string]
  wantExit: int
  wantText: seq[string]
  wantAbsent: seq[string] ## text the report must not print

proc main(): int =
  let args = commandLineParams()
  if args.len != 1:
    stderr.writeLine("usage: test_ct_leak_scan <ct-leak-scan>")
    return 2
  let scanner = absolutePath(args[0])
  let dir = getTempDir() / "ct-leak-scan-test-" & $getCurrentProcessId()
  createDir(dir)
  defer: removeDir(dir)
  let bs = int(DefaultBlockSize)
  var cases: seq[Case]

  # --- clean: what a recording made on a CI runner legitimately holds ------
  let fixtureSource = "#include <windows.h>\n\nint main(void) {\n  return calculate_sum(10);\n}\n"
  let allowedSource = dir / "fixture_prog.c"
  writeFile(allowedSource, fixtureSource)
  writeContainer(dir / "clean.ct", @[
    ("meta.json", bytesOf("{\"program\":\"C:\\actions-runner\\_work\\x\\ct_fixture_prog.exe\"}")),
    ("guest.env", utf16Of("TEMP=C:\\Windows\\ServiceProfiles\\NetworkService\\AppData\\Local\\Temp\0" &
      "PUBLIC=C:\\Users\\Public\0HOME=C:\\Users\\runneradmin\0X=C:\\Users\\%USERNAME%\\x\0")),
    ("debug.dat", bytesOf("RSDS") & noise(20, 1) &
      bytesOf("C:\\actions-runner\\_work\\x\\ct_fixture_prog.pdb\0") &
      bytesOf("ct_interpose/src/library_init_windows.nim\0") &
      bytesOf("stew@endians2.nim(134, 3) `x`\0") & noise(3 * bs, 2)),
    ("src.c", bytesOf(fixtureSource)),
    ("cppages.nzd", zstdCompress(utf16Of("C:\\Users\\Default\\NTUSER.DAT\0") & noise(bs, 3))),
  ])
  cases.add Case(name: "clean", wantExit: 0,
    args: @["--allow-source", allowedSource],
    wantText: @["CLEAN", "home-dir allowed", "home-dir placeholder",
                "allowed source text", "CodeView PDB path",
                "library_init_windows.nim"])

  # --- a home directory in plain ASCII --------------------------------------
  writeContainer(dir / "home-ascii.ct", @[
    ("meta.json", bytesOf("{\"program\":\"C:\\Users\\" & fakeUser & "\\src\\a.exe\"}"))])
  cases.add Case(name: "home-ascii", wantExit: 1, wantText: @["REFUSED home-dir"])

  # --- the measured leak: UTF-16LE INetCache path in a zstd frame whose
  # blocks are NOT contiguous in the container (two members written in turn).
  let inet = noise(2 * bs, 4) &
    utf16Of("C:\\Users\\" & fakeUser & "\\AppData\\Local\\Microsoft\\Windows\\INetCache\0") &
    noise(2 * bs, 5)
  let frame = zstdCompress(inet)
  doAssert frame.len > 2 * bs, "test setup: the frame must span blocks"
  block:
    var c = createCtfs()
    var a = c.addFile("t00000000000").get()
    var b = c.addFile("i00000000000").get()
    var at = 0
    while at < frame.len:
      let n = min(bs, frame.len - at)
      doAssert c.writeToFile(a, frame.toOpenArray(at, at + n - 1)).isOk
      doAssert c.writeToFile(b, noise(bs, 6 + at)).isOk
      at += n
    let raw = c.toBytes()
    # The point of this case: neither the text nor the whole frame is in the
    # raw bytes, so a raw scan cannot see it.
    doAssert not raw.holds(utf16Of(fakeUser)), "test setup: text not hidden"
    doAssert not raw.holds(frame), "test setup: the frame is contiguous"
    writeFile(dir / "split-frame.ct", cast[string](raw))
  cases.add Case(name: "split-frame", wantExit: 1,
    wantText: @["REFUSED home-dir", "utf16le", "member t00000000000 zstd@0"])

  # --- a forbidden literal (the recording host's name), UTF-16LE -----------
  writeContainer(dir / "forbid.ct", @[
    ("bootevt.bin", noise(bs, 7) & utf16Of("COMPUTERNAME=" & fakeHost & "\0") & noise(bs, 8))])
  cases.add Case(name: "forbid", wantExit: 1, args: @["--forbid", fakeHost],
    wantText: @["REFUSED forbidden --forbid"])

  # --- source code: a Nim module and a C file with no --allow-source -------
  writeContainer(dir / "nim-source.ct", @[
    ("b/0002", noise(bs, 9) & bytesOf("\nimport std/os\n\nproc leak*(x: int): int =\n  x + 1\n") & noise(bs, 10))])
  cases.add Case(name: "nim-source", wantExit: 1, wantText: @["REFUSED source-text Nim"],
    wantAbsent: @["leak*(x: int)", "import std/os"])
  writeContainer(dir / "c-source.ct", @[("src.c", bytesOf(fixtureSource))])
  cases.add Case(name: "c-source-not-allowed", wantExit: 1,
    wantText: @["REFUSED source-text C"])

  # --- a container inside a member (a portable export embeds files) --------
  let inner = containerBytes(@[("env", bytesOf("HOME=/home/" & fakeUser & "\0"))])
  writeContainer(dir / "nested-container.ct", @[("b/0001", inner)])
  cases.add Case(name: "nested-container", wantExit: 1,
    wantText: @["REFUSED home-dir", "member b/0001 > member env"])

  # --- a stale block: a member truncated and rewritten leaves its old blocks
  # in the container, owned by no member.
  block:
    var c = createCtfs()
    var f = c.addFile("meta.json").get()
    doAssert c.writeToFile(f, bytesOf("/Users/" & fakeUser & "/m/dev/ct_cli\0") & noise(bs, 11)).isOk
    var g = c.truncateFileContent(f).get()
    doAssert c.writeToFile(g, bytesOf("{}")).isOk
    let raw = c.toBytes()
    doAssert raw.holds(bytesOf(fakeUser)), "test setup: no stale block"
    writeFile(dir / "stale-block.ct", cast[string](raw))
  cases.add Case(name: "stale-block", wantExit: 1,
    wantText: @["REFUSED home-dir", "container bytes outside every member"])

  # --- an embedded PDB that carries its source files -----------------------
  writeContainer(dir / "pdb-injected-sources.ct", @[
    ("b/0003", bytesOf("Microsoft C/C++ MSF 7.00\r\n\x1aDS\0\0\0") & noise(bs, 12) &
      bytesOf("/src/headerblock\0") & noise(bs, 13))])
  cases.add Case(name: "pdb-injected-sources", wantExit: 1,
    wantText: @["REFUSED pdb-sources"])

  # --- a path split across two successive zstd frames of one stream, cut
  # inside the `\Users\` separator: neither frame holds a match by itself.
  # The recorder seals a stream's frames at byte counts, not at records.
  block:
    let whole = utf16Of("C:\\Users\\" & fakeUser & "\\AppData\\Local\\Temp\0")
    let cut = utf16Of("C:\\Us").len
    writeContainer(dir / "seam-split.ct", @[("t00000000000",
      zstdCompress(noise(bs, 14) & whole[0 ..< cut]) & noise(16, 15) &
      zstdCompress(whole[cut .. ^1] & noise(bs, 16)))])
  cases.add Case(name: "seam-split", wantExit: 1,
    wantText: @["REFUSED home-dir", "seam before zstd@"])

  # --- a user name in another script, UTF-16LE and UTF-8 ------------------
  block:
    var name16: seq[byte]
    for cp in [0x0417, 0x0430, 0x0445, 0x0430, 0x0440, 0x0438]:
      name16.add(byte(cp and 0xff)); name16.add(byte(cp shr 8))
    writeContainer(dir / "nonascii-utf16.ct", @[("t00000000000", zstdCompress(
      noise(bs, 17) & utf16Of("C:\\Users\\") & name16 & utf16Of("\\AppData\0") & noise(bs, 18)))])
    writeContainer(dir / "nonascii-utf8.ct", @[("env",
      bytesOf("HOME=/home/\xD0\x97\xD0\xB0\xD1\x85\xD0\xB0\xD1\x80\xD0\xB8/x\0"))])
  cases.add Case(name: "nonascii-utf16", wantExit: 1, wantText: @["REFUSED home-dir"])
  cases.add Case(name: "nonascii-utf8", wantExit: 1, wantText: @["REFUSED home-dir"])

  # --- an e-mail address, ASCII and UTF-16LE (a git identity in the
  # environment); allowed by name, it is reported instead.
  writeContainer(dir / "email-ascii.ct", @[("env",
    bytesOf("GIT_AUTHOR_EMAIL=" & fakeUser & "@example-corp.com\0"))])
  cases.add Case(name: "email-ascii", wantExit: 1, wantText: @["REFUSED e-mail address"])
  writeContainer(dir / "email-utf16.ct", @[("env",
    utf16Of("GIT_AUTHOR_EMAIL=" & fakeUser & "@example-corp.com\0"))])
  cases.add Case(name: "email-utf16", wantExit: 1,
    wantText: @["REFUSED e-mail address", "utf16le"])
  writeContainer(dir / "email-allowed.ct", @[("cp0.mzd",
    bytesOf("i18n FDCC-set\0Somebody\0maintainer@example.org\0"))])
  cases.add Case(name: "email-allowed", wantExit: 0,
    args: @["--allow-email", "maintainer@example.org"], wantText: @["e-mail allowed"])

  # --- a container stored as a zstd frame, its member's blocks interleaved
  # with another member's and the path cut inside the separator at a block
  # boundary: only walking the frame's content as a container finds it.
  block:
    var c = createCtfs()
    var f = c.addFile("env").get()
    var g = c.addFile("pad").get()
    let path = utf16Of("C:\\Users\\" & fakeUser & "\\x\0")
    let body = noise(bs - utf16Of("C:\\Us").len, 19) & path & noise(2 * bs, 20)
    var at = 0
    while at < body.len:
      let n = min(bs, body.len - at)
      doAssert c.writeToFile(f, body.toOpenArray(at, at + n - 1)).isOk
      doAssert c.writeToFile(g, noise(bs, 21 + at)).isOk
      at += n
    let inner = c.toBytes()
    doAssert not inner.holds(utf16Of("\\Users\\")), "test setup: separator contiguous"
    writeContainer(dir / "container-in-frame.ct", @[("b/0001", zstdCompress(inner))])
  cases.add Case(name: "container-in-frame", wantExit: 1,
    wantText: @["REFUSED home-dir", "member b/0001 zstd@0 > member env"])

  # --- the scanned file's own path names a user: printed masked ------------
  createDir(dir / "Users" / fakeUser)
  copyFile(dir / "clean.ct", dir / "Users" / fakeUser / "masked-path.ct")
  cases.add Case(name: "masked-path", wantExit: 0,
    args: @["--allow-source", allowedSource], wantText: @["CLEAN"])

  # --- not a container: never reported clean -------------------------------
  writeFile(dir / "not-ctfs.ct", "plain text, not a recording")
  cases.add Case(name: "not-a-container", wantExit: 2, wantText: @["ERROR"])

  var failures = 0
  for tc in cases:
    let path =
      if tc.name == "masked-path": dir / "Users" / fakeUser / "masked-path.ct"
      else: dir / (if tc.name == "c-source-not-allowed": "c-source" else: tc.name) & ".ct"
    var cmd = quoteShell(scanner) & " --no-host-identity"
    for a in tc.args: cmd.add(" " & quoteShell(a))
    cmd.add(" " & quoteShell(path))
    let (output, code) = execCmdEx(cmd)
    var ok = code == tc.wantExit
    for t in tc.wantText:
      if t notin output: ok = false
    for t in tc.wantAbsent:
      if t in output: ok = false
    # The report must never print a refused name.
    if fakeUser in output or fakeHost in output: ok = false
    if ok:
      echo "ok   " & tc.name
    else:
      inc failures
      echo "FAIL " & tc.name & ": exit " & $code & " (want " & $tc.wantExit &
        "), want text " & $tc.wantText & ", absent " & $tc.wantAbsent
      echo output.indent(6)
  if failures == 0:
    echo "all " & $cases.len & " cases passed"
    0
  else:
    echo $failures & " of " & $cases.len & " cases failed"
    1

quit(main())
