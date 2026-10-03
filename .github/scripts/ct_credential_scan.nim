## ct-credential-scan: refuse a .ct recording that carries a credential.
##
## A recording captures what the recorded process could see: its environment
## (the stack's envp, and the `guest.env` member), its argv, its memory. A
## recording made inside a CI job or a developer shell therefore carries that
## shell's tokens unless it was made under a scrubbed environment, and a
## committed fixture publishes them. This tool is the gate that catches it.
##
## Usage:
##   ct-credential-scan <file.ct> [<file.ct> ...]
##
## Exit 0: no file carries a credential pattern.  Exit 1: at least one does;
## each hit is printed with its file, where it was found and the pattern, with
## the matched value redacted to its first characters.  Exit 2: usage error or
## an unreadable file (an unreadable file is never reported as clean).
##
## WHERE IT LOOKS, so that neither compression nor block layout hides a match:
##   * the raw container bytes;
##   * every member of the root directory, reassembled from its blocks;
##   * every zstd frame found in the raw bytes or in any member, decompressed
##     (members such as the compressed snapshot pages and the chunked event
##     tables are zstd frames, and a whole-file-compressed container is one).
##
## PATTERNS (`findCredential` below):
##   GitHub tokens            ghp_ gho_ ghu_ ghs_ ghr_ + 36 alphanumerics,
##                            github_pat_ + 22 or more [A-Za-z0-9_]
##   HTTP authorization       `authorization:` (any case) + a basic/bearer/token
##                            scheme + a credential
##   git's token user         `x-access-token:` + a value, and its base64 form
##                            (`eC1hY2Nlc3MtdG9rZW46`, as inside a basic header)
##   AWS access keys          AKIA/ASIA + 16 [A-Z0-9], not inside a longer word
##   private keys             `-----BEGIN ` ... `PRIVATE KEY-----`
##
## Build against codetracer-trace-format-nim:
##   nim c -d:release -p:<codetracer-trace-format-nim>/src -o:ct-credential-scan ct_credential_scan.nim

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[os, strutils]
import results
import stew/endians2
import codetracer_ctfs/[container, base40, types, zstd_bindings]

type
  Hit = object
    where: string
    pattern: string
    preview: string

const
  ZstdMagic = [0x28'u8, 0xB5, 0x2F, 0xFD]
  MaxDecompressed = 1 shl 30 ## refuse to inflate a single frame past 1 GiB

proc isAlnum(b: byte): bool =
  char(b) in {'a' .. 'z', 'A' .. 'Z', '0' .. '9'}

proc lower(b: byte): char =
  toLowerAscii(char(b))

proc matchesAt(data: openArray[byte], pos: int, lit: string,
               caseless = false): bool =
  if pos < 0 or pos + lit.len > data.len:
    return false
  for i, c in lit:
    let b = data[pos + i]
    if caseless:
      if lower(b) != toLowerAscii(c): return false
    elif char(b) != c:
      return false
  true

proc runLen(data: openArray[byte], pos: int, ok: set[char]): int =
  var p = pos
  while p < data.len and char(data[p]) in ok:
    inc p
  p - pos

proc redact(data: openArray[byte], pos, len: int): string =
  ## The pattern's leading characters and the length; never the secret.
  let shown = min(len, 8)
  for i in 0 ..< shown:
    let c = char(data[pos + i])
    result.add(if c in {' ' .. '~'}: c else: '.')
  result.add("... (" & $len & " bytes)")

const
  Alnum = {'a' .. 'z', 'A' .. 'Z', '0' .. '9'}
  TokenChars = Alnum + {'_'}
  CredChars = Alnum + {'+', '/', '=', '.', '_', '-', '~'}
  UpperDigit = {'A' .. 'Z', '0' .. '9'}

proc findCredential(data: openArray[byte], where: string, hits: var seq[Hit]) =
  var i = 0
  while i < data.len:
    let c = char(data[i])
    var matched = 0
    var pattern = ""
    case c
    of 'g':
      if i + 4 <= data.len and matchesAt(data, i, "gh") and
          char(data[i + 2]) in {'p', 'o', 'u', 's', 'r'} and char(data[i + 3]) == '_':
        let n = runLen(data, i + 4, Alnum)
        if n >= 36:
          matched = 4 + n
          pattern = "GitHub token (gh" & char(data[i + 2]) & "_)"
      if matched == 0 and matchesAt(data, i, "github_pat_"):
        let n = runLen(data, i + 11, TokenChars)
        if n >= 22:
          matched = 11 + n
          pattern = "GitHub fine-grained token (github_pat_)"
    of 'a', 'A':
      if matchesAt(data, i, "authorization:", caseless = true):
        var p = i + 14
        p += runLen(data, p, {' ', '\t'})
        for scheme in ["basic", "bearer", "token"]:
          if matchesAt(data, p, scheme, caseless = true) and
              p + scheme.len < data.len and char(data[p + scheme.len]) == ' ':
            let q = p + scheme.len + 1
            let n = runLen(data, q, CredChars)
            if n >= 8:
              matched = q + n - i
              pattern = "HTTP authorization header (" & scheme & ")"
            break
      elif (matchesAt(data, i, "AKIA") or matchesAt(data, i, "ASIA")) and
          (i == 0 or not isAlnum(data[i - 1])):
        let n = runLen(data, i + 4, UpperDigit)
        if n == 16:
          matched = 20
          pattern = "AWS access key id"
    of 'x', 'X':
      if matchesAt(data, i, "x-access-token:", caseless = true):
        let n = runLen(data, i + 15, CredChars)
        if n >= 8:
          matched = 15 + n
          pattern = "git token user (x-access-token:)"
    of 'e':
      if matchesAt(data, i, "eC1hY2Nlc3MtdG9rZW4"):
        matched = 19 + runLen(data, i + 19, CredChars)
        pattern = "base64 of x-access-token: (a basic auth header)"
    of '-':
      if matchesAt(data, i, "-----BEGIN "):
        let lim = min(data.len, i + 11 + 48)
        var p = i + 11
        while p < lim and char(data[p]) in {'A' .. 'Z', ' '}:
          if matchesAt(data, p, "PRIVATE KEY-----"):
            matched = p + 16 - i
            pattern = "PEM private key"
            break
          inc p
    else:
      discard
    if matched > 0:
      hits.add(Hit(where: where, pattern: pattern,
                   preview: redact(data, i, matched)))
      i += matched
    else:
      inc i

proc decompressFrame(data: openArray[byte], pos: int,
                     consumed: var int): seq[byte] =
  ## Decompress the zstd frame starting at `pos`; empty when it is not a
  ## complete frame (a magic number inside other data is not one).
  consumed = 0
  let avail = csize_t(data.len - pos)
  let frameLen = ZSTD_findFrameCompressedSize(unsafeAddr data[pos], avail)
  if ZSTD_isError(frameLen) != 0 or frameLen == 0:
    return @[]
  var cap: int
  let declared = ZSTD_getFrameContentSize(unsafeAddr data[pos], frameLen)
  # 0ULL-1 is "unknown", 0ULL-2 is "error".
  if declared >= culonglong(high(uint64) - 1):
    cap = max(int(frameLen) * 8, 1 shl 16)
  else:
    if declared > culonglong(MaxDecompressed):
      return @[]
    cap = max(int(declared), 1)
  while cap <= MaxDecompressed:
    var output = newSeq[byte](cap)
    let n = ZSTD_decompress(addr output[0], csize_t(cap),
                            unsafeAddr data[pos], frameLen)
    if ZSTD_isError(n) == 0:
      output.setLen(int(n))
      consumed = int(frameLen)
      return output
    cap *= 4
  @[]

proc scanFrames(data: openArray[byte], where: string, hits: var seq[Hit],
                depth: int) =
  ## Every zstd frame in `data`, decompressed and scanned (and its own frames,
  ## to a small depth: a chunk can hold a compressed sub-stream).
  if depth > 2 or data.len < 4:
    return
  var i = 0
  while i + 4 <= data.len:
    if data[i] == ZstdMagic[0] and data[i + 1] == ZstdMagic[1] and
        data[i + 2] == ZstdMagic[2] and data[i + 3] == ZstdMagic[3]:
      var consumed = 0
      let inflated = decompressFrame(data, i, consumed)
      if consumed > 0:
        let label = where & " zstd@" & $i
        findCredential(inflated, label, hits)
        scanFrames(inflated, label, hits, depth + 1)
        i += consumed
        continue
    inc i

proc scanContainer(path: string, hits: var seq[Hit]): Result[int, string] =
  ## Returns the number of members read.
  let data = ?readCtfsFromFile(path)
  findCredential(data, "raw", hits)
  scanFrames(data, "raw", hits, 0)
  if data.len < HeaderSize + ExtHeaderSize or not hasCtfsMagic(data):
    return err("not a CTFS container")
  var arr: array[4, byte]
  for k in 0 ..< 4:
    arr[k] = data[HeaderSize + 4 + k]
  let maxEntries = int(fromBytesLE(uint32, arr))
  var members = 0
  for k in 0 ..< maxEntries:
    let off = HeaderSize + ExtHeaderSize + k * FileEntrySize
    if off + FileEntrySize > data.len:
      break
    let size = readU64LE(data, off)
    let mapBlock = readU64LE(data, off + 8)
    let encoded = readU64LE(data, off + 16)
    if size == 0 and mapBlock == 0 and encoded == 0:
      continue
    let name = base40Decode(encoded)
    let body = readMemberBytes(data, name, size, mapBlock, DefaultBlockSize)
    if body.isErr:
      return err("member " & name & ": " & body.error)
    inc members
    findCredential(body.get(), name, hits)
    scanFrames(body.get(), name, hits, 0)
  ok(members)

proc main(): int =
  let files = commandLineParams()
  if files.len == 0:
    stderr.writeLine("usage: ct-credential-scan <file.ct> [<file.ct> ...]")
    return 2
  var dirty = false
  var unreadable = false
  for f in files:
    var hits: seq[Hit]
    let res = scanContainer(f, hits)
    if res.isErr:
      echo "ERROR " & f & ": " & res.error
      unreadable = true
      continue
    if hits.len == 0:
      echo "CLEAN " & f & " (" & $res.get() & " members)"
    else:
      dirty = true
      echo "CREDENTIAL " & f & ": " & $hits.len & " match(es)"
      for h in hits:
        echo "    " & h.where & ": " & h.pattern & ": " & h.preview
  if unreadable: 2
  elif dirty: 1
  else: 0

quit(main())
