## The member renames the macOS recorder made after these recordings were
## written, shared by both conversion steps (`ctfs_v4_to_v5.nim` writes a
## version-4 member stored under an old key under its new name, because the
## current writer refuses a name outside the CTFS alphabet; `meta_v3_to_v6.nim`
## renames one in a version-5 container).  See `meta_v3_to_v6.nim`'s
## "MEMBER NAMES" note for where each rename comes from.

when defined(nimPreviewSlimSystem):
  import std/[syncio, assertions]

import codetracer_ctfs/base40

const MemberRenames* = [
  # recorder e16f18457: old full name -> storable name
  ("t_start.mem", "tstart.mem"), ("t_start.regs", "tstart.regs"),
  ("t_start.sysregs", "tstart.sregs"), ("t_start.stack", "tstart.stk"),
  ("t_start.cdata", "tstart.cdata"), ("t_start.clos", "tstart.clos"),
  ("t_start.comm", "tstart.comm"), ("t_start.notify_ports", "tstart.ntfy"),
  ("t_start.pmem", "tstart.pmem"), ("t_start.bpat", "tstart.bpat"),
  ("t_start.ete", "tstart.ete"), ("t_start.cache_arm_va", "tstart.cava"),
  ("t_start.predyld_blob", "tstart.pdyld"),
  ("cp0.predyld.syscalls", "cp0.pdysys"),
  # recorder 40aa129e: the event log's old names -> the names readers open
  ("event_log.dat", "eventlog.dat"), ("event_log.idx", "eventlog.idx")]

proc renamedMember*(storedKey: uint64): string =
  ## The storable name for a member stored under an old lossy key; "" when the
  ## key is no old name's.
  for (old, new) in MemberRenames:
    if base40Encode(old) == storedKey: return new
  ""
