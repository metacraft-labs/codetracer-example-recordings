// noaslr.c -- run a program with ASLR disabled (posix_spawn's
// _POSIX_SPAWN_DISABLE_ASLR), so its recorded addresses are the file's.
#include <spawn.h>
#include <stdio.h>
#include <sys/wait.h>
#ifndef _POSIX_SPAWN_DISABLE_ASLR
#define _POSIX_SPAWN_DISABLE_ASLR 0x0100
#endif
extern char **environ;
int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: noaslr <program> [args...]\n"); return 2; }
  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  posix_spawnattr_setflags(&attr, _POSIX_SPAWN_DISABLE_ASLR);
  pid_t pid;
  int rc = posix_spawn(&pid, argv[1], NULL, &attr, argv + 1, environ);
  if (rc != 0) { perror("posix_spawn"); return 127; }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0) { perror("waitpid"); return 127; }
  return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
