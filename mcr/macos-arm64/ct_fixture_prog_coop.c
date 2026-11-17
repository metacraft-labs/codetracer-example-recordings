// ct_fixture_prog_coop.c -- ct_fixture_prog built for the cooperative
// recorder: the program's own source, with its open/read/write/close and
// pthread_create calls sent through the recorder's hooks.
//
// The system headers come first, so the hook macros
// (CT_COOPERATIVE_WRAP_LIBC in ct_cooperative.h) rewrite only the program's
// calls: Darwin declares open/read/write/close with an assembler alias
// (__DARWIN_ALIAS_C), and a macro applied to those declarations would bind
// the hook's name to libc's symbol instead.
#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
#define CT_COOPERATIVE_WRAP_LIBC
#include "ct_cooperative.h"
#include "source.c"
