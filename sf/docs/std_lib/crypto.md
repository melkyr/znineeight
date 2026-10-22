# Cryptography — `std_crypto`

| | |
|---|---|
| **Modules** | `std_crypto` |
| **Layers** | `L5` — pure algorithm layer: streaming hashes, PRFs, key derivation, BLAKE2s, CRC-32, RC4, modular exponentiation, RSA verify |
| **Import (by path)** | `const std_crypto = @import("std_crypto.zig");` |
| **Consumes** | none |

`std_crypto` is not re-exported through `std`; import it by path.

## Module overview

`std_crypto` is a **pure** (no imports), **allocation-free** module. Every
operation uses caller-provided state and caller-owned buffers: `*Init` returns
a value-type state, `*Update` takes `*State` and may be called any number of
times with any chunk sizes, and `*Final` writes into a caller array (or returns
the finished `u32` for CRC-32). There is no heap, no global state, no clock/env
read, and no hidden runtime (R1/R6). The same bytes always produce the same
digest, tag, or verification result.

The module has two generations of API in one file:

- **Streaming hashes and legacy primitives** — SHA-1, SHA-256, MD5, CRC-32,
  RC4, and the MSE/PE-sized `modpow` (96-byte / 768-bit modulus cap).
- **M2 additions** — SHA-384, SHA-512, HMAC-SHA256 (one-shot and streaming),
  HKDF (RFC 5869), BLAKE2s (unkeyed and keyed), HMAC-BLAKE2s (WireGuard MAC
  form), and RSA **verify-only** PKCS#1 v1.5 / PSS (RFC 8017). RSA signing is
  deliberately absent.

The RSA path uses a new generic modexp over big-endian byte slices with a
fixed 512-byte (4096-bit) operand cap. It is separate from the existing
`modpow`, whose fixed width is only 96 bytes. Verification operates on public
values (modulus, exponent, signature, hash), so it does not require a
constant-time exponentiation; the padding checks still run without
caller-visible early acceptance, and every malformed signature path returns an
error.

All modular arithmetic uses explicit wrap operators (`+%`, `*%`), so the
default `-fsafe` build does not trap on expected mod-2³² additions. The module
is C89-safe: no libm, C99 features, compiler builtins, or f64 intermediates.

## Quick start

HMAC-SHA256, HKDF, and an RSA PKCS#1 v1.5 verify (signature bytes supplied by
the caller).

```zig
const std = @import("std");
const std_crypto = @import("std_crypto.zig");

pub fn main() void {
    var mac: [32]u8 = undefined;
    std_crypto.hmacSha256("key", "message", &mac);

    var prk: [32]u8 = undefined;
    std_crypto.hkdfExtract("salt", "ikm", &prk);
    var okm: [42]u8 = undefined;
    std_crypto.hkdfExpand(&prk, "info", okm[0..]) catch {
        return;
    };

    // RSA verify works on the caller's hash (SHA-256 here).
    var digest: [32]u8 = undefined;
    var sha = std_crypto.sha256Init();
    std_crypto.sha256Update(&sha, "message");
    std_crypto.sha256Final(&sha, &digest);
    std_crypto.rsaVerifyPkcs1v15(
        rsa_n[0..], 65537, std_crypto.HashAlg.sha256, digest[0..], rsa_sig[0..],
    ) catch |err| {
        if (err == error.BadSignature) return;
        return;
    };
}
```

## API

### Existing hashes and primitives

The existing SHA-1 / SHA-256 / MD5 / CRC-32 / RC4 / `modpow` entries are
documented in full in [`codecs.md`](codecs.md#std_crypto). Their public shapes
are:

- `Sha1`, `sha1Init()`, `sha1Update(*Sha1, []const u8)`,
  `sha1Final(*Sha1, *[20]u8)`.
- `Sha256`, `sha256Init()`, `sha256Update(*Sha256, []const u8)`,
  `sha256Final(*Sha256, *[32]u8)`.
- `Md5`, `md5Init()`, `md5Update(*Md5, []const u8)`,
  `md5Final(*Md5, *[16]u8)`.
- `crc32Init() u32`, `crc32Update(u32, []const u8) u32`, `crc32Final(u32) u32`.
- `Rc4` / `rc4Init(key, *Rc4)` / `rc4Apply(*Rc4, []u8)`.
- `modpow(base, exp, modulus, out)` — 96-byte modulus cap.

None of these fail: hashes and CRC have no error union; `modpow` zero-fills
`out` on a bad width or length. MD5 and RC4 are legacy/interop primitives, not
modern security choices.

### `Sha384` / `Sha512`

**Purpose** — streaming FIPS 180-4 SHA-384 and SHA-512 states.

**When to use** — certificate and TLS transcript hashing, P-384 ECDSA input,
and any 64-bit-length hash requirement. Use `Sha256` when 256 bits are enough.

**Signatures**
- `pub const Sha384 = struct { h: [8]u64, buf: [128]u8, buf_len: usize, total: u64 };`
- `pub const Sha512 = struct { h: [8]u64, buf: [128]u8, buf_len: usize, total: u64 };`
- `pub fn sha384Init() Sha384`
- `pub fn sha384Update(s: *Sha384, data: []const u8) void`
- `pub fn sha384Final(s: *Sha384, out: *[48]u8) void`
- `pub fn sha512Init() Sha512`
- `pub fn sha512Update(s: *Sha512, data: []const u8) void`
- `pub fn sha512Final(s: *Sha512, out: *[64]u8) void`

**Parameters**
- `s` — the streaming state; `Update` advances it in place.
- `data` — the next chunk; any length, including zero.
- `out` — the digest destination (48 or 64 bytes).

**Returns** — nothing; `*Final` writes the digest. SHA-384 is the first six
64-bit words of SHA-512, big-endian.

**Errors** — none.

**Example**
```zig
var s = std_crypto.sha512Init();
std_crypto.sha512Update(&s, msg);
var digest: [64]u8 = undefined;
std_crypto.sha512Final(&s, &digest);
```

**Gotchas** — do not `Update` after `Final`. The length field is 128-bit in the
standard; this implementation carries the byte count in a `u64`, which covers
every message representable on the target. Chunking is independent of the
digest.

### `HmacSha256`

**Purpose** — streaming HMAC-SHA256 state (RFC 2104 / RFC 4231). It holds both
the inner and outer SHA-256 states.

**When to use** — a streaming MAC when the message arrives in pieces. For a
one-shot call use `hmacSha256`.

**Signature** — `pub const HmacSha256 = struct { inner: Sha256, outer: Sha256 };`

**Parameters** (fields)
- `inner` — pre-seeded with the `0x36` key pad.
- `outer` — pre-seeded with the `0x5c` key pad.

**Returns** — a plain value type; `hmacSha256Init` returns one by value.

**Errors** — none.

**Gotchas** — initialize with `hmacSha256Init`; treat the fields as opaque.

#### `hmacSha256Init`

**Purpose** — derives the inner/outer hash states from a key.

**When to use** — at the start of a streaming HMAC.

**Signature** — `pub fn hmacSha256Init(key: []const u8) HmacSha256`

**Parameters**
- `key` — any length. Keys longer than 64 bytes are hashed to 32 bytes first.

**Returns** — an `HmacSha256` ready for `hmacSha256Update`.

**Errors** — none.

**Example**
```zig
var s = std_crypto.hmacSha256Init(key[0..]);
```

**Gotchas** — the key is copied into the state; the caller's buffer may be
reused immediately.

#### `hmacSha256Update`

**Purpose** — absorbs message bytes into the inner hash.

**Signature** — `pub fn hmacSha256Update(s: *HmacSha256, data: []const u8) void`

**Parameters**
- `s` — the streaming state.
- `data` — the next message chunk.

**Returns** — nothing.

**Errors** — none.

**Gotchas** — chunking-independent; call any number of times before `Final`.

#### `hmacSha256Final`

**Purpose** — finishes the HMAC and writes the 32-byte tag.

**Signature** — `pub fn hmacSha256Final(s: *HmacSha256, out: *[32]u8) void`

**Parameters**
- `s` — the state to finish (consumed).
- `out` — the 32-byte tag destination.

**Returns** — nothing; the tag is written through `out`.

**Errors** — none.

**Gotchas** — do not update after finalizing.

#### `hmacSha256`

**Purpose** — one-shot HMAC-SHA256.

**When to use** — when the whole key and message are already contiguous.

**Signature** — `pub fn hmacSha256(key: []const u8, msg: []const u8, out: *[32]u8) void`

**Parameters**
- `key` — any length (long keys are hashed).
- `msg` — the complete message.
- `out` — the 32-byte tag destination.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var tag: [32]u8 = undefined;
std_crypto.hmacSha256(key[0..], msg[0..], &tag);
```

**Gotchas** — equivalent to `Init` + one `Update` + `Final`.

### `hkdfExtract`

**Purpose** — HKDF-Extract (RFC 5869): `PRK = HMAC-SHA256(salt, IKM)`.

**When to use** — first step of HKDF key derivation.

**Signature** — `pub fn hkdfExtract(salt: []const u8, ikm: []const u8, out: *[32]u8) void`

**Parameters**
- `salt` — the salt; an empty slice is the RFC's zero-salt case (HMAC with a
  zero-length key).
- `ikm` — the input keying material.
- `out` — the 32-byte pseudorandom key.

**Returns** — nothing.

**Errors** — none.

**Gotchas** — the output is a PRK, not yet usable key material; feed it to
`hkdfExpand`.

### `hkdfExpand`

**Purpose** — HKDF-Expand (RFC 5869) with HMAC-SHA256 and the caller's `info`
string.

**When to use** — second step of HKDF; call for each output block (TLS
key schedule, WireGuard, etc.).

**Signature** — `pub fn hkdfExpand(prk: *const [32]u8, info: []const u8, out: []u8) !void`

**Parameters**
- `prk` — the 32-byte PRK from `hkdfExtract`.
- `info` — context/application string; may be empty.
- `out` — the output buffer, any length up to 255 × 32 = 8160 bytes. Its length
  is the requested output length.

**Returns** — nothing; fills `out`.

**Errors**
- `error.Corrupt` — `out.len > 8160` (the RFC 5869 counter would wrap).

**Example**
```zig
var okm: [64]u8 = undefined;
try std_crypto.hkdfExpand(&prk, "tls13 key", okm[0..]);
```

**Gotchas** — `out.len == 0` is valid and writes nothing. The same
`(prk, info, out.len)` always yields the same prefix.

### `Blake2s`

**Purpose** — streaming BLAKE2s state (RFC 7693), unkeyed or keyed.

**When to use** — BLAKE2s digests (up to 32 bytes) and the WireGuard
`MAC(key, data)` form. For a one-shot MAC use `hmacBlake2s`.

**Signature** — `pub const Blake2s = struct { h: [8]u32, t: u64, buf: [64]u8, buf_len: usize, out_len: u32, key_len: u32 };`

**Parameters** (fields)
- `h` — the eight-word chaining state.
- `t` — bytes absorbed so far.
- `buf` / `buf_len` — pending 64-byte block.
- `out_len` — requested digest length in bytes (1–32).
- `key_len` — key length in bytes (0 for unkeyed).

**Returns** — a plain value type; `blake2sInit` returns one by value.

**Errors** — none.

**Gotchas** — initialize with `blake2sInit`; do not hand-write `h`.

#### `blake2sInit`

**Purpose** — initializes BLAKE2s for a key and output length.

**When to use** — at the start of a hash or keyed MAC.

**Signature** — `pub fn blake2sInit(key: []const u8, out_len: u32) Blake2s`

**Parameters**
- `key` — the key; `""` selects unkeyed BLAKE2s.
- `out_len` — digest length in bytes, 1–32. Out-of-range values are clamped by
  the caller-visible contract: pass a valid length (the `hmacBlake2s` wrapper
  rejects `0` and `>32`).

**Returns** — a `Blake2s` ready for `blake2sUpdate`.

**Errors** — none.

**Example**
```zig
var s = std_crypto.blake2sInit("", 32);
```

**Gotchas** — a keyed BLAKE2s is **not** HMAC; use `hmacBlake2s` for the
WireGuard MAC construction.

#### `blake2sUpdate`

**Purpose** — absorbs a message chunk.

**Signature** — `pub fn blake2sUpdate(s: *Blake2s, data: []const u8) void`

**Parameters**
- `s` — the state.
- `data` — the next chunk.

**Returns** — nothing.

**Errors** — none.

**Gotchas** — chunking-independent.

#### `blake2sFinal`

**Purpose** — finishes BLAKE2s and writes `out.len` digest bytes.

**Signature** — `pub fn blake2sFinal(s: *Blake2s, out: []u8) void`

**Parameters**
- `s` — the state to finish (consumed).
- `out` — destination; its length selects the number of bytes written, up to
  the `out_len` fixed at init.

**Returns** — nothing.

**Errors** — none.

**Gotchas** — the caller must not ask for more bytes than `blake2sInit`'s
`out_len`.

#### `hmacBlake2s`

**Purpose** — keyed BLAKE2s MAC used by WireGuard (`MAC(key, data)`).

**When to use** — WireGuard handshake/transport MACs.

**Signature** — `pub fn hmacBlake2s(key: []const u8, msg: []const u8, out: []u8) void`

**Parameters**
- `key` — the MAC key.
- `msg` — the message.
- `out` — destination; length 1–32.

**Returns** — nothing.

**Errors** — none (an `out.len` of 0 or >32 writes nothing).

**Example**
```zig
var mac: [16]u8 = undefined;
std_crypto.hmacBlake2s(key[0..], msg[0..], mac[0..]);
```

**Gotchas** — despite the name it is keyed BLAKE2s, not HMAC-over-BLAKE2s.

### `HashAlg`

**Purpose** — selects the hash used by RSA PKCS#1 v1.5 / PSS and MGF1.

**Signature** — `pub const HashAlg = enum { sha256, sha384, sha512 };`

**Parameters** — none.

**Returns** — an enum value.

**Errors** — none. The enum makes an unsupported algorithm unrepresentable;
`error.UnsupportedAlgorithm` is therefore not produced by the current API.

**Gotchas** — the caller supplies the already-computed `hash`; the enum tells
the verifier which DigestInfo/MGF1 hash to expect.

### `rsaVerifyPkcs1v15`

**Purpose** — RSASSA-PKCS1-v1_5 verification per RFC 8017 §8.2.2.

**When to use** — verifying certificate and TLS 1.2 signatures that use
PKCS#1 v1.5 padding. Verify-only; there is no signing function.

**Signature** — `pub fn rsaVerifyPkcs1v15(n: []const u8, e: u32, hash_alg: HashAlg, hash: []const u8, sig: []const u8) !void`

**Parameters**
- `n` — the RSA modulus, big-endian, 1–512 bytes (up to 4096 bits).
- `e` — the public exponent (`65537` in normal certificates).
- `hash_alg` — selects SHA-256/384/512 DigestInfo and expected hash length.
- `hash` — the caller-computed digest; its length must equal the algorithm's
  digest length.
- `sig` — the signature, exactly `n.len` bytes.

**Returns** — nothing on success.

**Errors**
- `error.Corrupt` — `hash.len` does not match `hash_alg`, `n.len` is 0 or
  > 512, or `sig.len != n.len`.
- `error.BadSignature` — the modular result or the PKCS#1 v1.5 padding/hash
  comparison fails (including a signature ≥ `n`).

**Example**
```zig
std_crypto.rsaVerifyPkcs1v15(n[0..], 65537, .sha256, digest[0..], sig[0..]) catch |err| {
    if (err == error.BadSignature) return; // reject
};
```

**Gotchas** — a wrong signature **must** be rejected; never map
`error.BadSignature` to acceptance. The fixed scratch is 512-byte operands, so
the call uses a few kilobytes of stack.

### `rsaVerifyPss`

**Purpose** — RSASSA-PSS verification per RFC 8017 §8.1.2, with MGF1 over the
selected hash.

**When to use** — verifying TLS 1.3 / modern certificate PSS signatures.

**Signature** — `pub fn rsaVerifyPss(n: []const u8, e: u32, hash_alg: HashAlg, hash: []const u8, salt_len: u32, sig: []const u8) !void`

**Parameters**
- `n` — the RSA modulus, big-endian, 1–512 bytes.
- `e` — the public exponent.
- `hash_alg` — selects the hash and MGF1 hash.
- `hash` — the caller-computed digest.
- `salt_len` — the expected salt length in bytes (32 for SHA-256, 48 for
  SHA-384, 64 for SHA-512 in the common profiles; 0 is valid).
- `sig` — the signature, exactly `n.len` bytes.

**Returns** — nothing on success.

**Errors**
- `error.Corrupt` — hash length mismatch, bad modulus width, or an unusable
  encoded-message length.
- `error.BadSignature` — the RSA result, leading-zero prefix, trailer
  (`0xbc`), DB mask, PS padding, or H′ comparison fails.

**Example**
```zig
std_crypto.rsaVerifyPss(n[0..], 65537, .sha256, digest[0..], 32, sig[0..]) catch |err| {
    if (err == error.BadSignature) return; // reject
};
```

**Gotchas** — `salt_len` is part of the contract; a verifier configured for
the wrong salt length rejects a valid signature. PSS uses `emBits = modBits-1`.

## KAT provenance

All vectors are committed under `repro/mi_matrix/`; the gate runs the fixture
three times and byte-compares stdout and rc.

| Surface | Vectors | Fixture |
|---|---|---|
| SHA-384 / SHA-512 | FIPS 180-4 (empty, `abc`, 1-block, 112-byte padding boundary, multi-block; chunked == one-shot) | `stdlib_hash_sha384_512_xmod` |
| HMAC-SHA256 | RFC 4231 cases 1–7, one-shot and streaming | `stdlib_crypto_prf_xmod` |
| HKDF | RFC 5869 cases 1–3 and 7 | `stdlib_crypto_prf_xmod` |
| BLAKE2s | RFC 7693 appendix KATs plus keyed vectors (independent `hashlib.blake2s` oracle) | `stdlib_crypto_prf_xmod` |
| HMAC-BLAKE2s | keyed BLAKE2s WireGuard MAC form | `stdlib_crypto_prf_xmod` |
| RSA PKCS#1 v1.5 | 2048-bit key generated with OpenSSL; SHA-256 and SHA-384 good signatures; corrupted-signature negatives assert `error.BadSignature` | `stdlib_rsa_verify_xmod` |
| RSA PSS | OpenSSL signatures, SHA-256 with salt 32 and 0; corrupted-signature negatives assert `error.BadSignature` | `stdlib_rsa_verify_xmod` |
| Existing SHA-1/SHA-256/MD5/CRC-32/RC4/modpow | RFC 3174, FIPS 180-4, RFC 1321, IEEE 802.3, RFC 6229, MSE/PE 768-bit DH | see [`codecs.md`](codecs.md) |

## See also

- [`codecs.md`](codecs.md) — the existing SHA-1/SHA-256/MD5/CRC-32/RC4/
  `modpow` entries and the text codecs.
- [`cipher.md`](cipher.md) — symmetric primitives (ChaCha20-Poly1305,
  AES-128-GCM) that consume this module's hashes and PRFs.
- [`ecc.md`](ecc.md) — X25519 and ECDSA verify.
- [`rand.md`](rand.md) — caller-supplied xoshiro256\*\* used for nonces/keys.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
