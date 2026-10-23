/*
 * ref.c — C89 reference capture for the WireGuard NoiseIK initiator.
 *
 * Protocol logic is a standalone port of wireguard-lwip (smartalock),
 * Copyright (c) 2021 Daniel Hope (www.floorsense.nz), BSD-3-Clause.
 * The crypto sources under crypto/refc are vendored from the same project
 * (BLAKE2s RFC 7693 reference, ChaCha20/Poly1305, X25519 from STROBE; see
 * crypto/refc/x25519-license.txt); only `//` comments and `static inline`
 * spelling were adapted for strict C89, with no algorithmic changes.  This
 * file keeps only the initiator initiation/response subset needed to capture
 * the M6 Task 1 vectors.
 *
 * Build (self-contained; the includes pull in the vendored sources):
 *   gcc -m32 -std=c89 -O0 ref.c -o ref
 *
 * Usage:
 *   ./ref --crosscheck   read `seed wall_unix_ns` lines, print initiation hex
 *   ./ref --vectors      print the fixed-key initiation/response/transport keys
 *   ./ref [seed wall]    same as --vectors with optional override
 */

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>

#include "crypto.h"
#include "crypto/refc/blake2s.c"
#include "crypto/refc/chacha20.c"
#include "crypto/refc/poly1305-donna.c"
#include "crypto/refc/chacha20poly1305.c"
#include "crypto/refc/x25519.c"

#define WG_INIT_LEN 148
#define WG_RESP_LEN 92
#define WG_KEY_LEN 32
#define WG_HASH_LEN 32
#define WG_TAG_LEN 16
#define WG_MAC_LEN 16
#define WG_TAI64N_LEN 12
#define WG_COOKIE_LEN 16
#define WG_COOKIE_NONCE_LEN 24
#define WG_COOKIE_REPLY_LEN 64
#define WG_TRANSPORT_HDR_LEN 16
#define WG_TRANSPORT_MAX_PT 2048
#define WG_REJECT_AFTER_MESSAGES (0xFFFFFFFFFFFFFFFFULL - (1ULL << 13))

static const uint8_t CONSTRUCTION[37] =
    "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s";
static const uint8_t IDENTIFIER[34] =
    "WireGuard v1 zx2c4 Jason@zx2c4.com";
static const uint8_t LABEL_MAC1[8] = "mac1----";
static const uint8_t LABEL_COOKIE[8] = "cookie--";
static const uint8_t ZERO_KEY[WG_KEY_LEN] = { 0 };

void crypto_zero(void *dest, size_t len)
{
    volatile uint8_t *p = (volatile uint8_t *)dest;
    while (len--) {
        *p++ = 0;
    }
}

bool crypto_equal(const void *a, const void *b, size_t size)
{
    const uint8_t *pa = (const uint8_t *)a;
    const uint8_t *pb = (const uint8_t *)b;
    uint8_t neq = 0;
    while (size > 0) {
        neq |= *pa++ ^ *pb++;
        size -= 1;
    }
    return neq == 0;
}

static uint64_t rotl64(uint64_t x, unsigned n)
{
    n &= 63u;
    if (n == 0u) return x;
    return (x << n) | (x >> (64u - n));
}

typedef struct {
    uint64_t s[4];
} Xoshiro256;

static Xoshiro256 xoshiro_init(uint64_t seed)
{
    Xoshiro256 r;
    uint64_t x = seed;
    int i;
    for (i = 0; i < 4; i++) {
        uint64_t z;
        x += 0x9E3779B97F4A7C15ULL;
        z = x;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        r.s[i] = z ^ (z >> 31);
    }
    return r;
}

static uint64_t xoshiro_next(Xoshiro256 *r)
{
    uint64_t result = rotl64(r->s[1] * 5ULL, 7) * 9ULL;
    uint64_t t = (r->s[1] & 0x00007FFFFFFFFFFFULL) << 17;
    r->s[2] ^= r->s[0];
    r->s[3] ^= r->s[1];
    r->s[1] ^= r->s[2];
    r->s[0] ^= r->s[3];
    r->s[2] ^= t;
    r->s[3] = rotl64(r->s[3], 45u);
    return result;
}

/* std_tls fillRandom convention: consume one u64 per 8 bytes, big-endian. */
static void fill_random(Xoshiro256 *r, uint8_t *out, size_t len)
{
    size_t i = 0;
    while (i < len) {
        uint64_t v = xoshiro_next(r);
        int j;
        for (j = 0; j < 8 && i < len; j++) {
            out[i++] = (uint8_t)((v >> (8u * (7u - (unsigned)j))) & 0xFFu);
        }
    }
}

static void clamp_private(uint8_t key[WG_KEY_LEN])
{
    key[0] &= 248u;
    key[31] = (uint8_t)((key[31] & 127u) | 64u);
}

static uint32_t next_index(Xoshiro256 *r)
{
    uint32_t v;
    do {
        v = (uint32_t)(xoshiro_next(r) & 0xFFFFFFFFULL);
    } while (v == 0u || v == 0xFFFFFFFFu);
    return v;
}

static void mix_hash(uint8_t hash[WG_HASH_LEN], const uint8_t *src, size_t len)
{
    blake2s_ctx ctx;
    uint8_t prev[WG_HASH_LEN];
    memcpy(prev, hash, WG_HASH_LEN);
    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, prev, WG_HASH_LEN);
    blake2s_update(&ctx, src, len);
    blake2s_final(&ctx, hash);
}

static void hmac_blake2s(uint8_t out[WG_HASH_LEN], const uint8_t *key,
                         size_t key_len, const uint8_t *text, size_t text_len)
{
    blake2s_ctx ctx;
    uint8_t k_ipad[64];
    uint8_t k_opad[64];
    uint8_t tk[WG_HASH_LEN];
    int i;

    if (key_len > 64) {
        blake2s_ctx tctx;
        blake2s_init(&tctx, WG_HASH_LEN, NULL, 0);
        blake2s_update(&tctx, key, key_len);
        blake2s_final(&tctx, tk);
        key = tk;
        key_len = WG_HASH_LEN;
    }

    memset(k_ipad, 0, sizeof(k_ipad));
    memset(k_opad, 0, sizeof(k_opad));
    memcpy(k_ipad, key, key_len);
    memcpy(k_opad, key, key_len);
    for (i = 0; i < 64; i++) {
        k_ipad[i] ^= 0x36u;
        k_opad[i] ^= 0x5cu;
    }

    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, k_ipad, sizeof(k_ipad));
    blake2s_update(&ctx, text, text_len);
    blake2s_final(&ctx, out);

    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, k_opad, sizeof(k_opad));
    blake2s_update(&ctx, out, WG_HASH_LEN);
    blake2s_final(&ctx, out);

    crypto_zero(tk, sizeof(tk));
    crypto_zero(k_ipad, sizeof(k_ipad));
    crypto_zero(k_opad, sizeof(k_opad));
}

static void kdf1(uint8_t tau1[WG_HASH_LEN], const uint8_t ck[WG_HASH_LEN],
                 const uint8_t *data, size_t data_len)
{
    uint8_t tau0[WG_HASH_LEN];
    uint8_t one = 1;
    hmac_blake2s(tau0, ck, WG_HASH_LEN, data, data_len);
    hmac_blake2s(tau1, tau0, WG_HASH_LEN, &one, 1);
    crypto_zero(tau0, sizeof(tau0));
}

static void kdf2(uint8_t tau1[WG_HASH_LEN], uint8_t tau2[WG_HASH_LEN],
                 const uint8_t ck[WG_HASH_LEN],
                 const uint8_t *data, size_t data_len)
{
    uint8_t tau0[WG_HASH_LEN];
    uint8_t input[WG_HASH_LEN + 1];
    hmac_blake2s(tau0, ck, WG_HASH_LEN, data, data_len);
    input[0] = 1;
    hmac_blake2s(tau1, tau0, WG_HASH_LEN, input, 1);
    memcpy(input, tau1, WG_HASH_LEN);
    input[WG_HASH_LEN] = 2;
    hmac_blake2s(tau2, tau0, WG_HASH_LEN, input, WG_HASH_LEN + 1);
    crypto_zero(tau0, sizeof(tau0));
    crypto_zero(input, sizeof(input));
}

static void kdf3(uint8_t tau1[WG_HASH_LEN], uint8_t tau2[WG_HASH_LEN],
                 uint8_t tau3[WG_HASH_LEN], const uint8_t ck[WG_HASH_LEN],
                 const uint8_t *data, size_t data_len)
{
    uint8_t tau0[WG_HASH_LEN];
    uint8_t input[WG_HASH_LEN + 1];
    hmac_blake2s(tau0, ck, WG_HASH_LEN, data, data_len);
    input[0] = 1;
    hmac_blake2s(tau1, tau0, WG_HASH_LEN, input, 1);
    memcpy(input, tau1, WG_HASH_LEN);
    input[WG_HASH_LEN] = 2;
    hmac_blake2s(tau2, tau0, WG_HASH_LEN, input, WG_HASH_LEN + 1);
    memcpy(input, tau2, WG_HASH_LEN);
    input[WG_HASH_LEN] = 3;
    hmac_blake2s(tau3, tau0, WG_HASH_LEN, input, WG_HASH_LEN + 1);
    crypto_zero(tau0, sizeof(tau0));
    crypto_zero(input, sizeof(input));
}

static void mac_key(uint8_t key[WG_HASH_LEN], const uint8_t *pub,
                    const uint8_t *label, size_t label_len)
{
    blake2s_ctx ctx;
    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, label, label_len);
    blake2s_update(&ctx, pub, WG_KEY_LEN);
    blake2s_final(&ctx, key);
}

static void mac16(uint8_t out[WG_MAC_LEN], const uint8_t *msg, size_t len,
                  const uint8_t *key, size_t key_len)
{
    blake2s(out, WG_MAC_LEN, key, key_len, msg, len);
}

static void tai64n_now(uint8_t out[WG_TAI64N_LEN], uint64_t wall_unix_ns)
{
    uint64_t seconds = 0x400000000000000aULL + (wall_unix_ns / 1000000000ULL);
    uint32_t nanos = (uint32_t)(wall_unix_ns % 1000000000ULL);
    int i;
    for (i = 0; i < 8; i++) {
        out[7 - i] = (uint8_t)((seconds >> (8u * (unsigned)i)) & 0xFFu);
    }
    for (i = 0; i < 4; i++) {
        out[11 - i] = (uint8_t)((nanos >> (8u * (unsigned)i)) & 0xFFu);
    }
}

static void store32le(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static uint32_t load32le(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void store64le(uint8_t *p, uint64_t v)
{
    int i;
    for (i = 0; i < 8; i++) {
        p[i] = (uint8_t)((v >> (8u * (unsigned)i)) & 0xFFu);
    }
}

static void aead_encrypt(uint8_t *dst, const uint8_t *src, size_t len,
                         const uint8_t *ad, size_t ad_len,
                         const uint8_t key[WG_KEY_LEN])
{
    chacha20poly1305_encrypt(dst, src, len, ad, ad_len, 0, key);
}

static int aead_decrypt(uint8_t *dst, const uint8_t *src, size_t len,
                        const uint8_t *ad, size_t ad_len,
                        const uint8_t key[WG_KEY_LEN])
{
    return chacha20poly1305_decrypt(dst, src, len, ad, ad_len, 0, key) ? 1 : 0;
}

static void static_public(uint8_t pub[WG_KEY_LEN], const uint8_t priv[WG_KEY_LEN])
{
    (void)x25519(pub, priv, X25519_BASE_POINT, 1);
}

/*
 * Initiator: build message 1.  Mirrors wireguard_create_handshake_initiation,
 * with the caller's xoshiro seed supplying the ephemeral private key and the
 * unique sender index, and wall_unix_ns supplying TAI64N.
 */
static void build_initiation(const uint8_t priv_i[WG_KEY_LEN],
                             const uint8_t pub_i[WG_KEY_LEN],
                             const uint8_t pub_r[WG_KEY_LEN],
                             uint64_t seed, uint64_t wall_unix_ns,
                             const uint8_t *cookie,
                             uint8_t out[WG_INIT_LEN],
                             uint8_t timestamp[WG_TAI64N_LEN])
{
    uint8_t ck[WG_HASH_LEN];
    uint8_t hash[WG_HASH_LEN];
    uint8_t key[WG_KEY_LEN];
    uint8_t eph_priv[WG_KEY_LEN];
    uint8_t remote_dh[WG_KEY_LEN];
    uint8_t label_key[WG_HASH_LEN];
    blake2s_ctx ctx;
    Xoshiro256 rng;
    int i;

    memset(out, 0, WG_INIT_LEN);
    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, CONSTRUCTION, sizeof(CONSTRUCTION));
    blake2s_final(&ctx, ck);
    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, ck, WG_HASH_LEN);
    blake2s_update(&ctx, IDENTIFIER, sizeof(IDENTIFIER));
    blake2s_final(&ctx, hash);

    mix_hash(hash, pub_r, WG_KEY_LEN);

    rng = xoshiro_init(seed);
    fill_random(&rng, eph_priv, WG_KEY_LEN);
    clamp_private(eph_priv);
    (void)x25519(out + 8, eph_priv, X25519_BASE_POINT, 1);

    kdf1(ck, ck, out + 8, WG_KEY_LEN);
    mix_hash(hash, out + 8, WG_KEY_LEN);

    (void)x25519(remote_dh, eph_priv, pub_r, 1);
    kdf2(ck, key, ck, remote_dh, WG_KEY_LEN);
    aead_encrypt(out + 40, pub_i, WG_KEY_LEN, hash, WG_HASH_LEN, key);
    mix_hash(hash, out + 40, WG_KEY_LEN + WG_TAG_LEN);

    (void)x25519(remote_dh, priv_i, pub_r, 1);
    kdf2(ck, key, ck, remote_dh, WG_KEY_LEN);
    tai64n_now(timestamp, wall_unix_ns);
    aead_encrypt(out + 88, timestamp, WG_TAI64N_LEN, hash, WG_HASH_LEN, key);
    mix_hash(hash, out + 88, WG_TAI64N_LEN + WG_TAG_LEN);

    out[0] = 1;
    store32le(out + 4, next_index(&rng));

    mac_key(label_key, pub_r, LABEL_MAC1, sizeof(LABEL_MAC1));
    mac16(out + 116, out, WG_INIT_LEN - 2 * WG_MAC_LEN, label_key, WG_HASH_LEN);

    if (cookie) {
        mac16(out + 132, out, WG_INIT_LEN - WG_MAC_LEN, cookie, WG_MAC_LEN);
    } else {
        for (i = 0; i < WG_MAC_LEN; i++) out[132 + i] = 0;
    }

    crypto_zero(key, sizeof(key));
    crypto_zero(eph_priv, sizeof(eph_priv));
    crypto_zero(remote_dh, sizeof(remote_dh));
}

/*
 * Responder half used only to produce a canned response.  Mirrors
 * wireguard_process_initiation_message + wireguard_create_handshake_response.
 */
static int process_initiation(const uint8_t priv_r[WG_KEY_LEN],
                              const uint8_t pub_r[WG_KEY_LEN],
                              const uint8_t init[WG_INIT_LEN],
                              uint8_t hash[WG_HASH_LEN],
                              uint8_t ck[WG_HASH_LEN],
                              uint8_t remote_eph[WG_KEY_LEN],
                              uint8_t initiator_pub[WG_KEY_LEN])
{
    uint8_t key[WG_KEY_LEN];
    uint8_t dh[WG_KEY_LEN];
    uint8_t timestamp[WG_TAI64N_LEN];
    blake2s_ctx ctx;

    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, CONSTRUCTION, sizeof(CONSTRUCTION));
    blake2s_final(&ctx, ck);
    blake2s_init(&ctx, WG_HASH_LEN, NULL, 0);
    blake2s_update(&ctx, ck, WG_HASH_LEN);
    blake2s_update(&ctx, IDENTIFIER, sizeof(IDENTIFIER));
    blake2s_final(&ctx, hash);

    mix_hash(hash, pub_r, WG_KEY_LEN);
    kdf1(ck, ck, init + 8, WG_KEY_LEN);
    mix_hash(hash, init + 8, WG_KEY_LEN);

    (void)x25519(dh, priv_r, init + 8, 1);
    if (crypto_equal(dh, ZERO_KEY, WG_KEY_LEN)) return 0;
    kdf2(ck, key, ck, dh, WG_KEY_LEN);
    if (!aead_decrypt(initiator_pub, init + 40, WG_KEY_LEN + WG_TAG_LEN,
                      hash, WG_HASH_LEN, key)) return 0;
    mix_hash(hash, init + 40, WG_KEY_LEN + WG_TAG_LEN);

    (void)x25519(dh, priv_r, initiator_pub, 1);
    if (crypto_equal(dh, ZERO_KEY, WG_KEY_LEN)) return 0;
    kdf2(ck, key, ck, dh, WG_KEY_LEN);
    if (!aead_decrypt(timestamp, init + 88, WG_TAI64N_LEN + WG_TAG_LEN,
                      hash, WG_HASH_LEN, key)) return 0;
    mix_hash(hash, init + 88, WG_TAI64N_LEN + WG_TAG_LEN);

    memcpy(remote_eph, init + 8, WG_KEY_LEN);
    crypto_zero(key, sizeof(key));
    crypto_zero(dh, sizeof(dh));
    return 1;
}

static void build_response(const uint8_t initiator_pub[WG_KEY_LEN],
                           const uint8_t hash_in[WG_HASH_LEN],
                           const uint8_t ck_in[WG_HASH_LEN],
                           const uint8_t remote_eph[WG_KEY_LEN],
                           uint32_t receiver, uint32_t sender,
                           uint64_t seed, uint8_t out[WG_RESP_LEN],
                           uint8_t ck_out[WG_HASH_LEN])
{
    uint8_t hash[WG_HASH_LEN];
    uint8_t ck[WG_HASH_LEN];
    uint8_t key[WG_KEY_LEN];
    uint8_t tau[WG_HASH_LEN];
    uint8_t eph_priv[WG_KEY_LEN];
    uint8_t dh[WG_KEY_LEN];
    uint8_t label_key[WG_HASH_LEN];
    Xoshiro256 rng;
    int i;

    memset(out, 0, WG_RESP_LEN);
    memcpy(hash, hash_in, WG_HASH_LEN);
    memcpy(ck, ck_in, WG_HASH_LEN);

    rng = xoshiro_init(seed);
    fill_random(&rng, eph_priv, WG_KEY_LEN);
    clamp_private(eph_priv);
    (void)x25519(out + 12, eph_priv, X25519_BASE_POINT, 1);

    kdf1(ck, ck, out + 12, WG_KEY_LEN);
    mix_hash(hash, out + 12, WG_KEY_LEN);

    (void)x25519(dh, eph_priv, remote_eph, 1);
    kdf1(ck, ck, dh, WG_KEY_LEN);
    (void)x25519(dh, eph_priv, initiator_pub, 1);
    kdf1(ck, ck, dh, WG_KEY_LEN);

    kdf3(ck, tau, key, ck, ZERO_KEY, WG_KEY_LEN);
    mix_hash(hash, tau, WG_HASH_LEN);
    aead_encrypt(out + 44, NULL, 0, hash, WG_HASH_LEN, key);

    out[0] = 2;
    store32le(out + 4, sender);
    store32le(out + 8, receiver);

    mac_key(label_key, initiator_pub, LABEL_MAC1, sizeof(LABEL_MAC1));
    mac16(out + 60, out, WG_RESP_LEN - 2 * WG_MAC_LEN, label_key, WG_HASH_LEN);
    for (i = 0; i < WG_MAC_LEN; i++) out[76 + i] = 0;

    memcpy(ck_out, ck, WG_HASH_LEN);
    crypto_zero(eph_priv, sizeof(eph_priv));
    crypto_zero(dh, sizeof(dh));
    crypto_zero(key, sizeof(key));
}

static void print_hex(const char *label, const uint8_t *p, size_t len)
{
    size_t i;
    printf("%s ", label);
    for (i = 0; i < len; i++) printf("%02x", (unsigned)p[i]);
    putchar('\n');
}

static int parse_u64(const char *s, uint64_t *out)
{
    uint64_t v = 0;
    int any = 0;
    while (*s == ' ' || *s == '\t') s++;
    while (*s >= '0' && *s <= '9') {
        v = v * 10ULL + (uint64_t)(*s - '0');
        s++;
        any = 1;
    }
    if (!any) return 0;
    *out = v;
    return 1;
}

static void print_hex_only(const uint8_t *p, size_t len)
{
    size_t i;
    for (i = 0; i < len; i++) printf("%02x", (unsigned)p[i]);
    putchar('\n');
}

static int hex_nibble(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* Parse a hex token into out; "-" means empty.  Returns byte length or -1. */
static int parse_hex(const char *s, uint8_t *out, size_t out_cap)
{
    size_t n = 0;
    while (*s == ' ' || *s == '\t') s++;
    if (*s == '-') return 0;
    while (s[0] && s[1] && (s[0] != ' ' && s[0] != '\t')) {
        int hi = hex_nibble(s[0]);
        int lo = hex_nibble(s[1]);
        if (hi < 0 || lo < 0 || n >= out_cap) return -1;
        out[n++] = (uint8_t)((hi << 4) | lo);
        s += 2;
    }
    return (int)n;
}

/* Transport data (type 4): header, padded plaintext, ChaCha20-Poly1305 tag. */
static size_t transport_encrypt(uint8_t *out, uint64_t counter,
                                const uint8_t *pt, size_t pt_len,
                                const uint8_t tx[WG_KEY_LEN], uint32_t receiver)
{
    size_t padded = (pt_len + 15u) & ~(size_t)15u;
    memset(out, 0, WG_TRANSPORT_HDR_LEN + padded + WG_TAG_LEN);
    out[0] = 4;
    store32le(out + 4, receiver);
    store64le(out + 8, counter);
    if (pt_len > 0) memcpy(out + WG_TRANSPORT_HDR_LEN, pt, pt_len);
    chacha20poly1305_encrypt(out + WG_TRANSPORT_HDR_LEN,
                             out + WG_TRANSPORT_HDR_LEN, padded,
                             NULL, 0, counter, tx);
    return WG_TRANSPORT_HDR_LEN + padded + WG_TAG_LEN;
}

/* CookieReply (type 3): XChaCha20-Poly1305(enc_cookie, ad = initiation mac1). */
static void build_cookie_reply(uint8_t out[WG_COOKIE_REPLY_LEN],
                               const uint8_t label_cookie_key[WG_HASH_LEN],
                               const uint8_t mac1[WG_MAC_LEN],
                               uint32_t receiver,
                               const uint8_t cookie_secret[WG_KEY_LEN],
                               const uint8_t nonce[WG_COOKIE_NONCE_LEN])
{
    uint8_t cookie[WG_COOKIE_LEN];
    memset(out, 0, WG_COOKIE_REPLY_LEN);
    out[0] = 3;
    store32le(out + 4, receiver);
    memcpy(out + 8, nonce, WG_COOKIE_NONCE_LEN);
    mac16(cookie, NULL, 0, cookie_secret, WG_KEY_LEN);
    wireguard_xaead_encrypt(out + 32, cookie, WG_COOKIE_LEN,
                            mac1, WG_MAC_LEN, nonce, label_cookie_key);
}

static int process_cookie_reply(const uint8_t label_cookie_key[WG_HASH_LEN],
                                const uint8_t mac1[WG_MAC_LEN],
                                uint32_t local_index,
                                const uint8_t reply[WG_COOKIE_REPLY_LEN],
                                uint8_t cookie[WG_COOKIE_LEN])
{
    if (reply[0] != 3) return 0;
    if (load32le(reply + 4) != local_index) return 0;
    return wireguard_xaead_decrypt(cookie, reply + 32, WG_COOKIE_LEN + WG_TAG_LEN,
                                   mac1, WG_MAC_LEN, reply + 8,
                                   label_cookie_key) ? 1 : 0;
}

/* Fixed exchange used by transport vectors: same keys as --vectors. */
static void fixed_transport_keys(const uint8_t priv_i[WG_KEY_LEN],
                                 const uint8_t pub_i[WG_KEY_LEN],
                                 const uint8_t priv_r[WG_KEY_LEN],
                                 const uint8_t pub_r[WG_KEY_LEN],
                                 uint8_t tx[WG_HASH_LEN], uint8_t rx[WG_HASH_LEN])
{
    uint8_t init[WG_INIT_LEN];
    uint8_t resp[WG_RESP_LEN];
    uint8_t timestamp[WG_TAI64N_LEN];
    uint8_t hash[WG_HASH_LEN];
    uint8_t ck[WG_HASH_LEN];
    uint8_t resp_ck[WG_HASH_LEN];
    uint8_t remote_eph[WG_KEY_LEN];
    uint8_t initiator_pub[WG_KEY_LEN];

    build_initiation(priv_i, pub_i, pub_r, 0x0123456789ABCDEFULL,
                     1800000000123456789ULL, NULL, init, timestamp);
    if (!process_initiation(priv_r, pub_r, init, hash, ck,
                            remote_eph, initiator_pub)) {
        tx[0] = 0;
        rx[0] = 0;
        return;
    }
    build_response(initiator_pub, hash, ck, remote_eph,
                   load32le(init + 4), 0xA1B2C3D4u,
                   0x0F1E2D3C4B5A6978ULL, resp, resp_ck);
    kdf2(tx, rx, resp_ck, NULL, 0);
}

static uint64_t parse_counter(const char *s, const char **rest)
{
    uint64_t v = 0;
    int any = 0;
    while (*s == ' ' || *s == '\t') s++;
    while (*s >= '0' && *s <= '9') {
        v = v * 10ULL + (uint64_t)(*s - '0');
        s++;
        any = 1;
    }
    if (!any) return 0;
    if (rest) *rest = s;
    return v;
}

/* RFC 7748 test keypairs (Alice, Bob); x25519 clamps internally. */
static const uint8_t priv_i[WG_KEY_LEN] = {
    0x77,0x07,0x6d,0x0a,0x73,0x18,0xa5,0x7d,
    0x3c,0x16,0xc1,0x72,0x51,0xb2,0x66,0x45,
    0xdf,0x4c,0x2f,0x87,0xeb,0xc0,0x99,0x2a,
    0xb1,0x77,0xfb,0xa5,0x1d,0xb9,0x2c,0x2a
};
static const uint8_t priv_r[WG_KEY_LEN] = {
    0x5d,0xab,0x08,0x7e,0x62,0x4a,0x8a,0x4b,
    0x79,0xe1,0x7f,0x8b,0x83,0x80,0x0e,0xe6,
    0x6f,0x3b,0xb1,0x29,0x26,0x18,0xb6,0xfd,
    0x1c,0x2f,0x8b,0x27,0xff,0x88,0xe0,0xeb
};

static int crosscheck(void)
{
    char line[512];
    uint8_t pub_i[WG_KEY_LEN];
    uint8_t pub_r[WG_KEY_LEN];
    uint8_t init[WG_INIT_LEN];
    uint8_t init2[WG_INIT_LEN];
    uint8_t timestamp[WG_TAI64N_LEN];
    uint8_t tx[WG_HASH_LEN];
    uint8_t rx[WG_HASH_LEN];
    uint8_t label_cookie_key[WG_HASH_LEN];
    uint8_t pt[WG_TRANSPORT_MAX_PT];
    uint8_t pkt[WG_TRANSPORT_HDR_LEN + WG_TRANSPORT_MAX_PT + WG_TAG_LEN];
    uint8_t reply[WG_COOKIE_REPLY_LEN];
    uint8_t cookie[WG_COOKIE_LEN];

    static_public(pub_i, priv_i);
    static_public(pub_r, priv_r);
    fixed_transport_keys(priv_i, pub_i, priv_r, pub_r, tx, rx);
    mac_key(label_cookie_key, pub_r, LABEL_COOKIE, sizeof(LABEL_COOKIE));

    while (fgets(line, (int)sizeof(line), stdin) != NULL) {
        const char *p = line;
        uint64_t seed;
        uint64_t wall;
        const char *rest;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == 't' && (p[1] == ' ' || p[1] == '\t')) {
            uint64_t counter = parse_counter(p + 1, &rest);
            int n = parse_hex(rest, pt, sizeof(pt));
            if (n < 0) continue;
            {
                size_t out_len = transport_encrypt(pkt, counter, pt, (size_t)n,
                                                   tx, 0xA1B2C3D4u);
                print_hex_only(pkt, out_len);
            }
            continue;
        }
        if (*p == 'c' && (p[1] == ' ' || p[1] == '\t')) {
            seed = parse_counter(p + 1, &rest);
            wall = parse_counter(rest, &rest);
            if (parse_hex(rest, reply, sizeof(reply)) != WG_COOKIE_REPLY_LEN) continue;
            build_initiation(priv_i, pub_i, pub_r, seed, wall, NULL, init, timestamp);
            if (process_cookie_reply(label_cookie_key, init + 116,
                                     load32le(init + 4), reply, cookie)) {
                build_initiation(priv_i, pub_i, pub_r, seed, wall, cookie,
                                 init2, timestamp);
                print_hex_only(init2, WG_INIT_LEN);
            }
            continue;
        }
        seed = parse_counter(p, &rest);
        wall = parse_counter(rest, &rest);
        build_initiation(priv_i, pub_i, pub_r, seed, wall, NULL, init, timestamp);
        print_hex_only(init, WG_INIT_LEN);
    }
    return 0;
}

static int transport_capture(void)
{
    static const uint8_t pt_a[13] = {
        0x45,0x00,0x00,0x1d,0xaa,0xbb,0xcc,0xdd,
        0x01,0x02,0x03,0x04,0x05
    };
    static const uint8_t pt_b[3] = { 0xde, 0xad, 0xbe };
    uint8_t pub_i[WG_KEY_LEN];
    uint8_t pub_r[WG_KEY_LEN];
    uint8_t tx[WG_HASH_LEN];
    uint8_t rx[WG_HASH_LEN];
    uint8_t pkt[WG_TRANSPORT_HDR_LEN + WG_TRANSPORT_MAX_PT + WG_TAG_LEN];
    size_t n;

    static_public(pub_i, priv_i);
    static_public(pub_r, priv_r);
    fixed_transport_keys(priv_i, pub_i, priv_r, pub_r, tx, rx);

    n = transport_encrypt(pkt, 0, pt_a, sizeof(pt_a), tx, 0xA1B2C3D4u);
    print_hex_only(pkt, n);
    n = transport_encrypt(pkt, 1, pt_b, sizeof(pt_b), tx, 0xA1B2C3D4u);
    print_hex_only(pkt, n);
    n = transport_encrypt(pkt, WG_REJECT_AFTER_MESSAGES - 1, NULL, 0,
                          tx, 0xA1B2C3D4u);
    print_hex_only(pkt, n);
    return 0;
}

static int cookie_capture(void)
{
    static const uint8_t cookie_secret[WG_KEY_LEN] = {
        0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x42,
        0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x42,
        0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x42,
        0x42,0x42,0x42,0x42,0x42,0x42,0x42,0x42
    };
    static const uint8_t nonce[WG_COOKIE_NONCE_LEN] = {
        0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
        0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,
        0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17
    };
    uint8_t pub_i[WG_KEY_LEN];
    uint8_t pub_r[WG_KEY_LEN];
    uint8_t init[WG_INIT_LEN];
    uint8_t init2[WG_INIT_LEN];
    uint8_t reply[WG_COOKIE_REPLY_LEN];
    uint8_t cookie[WG_COOKIE_LEN];
    uint8_t timestamp[WG_TAI64N_LEN];
    uint8_t label_cookie_key[WG_HASH_LEN];

    static_public(pub_i, priv_i);
    static_public(pub_r, priv_r);
    mac_key(label_cookie_key, pub_r, LABEL_COOKIE, sizeof(LABEL_COOKIE));

    build_initiation(priv_i, pub_i, pub_r, 0x0123456789ABCDEFULL,
                     1800000000123456789ULL, NULL, init, timestamp);
    build_cookie_reply(reply, label_cookie_key, init + 116,
                       load32le(init + 4), cookie_secret, nonce);
    if (!process_cookie_reply(label_cookie_key, init + 116,
                              load32le(init + 4), reply, cookie)) {
        fprintf(stderr, "cookie reply self-check failed\n");
        return 1;
    }
    build_initiation(priv_i, pub_i, pub_r, 0x0123456789ABCDEFULL,
                     1800000000123456789ULL, cookie, init2, timestamp);

    printf("c 81985529216486895 1800000000123456789 ");
    print_hex_only(reply, WG_COOKIE_REPLY_LEN);
    print_hex_only(init2, WG_INIT_LEN);
    return 0;
}

int main(int argc, char **argv)
{
    uint64_t seed_i = 0x0123456789ABCDEFULL;
    uint64_t seed_r = 0x0F1E2D3C4B5A6978ULL;
    uint64_t wall_ns = 1800000000123456789ULL;
    uint8_t pub_i[WG_KEY_LEN];
    uint8_t pub_r[WG_KEY_LEN];
    uint8_t init[WG_INIT_LEN];
    uint8_t resp[WG_RESP_LEN];
    uint8_t timestamp[WG_TAI64N_LEN];
    uint8_t hash[WG_HASH_LEN];
    uint8_t ck[WG_HASH_LEN];
    uint8_t resp_ck[WG_HASH_LEN];
    uint8_t remote_eph[WG_KEY_LEN];
    uint8_t initiator_pub[WG_KEY_LEN];
    uint8_t tx[WG_HASH_LEN];
    uint8_t rx[WG_HASH_LEN];

    if (argc <= 1 || strcmp(argv[1], "--crosscheck") == 0) return crosscheck();
    if (argc > 1 && strcmp(argv[1], "--transport-capture") == 0) return transport_capture();
    if (argc > 1 && strcmp(argv[1], "--cookie-capture") == 0) return cookie_capture();
    if (argc > 1 && strcmp(argv[1], "--vectors") != 0) {
        if (!parse_u64(argv[1], &seed_i)) return 2;
        if (argc > 2 && !parse_u64(argv[2], &wall_ns)) return 2;
    }

    static_public(pub_i, priv_i);
    static_public(pub_r, priv_r);

    build_initiation(priv_i, pub_i, pub_r, seed_i, wall_ns, NULL, init, timestamp);
    if (!process_initiation(priv_r, pub_r, init, hash, ck,
                            remote_eph, initiator_pub)) {
        fprintf(stderr, "process initiation failed\n");
        return 1;
    }

    build_response(initiator_pub, hash, ck, remote_eph,
                   load32le(init + 4), 0xA1B2C3D4u, seed_r,
                   resp, resp_ck);
    kdf2(tx, rx, resp_ck, NULL, 0);

    print_hex("initiator_static_priv", priv_i, WG_KEY_LEN);
    print_hex("initiator_static_pub", pub_i, WG_KEY_LEN);
    print_hex("responder_static_priv", priv_r, WG_KEY_LEN);
    print_hex("responder_static_pub", pub_r, WG_KEY_LEN);
    print_hex("initiation", init, WG_INIT_LEN);
    print_hex("timestamp", timestamp, WG_TAI64N_LEN);
    print_hex("response", resp, WG_RESP_LEN);
    print_hex("tx_key", tx, WG_HASH_LEN);
    print_hex("rx_key", rx, WG_HASH_LEN);
    return 0;
}
