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
- `test_ctfs_v4_to_v5.nim` converts `testdata/null_main.v4.ct`, the
  pre-conversion `eme5/null_main.ct`. It checks each member's length and
  sha256 against a table computed by the `86ca226^` reader. It runs the same
  check on the committed, converted fixture.

```sh
TF=../../../codetracer-trace-format-nim/src   # the workspace sibling
nim c -r --path:$TF test_ctfs_v4_to_v5.nim
nim c -d:release --path:$TF ctfs_v4_to_v5.nim
./ctfs_v4_to_v5 in.ct out.ct                  # in == out converts in place
```

A new recording is written as version 5 by the recorder. Do not use this
tool for one.
