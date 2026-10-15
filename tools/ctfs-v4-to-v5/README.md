# ctfs-v4-to-v5

A one-off converter from CTFS container version 4 to version 5 that leaves
every member byte-identical. It exists for the five
`mcr/macos-arm64/emulator/` recordings, which were written as version 4 and
cannot be re-recorded without a SIP-disabled Mac. Since
codetracer-trace-format-nim `86ca226` (2026-10-01), every reader refuses any
container version but 5.

- `ctfs_v4_to_v5.nim` contains the converter. The version-4 member walk is
  vendored from codetracer-trace-format-nim at `86ca226^`, and members are
  written with the current writer. Each converted container is read back
  through the current reader, and the converter refuses it unless every
  member matches.
- `test_ctfs_v4_to_v5.nim` converts `testdata/null_main.v4.ct` and
  `testdata/one_puts.v4.ct`, the pre-conversion `eme5/null_main.ct` and
  `eme5/one_puts.ct` (as committed at `50d4a69`). For `null_main` it checks
  each member's length and sha256 against a table computed by the `86ca226^`
  reader. It requires each committed fixture to be the whole chain below of
  its original.
- `member_renames.nim` lists the members the macOS recorder renamed after
  these recordings were made (`t_start.*` in `e16f18457`, `event_log.dat` /
  `.idx` in `40aa129e`). The old names are not storable CTFS names. The
  version-4 to version-5 step writes such a member under its new name, because
  the current writer refuses the old key.

```sh
TF=../../../codetracer-trace-format-nim/src   # the workspace sibling
nim c -r --path:$TF test_ctfs_v4_to_v5.nim
nim c -d:release --path:$TF ctfs_v4_to_v5.nim
./ctfs_v4_to_v5 in.ct out.ct                  # in == out converts in place
```

`meta_v3_to_v6.nim` is the second step for the same recordings. It upgrades a
container's `meta.dat` from schema 3 to 6 and moves the path list into
`paths.dat`. It writes `paths.dat` as one of the four interning tables, which a
trace carries all four or none, so `funcs`, `types` and `varnames` are written
empty, as the native recorder writes them. It applies the member renames to a
version-5 container that still has the old keys. Every
derivation is described in its header, and the result is verified through the
current readers. The test runs both steps over the kept original and requires
the committed fixture to be exactly the result.

```sh
nim c -d:release --path:$TF meta_v3_to_v6.nim
./meta_v3_to_v6 in.ct out.ct
```

Since codetracer-trace-format-nim `20ba929` the current readers accept only
`meta.dat` version 7, so the chain has a third step, `../meta-v6-to-v7`. The
`meta_v3_to_v6` result is verified as the version-7 container that step makes
of it, and the test requires the committed fixture to be the result of all
three steps.

A new recording is written by the recorder in the current format. Do not use
these tools for one.
