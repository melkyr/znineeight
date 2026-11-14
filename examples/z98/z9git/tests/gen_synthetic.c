/* gen_synthetic.c -- dev-time generator for the z9git synthetic fixtures.
 *
 * The unit tier never regenerates fixtures; they are committed.  This program
 * writes two tiny bare git object directories from scratch:
 *
 *   <out>/hybrid_repo/          a pack with ONE REF_DELTA entry whose base is
 *                               NOT in the pack but in the loose layout.
 *                               Real git cannot leave a thin pack in an object
 *                               store, so the pack and idx v2 are emitted
 *                               directly here.  The base object file is
 *                               zlib("blob <len>\0" + base).  The delta
 *                               appends a suffix to the base (one COPY of the
 *                               whole base followed by one INSERT).
 *
 *   <out>/large_offset_repo/    a pack with one normal blob whose idx v2
 *                               31-bit offset field has the MSB set and points
 *                               at large-offset slot 0.  Slot 0 holds the real
 *                               offset (12).  This exercises the 8-byte
 *                               indirection path without needing a >2 GiB pack.
 *
 * It also writes the matching cat-file-style goldens:
 *   <out>/goldens/hybrid.catfile
 *   <out>/goldens/large_offset.catfile
 *
 * Build/run (from the repo root):
 *   gcc -O2 -o /tmp/gen_z9git_synth \
 *       examples/z98/z9git/tests/gen_synthetic.c -lz
 *   /tmp/gen_z9git_synth examples/z98/z9git/tests/testdata
 *
 * SHA-1 and CRC-32 are local/ zlib, so no external hash tool is involved.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <zlib.h>

/* ------------------------------------------------------------------ SHA-1 */
typedef struct {
    uint32_t h[5];
    uint64_t bits;
    unsigned char buf[64];
    size_t used;
} Sha1;

static uint32_t rol32(uint32_t v, unsigned n) {
    return (v << n) | (v >> (32 - n));
}

static void sha1_block(Sha1 *s, const unsigned char *p) {
    uint32_t w[80];
    uint32_t a, b, c, d, e;
    int i;
    for (i = 0; i < 16; i++) {
        w[i] = ((uint32_t)p[i * 4] << 24) | ((uint32_t)p[i * 4 + 1] << 16) |
               ((uint32_t)p[i * 4 + 2] << 8) | (uint32_t)p[i * 4 + 3];
    }
    for (i = 16; i < 80; i++) w[i] = rol32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    a = s->h[0]; b = s->h[1]; c = s->h[2]; d = s->h[3]; e = s->h[4];
    for (i = 0; i < 80; i++) {
        uint32_t f, k, t;
        if (i < 20) { f = (b & c) | ((~b) & d); k = 0x5A827999u; }
        else if (i < 40) { f = b ^ c ^ d; k = 0x6ED9EBA1u; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDCu; }
        else { f = b ^ c ^ d; k = 0xCA62C1D6u; }
        t = rol32(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rol32(b, 30); b = a; a = t;
    }
    s->h[0] += a; s->h[1] += b; s->h[2] += c; s->h[3] += d; s->h[4] += e;
}

static void sha1_init(Sha1 *s) {
    s->h[0] = 0x67452301u; s->h[1] = 0xEFCDAB89u; s->h[2] = 0x98BADCFEu;
    s->h[3] = 0x10325476u; s->h[4] = 0xC3D2E1F0u;
    s->bits = 0; s->used = 0;
}

static void sha1_update(Sha1 *s, const void *data, size_t n) {
    const unsigned char *p = (const unsigned char *)data;
    s->bits += (uint64_t)n * 8u;
    while (n != 0) {
        size_t take = 64 - s->used;
        if (take > n) take = n;
        memcpy(s->buf + s->used, p, take);
        s->used += take; p += take; n -= take;
        if (s->used == 64) { sha1_block(s, s->buf); s->used = 0; }
    }
}

static void sha1_final(Sha1 *s, unsigned char out[20]) {
    unsigned char pad[72];
    size_t padn;
    uint64_t bits = s->bits;
    int i;
    pad[0] = 0x80;
    padn = (s->used < 56) ? (56 - s->used) : (120 - s->used);
    memset(pad + 1, 0, padn - 1);
    sha1_update(s, pad, padn);
    for (i = 0; i < 8; i++) pad[i] = (unsigned char)(bits >> (56 - i * 8));
    sha1_update(s, pad, 8);
    for (i = 0; i < 5; i++) {
        out[i * 4] = (unsigned char)(s->h[i] >> 24);
        out[i * 4 + 1] = (unsigned char)(s->h[i] >> 16);
        out[i * 4 + 2] = (unsigned char)(s->h[i] >> 8);
        out[i * 4 + 3] = (unsigned char)s->h[i];
    }
}

static void sha1_buf(const void *data, size_t n, unsigned char out[20]) {
    Sha1 s;
    sha1_init(&s);
    sha1_update(&s, data, n);
    sha1_final(&s, out);
}

/* ------------------------------------------------------------- utilities */
static void die(const char *what) {
    fprintf(stderr, "gen_synthetic: %s\n", what);
    exit(1);
}

static void ensure_dir(const char *path) {
    char tmp[4096];
    size_t n = strlen(path);
    size_t i;
    if (n >= sizeof tmp) die("path too long");
    memcpy(tmp, path, n + 1);
    for (i = 1; i <= n; i++) {
        if (tmp[i] == '/' || tmp[i] == '\0') {
            char save = tmp[i];
            tmp[i] = '\0';
            if (mkdir(tmp, 0777) != 0) {
                struct stat st;
                if (stat(tmp, &st) != 0 || !S_ISDIR(st.st_mode)) die("mkdir failed");
            }
            tmp[i] = save;
        }
    }
}

static void write_file(const char *path, const void *data, size_t n) {
    FILE *f = fopen(path, "wb");
    if (f == NULL) die("cannot open output");
    if (n != 0 && fwrite(data, 1, n, f) != n) die("short write");
    if (fclose(f) != 0) die("close failed");
}

static void write_hex_line(FILE *f, const unsigned char id[20],
                           const char *type, const unsigned char *data, size_t n) {
    int i;
    for (i = 0; i < 20; i++) fprintf(f, "%02x", id[i]);
    fprintf(f, " %s %lu\n", type, (unsigned long)n);
    if (n != 0) fwrite(data, 1, n, f);
}

static void write_id_line(FILE *f, const unsigned char id[20]) {
    int i;
    for (i = 0; i < 20; i++) fprintf(f, "%02x", id[i]);
    fputc('\n', f);
}

static size_t put_varint(unsigned char *dst, uint64_t v) {
    size_t n = 0;
    do {
        unsigned char b = (unsigned char)(v & 0x7F);
        v >>= 7;
        if (v != 0) b |= 0x80;
        dst[n++] = b;
    } while (v != 0);
    return n;
}

static size_t put_entry_header(unsigned char *dst, unsigned type, uint64_t size) {
    size_t n = 0;
    unsigned char b = (unsigned char)((type << 4) | (size & 0x0F));
    size >>= 4;
    if (size != 0) b |= 0x80;
    dst[n++] = b;
    while (size != 0) {
        b = (unsigned char)(size & 0x7F);
        size >>= 7;
        if (size != 0) b |= 0x80;
        dst[n++] = b;
    }
    return n;
}

static size_t make_object_bytes(unsigned char *dst, size_t cap,
                                const char *type, const unsigned char *data, size_t n,
                                unsigned char id[20]) {
    int hdr = snprintf((char *)dst, cap, "%s %lu", type, (unsigned long)n);
    if (hdr < 0 || (size_t)hdr + 1 + n > cap) die("object too large");
    dst[hdr] = 0;
    memcpy(dst + hdr + 1, data, n);
    sha1_buf(dst, (size_t)hdr + 1 + n, id);
    return (size_t)hdr + 1 + n;
}

static size_t zlib_bytes(const unsigned char *src, size_t n, unsigned char *dst, size_t cap) {
    uLongf out = (uLongf)cap;
    if (compress2(dst, &out, src, (uLong)n, 9) != Z_OK) die("zlib compress failed");
    return (size_t)out;
}

static size_t put_be32(unsigned char *p, uint32_t v) {
    p[0] = (unsigned char)(v >> 24); p[1] = (unsigned char)(v >> 16);
    p[2] = (unsigned char)(v >> 8); p[3] = (unsigned char)v;
    return 4;
}

static size_t put_be64(unsigned char *p, uint64_t v) {
    int i;
    for (i = 0; i < 8; i++) p[i] = (unsigned char)(v >> (56 - i * 8));
    return 8;
}

/* ----------------------------------------------------- pack/idx synthesis */
static void make_idx(unsigned char *idx, size_t *idx_len,
                     const unsigned char id[20], uint32_t crc, uint32_t offset,
                     uint64_t large_offset, int use_large,
                     const unsigned char pack_id[20]) {
    size_t p = 0;
    uint32_t fan[256];
    int i;
    unsigned char *names, *crcs, *offs, *large;

    memset(fan, 0, sizeof fan);
    for (i = (int)id[0]; i < 256; i++) fan[i] = 1;

    idx[p++] = 0xFF; idx[p++] = 't'; idx[p++] = 'O'; idx[p++] = 'c';
    p += put_be32(idx + p, 2);
    for (i = 0; i < 256; i++) p += put_be32(idx + p, fan[i]);

    names = idx + p; memcpy(names, id, 20); p += 20;
    crcs = idx + p; p += put_be32(crcs, crc);
    offs = idx + p;
    if (use_large) p += put_be32(offs, offset | 0x80000000u);
    else p += put_be32(offs, offset);
    large = idx + p;
    if (use_large) p += put_be64(large, large_offset);

    memcpy(idx + p, pack_id, 20); p += 20;
    sha1_buf(idx, p, idx + p); p += 20;
    *idx_len = p;
}

static void gen_hybrid(const char *td) {
    static const char base[] = "hybrid loose base object\n";
    static const char suffix[] = "target suffix appended by REF_DELTA\n";
    unsigned char target[256], objbuf[512], delta[256], comp[512];
    unsigned char base_obj[512], base_comp[512];
    unsigned char pack[2048], entry[1024], idx[2048];
    unsigned char base_id[20], target_id[20], pack_id[20], loose_id[20];
    unsigned char path[4096];
    size_t base_n = sizeof(base) - 1, suffix_n = sizeof(suffix) - 1;
    size_t target_n = base_n + suffix_n, obj_n, delta_n, comp_n;
    size_t entry_n = 0, pack_n = 0, idx_n;
    uint32_t crc;
    FILE *g;

    memcpy(target, base, base_n);
    memcpy(target + base_n, suffix, suffix_n);
    make_object_bytes(objbuf, sizeof objbuf, "blob", base, base_n, base_id);
    make_object_bytes(objbuf, sizeof objbuf, "blob", target, target_n, target_id);
    (void)loose_id;

    delta_n = 0;
    delta_n += put_varint(delta + delta_n, (uint64_t)base_n);
    delta_n += put_varint(delta + delta_n, (uint64_t)target_n);
    if (base_n > 255) die("base too large for one copy");
    delta[delta_n++] = 0x90;                 /* COPY, one size byte, offset 0 */
    delta[delta_n++] = (unsigned char)base_n;
    if (suffix_n > 127) die("suffix too large for one insert");
    delta[delta_n++] = (unsigned char)suffix_n; /* INSERT */
    memcpy(delta + delta_n, suffix, suffix_n);
    delta_n += suffix_n;
    comp_n = zlib_bytes(delta, delta_n, comp, sizeof comp);

    /* entry header: REF_DELTA (7), size = delta_n */
    entry_n += put_entry_header(entry + entry_n, 7, delta_n);
    memcpy(entry + entry_n, base_id, 20); entry_n += 20;
    memcpy(entry + entry_n, comp, comp_n); entry_n += comp_n;
    crc = (uint32_t)crc32(0L, entry, (uInt)entry_n);

    memcpy(pack + pack_n, "PACK", 4); pack_n += 4;
    pack_n += put_be32(pack + pack_n, 2);
    pack_n += put_be32(pack + pack_n, 1);
    if (pack_n + entry_n + 20 > sizeof pack) die("pack too large");
    memcpy(pack + pack_n, entry, entry_n); pack_n += entry_n;
    sha1_buf(pack, pack_n, pack + pack_n); pack_n += 20;
    memcpy(pack_id, pack + pack_n - 20, 20);

    make_idx(idx, &idx_n, target_id, crc, 12, 0, 0, pack_id);

    snprintf(path, sizeof path, "%s/hybrid_repo/objects/pack", td);
    ensure_dir(path);
    snprintf(path, sizeof path, "%s/hybrid_repo/objects/pack/pack-hybrid.pack", td);
    write_file(path, pack, pack_n);
    snprintf(path, sizeof path, "%s/hybrid_repo/objects/pack/pack-hybrid.idx", td);
    write_file(path, idx, idx_n);

    obj_n = make_object_bytes(base_obj, sizeof base_obj, "blob", base, base_n, loose_id);
    (void)obj_n;
    comp_n = zlib_bytes(base_obj, strlen((char *)base_obj) + 1 + base_n, base_comp, sizeof base_comp);
    snprintf(path, sizeof path, "%s/hybrid_repo/objects/%02x", td, base_id[0]);
    ensure_dir(path);
    snprintf(path, sizeof path, "%s/hybrid_repo/objects/%02x/%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
             td, base_id[0], base_id[1], base_id[2], base_id[3], base_id[4], base_id[5],
             base_id[6], base_id[7], base_id[8], base_id[9], base_id[10], base_id[11],
             base_id[12], base_id[13], base_id[14], base_id[15], base_id[16], base_id[17],
             base_id[18], base_id[19]);
    write_file(path, base_comp, comp_n);

    snprintf(path, sizeof path, "%s/goldens", td);
    ensure_dir(path);
    snprintf(path, sizeof path, "%s/goldens/hybrid.catfile", td);
    g = fopen(path, "wb");
    if (g == NULL) die("cannot write hybrid golden");
    write_hex_line(g, target_id, "blob", target, target_n);
    fputc('\n', g);
    write_hex_line(g, base_id, "blob", base, base_n);
    fclose(g);
}

static void gen_large_offset(const char *td) {
    static const char data[] = "large offset indirection fixture\n";
    unsigned char objbuf[256], comp[256], pack[1024], entry[512], idx[2048];
    unsigned char id[20], pack_id[20], path[4096];
    size_t n = sizeof(data) - 1, entry_n = 0, pack_n = 0, idx_n, obj_n, comp_n;
    uint32_t crc;
    FILE *g;

    obj_n = make_object_bytes(objbuf, sizeof objbuf, "blob", data, n, id);
    (void)obj_n;
    comp_n = zlib_bytes(data, n, comp, sizeof comp);

    entry_n += put_entry_header(entry + entry_n, 3, n);
    memcpy(entry + entry_n, comp, comp_n); entry_n += comp_n;
    crc = (uint32_t)crc32(0L, entry, (uInt)entry_n);

    memcpy(pack + pack_n, "PACK", 4); pack_n += 4;
    pack_n += put_be32(pack + pack_n, 2);
    pack_n += put_be32(pack + pack_n, 1);
    memcpy(pack + pack_n, entry, entry_n); pack_n += entry_n;
    sha1_buf(pack, pack_n, pack + pack_n); pack_n += 20;
    memcpy(pack_id, pack + pack_n - 20, 20);

    make_idx(idx, &idx_n, id, crc, 0x80000000u, 12, 1, pack_id);

    snprintf(path, sizeof path, "%s/large_offset_repo/objects/pack", td);
    ensure_dir(path);
    snprintf(path, sizeof path, "%s/large_offset_repo/objects/pack/pack-large.pack", td);
    write_file(path, pack, pack_n);
    snprintf(path, sizeof path, "%s/large_offset_repo/objects/pack/pack-large.idx", td);
    write_file(path, idx, idx_n);

    snprintf(path, sizeof path, "%s/goldens", td);
    ensure_dir(path);
    snprintf(path, sizeof path, "%s/goldens/large_offset.catfile", td);
    g = fopen(path, "wb");
    if (g == NULL) die("cannot write large-offset golden");
    write_hex_line(g, id, "blob", (const unsigned char *)data, n);
    fclose(g);
}

typedef struct {
    unsigned char id[20];
    uint32_t crc;
    uint32_t off;
    uint32_t large_index;
    int use_large;
    uint64_t large_off;
} IdxEnt;

static void make_idx2(unsigned char *idx, size_t *idx_len, IdxEnt *e, int n,
                      const unsigned char pack_id[20]) {
    size_t p = 0;
    uint32_t fan[256];
    uint32_t running = 0;
    int i, j, li;

    for (i = 0; i < n; i++) {
        for (j = i + 1; j < n; j++) {
            if (memcmp(e[i].id, e[j].id, 20) > 0) {
                IdxEnt t = e[i];
                e[i] = e[j];
                e[j] = t;
            }
        }
    }

    memset(fan, 0, sizeof fan);
    for (i = 0; i < n; i++) fan[e[i].id[0]]++;
    for (i = 0; i < 256; i++) {
        running += fan[i];
        fan[i] = running;
    }

    idx[p++] = 0xFF; idx[p++] = 't'; idx[p++] = 'O'; idx[p++] = 'c';
    p += put_be32(idx + p, 2);
    for (i = 0; i < 256; i++) p += put_be32(idx + p, fan[i]);
    for (i = 0; i < n; i++) { memcpy(idx + p, e[i].id, 20); p += 20; }
    for (i = 0; i < n; i++) p += put_be32(idx + p, e[i].crc);
    for (i = 0; i < n; i++) {
        if (e[i].use_large) p += put_be32(idx + p, e[i].large_index | 0x80000000u);
        else p += put_be32(idx + p, e[i].off);
    }
    for (li = 0; li < n; li++) {
        for (i = 0; i < n; i++) {
            if (e[i].use_large && (int)e[i].large_index == li) {
                p += put_be64(idx + p, e[i].large_off);
            }
        }
    }
    memcpy(idx + p, pack_id, 20); p += 20;
    sha1_buf(idx, p, idx + p); p += 20;
    *idx_len = p;
}

static void gen_large_offset_delta(const char *td) {
    static const char base[] = "base";
    static const char target[] = "ok";
    unsigned char objbuf[256], base_comp[256], delta_comp[256];
    unsigned char base_entry[512], delta_entry[512], pack[2048], idx[4096];
    unsigned char base_id[20], target_id[20], pack_id[20], path[4096];
    size_t base_n = sizeof(base) - 1, target_n = sizeof(target) - 1;
    size_t base_comp_n, delta_comp_n, delta_n = 0;
    size_t base_entry_n = 0, delta_entry_n = 0, pack_n = 0, idx_n;
    uint32_t base_crc, delta_crc;
    uint64_t target_off;
    unsigned char delta[64];
    IdxEnt ents[2];
    FILE *g;

    make_object_bytes(objbuf, sizeof objbuf, "blob",
                      (const unsigned char *)base, base_n, base_id);
    make_object_bytes(objbuf, sizeof objbuf, "blob",
                      (const unsigned char *)target, target_n, target_id);

    /* Malicious delta: COPY offset 0xFFFFFFFE, size 4.  offset+size wraps a
     * 32-bit value to 2; the decoder must reject it as Corrupt, never wrap. */
    delta_n += put_varint(delta + delta_n, (uint64_t)base_n);
    delta_n += put_varint(delta + delta_n, (uint64_t)target_n);
    delta[delta_n++] = 0x9F; /* COPY with 4 offset bytes and 1 size byte */
    delta[delta_n++] = 0xFE;
    delta[delta_n++] = 0xFF;
    delta[delta_n++] = 0xFF;
    delta[delta_n++] = 0xFF;
    delta[delta_n++] = 0x04;
    delta_comp_n = zlib_bytes(delta, delta_n, delta_comp, sizeof delta_comp);

    base_comp_n = zlib_bytes((const unsigned char *)base, base_n,
                             base_comp, sizeof base_comp);
    base_entry_n += put_entry_header(base_entry + base_entry_n, 3, base_n);
    memcpy(base_entry + base_entry_n, base_comp, base_comp_n);
    base_entry_n += base_comp_n;
    base_crc = (uint32_t)crc32(0L, base_entry, (uInt)base_entry_n);
    target_off = (uint64_t)12 + (uint64_t)base_entry_n;

    delta_entry_n += put_entry_header(delta_entry + delta_entry_n, 7, delta_n);
    memcpy(delta_entry + delta_entry_n, base_id, 20); delta_entry_n += 20;
    memcpy(delta_entry + delta_entry_n, delta_comp, delta_comp_n);
    delta_entry_n += delta_comp_n;
    delta_crc = (uint32_t)crc32(0L, delta_entry, (uInt)delta_entry_n);

    memcpy(pack + pack_n, "PACK", 4); pack_n += 4;
    pack_n += put_be32(pack + pack_n, 2);
    pack_n += put_be32(pack + pack_n, 2);
    if (pack_n + base_entry_n + delta_entry_n + 20 > sizeof pack) die("pack too large");
    memcpy(pack + pack_n, base_entry, base_entry_n); pack_n += base_entry_n;
    memcpy(pack + pack_n, delta_entry, delta_entry_n); pack_n += delta_entry_n;
    sha1_buf(pack, pack_n, pack + pack_n); pack_n += 20;
    memcpy(pack_id, pack + pack_n - 20, 20);

    memcpy(ents[0].id, base_id, 20);
    ents[0].crc = base_crc;
    ents[0].off = 12;
    ents[0].use_large = 0;
    ents[0].large_index = 0;
    ents[0].large_off = 0;
    memcpy(ents[1].id, target_id, 20);
    ents[1].crc = delta_crc;
    ents[1].off = (uint32_t)target_off;
    ents[1].use_large = 1;
    ents[1].large_index = 0; /* idx offset field = 0x80000000 */
    ents[1].large_off = target_off;
    make_idx2(idx, &idx_n, ents, 2, pack_id);

    snprintf(path, sizeof path, "%s/large_offset_delta_repo/objects/pack", td);
    ensure_dir(path);
    snprintf(path, sizeof path, "%s/large_offset_delta_repo/objects/pack/pack-large-delta.pack", td);
    write_file(path, pack, pack_n);
    snprintf(path, sizeof path, "%s/large_offset_delta_repo/objects/pack/pack-large-delta.idx", td);
    write_file(path, idx, idx_n);

    snprintf(path, sizeof path, "%s/goldens", td);
    ensure_dir(path);
    snprintf(path, sizeof path, "%s/goldens/large_offset_delta.ids", td);
    g = fopen(path, "wb");
    if (g == NULL) die("cannot write large-offset-delta ids");
    write_id_line(g, target_id);
    write_id_line(g, base_id);
    fclose(g);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <testdata-dir>\n", argv[0]);
        return 1;
    }
    gen_hybrid(argv[1]);
    gen_large_offset(argv[1]);
    gen_large_offset_delta(argv[1]);
    return 0;
}
