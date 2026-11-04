/* gen_zstd_fixtures.c -- dev-time generator for the std_zstd dictionary
 * fixtures (Task 1, Phase 3).
 *
 * Links against the system libzstd (1.5.4 in the dev environment) and writes
 * the self-contained `data.zig` byte-array modules used by
 * repro/mi_matrix/stdlib_zstd_dict_{basic,hist,raw,mismatch}_xmod.
 *
 * Build/run (from the repo root):
 *   gcc -O2 -o /tmp/gen_zstd_fixtures scripts/fixtures/gen_zstd_fixtures.c -lzstd
 *   /tmp/gen_zstd_fixtures .
 *
 * The output is deterministic (fixed xorshift seed, fixed samples, fixed dict
 * ids), so regenerating on libzstd 1.5.4 reproduces byte-identical fixtures.
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
    fprintf(stderr, "gen_zstd_fixtures: %s\n", what);
    exit(1);
}

static size_t compress_with_dict(const unsigned char *dict, size_t dict_sz,
                                 const unsigned char *src, size_t src_sz,
                                 int window_log, int content_size_flag,
                                 unsigned char *dst, size_t cap,
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
    if (ZSTD_isError(ZSTD_CCtx_loadDictionary(cctx, dict, dict_sz)))
        die("loadDictionary failed");

    n = ZSTD_compress2(cctx, dst, cap, src, src_sz);
    if (ZSTD_isError(n)) {
        fprintf(stderr, "gen_zstd_fixtures: compress (%s): %s\n", what,
                ZSTD_getErrorName(n));
        exit(1);
    }
    ZSTD_freeCCtx(cctx);
    return n;
}

static void emit_array(FILE *f, const char *name, const unsigned char *data,
                       size_t n) {
    size_t i;
    fprintf(f, "pub const %s = [_]u8{\n", name);
    for (i = 0; i < n; i++) {
        if ((i % 12u) == 0) fprintf(f, "    ");
        fprintf(f, "0x%02X,", (unsigned)data[i]);
        if ((i % 12u) == 11u || i + 1u == n) fprintf(f, "\n");
        else fprintf(f, " ");
    }
    fprintf(f, "};\n\n");
    fprintf(f, "pub fn %s_slice() []const u8 { return %s[0..]; }\n\n",
            name, name);
}

static FILE *open_data(const char *root, const char *fixture) {
    char path[4096];
    FILE *f;
    snprintf(path, sizeof path, "%s/repro/mi_matrix/%s/data.zig", root, fixture);
    f = fopen(path, "wb");
    if (f == NULL) {
        fprintf(stderr, "gen_zstd_fixtures: cannot write %s\n", path);
        exit(1);
    }
    return f;
}

int main(int argc, char **argv) {
    const char *root = (argc > 1) ? argv[1] : ".";
    unsigned char samples[NSAMP * SAMP_SZ];
    size_t sample_sizes[NSAMP];
    unsigned char dict1[32768];
    unsigned char dict2[32768];
    unsigned char custom[CUSTOM_SZ];
    unsigned char plain[SAMP_SZ * 2u];
    unsigned char frame[262144];
    unsigned char buf[262144];
    unsigned char wrong_dict[32768];
    unsigned id1, id2;
    size_t dict1_sz, dict2_sz, custom_off, plain_sz, n;
    unsigned i;
    FILE *f;

    /* Deterministic training corpus: each sample is a distinct text blob. */
    for (i = 0; i < NSAMP; i++) {
        fill_text(samples + (size_t)i * SAMP_SZ, SAMP_SZ, i + 1u);
        sample_sizes[i] = SAMP_SZ;
    }

    dict1_sz = ZDICT_trainFromBuffer(dict1, sizeof dict1, samples,
                                     sample_sizes, NSAMP);
    if (ZDICT_isError(dict1_sz)) {
        fprintf(stderr, "gen_zstd_fixtures: trainFromBuffer: %s\n",
                ZDICT_getErrorName(dict1_sz));
        return 1;
    }
    id1 = ZSTD_getDictID_fromDict(dict1, dict1_sz);

    /* Custom content with a unique random tail for dictionary-history tests. */
    fill_random(custom, CUSTOM_SZ);
    {
        ZDICT_params_t p;
        memset(&p, 0, sizeof p);
        p.compressionLevel = 3;
        p.notificationLevel = 0;
        p.dictID = 0x0BADF00Du;
        dict2_sz = ZDICT_finalizeDictionary(dict2, sizeof dict2, custom,
                                            CUSTOM_SZ, samples, sample_sizes,
                                            NSAMP, p);
        if (ZDICT_isError(dict2_sz)) {
            fprintf(stderr, "gen_zstd_fixtures: finalizeDictionary: %s\n",
                    ZDICT_getErrorName(dict2_sz));
            return 1;
        }
    }
    id2 = ZSTD_getDictID_fromDict(dict2, dict2_sz);
    custom_off = ZDICT_getDictHeaderSize(dict2, dict2_sz);
    if (ZDICT_isError(custom_off)) die("getDictHeaderSize failed");
    if (custom_off + CUSTOM_SZ != dict2_sz) {
        fprintf(stderr, "gen_zstd_fixtures: dict2 content is not our custom "
                "content (off=%lu len=%lu, want %lu)\n",
                (unsigned long)custom_off, (unsigned long)dict2_sz,
                (unsigned long)(custom_off + CUSTOM_SZ));
        return 1;
    }
    if (memcmp(dict2 + custom_off, custom, CUSTOM_SZ) != 0)
        die("dict2 content mismatch");
    if (id1 == 0 || id2 == 0 || id1 == id2)
        die("unexpected dictionary ids");

    printf("dict1: %lu bytes id=0x%08X\n", (unsigned long)dict1_sz, id1);
    printf("dict2: %lu bytes id=0x%08X content_off=%lu\n",
           (unsigned long)dict2_sz, id2, (unsigned long)custom_off);

    /* (a) basic: magic dict from ZDICT_trainFromBuffer, plain text frame. */
    memcpy(plain, samples + 0 * SAMP_SZ, SAMP_SZ);
    memcpy(plain + SAMP_SZ, samples + 1 * SAMP_SZ, SAMP_SZ);
    plain_sz = sizeof plain;
    n = compress_with_dict(dict1, dict1_sz, plain, plain_sz, 0, -1,
                           frame, sizeof frame, "basic");
    f = open_data(root, "stdlib_zstd_dict_basic_xmod");
    emit_array(f, "dict", dict1, dict1_sz);
    emit_array(f, "frame", frame, n);
    emit_array(f, "want", plain, plain_sz);
    fclose(f);
    printf("basic frame: %lu bytes (plain %lu)\n", (unsigned long)n,
           (unsigned long)plain_sz);

    /* (b) hist: dict2 content, first block matches the last window bytes.
     * contentSizeFlag=0 keeps the frame non-single-segment so the decoder
     * honours ZSTD_c_windowLog and only the last min(content,window) dict
     * bytes are matchable. */
    {
        const int wlogs[2] = { 10, 11 };
        FILE *hf = open_data(root, "stdlib_zstd_dict_hist_xmod");
        emit_array(hf, "dict", dict2, dict2_sz);
        for (i = 0; i < 2u; i++) {
            size_t w = (size_t)1u << wlogs[i];
            char name[16];
            n = compress_with_dict(dict2, dict2_sz, custom + CUSTOM_SZ - w, w,
                                   wlogs[i], 0, buf, sizeof buf, "hist");
            snprintf(name, sizeof name, "frame_w%d", wlogs[i]);
            emit_array(hf, name, buf, n);
            printf("hist wlog %d frame: %lu bytes (payload %lu)\n", wlogs[i],
                   (unsigned long)n, (unsigned long)w);
        }
        fclose(hf);
    }

    /* (c) raw-content dict (no magic, no id): dict-id-0 frame. */
    {
        size_t w = 1024u;
        n = compress_with_dict(custom, CUSTOM_SZ, custom + CUSTOM_SZ - w, w,
                               10, 0, frame, sizeof frame, "raw");
        f = open_data(root, "stdlib_zstd_dict_raw_xmod");
        emit_array(f, "dict", custom, CUSTOM_SZ);
        emit_array(f, "frame", frame, n);
        fclose(f);
        printf("raw frame: %lu bytes (payload %lu)\n", (unsigned long)n,
               (unsigned long)w);
    }

    /* (d) mismatch: basic-frame dict id vs. an unrelated magic dictionary. */
    {
        memcpy(wrong_dict, dict2, dict2_sz);
        n = compress_with_dict(dict1, dict1_sz, plain, plain_sz, 0, -1,
                               frame, sizeof frame, "mismatch");
        f = open_data(root, "stdlib_zstd_dict_mismatch_xmod");
        emit_array(f, "frame", frame, n);
        emit_array(f, "wrong_dict", wrong_dict, dict2_sz);
        fclose(f);
        printf("mismatch frame: %lu bytes id=0x%08X wrong id=0x%08X\n",
               (unsigned long)n, id1, id2);
    }

    return 0;
}
