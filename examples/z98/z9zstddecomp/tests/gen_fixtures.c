/* gen_fixtures.c -- dev-time generator for the z9zstddecomp tier fixtures.
 *
 * Links against the system libzstd (1.5.4 in the dev environment) and writes
 * the committed tests/fixtures fixture files. The tier itself never
 * regenerates them; it consumes the committed bytes.
 *
 * Build/run (from the repo root):
 *   gcc -O2 -o /tmp/gen_zstddecomp_fixtures \
 *       examples/z98/z9zstddecomp/tests/gen_fixtures.c -lzstd
 *   mkdir -p /tmp/zstddecomp_fixtures
 *   /tmp/gen_zstddecomp_fixtures /tmp/zstddecomp_fixtures
 *
 * Output is deterministic (fixed xorshift seed, fixed samples, fixed dict id).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <zstd.h>
#include <zdict.h>

#define NSAMP 128u
#define SAMP_SZ 512u
#define CUSTOM_SZ 8192u

static uint32_t g_rng = 0x12345678u;

static uint32_t nextu(void) {
    g_rng ^= g_rng << 13;
    g_rng ^= g_rng >> 17;
    g_rng ^= g_rng << 5;
    return g_rng;
}

static void fill_text(unsigned char *p, size_t n, unsigned seed) {
    static const char *words[16] = {
        "zstd", "dictionary", "window", "history", "compressed", "literal",
        "entropy", "match", "frame", "z98", "decompress", "stream", "offset",
        "sequence", "content", "boundary"
    };
    size_t i = 0;
    while (i < n) {
        unsigned w = (unsigned)((seed * 2654435761u + (uint32_t)i * 40503u) >> 4) & 15u;
        const char *s = words[w];
        while (*s != '\0' && i < n) p[i++] = (unsigned char)*s;
        if (i < n) p[i++] = ' ';
    }
}

static void fill_random(unsigned char *p, size_t n) {
    size_t i = 0;
    while (i < n) p[i++] = (unsigned char)(nextu() & 0xFFu);
}

static void die(const char *what) {
    fprintf(stderr, "gen_fixtures: %s\n", what);
    exit(1);
}

static void write_file(const char *dir, const char *name,
                       const unsigned char *data, size_t n) {
    char path[4096];
    FILE *f;
    snprintf(path, sizeof path, "%s/%s", dir, name);
    f = fopen(path, "wb");
    if (f == NULL) {
        fprintf(stderr, "gen_fixtures: cannot write %s\n", path);
        exit(1);
    }
    if (n != 0 && fwrite(data, 1, n, f) != n) die("short write");
    if (fclose(f) != 0) die("fclose failed");
}

static size_t compress_frame(const unsigned char *dict, size_t dict_sz,
                             const unsigned char *src, size_t src_sz,
                             int window_log, int content_size_flag,
                             int checksum, unsigned char *dst, size_t cap,
                             const char *what) {
    ZSTD_CCtx *cctx = ZSTD_createCCtx();
    size_t n;
    if (cctx == NULL) die("ZSTD_createCCtx failed");
    if (ZSTD_isError(ZSTD_CCtx_setParameter(cctx, ZSTD_c_compressionLevel, 3)))
        die("set compressionLevel failed");
    if (window_log > 0) {
        if (ZSTD_isError(ZSTD_CCtx_setParameter(cctx, ZSTD_c_windowLog, window_log)))
            die("set windowLog failed");
    }
    if (content_size_flag >= 0) {
        if (ZSTD_isError(ZSTD_CCtx_setParameter(cctx, ZSTD_c_contentSizeFlag,
                                                content_size_flag)))
            die("set contentSizeFlag failed");
    }
    if (ZSTD_isError(ZSTD_CCtx_setParameter(cctx, ZSTD_c_checksumFlag, checksum)))
        die("set checksumFlag failed");
    if (dict != NULL) {
        if (ZSTD_isError(ZSTD_CCtx_loadDictionary(cctx, dict, dict_sz)))
            die("loadDictionary failed");
    }
    n = ZSTD_compress2(cctx, dst, cap, src, src_sz);
    if (ZSTD_isError(n)) {
        fprintf(stderr, "gen_fixtures: compress (%s): %s\n", what,
                ZSTD_getErrorName(n));
        exit(1);
    }
    ZSTD_freeCCtx(cctx);
    return n;
}

static size_t frame_header_size(const unsigned char *f, size_t n) {
    unsigned desc;
    int single;
    unsigned fcs_flag, did_flag;
    size_t p, fcs_size;
    if (n < 5) return 0;
    desc = f[4];
    single = (int)((desc >> 5) & 1);
    fcs_flag = desc >> 6;
    did_flag = desc & 3;
    p = 5;
    if (!single) {
        if (p >= n) return 0;
        p += 1;
    }
    if (did_flag == 1) p += 1;
    else if (did_flag == 2) p += 2;
    else if (did_flag == 3) p += 4;
    if (fcs_flag == 0) fcs_size = single ? 1u : 0u;
    else if (fcs_flag == 1) fcs_size = 2;
    else if (fcs_flag == 2) fcs_size = 4;
    else fcs_size = 8;
    p += fcs_size;
    if (p > n) return 0;
    return p;
}

/* Assert the first block is compressed and carries 4-stream Huffman literals. */
static void assert_four_stream(const unsigned char *frame, size_t n) {
    size_t pos = frame_header_size(frame, n);
    uint32_t bh, lhc;
    int type, lit_type, lit_sf;
    size_t lit_size;
    unsigned char b;
    if (pos == 0) die("fourstream: bad frame header");
    if (pos + 3 > n) die("fourstream: truncated block header");
    bh = (uint32_t)frame[pos] | ((uint32_t)frame[pos + 1] << 8) |
        ((uint32_t)frame[pos + 2] << 16);
    pos += 3;
    type = (int)((bh >> 1) & 3);
    if (type != 2) die("fourstream: first block is not compressed");
    if (pos >= n) die("fourstream: missing literals header");
    b = frame[pos];
    lit_type = (int)(b & 3);
    lit_sf = (int)((b >> 2) & 3);
    if (lit_type != 2 && lit_type != 3)
        die("fourstream: first block has no Huffman literals");
    if (lit_sf == 0)
        die("fourstream: literals are single-stream (size_format 0)");
    if (lit_sf == 0 || lit_sf == 1) {
        if (pos + 3 > n) die("fourstream: truncated literals header");
        lhc = (uint32_t)frame[pos] | ((uint32_t)frame[pos + 1] << 8) |
            ((uint32_t)frame[pos + 2] << 16);
        lit_size = (size_t)((lhc >> 4) & 0x3FF);
    } else if (lit_sf == 2) {
        if (pos + 4 > n) die("fourstream: truncated literals header");
        lhc = (uint32_t)frame[pos] | ((uint32_t)frame[pos + 1] << 8) |
            ((uint32_t)frame[pos + 2] << 16) |
            ((uint32_t)frame[pos + 3] << 24);
        lit_size = (size_t)((lhc >> 4) & 0x3FFF);
    } else {
        if (pos + 5 > n) die("fourstream: truncated literals header");
        lhc = (uint32_t)frame[pos] | ((uint32_t)frame[pos + 1] << 8) |
            ((uint32_t)frame[pos + 2] << 16) |
            ((uint32_t)frame[pos + 3] << 24);
        lit_size = (size_t)((lhc >> 4) & 0x3FFFF);
    }
    if (lit_size <= 1024) die("fourstream: literals too small for 4 streams");
    printf("fourstream: lit_type=%d size_format=%d lit_size=%lu\n",
           lit_type, lit_sf, (unsigned long)lit_size);
}

static void assert_first_block_rle(const unsigned char *frame, size_t n) {
    size_t pos = frame_header_size(frame, n);
    uint32_t bh;
    int type;
    if (pos == 0) die("rle: bad frame header");
    if (pos + 3 > n) die("rle: truncated block header");
    bh = (uint32_t)frame[pos] | ((uint32_t)frame[pos + 1] << 8) |
        ((uint32_t)frame[pos + 2] << 16);
    type = (int)((bh >> 1) & 3);
    if (type != 1) die("rle: first block is not an RLE block");
    printf("rle: first block type=1 size=%lu\n",
           (unsigned long)(bh >> 3));
}

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : ".";
    unsigned char samples[NSAMP * SAMP_SZ];
    size_t sample_sizes[NSAMP];
    unsigned char dict1[32768];
    unsigned char dict2[32768];
    unsigned char custom[CUSTOM_SZ];
    unsigned char raw_dict[CUSTOM_SZ];
    unsigned char plain[4096];
    unsigned char big[131072];
    unsigned char rle[32768];
    unsigned char skippable[8 + 16 + 262144];
    unsigned char frame[262144];
    unsigned char buf[262144];
    unsigned id1, id2;
    size_t dict1_sz, dict2_sz, n, plain_n;
    unsigned i;
    ZDICT_params_t p;

    for (i = 0; i < NSAMP; i++) {
        fill_text(samples + (size_t)i * SAMP_SZ, SAMP_SZ, i + 1u);
        sample_sizes[i] = SAMP_SZ;
    }

    dict1_sz = ZDICT_trainFromBuffer(dict1, sizeof dict1, samples,
                                     sample_sizes, NSAMP);
    if (ZDICT_isError(dict1_sz)) {
        fprintf(stderr, "gen_fixtures: trainFromBuffer: %s\n",
                ZDICT_getErrorName(dict1_sz));
        return 1;
    }
    id1 = ZSTD_getDictID_fromDict(dict1, dict1_sz);
    if (id1 == 0) die("dict1 has no dictionary id");

    fill_random(custom, CUSTOM_SZ);
    memset(&p, 0, sizeof p);
    p.compressionLevel = 3;
    p.notificationLevel = 0;
    p.dictID = 0x0BADF00Du;
    dict2_sz = ZDICT_finalizeDictionary(dict2, sizeof dict2, custom, CUSTOM_SZ,
                                        samples, sample_sizes, NSAMP, p);
    if (ZDICT_isError(dict2_sz)) {
        fprintf(stderr, "gen_fixtures: finalizeDictionary: %s\n",
                ZDICT_getErrorName(dict2_sz));
        return 1;
    }
    id2 = ZSTD_getDictID_fromDict(dict2, dict2_sz);
    if (id2 == 0 || id1 == id2) die("dict2 id is missing or collides with dict1");
    printf("dict1: %lu bytes id=0x%08X\n", (unsigned long)dict1_sz, id1);
    printf("dict2: %lu bytes id=0x%08X\n", (unsigned long)dict2_sz, id2);

    /* plain: ordinary text frame with the exact content size declared. */
    fill_text(plain, sizeof plain, 7u);
    write_file(dir, "plain.raw", plain, sizeof plain);
    n = compress_frame(NULL, 0, plain, sizeof plain, 0, -1, 0,
                       frame, sizeof frame, "plain");
    write_file(dir, "plain.zst", frame, n);
    printf("plain: %lu bytes (raw %lu)\n", (unsigned long)n,
           (unsigned long)sizeof plain);

    /* fourstream: a compressed block whose literals use the 4-stream layout.
     * A single 2 KiB block of random lowercase letters (Huffman-friendly, but
     * more than 1024 distinct literals) is repeated to give zstd long matches. */
    {
        unsigned char base[2048];
        for (i = 0; i < (unsigned)sizeof base; i++)
            base[i] = (unsigned char)('a' + (nextu() % 26u));
        for (i = 0; i < 64u; i++)
            memcpy(big + (size_t)i * sizeof base, base, sizeof base);
    }
    write_file(dir, "fourstream.raw", big, sizeof big);
    n = compress_frame(NULL, 0, big, sizeof big, 15, 0, 0,
                       frame, sizeof frame, "fourstream");
    assert_four_stream(frame, n);
    write_file(dir, "fourstream.zst", frame, n);
    printf("fourstream: %lu bytes (raw %lu)\n", (unsigned long)n,
           (unsigned long)sizeof big);

    /* rle: one RLE block (block type 1) emitted directly. libzstd 1.5.4
     * prefers a compressed block with RLE literals for this input, so build
     * the canonical frame ourselves: single-segment, 2-byte content size. */
    {
        size_t content = 1000u;
        size_t fcs = content - 256u;
        size_t bh = (content << 3) | (1u << 1) | 1u;
        memset(rle, 'A', content);
        write_file(dir, "rle.raw", rle, content);
        frame[0] = 0x28;
        frame[1] = 0xB5;
        frame[2] = 0x2F;
        frame[3] = 0xFD;
        frame[4] = 0x60; /* fcs_flag=1, single_segment=1 */
        frame[5] = (unsigned char)(fcs & 0xFFu);
        frame[6] = (unsigned char)((fcs >> 8) & 0xFFu);
        frame[7] = (unsigned char)(bh & 0xFFu);
        frame[8] = (unsigned char)((bh >> 8) & 0xFFu);
        frame[9] = (unsigned char)((bh >> 16) & 0xFFu);
        frame[10] = 'A';
        n = 11u;
        assert_first_block_rle(frame, n);
        write_file(dir, "rle.zst", frame, n);
        printf("rle: %lu bytes (raw %lu)\n", (unsigned long)n,
               (unsigned long)content);
    }

    /* skippable: one skippable frame followed by the plain frame. */
    {
        size_t payload = 16u;
        size_t total;
        uint32_t magic = 0x184D2A50u;
        skippable[0] = (unsigned char)(magic & 0xFFu);
        skippable[1] = (unsigned char)((magic >> 8) & 0xFFu);
        skippable[2] = (unsigned char)((magic >> 16) & 0xFFu);
        skippable[3] = (unsigned char)((magic >> 24) & 0xFFu);
        skippable[4] = (unsigned char)(payload & 0xFFu);
        skippable[5] = (unsigned char)((payload >> 8) & 0xFFu);
        skippable[6] = (unsigned char)((payload >> 16) & 0xFFu);
        skippable[7] = (unsigned char)((payload >> 24) & 0xFFu);
        for (i = 0; i < (unsigned)payload; i++)
            skippable[8 + i] = (unsigned char)(0x80u + i);
        n = compress_frame(NULL, 0, plain, sizeof plain, 0, -1, 0,
                           buf, sizeof buf, "skippable-body");
        memcpy(skippable + 8 + payload, buf, n);
        total = 8 + payload + n;
        write_file(dir, "skippable.zst", skippable, total);
        printf("skippable: %lu bytes (payload %lu + frame %lu)\n",
               (unsigned long)total, (unsigned long)payload,
               (unsigned long)n);
    }

    /* checksum: the plain frame with the xxh64 content checksum enabled. */
    n = compress_frame(NULL, 0, plain, sizeof plain, 0, -1, 1,
                       frame, sizeof frame, "checksum");
    write_file(dir, "checksum.zst", frame, n);
    printf("checksum: %lu bytes\n", (unsigned long)n);

    /* magic-dict: real trained magic dictionary + dict-compressed frame. */
    memcpy(buf, samples + 0 * SAMP_SZ, SAMP_SZ);
    memcpy(buf + SAMP_SZ, samples + 1 * SAMP_SZ, SAMP_SZ);
    plain_n = 2u * SAMP_SZ;
    write_file(dir, "magic-dict.raw", buf, plain_n);
    n = compress_frame(dict1, dict1_sz, buf, plain_n, 0, -1, 0,
                       frame, sizeof frame, "magic-dict");
    write_file(dir, "magic-dict.zst", frame, n);
    write_file(dir, "dict-magic.bin", dict1, dict1_sz);
    printf("magic-dict: %lu bytes (raw %lu, id=0x%08X)\n",
           (unsigned long)n, (unsigned long)plain_n, id1);

    /* raw-dict: no magic/id; the last 1 KiB is matchable dictionary history. */
    fill_random(raw_dict, sizeof raw_dict);
    memcpy(buf, raw_dict + sizeof raw_dict - 1024u, 1024u);
    write_file(dir, "raw-dict.raw", buf, 1024u);
    n = compress_frame(raw_dict, sizeof raw_dict, buf, 1024u, 10, 0, 0,
                       frame, sizeof frame, "raw-dict");
    write_file(dir, "raw-dict.zst", frame, n);
    write_file(dir, "dict-raw.bin", raw_dict, sizeof raw_dict);
    printf("raw-dict: %lu bytes (raw 1024)\n", (unsigned long)n);

    /* dict-mismatch: magic dict1 frame; the tier decodes with dict2. */
    n = compress_frame(dict1, dict1_sz, buf, 1024u, 0, -1, 0,
                       frame, sizeof frame, "dict-mismatch");
    write_file(dir, "dict-mismatch.zst", frame, n);
    write_file(dir, "dict-other.bin", dict2, dict2_sz);
    printf("dict-mismatch: %lu bytes (frame id=0x%08X, wrong id=0x%08X)\n",
           (unsigned long)n, id1, id2);

    /* truncated: the plain frame cut mid-stream. */
    n = compress_frame(NULL, 0, plain, sizeof plain, 0, -1, 0,
                       frame, sizeof frame, "truncated-source");
    if (n < 8) die("truncated: source frame too small");
    write_file(dir, "truncated.zst", frame, n / 2u);
    printf("truncated: %lu bytes (from %lu)\n", (unsigned long)(n / 2u),
           (unsigned long)n);

    /* lying FCS: a single-segment frame declares 1 (and 0) bytes but its one
     * raw block writes 10. Both must be decode errors (rc3), never OOB/hang. */
    {
        size_t declared_sz;
        size_t j;
        size_t block_bytes = 10u;
        size_t bh = (block_bytes << 3) | 1u;
        for (j = 0; j < 2u; j++) {
            const char *name = (j == 0) ? "fcs-lie-1.zst" : "fcs-lie-0.zst";
            declared_sz = (j == 0) ? 1u : 0u;
            frame[0] = 0x28;
            frame[1] = 0xB5;
            frame[2] = 0x2F;
            frame[3] = 0xFD;
            frame[4] = 0x20; /* single_segment=1, fcs_flag=0 (1-byte FCS) */
            frame[5] = (unsigned char)declared_sz;
            frame[6] = (unsigned char)(bh & 0xFFu);
            frame[7] = (unsigned char)((bh >> 8) & 0xFFu);
            frame[8] = (unsigned char)((bh >> 16) & 0xFFu);
            for (i = 0; i < (unsigned)block_bytes; i++)
                frame[9 + i] = (unsigned char)('B' + i);
            n = 9u + block_bytes;
            write_file(dir, name, frame, n);
            printf("lying FCS: %s %lu bytes (declared %lu, raw block %lu)\n",
                   name, (unsigned long)n, (unsigned long)declared_sz,
                   (unsigned long)block_bytes);
        }
    }

    return 0;
}
