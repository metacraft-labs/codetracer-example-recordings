// ct_fixture_prog.c — cross-platform test program for MCR recording fixtures.
//
// Exercises the features needed for DAP integration testing:
// - Multiple functions (calltrace)
// - Loops (tick counting)
// - I/O (event recording via platform-native file APIs)
// - Thread creation (multi-thread support)
//
// Platform-specific sections use #ifdef _WIN32 for Windows (Win32 APIs)
// and POSIX APIs elsewhere (Linux, macOS, Android, iOS).

#include <stdio.h>

#ifdef _WIN32
  #include <windows.h>
#else
  #include <fcntl.h>
  #include <unistd.h>
  #include <pthread.h>
#endif

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
// I/O (generates file open/read/close events via platform-native APIs)
// ---------------------------------------------------------------------------

int read_null_device(int iterations) {
  int total_bytes = 0;
  for (int i = 0; i < iterations; i++) {
#ifdef _WIN32
    HANDLE h = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ,
                           NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (h != INVALID_HANDLE_VALUE) {
      char buf[64];
      DWORD n = 0;
      if (ReadFile(h, buf, sizeof(buf), &n, NULL)) {
        total_bytes += (int)n;
      }
      CloseHandle(h);
    }
#else
    int fd = open("/dev/null", O_RDONLY);
    if (fd >= 0) {
      char buf[64];
      ssize_t n = read(fd, buf, sizeof(buf));
      if (n >= 0) total_bytes += (int)n;
      close(fd);
    }
#endif
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

#ifdef _WIN32

DWORD WINAPI worker_thread(LPVOID arg) {
  WorkerArg *wa = (WorkerArg *)arg;

  // Computation ticks
  int sum = 0;
  for (int i = 0; i < wa->iterations; i++) {
    sum += i * wa->worker_id;
  }

  // I/O events
  HANDLE h = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ,
                         NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (h != INVALID_HANDLE_VALUE) {
    char buf[16];
    DWORD n = 0;
    ReadFile(h, buf, sizeof(buf), &n, NULL);
    CloseHandle(h);
  }

  wa->result = sum;
  return 0;
}

#else

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

#endif

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main(void) {
  // Phase 1: computation (ticks)
  int s1 = calculate_sum(10, 32);    // expected: 483 (sum 10..32)
  int s2 = sum_with_for(9);          // expected: 45
  int s3 = sum_with_while(9);        // expected: 45

  printf("calculate_sum(10, 32) = %d\n", s1);
  printf("sum_with_for(9) = %d\n", s2);
  printf("sum_with_while(9) = %d\n", s3);

  // Phase 2: I/O (events)
  int bytes = read_null_device(5);
  printf("read_null_device(5) = %d bytes\n", bytes);

  // Phase 3: threads
  #define NUM_WORKERS 3
  WorkerArg args[NUM_WORKERS];

#ifdef _WIN32
  HANDLE threads[NUM_WORKERS];

  for (int i = 0; i < NUM_WORKERS; i++) {
    args[i].worker_id = i + 1;
    args[i].iterations = 100;
    args[i].result = 0;
    threads[i] = CreateThread(NULL, 0, worker_thread, &args[i], 0, NULL);
  }

  WaitForMultipleObjects(NUM_WORKERS, threads, TRUE, INFINITE);

  for (int i = 0; i < NUM_WORKERS; i++) {
    CloseHandle(threads[i]);
    printf("worker %d result = %d\n", i + 1, args[i].result);
  }
#else
  pthread_t threads[NUM_WORKERS];

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
#endif

  // Phase 4: final computation
  int final_sum = s1 + s2 + s3;
  for (int i = 0; i < NUM_WORKERS; i++) {
    final_sum += args[i].result;
  }
  printf("final_sum = %d\n", final_sum);

  return 0;
}
