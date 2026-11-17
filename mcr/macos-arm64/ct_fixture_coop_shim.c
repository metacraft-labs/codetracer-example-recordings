// ct_fixture_coop_shim.c -- starts the cooperative recorder for
// ct_fixture_prog before main and stops it at exit.
//
// The fixture program is compiled with `-include ct_cooperative.h
// -DCT_COOPERATIVE_WRAP_LIBC`, so its open/read/write/close/pthread_create
// calls go through the recorder's hooks; this file only owns the recording's
// lifetime.  It asks for the entry snapshot (the registers and memory main
// starts with), which a replay on another host starts from.  The trace path
// is the CT_FIXTURE_TRACE environment variable.
#include "ct_cooperative.h"
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// libct_cooperative is a Nim `--app:staticlib --noMain` archive: its module
// initialisers run from NimMain, which the program calls before the first
// recorder API (as ct_cooperative's own fixtures do).
extern void NimMain(void);

static char program_path[PATH_MAX];

static void stop_recording(void) {
  if (ct_recording_stop() != 0) {
    fprintf(stderr, "ct_fixture_prog: ct_recording_stop: %s\n", ct_recording_last_error());
    _exit(71);
  }
}

__attribute__((constructor)) static void start_recording(void) {
  const char *out = getenv("CT_FIXTURE_TRACE");
  if (out == NULL || out[0] == '\0') return;  // run without recording
  char raw[PATH_MAX];
  uint32_t n = sizeof(raw);
  if (_NSGetExecutablePath(raw, &n) != 0 || realpath(raw, program_path) == NULL) {
    fprintf(stderr, "ct_fixture_prog: cannot resolve the executable path\n");
    _exit(70);
  }
  NimMain();
  ct_recording_config_t cfg = {0};
  cfg.sink_mode = CT_SINK_LOCAL_FILE;
  cfg.output_path = out;
  cfg.program_name = program_path;
  cfg.tick_source = "none";
  if (ct_recording_init(&cfg) != 0 || ct_recording_start() != 0 ||
      ct_recording_capture_entry_snapshot() != 0) {
    fprintf(stderr, "ct_fixture_prog: starting the recording: %s\n", ct_recording_last_error());
    _exit(70);
  }
  atexit(stop_recording);
}
