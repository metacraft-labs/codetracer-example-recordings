// source.c — test program for MCR cooperative-mode recording fixtures.
//
// Exercises the features needed for DAP integration testing:
// - Multiple functions (calltrace)
// - Loops (tick counting)
// - Syscalls (event recording via open/read/close)
// - Thread creation (multi-thread support)

#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>

// ---------------------------------------------------------------------------
// Pure computation (generates ticks from compiler instrumentation)
// ---------------------------------------------------------------------------

int calculate_sum(int a, int b) {
  int result = 0;
  for (int i = a; i <= b; i++) {
    result += i;
  }
  return result;
}

int sum_with_for(int n) {
  int total = 0;
  for (int i = 1; i <= n; i++) {
    total += i;
  }
  return total;
}

int sum_with_while(int n) {
  int total = 0;
  int i = 1;
  while (i <= n) {
    total += i;
    i++;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Syscall-heavy function (generates open/read/close events)
// ---------------------------------------------------------------------------

int read_dev_null(int iterations) {
  int total_bytes = 0;
  for (int i = 0; i < iterations; i++) {
    int fd = open("/dev/null", O_RDONLY);
    if (fd >= 0) {
      char buf[64];
      ssize_t n = read(fd, buf, sizeof(buf));
      if (n >= 0) total_bytes += (int)n;
      close(fd);
    }
  }
  return total_bytes;
}

// ---------------------------------------------------------------------------
// Worker thread (exercises multi-thread recording)
// ---------------------------------------------------------------------------

typedef struct {
  int worker_id;
  int iterations;
  int result;
} WorkerArg;

void *worker_thread(void *arg) {
  WorkerArg *wa = (WorkerArg *)arg;

  // Computation ticks
  int sum = 0;
  for (int i = 0; i < wa->iterations; i++) {
    sum += i * wa->worker_id;
  }

  // Syscall events
  int fd = open("/dev/null", O_RDONLY);
  if (fd >= 0) {
    char buf[16];
    read(fd, buf, sizeof(buf));
    close(fd);
  }

  wa->result = sum;
  return NULL;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main(void) {
  // Phase 1: computation (ticks)
  int s1 = calculate_sum(10, 32);    // expected: 94 + ... = 483 (sum 10..32)
  int s2 = sum_with_for(9);          // expected: 45
  int s3 = sum_with_while(9);        // expected: 45

  printf("calculate_sum(10, 32) = %d\n", s1);
  printf("sum_with_for(9) = %d\n", s2);
  printf("sum_with_while(9) = %d\n", s3);

  // Phase 2: syscalls (events)
  int bytes = read_dev_null(5);
  printf("read_dev_null(5) = %d bytes\n", bytes);

  // Phase 3: threads
  const int NUM_WORKERS = 3;
  pthread_t threads[3];
  WorkerArg args[3];

  for (int i = 0; i < NUM_WORKERS; i++) {
    args[i].worker_id = i + 1;
    args[i].iterations = 100;
    args[i].result = 0;
    pthread_create(&threads[i], NULL, worker_thread, &args[i]);
  }

  for (int i = 0; i < NUM_WORKERS; i++) {
    pthread_join(threads[i], NULL);
    printf("worker %d result = %d\n", i + 1, args[i].result);
  }

  // Phase 4: final computation
  int final_sum = s1 + s2 + s3;
  for (int i = 0; i < NUM_WORKERS; i++) {
    final_sum += args[i].result;
  }
  printf("final_sum = %d\n", final_sum);

  return 0;
}
