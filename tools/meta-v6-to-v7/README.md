# meta-v6-to-v7

Upgrades a container's `meta.dat` from schema version 6 to 7. Version 7
(codetracer-trace-format-spec `internal-files.md`, Version History) changes no
byte of the header or body. It allocates the `EventLogKind` values 14-23, and
it moves the version so that a version-6 reader refuses a version-7 trace when
it opens it. A version-6 recording carries only kinds 0-13, so the version-7
container of the same recording differs in one byte, the version. Every reader
refuses any version but 7.

The tool rewrites that byte where it sits in the file and writes nothing else.
It refuses a container whose `meta.dat` is not version 6, or whose image is not
the file's bytes, or whose `events.dat` carries a kind outside 0-13. Each
result is read back through the current readers. `meta.dat` must differ from
the input only in its version and the file in that one byte, and for a
split-stream trace the trace reader must read every event. A native (MCR)
bundle has no `events.dat` and is checked through `meta.dat` alone.

`test_meta_v6_to_v7.nim` writes a recording with the current writer, sets its
version byte back to 6, and requires the upgrade to return the original file
byte for byte. It also checks both refusals, and it pins the committed
fixtures this tool upgraded: each, with its version byte set back to 6, must
have the sha256 of its version-6 file at `76e71a4^`, and must upgrade back to
itself. The two `eme5` fixtures were regenerated since, and are pinned by
`../ctfs-v4-to-v5` as the whole chain from their version-4 originals.

```sh
TF=../../../codetracer-trace-format-nim/src   # the workspace sibling
nim c -r --path:$TF test_meta_v6_to_v7.nim
nim c -d:release --path:$TF meta_v6_to_v7.nim
./meta_v6_to_v7 in.ct out.ct                  # in == out upgrades in place
```

Use it for a committed fixture that cannot be re-recorded where it is used, for
example a recording made on another OS or by a recorder its consumer does not
build. A new recording is written as version 7 by its recorder.
