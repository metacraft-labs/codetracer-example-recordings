/*
 * Does this host let a process turn on CPUID faulting?
 *
 * ct-mcr records CPUID results per execution by asking the kernel to make
 * every CPUID instruction fault (arch_prctl(ARCH_SET_CPUID, 0)), and refuses
 * to record when the kernel says no.  The kernel can only say yes when the
 * CPU has the CPUID-faulting feature (Intel; AMD from Zen 4) and nothing
 * between the process and the CPU (a hypervisor, a seccomp filter) hides it.
 * This makes the same request, undoes it, and reports.
 *
 * Exit 0: supported.  Exit 1: not supported, with the reason on stderr.
 *
 *   cc -o probe-cpuid-faulting probe-cpuid-faulting.c && ./probe-cpuid-faulting
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef ARCH_GET_CPUID
#define ARCH_GET_CPUID 0x1011
#endif
#ifndef ARCH_SET_CPUID
#define ARCH_SET_CPUID 0x1012
#endif

int main(void) {
  long before = syscall(SYS_arch_prctl, ARCH_GET_CPUID, 0);
  if (syscall(SYS_arch_prctl, ARCH_SET_CPUID, 0) != 0) {
    int e = errno;
    fprintf(stderr,
            "CPUID faulting: NOT available: arch_prctl(ARCH_SET_CPUID, 0) "
            "failed with %s (errno %d)%s\n",
            strerror(e), e,
            e == ENODEV ? " -- the CPU, or the hypervisor below this host, "
                          "does not offer CPUID faulting"
                        : "");
    return 1;
  }
  syscall(SYS_arch_prctl, ARCH_SET_CPUID, 1);
  printf("CPUID faulting: available (ARCH_GET_CPUID was %ld before the "
         "probe; restored)\n",
         before);
  return 0;
}
