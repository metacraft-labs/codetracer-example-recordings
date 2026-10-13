## ct-leak-scan: refuse a .ct recording that carries personal data or source
## code.
##
## A recording captures what the recorded process saw: its environment, the
## paths of the files it mapped, the per-user registry values its DLLs read,
## its memory, and (for a portable export) the files the export embeds. A
## recording made under a developer's account therefore names that developer,
## and an export can embed source files. This tool is the gate for both. It is
## the companion of ct-credential-scan (tokens and keys), not a replacement.
##
## Usage:
##   ct-leak-scan [options] <file.ct> [<file.ct> ...]
##
## Options (each may be repeated):
##   --allow-user NAME    a home-directory name that may be published, besides
##                        the built-in ones: Public, Default, Default User,
##                        All Users, runner (GARM's ephemeral Windows runners)
##                        and runneradmin (GitHub-hosted Windows runners)
##   --forbid VALUE       a literal that must not appear
##   --report VALUE       a literal that may appear; its count is reported
##   --allow-source FILE  a source file whose text may appear (a fixture
##                        program's own public source)
##   --dump DIR           also write every decoded buffer to DIR
##   --no-host-identity   do not derive rules from the scanning account
##
## Exit 0: no file carries a refused finding.  Exit 1: at least one does.
## Exit 2: usage error, or a file this tool cannot read (an unreadable file is
## never reported as clean).
##
## WHERE IT LOOKS, so that neither compression nor block layout hides a match.
## Every "buffer" below is scanned the same way:
##   * the raw container bytes;
##   * every member, read through the trace-format reader
##     (`codetracer_ctfs/compact`: `reconstructImage`, then
##     `collectFullProfileMembers` or `decodeCompactContainer`), so a member's
##     blocks are reassembled in order wherever the container put them. A raw
##     byte scan does not see a zstd frame whose blocks are not contiguous;
##     this is the gap the recorder's corpus_leak_scan has;
##   * every member that is itself a CTFS container, recursively;
##   * every zstd frame found in any of the above, decompressed, and the frames
##     inside it, to a depth of 3.
## Matching is case-insensitive, in ASCII and in UTF-16LE (the Windows
## environment block, registry values and NT paths are UTF-16LE).
##
## WHAT IS REFUSED (exit 1):
##   home-dir      `\Users\<name>`, `/Users/<name>` or `/home/<name>` whose
##                 <name> is not an allowed one or a placeholder (`%USERNAME%`,
##                 `<user>`, `$USER`, `*`). Catches `C:\Users\x`, `C:/Users/x`,
##                 `\Device\HarddiskVolume5\Users\x`, `\??\C:\Users\x`.
##   forbidden     a `--forbid` literal, or the scanning account's identity
##                 (below).
##   source-text   a line that only source code has: `#include <`, `#define `,
##                 `#pragma `, `import std/`, `proc ...(`, `{.push`, `{.pragma`,
##                 `use std::`, ... (`SourceMarkers`), unless the text around it
##                 occurs in an `--allow-source` file.
##   pdb-sources   an embedded PDB (MSF 7.00) that carries injected source
##                 files (`/src/headerblock`).
## WHAT IS REPORTED (never refused, printed so a reviewer sees it):
##   allowed home directories and placeholders; `--report` literals; CodeView
##   (RSDS) PDB paths; embedded PDBs; every distinct source-file path
##   (`*.nim`, `*.c`, `*.h`, `*.cpp`, `*.rs`, `*.asm`, ...); text of an
##   `--allow-source` file; e-mail addresses; and, per member, the bytes the
##   scan could not decode (high-entropy 4 KiB windows outside every zstd frame:
##   a codec this tool does not know would hide text there).
##
## THE SCANNING ACCOUNT. Unless `--no-host-identity`: when USERPROFILE is a
## personal profile (`<drive>:\Users\<name>`, <name> not allowed), USERNAME,
## COMPUTERNAME and USERPROFILE are forbidden; otherwise (a service account
## such as the self-hosted runners' NETWORK SERVICE, whose profile is
## `C:\Windows\ServiceProfiles\NetworkService`, or an allowed CI account) they
## are reported. So a developer who scans a local recording is refused on
## their own name, and a CI job sees how often the runner's identity appears.
##
## THE REPORT NEVER PRINTS A REFUSED NAME. A refused home-directory name or
## forbidden literal is shown as its first character and its length, so the
## log of a public CI job does not republish what it caught.
##
## Build against codetracer-trace-format-nim:
##   nim c -d:release -p:<codetracer-trace-format-nim>/src -o:ct-leak-scan ct_leak_scan.nim

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import std/[os, strutils, tables, algorithm, math, sets]
import results
import codetracer_ctfs/[container, compact, types, zstd_bindings]

const
  ZstdMagic = [0x28'u8, 0xB5, 0x2F, 0xFD]
  MaxDecompressed = 1 shl 30 ## refuse to inflate a single frame past 1 GiB
  MaxFrameDepth = 3
  MaxContainerDepth = 4
  BuiltinAllowedUsers = ["public", "default", "default user", "all users",
                         "runner", "runneradmin"]
  MsfMagic = "Microsoft C/C++ MSF 7.00\r\n\x1aDS"
  SourceExts = ["nim", "nims", "nimble", "c", "h", "cc", "cpp", "cxx", "hpp",
                "rs", "asm", "s", "zig", "go", "py", "ts", "js"]

  ## Text only source code has. `lineStart` markers must begin a line (or
  ## follow a NUL), because a compiled binary never holds them that way.
  SourceMarkers: array[19, tuple[text: string, lineStart: bool, lang: string]] = [
    ("#include <", true, "C"), ("#include \"", true, "C"),
    ("#define ", true, "C"), ("#pragma ", true, "C"), ("#ifndef ", true, "C"),
    ("int main(", true, "C"), ("static void ", true, "C"),
    ("import std/", true, "Nim"), ("from std/", true, "Nim"),
    ("proc ", true, "Nim"), ("func ", true, "Nim"),
    ("when defined(", true, "Nim"), ("{.push ", false, "Nim"),
    ("{.pragma", false, "Nim"), ("{.importc", false, "Nim"),
    ("use std::", true, "Rust"), ("#[derive(", true, "Rust"),
    ("fn main(", true, "Rust"), (" PROC FRAME", false, "MASM")]

type
  Severity = enum sevReport, sevRefuse

  Finding = object
    severity: Severity
    rule: string
    shown: string       ## what the report prints (redacted when refused)
    count: int
    places: seq[string] ## the first few locations

  Rules = object
    allowedUsers: HashSet[string]
    forbid: seq[tuple[label, value: string]]
    report: seq[tuple[label, value: string]]
    allowedSources: seq[tuple[path, text: string]]
    dumpDir: string

  Scan = object
    file: string
    findings: OrderedTable[string, Finding]
    sourcePaths: CountTable[string]
    opaque: seq[string]
    buffers: int
    decodedBytes: int64
    dumpIndex: int

proc toStr(data: openArray[byte]): string =
  result = newString(data.len)
  if data.len > 0:
    copyMem(addr result[0], unsafeAddr data[0], data.len)

proc foldAscii(data: openArray[byte]): string =
  ## Lower-case A-Z, every other byte unchanged (so UTF-16LE ASCII folds too).
  result = newString(data.len)
  for i, b in data:
    result[i] = if b >= byte('A') and b <= byte('Z'): char(b + 32) else: char(b)

proc utf16(s: string): string =
  for c in s:
    result.add(c)
    result.add('\0')

proc redactName(name: string): string =
  if name.len == 0: return "<empty>"
  $name[0] & repeat('*', max(name.len - 1, 0)) & " (" & $name.len & " chars)"

proc printable(s: string): string =
  for c in s:
    result.add(if c in {' ' .. '~'}: c else: '.')

var maskRules: Rules
  ## The rules every printed string is masked with (set once, in `main`).

proc isPlaceholder(name: string): bool

proc maskText(s: string): string =
  ## `s` with every refused home-directory name and every forbidden literal
  ## replaced by its redaction, wherever it occurs, so a context window or a
  ## path never prints what a rule refuses.
  result = s
  var lowered = result.toLowerAscii
  for sep in ["\\users\\", "/users/", "/home/", "-users-"]:
    var p = lowered.find(sep)
    while p >= 0:
      let at = p + sep.len
      var e = at
      # `-Users-<name>-` is a path flattened into a file name (macOS
      # temporary directories); elsewhere a name may hold `-` and spaces.
      let stops = {'\\', '/', '"', '\'', ';', '|', '<', '>', ':', '\0', '\t'} +
        (if sep == "-users-": {'-', ' '} else: {})
      while e < result.len and result[e] notin stops:
        inc e
      let name = result[at ..< e]
      if name.len > 0 and not isPlaceholder(name) and
          name.toLowerAscii notin maskRules.allowedUsers:
        let red = redactName(name)
        result = result[0 ..< at] & red & result[e .. ^1]
        lowered = result.toLowerAscii
        p = lowered.find(sep, at + red.len)
      else:
        p = lowered.find(sep, at)
  for (label, value) in maskRules.forbid:
    let v = value.toLowerAscii
    var p = lowered.find(v)
    while p >= 0:
      let red = redactName(result[p ..< p + value.len])
      result = result[0 ..< p] & red & result[p + value.len .. ^1]
      lowered = result.toLowerAscii
      p = lowered.find(v, p + red.len)

proc add(scan: var Scan, severity: Severity, rule, shown, where: string) =
  let shown = maskText(shown)
  let where = maskText(where)
  let key = $severity & "|" & rule & "|" & shown
  if key notin scan.findings:
    scan.findings[key] = Finding(severity: severity, rule: rule, shown: shown)
  scan.findings[key].count += 1
  if scan.findings[key].places.len < 3 and
      where notin scan.findings[key].places:
    scan.findings[key].places.add(where)

# ---------------------------------------------------------------------------
# Reading text out of a buffer, in either encoding
# ---------------------------------------------------------------------------

proc unitAt(data: openArray[byte], pos, width: int): int =
  ## The code unit at `pos` (one byte, or a UTF-16LE unit), or -1 past the end.
  if pos < 0 or pos + width > data.len: return -1
  if width == 1: int(data[pos])
  else: int(data[pos]) or (int(data[pos + 1]) shl 8)

proc readSegment(data: openArray[byte], pos, width: int,
                 stop: set[char], maxLen = 64): string =
  ## Code units from `pos` up to a stop character, a control character or
  ## `maxLen`; non-ASCII UTF-16 units are kept as `?`.
  var p = pos
  while result.len < maxLen:
    let u = unitAt(data, p, width)
    if u < 0x20: break
    if u < 0x80:
      if char(u) in stop: break
      result.add(char(u))
    elif width == 2:
      result.add('?')
    else:
      break
    p += width

proc contextAround(data: openArray[byte], pos, width, matchLen: int,
                   redactFrom, redactLen: int): string =
  ## Up to 40 printable units before and after the match, with the redacted
  ## span (in units, relative to `pos`) replaced by its redaction.
  var before = ""
  var p = pos - width
  while p >= 0 and before.len < 40:
    let u = unitAt(data, p, width)
    if u < 0x20 or u >= 0x7f: break
    before.insert($char(u), 0)
    p -= width
  var mid = ""
  for k in 0 ..< matchLen:
    let u = unitAt(data, pos + k * width, width)
    mid.add(if u >= 0x20 and u < 0x7f: char(u) else: '.')
  var after = ""
  p = pos + matchLen * width
  while after.len < 40:
    let u = unitAt(data, p, width)
    if u < 0x20 or u >= 0x7f: break
    after.add(char(u))
    p += width
  if redactLen > 0:
    let all = before & mid & after
    let s = before.len + redactFrom
    if s >= 0 and s + redactLen <= all.len:
      return printable(all[0 ..< s]) & redactName(all[s ..< s + redactLen]) &
        printable(all[s + redactLen .. ^1])
  printable(before & mid & after)

iterator findAll(hay, needle: string): int =
  if needle.len > 0:
    var p = hay.find(needle)
    while p >= 0:
      yield p
      p = hay.find(needle, p + 1)

proc isPlaceholder(name: string): bool =
  name.len == 0 or name[0] in {'%', '<', '$', '{', '*', '?'} or
    name.contains('*') or name.contains('%')

# ---------------------------------------------------------------------------
# The rules, applied to one decoded buffer
# ---------------------------------------------------------------------------

proc scanHomeDirs(scan: var Scan, rules: Rules, data: openArray[byte],
                  folded, where: string) =
  for width in [1, 2]:
    for sep in ["\\users\\", "/users/", "/home/"]:
      let needle = if width == 1: sep else: utf16(sep)
      for p in findAll(folded, needle):
        let at = p + needle.len
        let name = readSegment(data, at, width,
          {'\\', '/', '"', '\'', ';', '|', '<', '>', ':', '\0', '\t'})
        let enc = if width == 1: "ascii" else: "utf16le"
        let prefix = sep.replace("users", "Users").replace("home", "home")
        if name.len == 0:
          continue
        if isPlaceholder(name):
          scan.add(sevReport, "home-dir placeholder", prefix & name,
                   where & " " & enc)
        elif name.toLowerAscii in rules.allowedUsers:
          scan.add(sevReport, "home-dir allowed", prefix & name,
                   where & " " & enc)
        else:
          let ctx = contextAround(data, p, width, sep.len, sep.len, name.len)
          scan.add(sevRefuse, "home-dir", prefix & redactName(name),
                   where & " " & enc & ": " & ctx)

proc scanLiterals(scan: var Scan, rules: Rules, data: openArray[byte],
                  folded, where: string) =
  for width in [1, 2]:
    let enc = if width == 1: "ascii" else: "utf16le"
    for (label, value) in rules.forbid:
      let v = value.toLowerAscii
      let needle = if width == 1: v else: utf16(v)
      for p in findAll(folded, needle):
        let ctx = contextAround(data, p, width, value.len, 0, value.len)
        scan.add(sevRefuse, "forbidden " & label, redactName(value),
                 where & " " & enc & ": " & ctx)
    for (label, value) in rules.report:
      let v = value.toLowerAscii
      let needle = if width == 1: v else: utf16(v)
      for p in findAll(folded, needle):
        scan.add(sevReport, "present " & label, value, where & " " & enc)

proc attributedToAllowedSource(rules: Rules, data: openArray[byte],
                               pos: int): string =
  ## The allowed source file holding the line at `pos`, or "".
  var e = pos
  while e < data.len and e - pos < 96 and data[e] notin {byte('\n'), byte('\r'), 0'u8}:
    inc e
  let line = toStr(data.toOpenArray(pos, e - 1)).strip
  if line.len < 8: return ""
  for (path, text) in rules.allowedSources:
    if line in text: return path
  ""

proc scanSourceText(scan: var Scan, rules: Rules, data: openArray[byte],
                    where: string) =
  let raw = toStr(data)
  for m in SourceMarkers:
    for p in findAll(raw, m.text):
      if m.lineStart and p > 0 and raw[p - 1] notin {'\n', '\r', '\0'}:
        continue
      # A Nim `proc`/`func` line also needs a name and a parameter list.
      if m.text in ["proc ", "func "]:
        var q = p + m.text.len
        var ident = 0
        while q < raw.len and raw[q] in IdentChars:
          inc q; inc ident
        if q < raw.len and raw[q] == '*': inc q
        if ident == 0 or q >= raw.len or raw[q] notin {'(', '['}:
          continue
      var e = p
      while e < raw.len and e - p < 72 and raw[e] notin {'\n', '\r', '\0'}:
        inc e
      let line = printable(raw[p ..< e])
      let owner = attributedToAllowedSource(rules, data, p)
      if owner.len > 0:
        scan.add(sevReport, "allowed source text (" & owner.extractFilename & ")",
                 m.lang & " " & m.text.strip, where)
      else:
        scan.add(sevRefuse, "source-text " & m.lang, line, where & " @" & $p)

proc scanPdb(scan: var Scan, data: openArray[byte], folded: string,
             where: string) =
  let raw = toStr(data)
  for p in findAll(raw, "RSDS"):
    let pathAt = p + 4 + 16 + 4
    if pathAt >= data.len: continue
    let path = readSegment(data, pathAt, 1, {'\0'}, 260)
    if path.len >= 5 and path.toLowerAscii.endsWith(".pdb"):
      scan.add(sevReport, "CodeView PDB path", printable(path), where)
  for p in findAll(raw, MsfMagic):
    scan.add(sevReport, "embedded PDB (MSF 7.00)", "at " & $p, where)
    if raw.find("/src/headerblock", p) >= 0:
      scan.add(sevRefuse, "pdb-sources",
               "embedded PDB carries injected source files (/src/headerblock)",
               where)

proc scanSourcePaths(scan: var Scan, data: openArray[byte], folded: string) =
  const PathChars = {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '-', '.', '/',
                     '\\', ':', '~', '+', '@'}
  for width in [1, 2]:
    for ext in SourceExts:
      let suffix = "." & ext
      let needle = if width == 1: suffix else: utf16(suffix)
      for p in findAll(folded, needle):
        let after = unitAt(data, p + needle.len, width)
        if after >= 0 and after < 0x80 and char(after) in IdentChars + {'.'}:
          continue
        var s = p
        var n = 0
        while n < 260:
          let u = unitAt(data, s - width, width)
          if u < 0 or u >= 0x80 or char(u) notin PathChars: break
          s -= width
          inc n
        if n < 3: continue
        var path = ""
        var q = s
        while q < p + needle.len:
          path.add(char(unitAt(data, q, width)))
          q += width
        let stem = path[0 ..< path.len - suffix.len]
        var letters = 0
        for c in stem:
          if c in Letters: inc letters
        # Binary noise makes short runs of path characters; a path a person
        # would recognise has a letter-bearing name and a lower-case
        # extension (`Zrj.C`, `HOl.H` are compressed bytes, not files).
        if letters < 4 or stem.endsWith(".") or path[0] == '.' or
            path[^suffix.len .. ^1] != suffix:
          continue
        scan.sourcePaths.inc(path)

proc scanEmails(scan: var Scan, data: openArray[byte], where: string) =
  let raw = toStr(data)
  for p in findAll(raw, "@"):
    var s = p
    while s > 0 and raw[s - 1] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '_', '-', '+'}:
      dec s
    var e = p + 1
    while e < raw.len and raw[e] in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '-'}:
      inc e
    if p - s < 2 or e - p < 5: continue
    let domain = raw[p + 1 ..< e].strip(chars = {'.'})
    let dot = domain.rfind('.')
    if dot <= 0 or domain.len - dot - 1 < 2: continue
    var alphaTld = true
    for c in domain[dot + 1 .. ^1]:
      if c notin Letters: alphaTld = false
    if not alphaTld: continue
    scan.add(sevReport, "e-mail address", raw[s ..< e], where)

proc entropy(data: openArray[byte], a, b: int): float =
  var counts: array[256, int]
  for i in a ..< b: inc counts[int(data[i])]
  let n = float(b - a)
  for c in counts:
    if c > 0:
      let q = float(c) / n
      result -= q * log2(q)

# ---------------------------------------------------------------------------
# Walking the container
# ---------------------------------------------------------------------------

proc decompressFrame(data: openArray[byte], pos: int,
                     consumed: var int): seq[byte] =
  ## The zstd frame starting at `pos`, decompressed; empty when it is not a
  ## complete frame (a magic number inside other data is not one).
  consumed = 0
  let avail = csize_t(data.len - pos)
  let frameLen = ZSTD_findFrameCompressedSize(unsafeAddr data[pos], avail)
  if ZSTD_isError(frameLen) != 0 or frameLen == 0:
    return @[]
  var cap: int
  let declared = ZSTD_getFrameContentSize(unsafeAddr data[pos], frameLen)
  if declared >= culonglong(high(uint64) - 1): # unknown or error
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

proc scanContainer(scan: var Scan, rules: Rules, data: openArray[byte],
                   where: string, depth: int): Result[void, string]

proc dump(scan: var Scan, rules: Rules, data: openArray[byte], where: string) =
  if rules.dumpDir.len == 0: return
  var name = ""
  for c in where:
    name.add(if c in {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '-'}: c else: '_')
  inc scan.dumpIndex
  let path = rules.dumpDir / (scan.file.extractFilename & "." &
    align($scan.dumpIndex, 4, '0') & "." & name[0 ..< min(name.len, 80)] & ".bin")
  try: writeFile(path, toStr(data))
  except IOError, OSError: stderr.writeLine("warning: cannot write " & path)

proc scanBuffer(scan: var Scan, rules: Rules, data: openArray[byte],
                where: string, frameDepth: int, containerDepth: int,
                isMember: bool): Result[void, string] =
  inc scan.buffers
  scan.decodedBytes += int64(data.len)
  dump(scan, rules, data, where)
  let folded = foldAscii(data)
  scanHomeDirs(scan, rules, data, folded, where)
  scanLiterals(scan, rules, data, folded, where)
  scanSourceText(scan, rules, data, where)
  scanPdb(scan, data, folded, where)
  scanSourcePaths(scan, data, folded)
  scanEmails(scan, data, where)

  # Every zstd frame inside, decompressed and scanned in turn; the spans they
  # cover are what the undecoded-bytes report leaves out.
  var covered: seq[(int, int)]
  if frameDepth < MaxFrameDepth and data.len >= 4:
    var i = 0
    while i + 4 <= data.len:
      if data[i] == ZstdMagic[0] and data[i + 1] == ZstdMagic[1] and
          data[i + 2] == ZstdMagic[2] and data[i + 3] == ZstdMagic[3]:
        var consumed = 0
        let inflated = decompressFrame(data, i, consumed)
        if consumed > 0:
          covered.add((i, i + consumed))
          ? scanBuffer(scan, rules, inflated, where & " zstd@" & $i,
                       frameDepth + 1, containerDepth, false)
          i += consumed
          continue
      inc i

  if not isMember:
    return ok()

  # A member that is itself a container (a portable export embeds files).
  if containerDepth < MaxContainerDepth and hasCtfsMagic(data):
    return scanContainer(scan, rules, data, where & " >", containerDepth + 1)

  # Bytes nothing above decoded: high-entropy stretches outside every frame.
  # `covered` is in ascending order and its spans do not overlap.
  var opaqueBytes = 0
  var gaps: seq[(int, int)]
  var at = 0
  for (a, b) in covered:
    if a > at: gaps.add((at, a))
    at = max(at, b)
  if at < data.len: gaps.add((at, data.len))
  for (a, b) in gaps:
    var w = a
    while b - w >= 1024:
      let e = min(w + 4096, b)
      # Random bytes measure ~7.95 bits over 4 KiB and ~7.8 over 1 KiB.
      let threshold = if e - w >= 4096: 7.6 else: 7.2
      if entropy(data, w, e) > threshold:
        opaqueBytes += e - w
      w = e
  if opaqueBytes > 0:
    scan.opaque.add(where & ": " & $opaqueBytes & " of " & $data.len &
      " bytes in high-entropy stretches outside any zstd frame")
  ok()

proc scanContainer(scan: var Scan, rules: Rules, data: openArray[byte],
                   where: string, depth: int): Result[void, string] =
  ## Every member, read through the trace-format reader, then the container
  ## bytes no member owns: header, directory, mapping blocks and free space,
  ## where a stale block of an earlier write would sit.
  let prefix = if where.len > 0: where & " " else: ""
  let image = ? reconstructImage(data)
  let compactBody = isCompactContainer(image)
  let members =
    if compactBody: ? decodeCompactContainer(image, true)
    else: ? collectFullProfileMembers(image)
  for m in members:
    ? scanBuffer(scan, rules, m.payload, prefix & "member " & m.name, 0,
                 depth, true)
  var rest = @image
  var located = true
  if image.len >= 16:
    let blockSize = if compactBody: DefaultBlockSize else: readU32LE(image, 8)
    let declared = readU32LE(image, 12)
    let maxEntries = if declared > 0'u32: declared else: DefaultMaxRootEntries
    for m in members:
      let runs = locateMember(image, m.name, blockSize, maxEntries)
      if runs.isErr:
        located = false
        break
      for r in runs.get():
        if r.len > 0:
          zeroMem(addr rest[r.at], r.len)
  if located:
    scanBuffer(scan, rules, rest, prefix & "container bytes outside every member",
               0, depth, false)
  else:
    scanBuffer(scan, rules, image, prefix & "container bytes (all; member layout not located)",
               0, depth, false)

proc scanFile(scan: var Scan, rules: Rules): Result[void, string] =
  let data = ? readCtfsFromFile(scan.file)
  if not hasCtfsMagic(data):
    return err("not a CTFS container")
  scanContainer(scan, rules, data, "", 1).mapErr(
    proc(e: string): string = "reading the container: " & e)

# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

proc hostIdentity(rules: var Rules) =
  let profile = getEnv("USERPROFILE")
  let user = getEnv("USERNAME", getEnv("USER"))
  let host = getEnv("COMPUTERNAME")
  let lowered = profile.toLowerAscii.replace('/', '\\')
  let k = lowered.find("\\users\\")
  var personal = false
  if k >= 0:
    let name = lowered[k + 7 .. ^1].split('\\')[0]
    personal = name.len > 0 and name notin rules.allowedUsers
  let temp = getEnv("TEMP", getEnv("TMPDIR"))
  if personal:
    if user.len > 0: rules.forbid.add(("scanning account's USERNAME", user))
    if host.len > 0: rules.forbid.add(("scanning host's COMPUTERNAME", host))
    rules.forbid.add(("scanning account's USERPROFILE", profile))
  else:
    if user.len > 0: rules.report.add(("scanning account's USERNAME", user))
    if host.len > 0: rules.report.add(("scanning host's COMPUTERNAME", host))
    if profile.len > 0: rules.report.add(("scanning account's USERPROFILE", profile))
    if temp.len > 0: rules.report.add(("scanning account's TEMP", temp))

proc main(): int =
  var rules = Rules(allowedUsers: toHashSet(BuiltinAllowedUsers))
  var files: seq[string]
  var hostRules = true
  let args = commandLineParams()
  var i = 0
  proc need(i: int): string =
    if i >= args.len:
      stderr.writeLine("error: " & args[i - 1] & " needs a value")
      quit(2)
    args[i]
  while i < args.len:
    case args[i]
    of "--allow-user":
      inc i; rules.allowedUsers.incl(need(i).toLowerAscii)
    of "--forbid":
      inc i; rules.forbid.add(("--forbid", need(i)))
    of "--report":
      inc i; rules.report.add(("--report", need(i)))
    of "--allow-source":
      inc i
      let path = need(i)
      try: rules.allowedSources.add((path, readFile(path)))
      except IOError, OSError:
        stderr.writeLine("error: cannot read --allow-source " & path)
        return 2
    of "--dump":
      inc i; rules.dumpDir = need(i)
      createDir(rules.dumpDir)
    of "--no-host-identity":
      hostRules = false
    of "-h", "--help":
      echo "usage: ct-leak-scan [--allow-user NAME] [--forbid VALUE] " &
        "[--report VALUE] [--allow-source FILE] [--dump DIR] " &
        "[--no-host-identity] <file.ct> [<file.ct> ...]"
      return 0
    else:
      if args[i].startsWith("--"):
        stderr.writeLine("error: unknown option " & args[i])
        return 2
      files.add(args[i])
    inc i
  if files.len == 0:
    stderr.writeLine("usage: ct-leak-scan [options] <file.ct> [<file.ct> ...]")
    return 2
  if hostRules:
    hostIdentity(rules)
  maskRules = rules
  for (label, value) in rules.forbid:
    if value.len < 3:
      stderr.writeLine("error: " & label & " value is shorter than 3 characters")
      return 2

  var refused = false
  var unreadable = false
  for f in files:
    var scan = Scan(file: f)
    let res = scanFile(scan, rules)
    if res.isErr:
      echo "ERROR " & f & ": " & res.error
      unreadable = true
      continue
    var refusedHere = 0
    for k, fd in scan.findings:
      if fd.severity == sevRefuse: inc refusedHere
    echo (if refusedHere > 0: "LEAK  " else: "CLEAN ") & f & " (" &
      $scan.buffers & " buffers, " & $scan.decodedBytes & " bytes decoded)"
    for sev in [sevRefuse, sevReport]:
      for k, fd in scan.findings:
        if fd.severity != sev: continue
        echo "    " & (if sev == sevRefuse: "REFUSED " else: "report  ") &
          fd.rule & ": " & fd.shown & "  x" & $fd.count
        for p in fd.places:
          echo "        at " & p
    if scan.sourcePaths.len > 0:
      scan.sourcePaths.sort()
      echo "    report  source-file paths: " & $scan.sourcePaths.len & " distinct"
      for path, n in scan.sourcePaths:
        let shown = maskText(path)
        echo "        " & printable(shown) & "  x" & $n
    for o in scan.opaque:
      echo "    report  undecoded: " & o
    if refusedHere > 0: refused = true
  if unreadable: 2
  elif refused: 1
  else: 0

quit(main())
