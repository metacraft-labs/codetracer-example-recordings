## ct-member-names: refuse a recording any of whose members is stored under a
## key that is not a storable CTFS name.
##
## CTFS names a member by one `u64`: base40 over at most 12 characters from
## `\0 0-9 a-z . / -` (codetracer-trace-format-spec `ctfs-container.md` §3).
## A writer handed a longer name, or one with a character outside that set,
## stores a key that decodes to some other string. Such a member can be found
## only by a reader that repeats the same lossy encoding of the same name;
## `ct-print`, codetracer's reader and every listing cannot. The decoded key
## then has a NUL inside it (a foreign character maps to the padding index)
## or does not re-encode to the stored key.
##
## Usage: ct-member-names <file.ct> [<file.ct> ...]
##   exit 0  every member of every file has a storable name
##   exit 1  some member does not (each is printed)
##   exit 2  a file could not be read as a CTFS container
##
## Lists each file's members, so a run's log shows the names a recording
## carries.

import std/[os, strutils]
import results
import stew/endians2
import codetracer_ctfs/[container, base40, types]

type Member* = object
  key*: uint64
  name*: string    ## the stored key, decoded
  size*: uint64

proc storableKey*(key: uint64, name: string): bool =
  ## Is `name` (the decoding of `key`) a name a writer could have been given,
  ## and does it encode back to exactly `key`?
  name.len > 0 and '\0' notin name and base40Encodable(name) and
    base40Encode(name) == key

proc listMembers*(data: openArray[byte]): Result[seq[Member], string] =
  if data.len < HeaderSize + ExtHeaderSize or not hasCtfsMagic(data):
    return err("not a CTFS container")
  var arr: array[4, byte]
  for k in 0 ..< 4:
    arr[k] = data[HeaderSize + 4 + k]
  let maxEntries = int(fromBytesLE(uint32, arr))
  var members: seq[Member]
  for k in 0 ..< maxEntries:
    let off = HeaderSize + ExtHeaderSize + k * FileEntrySize
    if off + FileEntrySize > data.len:
      break
    let size = readU64LE(data, off)
    let mapBlock = readU64LE(data, off + 8)
    let key = readU64LE(data, off + 16)
    if size == 0 and mapBlock == 0 and key == 0:
      continue
    members.add(Member(key: key, name: base40Decode(key), size: size))
  ok(members)

proc main(): int =
  let files = commandLineParams()
  if files.len == 0:
    stderr.writeLine("usage: ct-member-names <file.ct> [<file.ct> ...]")
    return 2
  var bad = false
  var unreadable = false
  for f in files:
    let data = readCtfsFromFile(f)
    if data.isErr:
      echo "ERROR " & f & ": " & data.error
      unreadable = true
      continue
    let members = listMembers(data.get())
    if members.isErr:
      echo "ERROR " & f & ": " & members.error
      unreadable = true
      continue
    var offenders: seq[string]
    var names: seq[string]
    for m in members.get():
      names.add(m.name.escape)
      if not storableKey(m.key, m.name):
        offenders.add(m.name.escape & " (key 0x" & m.key.toHex & ")")
    if offenders.len == 0:
      echo "OK   " & f & " (" & $names.len & " members: " & names.join(" ") & ")"
    else:
      bad = true
      echo "FAIL " & f & ": " & $offenders.len & " member(s) stored under a " &
           "key that is no storable CTFS name: " & offenders.join(", ")
  if unreadable: 2
  elif bad: 1
  else: 0

when isMainModule:
  quit(main())
