## Test for ct-credential-scan: plant fake credentials in CTFS containers and
## require the scanner to refuse each one, and to pass a clean container that
## carries the harmless look-alikes a real recording holds.
##
## Usage:
##   test_ct_credential_scan <path-to-ct-credential-scan>
##
## No mocks: the containers are written with the real CTFS writer
## (codetracer_ctfs/container), and the scanner is the built binary, run as a
## process exactly as verify-recordings.sh runs it.
##
## The fake tokens are assembled at run time, so this source file carries no
## string a secret scanner would flag.
##
## Build against codetracer-trace-format-nim:
##   nim c -d:release -p:<codetracer-trace-format-nim>/src -o:test_ct_credential_scan test_ct_credential_scan.nim

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[os, osproc, strutils]
import results
import codetracer_ctfs/[container, types, zstd_bindings]

proc bytesOf(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

proc zstdCompress(data: seq[byte]): seq[byte] =
  let bound = ZSTD_compressBound(csize_t(data.len))
  result = newSeq[byte](int(bound))
  let n = ZSTD_compress(addr result[0], bound, unsafeAddr data[0],
                        csize_t(data.len), 3)
  doAssert ZSTD_isError(n) == 0, "zstd compress failed"
  result.setLen(int(n))

proc writeContainer(path: string, members: openArray[(string, seq[byte])]) =
  var c = createCtfs()
  for (name, body) in members:
    var f = c.addFile(name).get()
    doAssert c.writeToFile(f, body).isOk
  doAssert c.writeCtfsToFile(path).isOk

proc fakeGithubToken(kind: char): string =
  "gh" & $kind & "_" & repeat("Fake0Token1For2The3Gate", 2)[0 ..< 36]

proc fakeBasicHeader(): string =
  # base64("x-access-token:" & fake), as git's extraheader carries it.
  "AUTHORIZ" & "ATION: basic " & "eC1hY2Nlc3MtdG9r" & "ZW46Z2hzX0ZBS0VGQUtFRkFLRQ=="

proc noise(n: int, seed: int): seq[byte] =
  ## Deterministic incompressible-ish filler, so members span several blocks.
  result = newSeq[byte](n)
  var x = uint32(seed) * 2654435761'u32 + 12345'u32
  for i in 0 ..< n:
    x = x xor (x shl 13); x = x xor (x shr 17); x = x xor (x shl 5)
    result[i] = byte(x and 0x7f) or 0x80 # never printable ASCII

type Case = object
  name: string
  members: seq[(string, seq[byte])]
  wantExit: int
  wantPattern: string

proc main(): int =
  let args = commandLineParams()
  if args.len != 1:
    stderr.writeLine("usage: test_ct_credential_scan <ct-credential-scan>")
    return 2
  let scanner = absolutePath(args[0])
  let dir = getTempDir() / "ct-credential-scan-test-" & $getCurrentProcessId()
  createDir(dir)
  defer: removeDir(dir)

  let blockSize = int(DefaultBlockSize)
  var cases: seq[Case]

  # A clean recording-shaped container, carrying the look-alikes real
  # recordings hold: header NAMES without a credential (nginx's own strings),
  # a bare `x-access-token` word, a certificate (public), an `AKIA` inside a
  # longer identifier, and binary noise.
  cases.add Case(name: "clean", wantExit: 0, members: @[
    ("meta.json", bytesOf("""{"program":"nginx","args":["-c","nginx.conf"]}""")),
    ("guest.env", bytesOf("PATH=/usr/bin:/bin\0HOME=/nonexistent\0LANG=C\0")),
    ("debug.dat", bytesOf("Authorization\0Proxy-Authorization: \0x-access-token\0" &
        "-----BEGIN CERTIFICATE-----\0XAKIAABCDEFGHIJKLMNOP\0") & noise(3 * blockSize, 1)),
    ("cppages.nzd", zstdCompress(bytesOf("Authorization: basic\0") & noise(blockSize, 2))),
  ])

  # The leak that happened: git's extraheader in the recorded environment.
  cases.add Case(name: "env-auth-header", wantExit: 1,
    wantPattern: "HTTP authorization header (basic)", members: @[
      ("guest.env", bytesOf("PATH=/usr/bin\0GIT_CONFIG_VALUE_0=" & fakeBasicHeader() & "\0")),
    ])

  # The same, visible ONLY after decompression, across several blocks.
  let hidden = noise(2 * blockSize, 3) &
    bytesOf("GITHUB_TOKEN=" & fakeGithubToken('s') & "\0") & noise(blockSize, 4)
  cases.add Case(name: "compressed-member", wantExit: 1,
    wantPattern: "GitHub token (ghs_)", members: @[
      ("cppages.nzd", zstdCompress(hidden)),
    ])

  # A plaintext token that straddles a block boundary inside a member.
  let straddle = noise(blockSize - 10, 5) &
    bytesOf(fakeGithubToken('p')) & noise(blockSize, 6)
  cases.add Case(name: "straddles-block", wantExit: 1,
    wantPattern: "GitHub token (ghp_)", members: @[("bootelf.stk", straddle)])

  cases.add Case(name: "fine-grained-pat", wantExit: 1,
    wantPattern: "GitHub fine-grained token", members: @[
      ("guest.env", bytesOf("GH_TOKEN=github" & "_pat_" & repeat("Ab1_", 20) & "\0"))])

  cases.add Case(name: "aws-key", wantExit: 1, wantPattern: "AWS access key id",
    members: @[("guest.env", bytesOf("AWS_ACCESS_KEY_ID=" & "AK" & "IA" &
      "FAKEFAKEFAKE0123" & "\0"))])

  cases.add Case(name: "private-key", wantExit: 1, wantPattern: "PEM private key",
    members: @[("debug.dat", bytesOf("-----BEGIN " & "OPENSSH PRIVATE" &
      " KEY-----\nAAAAfake\n"))])

  cases.add Case(name: "x-access-token", wantExit: 1,
    wantPattern: "git token user (x-access-token:)", members: @[
      ("meta.json", bytesOf("https://x-access" & "-token:" & fakeGithubToken('s')[0 ..< 12] &
        "@github.com/org/repo"))])

  var failures = 0
  for tc in cases:
    let path = dir / (tc.name & ".ct")
    writeContainer(path, tc.members)
    if tc.name == "compressed-member":
      # The point of this case: the token is invisible in the raw bytes.
      let raw = readFile(path)
      doAssert "ghs_" notin raw, "test setup: the planted token is not hidden"
    let (output, code) = execCmdEx(quoteShell(scanner) & " " & quoteShell(path))
    var ok = code == tc.wantExit
    if ok and tc.wantPattern.len > 0 and tc.wantPattern notin output:
      ok = false
    # The report must never print the planted secret itself.
    if "Fake0Token1For2The3Gate" in output or "FAKEFAKEFAKE0123" in output:
      ok = false
    if ok:
      echo "ok   " & tc.name
    else:
      inc failures
      echo "FAIL " & tc.name & ": exit " & $code & " (want " & $tc.wantExit &
        "), want pattern '" & tc.wantPattern & "'"
      echo output.indent(6)
  if failures == 0:
    echo "all " & $cases.len & " cases passed"
    0
  else:
    echo $failures & " of " & $cases.len & " cases failed"
    1

quit(main())
