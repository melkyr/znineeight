/*
 * ref_check.c -- z9torr reference checker (C89).
 *
 * Usage: ref_check --infohash <file>
 * Prints: infohash <40 lowercase hex>
 *
 * The printed value is SHA-1 over the EXACT bytes of the top-level `info`
 * dictionary value in the torrent file -- never a re-encoding. This is the
 * binding definition of a BitTorrent info_hash and is what z9torr computes
 * and what the tier-1 suite diffs against.
 *
 * Build: gcc -std=c89 -O0 -Wall -o ref_check ref_check.c
 *
 * 32-bit note: SHA-1 wraps modulo 2^32. The host's `unsigned long` is 64-bit,
 * which would break that wrap, so the word type here is `unsigned int`
 * (asserted to be exactly 4 bytes below).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned int u32;
typedef unsigned char u8;

/* Fail to compile unless u32 is exactly 32 bits wide. */
typedef char ref_check_u32_must_be_32_bit[(sizeof(u32) == 4) ? 1 : -1];

/* ------------------------------------------------------------------ */
/* SHA-1 (RFC 3174)                                                    */
/* ------------------------------------------------------------------ */

typedef struct {
    u32 state[5];
    unsigned long count; /* total message bytes */
    u8 buffer[64];
} SHA1_CTX;

static u32 sha1_rol(u32 v, int n)
{
    return (v << n) | (v >> (32 - n));
}

static void sha1_transform(u32 state[5], const u8 block[64])
{
    u32 w[80];
    u32 a, b, c, d, e, f, k, t;
    int i;

    for (i = 0; i < 16; i++) {
        w[i] = ((u32)block[i * 4] << 24) | ((u32)block[i * 4 + 1] << 16) |
               ((u32)block[i * 4 + 2] << 8) | (u32)block[i * 4 + 3];
    }
    for (i = 16; i < 80; i++) {
        w[i] = sha1_rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    a = state[0];
    b = state[1];
    c = state[2];
    d = state[3];
    e = state[4];

    for (i = 0; i < 80; i++) {
        if (i < 20) {
            f = (b & c) | ((~b) & d);
            k = 0x5A827999u;
        } else if (i < 40) {
            f = b ^ c ^ d;
            k = 0x6ED9EBA1u;
        } else if (i < 60) {
            f = (b & c) | (b & d) | (c & d);
            k = 0x8F1BBCDCu;
        } else {
            f = b ^ c ^ d;
            k = 0xCA62C1D6u;
        }
        t = sha1_rol(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = sha1_rol(b, 30);
        b = a;
        a = t;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
}

static void sha1_init(SHA1_CTX *ctx)
{
    ctx->state[0] = 0x67452301u;
    ctx->state[1] = 0xEFCDAB89u;
    ctx->state[2] = 0x98BADCFEu;
    ctx->state[3] = 0x10325476u;
    ctx->state[4] = 0xC3D2E1F0u;
    ctx->count = 0;
}

static void sha1_update(SHA1_CTX *ctx, const u8 *data, size_t len)
{
    size_t i = 0;
    size_t idx = (size_t)(ctx->count % 64);

    ctx->count += (unsigned long)len;
    while (i < len) {
        size_t fill = 64 - idx;
        if (fill > len - i) {
            fill = len - i;
        }
        memcpy(ctx->buffer + idx, data + i, fill);
        idx += fill;
        i += fill;
        if (idx == 64) {
            sha1_transform(ctx->state, ctx->buffer);
            idx = 0;
        }
    }
}

static void sha1_final(SHA1_CTX *ctx, u8 out[20])
{
    u8 pad[120];
    u8 len8[8];
    unsigned long bits;
    size_t rem, k;
    int i;

    bits = ctx->count * 8;
    for (i = 0; i < 8; i++) {
        len8[7 - i] = (u8)((bits >> (i * 8)) & 0xFF);
    }

    rem = (size_t)(ctx->count % 64);
    k = (rem < 56) ? (55 - rem) : (119 - rem); /* zeros after the 0x80 */

    pad[0] = 0x80;
    memset(pad + 1, 0, k);
    sha1_update(ctx, pad, k + 1);
    sha1_update(ctx, len8, 8);

    for (i = 0; i < 5; i++) {
        out[i * 4] = (u8)(ctx->state[i] >> 24);
        out[i * 4 + 1] = (u8)(ctx->state[i] >> 16);
        out[i * 4 + 2] = (u8)(ctx->state[i] >> 8);
        out[i * 4 + 3] = (u8)(ctx->state[i]);
    }
}

/* ------------------------------------------------------------------ */
/* Minimal bencode value skipper (enough to locate the `info` span)    */
/* ------------------------------------------------------------------ */

static const char *skip_string(const char *p, const char *end)
{
    unsigned long len = 0;

    if (p >= end || *p < '0' || *p > '9') {
        return NULL;
    }
    while (p < end && *p >= '0' && *p <= '9') {
        len = len * 10 + (unsigned long)(*p - '0');
        p++;
    }
    if (p >= end || *p != ':') {
        return NULL;
    }
    p++;
    if ((unsigned long)(end - p) < len) {
        return NULL;
    }
    return p + len;
}

static const char *skip_value(const char *p, const char *end)
{
    if (p >= end) {
        return NULL;
    }
    if (*p == 'i') {
        p++;
        while (p < end && *p != 'e') {
            p++;
        }
        if (p >= end) {
            return NULL;
        }
        return p + 1;
    }
    if (*p == 'l') {
        p++;
        while (p < end && *p != 'e') {
            p = skip_value(p, end);
            if (p == NULL) {
                return NULL;
            }
        }
        if (p >= end) {
            return NULL;
        }
        return p + 1;
    }
    if (*p == 'd') {
        p++;
        while (p < end && *p != 'e') {
            p = skip_string(p, end);
            if (p == NULL) {
                return NULL;
            }
            p = skip_value(p, end);
            if (p == NULL) {
                return NULL;
            }
        }
        if (p >= end) {
            return NULL;
        }
        return p + 1;
    }
    return skip_string(p, end);
}

/*
 * Top-level dict scan: for each key, skip its value and remember the span
 * [value_start, value_end). Return 1 and set the span when key == "info".
 */
static int find_info_span(const char *buf, size_t n,
                          const char **out_start, const char **out_end)
{
    const char *p = buf;
    const char *end = buf + n;

    if (p >= end || *p != 'd') {
        return 0;
    }
    p++;
    while (p < end && *p != 'e') {
        const char *kstart = p;
        const char *kend = skip_string(p, end);
        const char *vstart, *vend;
        const char *colon;
        size_t keylen;

        if (kend == NULL) {
            return 0;
        }
        vstart = kend;
        vend = skip_value(vstart, end);
        if (vend == NULL) {
            return 0;
        }
        keylen = (size_t)(kend - kstart);
        colon = (const char *)memchr(kstart, ':', keylen);
        if (colon != NULL && colon + 1 + 4 == kend &&
            memcmp(colon + 1, "info", 4) == 0) {
            *out_start = vstart;
            *out_end = vend;
            return 1;
        }
        p = vend;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* I/O + entry point                                                   */
/* ------------------------------------------------------------------ */

static u8 *read_file(const char *path, size_t *out_len)
{
    FILE *f = fopen(path, "rb");
    u8 *buf;
    long sz;

    if (f == NULL) {
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    sz = ftell(f);
    if (sz < 0) {
        fclose(f);
        return NULL;
    }
    rewind(f);
    buf = (u8 *)malloc((size_t)sz + 1);
    if (buf == NULL) {
        fclose(f);
        return NULL;
    }
    if (fread(buf, 1, (size_t)sz, f) != (size_t)sz) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    buf[sz] = 0;
    *out_len = (size_t)sz;
    return buf;
}

int main(int argc, char **argv)
{
    u8 *buf;
    size_t n = 0;
    const char *info_start = NULL;
    const char *info_end = NULL;
    SHA1_CTX ctx;
    u8 digest[20];
    int i;

    if (argc != 3 || strcmp(argv[1], "--infohash") != 0) {
        fprintf(stderr, "usage: ref_check --infohash <file>\n");
        return 2;
    }

    buf = read_file(argv[2], &n);
    if (buf == NULL) {
        fprintf(stderr, "ref_check: cannot read %s\n", argv[2]);
        return 2;
    }
    if (!find_info_span((const char *)buf, n, &info_start, &info_end)) {
        fprintf(stderr, "ref_check: no top-level info dict\n");
        free(buf);
        return 3;
    }

    sha1_init(&ctx);
    sha1_update(&ctx, (const u8 *)info_start, (size_t)(info_end - info_start));
    sha1_final(&ctx, digest);

    printf("infohash ");
    for (i = 0; i < 20; i++) {
        printf("%02x", digest[i]);
    }
    printf("\n");

    free(buf);
    return 0;
}
