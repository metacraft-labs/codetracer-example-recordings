/*
 * android_ctsp_client.c — Minimal CTSP client for Android phone-to-desktop
 * integration testing.
 *
 * This is a pure C program (no Nim dependency) that speaks the CTSP wire
 * protocol directly.  It connects to a stream-receiver over TCP, sends
 * metadata + event batches + end-recording, then prints "DONE".
 *
 * Usage: android_ctsp_client <host> <port>
 *   host  — IP or hostname of the stream-receiver (usually 127.0.0.1 when
 *           using adb reverse)
 *   port  — TCP port (e.g. 14290)
 *
 * CTSP wire format (from ctsp.nim):
 *   [0:1]  messageType  uint16 LE
 *   [2:3]  flags        uint16 LE
 *   [4:7]  payloadLen   uint32 LE
 *   [8..]  payload      (payloadLen bytes)
 *
 * Message types (client -> server):
 *   0x0001  EVENT_BATCH   flags = ctTid (low 16 bits)
 *   0x0002  CHECKPOINT
 *   0x0003  METADATA      payload = JSON string
 *   0x0004  END_RECORDING
 *   0x0005  HEARTBEAT
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

/* CTSP message types */
#define CTSP_EVENT_BATCH    0x0001
#define CTSP_CHECKPOINT     0x0002
#define CTSP_METADATA       0x0003
#define CTSP_END_RECORDING  0x0004
#define CTSP_HEARTBEAT      0x0005

/* CTSP header: 8 bytes */
typedef struct {
    uint16_t message_type;  /* LE */
    uint16_t flags;         /* LE */
    uint32_t payload_len;   /* LE */
} __attribute__((packed)) ctsp_header_t;

/* -------------------------------------------------------------------------- */
/* Helpers                                                                     */
/* -------------------------------------------------------------------------- */

static void write_u16_le(uint8_t *buf, uint16_t v) {
    buf[0] = (uint8_t)(v & 0xFF);
    buf[1] = (uint8_t)((v >> 8) & 0xFF);
}

static void write_u32_le(uint8_t *buf, uint32_t v) {
    buf[0] = (uint8_t)(v & 0xFF);
    buf[1] = (uint8_t)((v >> 8) & 0xFF);
    buf[2] = (uint8_t)((v >> 16) & 0xFF);
    buf[3] = (uint8_t)((v >> 24) & 0xFF);
}

/* Send exactly `len` bytes, retrying on short writes. */
static int send_all(int fd, const uint8_t *buf, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, buf + sent, len - sent, 0);
        if (n <= 0) {
            if (n < 0 && errno == EINTR)
                continue;
            return -1;
        }
        sent += (size_t)n;
    }
    return 0;
}

/* Build and send a CTSP message. */
static int send_ctsp(int fd, uint16_t type, uint16_t flags,
                     const uint8_t *payload, uint32_t payload_len) {
    uint8_t hdr[8];
    write_u16_le(hdr + 0, type);
    write_u16_le(hdr + 2, flags);
    write_u32_le(hdr + 4, payload_len);

    if (send_all(fd, hdr, 8) != 0)
        return -1;
    if (payload_len > 0 && send_all(fd, payload, payload_len) != 0)
        return -1;
    return 0;
}

/* -------------------------------------------------------------------------- */
/* Fake event data builder                                                     */
/* -------------------------------------------------------------------------- */

/*
 * Build a minimal event batch payload.  The stream receiver does not parse
 * individual events inside the batch — it just passes the raw bytes to
 * TraceWriter.writeEventData().  So any non-empty payload will be recorded
 * as event data in the trace.
 *
 * We build a plausible-looking blob: 16 bytes per "event" containing
 * a 4-byte event type + 4-byte tick + 8-byte payload stub.
 */
#define EVENTS_PER_BATCH 5
#define EVENT_SIZE       16
#define BATCH_SIZE       (EVENTS_PER_BATCH * EVENT_SIZE)

static void build_event_batch(uint8_t *buf, int batch_idx) {
    memset(buf, 0, BATCH_SIZE);
    for (int i = 0; i < EVENTS_PER_BATCH; i++) {
        uint8_t *ev = buf + (i * EVENT_SIZE);
        /* event type placeholder (4 bytes LE) */
        write_u32_le(ev + 0, 0x01);
        /* tick value (4 bytes LE) — ascending across batches */
        write_u32_le(ev + 4, (uint32_t)(batch_idx * EVENTS_PER_BATCH + i + 1));
        /* payload stub — 8 bytes of pattern data */
        write_u32_le(ev + 8, 0xDEADBEEF);
        write_u32_le(ev + 12, (uint32_t)(batch_idx * 100 + i));
    }
}

/* -------------------------------------------------------------------------- */
/* Main                                                                        */
/* -------------------------------------------------------------------------- */

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <host> <port>\n", argv[0]);
        return 1;
    }

    const char *host = argv[1];
    int port = atoi(argv[2]);
    if (port <= 0 || port > 65535) {
        fprintf(stderr, "ERROR: invalid port: %s\n", argv[2]);
        return 1;
    }

    printf("android_ctsp_client: connecting to %s:%d\n", host, port);

    /* Create TCP socket */
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
        fprintf(stderr, "ERROR: invalid host address: %s\n", host);
        close(sock);
        return 1;
    }

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        perror("connect");
        close(sock);
        return 1;
    }

    printf("android_ctsp_client: connected\n");

    /* --- Send METADATA --- */
    const char *metadata_json =
        "{\"program\":\"android_ctsp_client\","
        "\"tickSource\":\"none\","
        "\"recordingMode\":\"cooperative-stream\"}";
    uint32_t meta_len = (uint32_t)strlen(metadata_json);
    if (send_ctsp(sock, CTSP_METADATA, 0,
                  (const uint8_t *)metadata_json, meta_len) != 0) {
        fprintf(stderr, "ERROR: failed to send METADATA\n");
        close(sock);
        return 1;
    }
    printf("android_ctsp_client: sent METADATA (%u bytes)\n", meta_len);

    /* --- Send EVENT_BATCH messages --- */
    #define NUM_BATCHES 10

    for (int i = 0; i < NUM_BATCHES; i++) {
        uint8_t batch[BATCH_SIZE];
        build_event_batch(batch, i);

        /* ctTid=1 for all batches (single-threaded test program) */
        if (send_ctsp(sock, CTSP_EVENT_BATCH, /*ctTid=*/1,
                      batch, BATCH_SIZE) != 0) {
            fprintf(stderr, "ERROR: failed to send EVENT_BATCH %d\n", i);
            close(sock);
            return 1;
        }
    }
    printf("android_ctsp_client: sent %d EVENT_BATCH messages "
           "(%d events total)\n",
           NUM_BATCHES, NUM_BATCHES * EVENTS_PER_BATCH);

    /* --- Send END_RECORDING --- */
    if (send_ctsp(sock, CTSP_END_RECORDING, 0, NULL, 0) != 0) {
        fprintf(stderr, "ERROR: failed to send END_RECORDING\n");
        close(sock);
        return 1;
    }
    printf("android_ctsp_client: sent END_RECORDING\n");

    close(sock);
    printf("DONE\n");
    return 0;
}
