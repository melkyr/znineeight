# Symmetric ciphers — `std_cipher`

| | |
|---|---|
| **Modules** | `std_cipher` |
| **Layers** | `L5` — pure algorithm layer: ChaCha20, Poly1305, ChaCha20-Poly1305 AEAD, AES-128, AES-128-GCM |
| **Import (by path)** | `const std_cipher = @import("std_cipher.zig");` |
| **Consumes** | none |

`std_cipher` is not re-exported through `std`; import it by path.

## Module overview

`std_cipher` is a **pure** (no imports), **allocation-free** symmetric-crypto
module. Every operation takes caller-owned key/nonce/input/output buffers and
either a caller-owned state struct or an immediate key. There is no heap, no
arena use, no global mutable state, no clock/env read, and no hidden runtime
(R1/R6). The same inputs always produce the same ciphertext and tag.

- **ChaCha20** follows RFC 8439: a 32-byte key, 12-byte nonce, 32-bit block
  counter, and all 20 rounds fully unrolled.
- **Poly1305** uses the donna 5×26-bit limb representation and wrap arithmetic
  (`+%`/`*%`). Its block path has no data-dependent branches or table indices.
- **ChaCha20-Poly1305** is the RFC 8439 §2.8 AEAD construction
  (`counter = 1` for the payload, Poly1305 key from counter 0). `Open`
  authenticates the ciphertext first and decrypts only on a tag match; a
  mismatch returns `error.AuthenticationFailed` without writing plaintext.
- **AES-128** is FIPS-197 with a 44-word expanded key. The T-tables
  (`Te0`–`Te3`, 4 × 256 × `u32` = 4 KiB) and `SBOX` are file-scope `const`
  values emitted as C89 `static const` rodata. They are never copied into an
  arena or re-created on the stack; `scripts/compiler/gate_cipher_rodata.sh`
  asserts their `nm` section type is `R/r`.
- **AES-128-GCM** is SP800-38D. GHASH uses the BearSSL-style 4-bit tables (16
  entries) and shifts/xors, with no carry-less-multiply intrinsic.

**Side-channel scope.** ChaCha20, Poly1305, the AEAD tag comparison, and the
GHASH bookkeeping use fixed loops (the tag compare is a full 16-byte
accumulate). AES-128 uses the classic software T-table construction, so its
S-box access is table-indexed; the module does not claim bitsliced/cache-
constant-time AES. The explicitly constant-time-required primitives in the M2
contract are Poly1305 and the ECC scalar paths (see [`ecc.md`](ecc.md)).

**Errors are only for AEAD misuse/failure:** `error.Corrupt` for a
ciphertext/plaintext or tag-buffer length mismatch, and
`error.AuthenticationFailed` for a tag mismatch. The raw cipher and hash
primitives cannot fail.

## Quick start

Seal and open a message with ChaCha20-Poly1305, then hash a block with
AES-128-GCM.

```zig
const std = @import("std");
const std_cipher = @import("std_cipher.zig");

pub fn main() void {
    var key: [32]u8 = undefined;
    var nonce: [12]u8 = undefined;
    // fill key/nonce from std_rand in real code

    var ct: [5]u8 = undefined;
    var tag: [16]u8 = undefined;
    std_cipher.chacha20Poly1305Seal(
        &key, &nonce, ad[0..], "hello", ct[0..], &tag,
    ) catch return;

    var pt: [5]u8 = undefined;
    std_cipher.chacha20Poly1305Open(
        &key, &nonce, ad[0..], ct[0..], &tag, pt[0..],
    ) catch |err| {
        if (err == error.AuthenticationFailed) return; // reject
        return;
    };
}
```

## API

### `ChaCha20`

**Purpose** — ChaCha20 state: the 16-word RFC 8439 input matrix (constants,
key, counter, nonce).

**Signature** — `pub const ChaCha20 = struct { state: [16]u32 };`

**Parameters** (fields)
- `state` — the working matrix; words 12–15 are the counter and nonce.

**Returns** — a plain value type; `chacha20Init` returns one by value.

**Errors** — none.

**Gotchas** — initialize with `chacha20Init`; hand-writing `state` invites
endianness/counter mistakes. `chacha20Xor` advances the counter in place, so
copy the state to replay a keystream.

#### `chacha20Init`

**Purpose** — builds a ChaCha20 state from a key, nonce, and initial block
counter.

**When to use** — once per stream/direction; pass counter `1` for RFC 8439
AEAD payloads (`0` is reserved for the Poly1305 key), or `0` for a raw stream.

**Signature** — `pub fn chacha20Init(key: *const [32]u8, nonce: *const [12]u8, counter: u32) ChaCha20`

**Parameters**
- `key` — the 32-byte ChaCha20 key.
- `nonce` — the 12-byte nonce (96-bit IETF form).
- `counter` — the initial 32-bit block counter.

**Returns** — a `ChaCha20` ready for `chacha20Xor`.

**Errors** — none.

**Example**
```zig
var s = std_cipher.chacha20Init(&key, &nonce, 1);
```

**Gotchas** — the key/nonce are read immediately; the caller's buffers may be
reused after the call. Counter wrap is not prevented.

#### `chacha20Xor`

**Purpose** — XORs the ChaCha20 keystream over `src` into `dst`.

**When to use** — raw stream encryption/decryption (decryption is the same
operation).

**Signature** — `pub fn chacha20Xor(s: *ChaCha20, dst: []u8, src: []const u8) void`

**Parameters**
- `s` — the initialized state; the block counter advances by one per 64-byte
  block.
- `dst` — destination; must be at least `src.len`. If smaller, the call
  returns without writing.
- `src` — plaintext or ciphertext bytes; any length.

**Returns** — nothing; writes `src.len` bytes to `dst`.

**Errors** — none.

**Example**
```zig
var ct: [114]u8 = undefined;
std_cipher.chacha20Xor(&s, ct[0..], pt[0..]);
```

**Gotchas** — `dst` and `src` may not be assumed overlap-safe in general; use
separate buffers. A short `dst` silently does nothing (precondition violation).

### `Poly1305`

**Purpose** — Poly1305 state: clamped `r` limbs, accumulator `h`, pad words,
and a 16-byte partial block.

**Signature** — `pub const Poly1305 = struct { r: [5]u32, h: [5]u32, pad: [4]u32, buf: [16]u8, left: usize };`

**Parameters** (fields)
- `r` — the five clamped 26-bit key limbs.
- `h` — the five accumulator limbs.
- `pad` — the final 128-bit addition key.
- `buf` / `left` — pending partial block and byte count.

**Returns** — a plain value type; `poly1305Init` returns one by value.

**Errors** — none.

**Gotchas** — initialize with `poly1305Init`; treat fields as opaque.

#### `poly1305Init`

**Purpose** — derives the Poly1305 state from a 32-byte one-time key.

**When to use** — once per message with a unique one-time key (the first 32
bytes of the ChaCha20 block at counter 0 in the AEAD construction).

**Signature** — `pub fn poly1305Init(key: *const [32]u8) Poly1305`

**Parameters**
- `key` — the 32-byte r‖pad key (r is clamped internally).

**Returns** — a `Poly1305` ready for `poly1305Update`.

**Errors** — none.

**Example**
```zig
var p = std_cipher.poly1305Init(&one_time_key);
```

**Gotchas** — reusing a one-time key for two messages destroys Poly1305
security. The key is read immediately.

#### `poly1305Update`

**Purpose** — absorbs message bytes, buffering a partial 16-byte block.

**Signature** — `pub fn poly1305Update(s: *Poly1305, data: []const u8) void`

**Parameters**
- `s` — the streaming state.
- `data` — the next chunk; any length.

**Returns** — nothing.

**Errors** — none.

**Gotchas** — chunking-independent; the full-block path has no data-dependent
branches or table indices.

#### `poly1305Final`

**Purpose** — finalizes the tag and writes 16 bytes.

**Signature** — `pub fn poly1305Final(s: *Poly1305, out: *[16]u8) void`

**Parameters**
- `s` — the state to finish (consumed).
- `out` — the 16-byte tag destination.

**Returns** — nothing.

**Errors** — none.

**Gotchas** — a trailing partial block gets the `1` byte and no high bit, per
RFC 8439. Do not update after finalizing.

### `chacha20Poly1305Seal`

**Purpose** — encrypts and authenticates with ChaCha20-Poly1305 (RFC 8439
§2.8).

**When to use** — an authenticated-encryption envelope when both sides have a
32-byte key and 12-byte nonce.

**Signature** — `pub fn chacha20Poly1305Seal(key: *const [32]u8, nonce: *const [12]u8, ad: []const u8, pt: []const u8, ct: []u8, tag: *[16]u8) !void`

**Parameters**
- `key` — the 32-byte AEAD key.
- `nonce` — the 12-byte nonce; **never reuse with the same key**.
- `ad` — additional authenticated data (not encrypted).
- `pt` — plaintext.
- `ct` — ciphertext destination; must be exactly `pt.len` bytes.
- `tag` — the 16-byte tag destination.

**Returns** — nothing; writes `ct` and `tag`.

**Errors**
- `error.Corrupt` — `ct.len != pt.len`.

**Example**
```zig
try std_cipher.chacha20Poly1305Seal(&key, &nonce, ad[0..], pt[0..], ct[0..], &tag);
```

**Gotchas** — the tag covers `ad`, `ct`, and both lengths; the same `ad` must
be supplied to `Open`. The payload uses counter 1.

### `chacha20Poly1305Open`

**Purpose** — verifies and decrypts a ChaCha20-Poly1305 message.

**When to use** — the receiving side of `chacha20Poly1305Seal`.

**Signature** — `pub fn chacha20Poly1305Open(key: *const [32]u8, nonce: *const [12]u8, ad: []const u8, ct: []const u8, tag: *const [16]u8, pt: []u8) !void`

**Parameters**
- `key` — the 32-byte AEAD key.
- `nonce` — the 12-byte nonce used to seal.
- `ad` — the same additional data used to seal.
- `ct` — the ciphertext.
- `tag` — the received 16-byte tag.
- `pt` — plaintext destination; must be exactly `ct.len` bytes.

**Returns** — nothing; writes `pt` only when the tag matches.

**Errors**
- `error.Corrupt` — `pt.len != ct.len`.
- `error.AuthenticationFailed` — the recomputed tag differs from `tag`.

**Example**
```zig
std_cipher.chacha20Poly1305Open(&key, &nonce, ad[0..], ct[0..], &tag, pt[0..]) catch |err| {
    if (err == error.AuthenticationFailed) return; // reject; pt untouched
};
```

**Gotchas** — authenticate-before-decrypt: plaintext is written only after the
tag check. Never release `pt` on error, and never ignore the error.

### `Aes128`

**Purpose** — AES-128 expanded key schedule (44 words).

**Signature** — `pub const Aes128 = struct { rk: [44]u32 };`

**Parameters** (fields)
- `rk` — the 11 round keys (4 words each).

**Returns** — a plain value type; `aes128Init` returns one by value.

**Errors** — none.

**Gotchas** — initialize with `aes128Init`; the T-tables are module-level
`const` rodata, not part of this struct.

#### `aes128Init`

**Purpose** — expands a 16-byte AES-128 key.

**Signature** — `pub fn aes128Init(key: *const [16]u8) Aes128`

**Parameters**
- `key` — the 16-byte AES-128 key.

**Returns** — an `Aes128` ready for `aes128EncryptBlock` /
`aes128GcmSeal`/`Open`.

**Errors** — none.

**Example**
```zig
var a = std_cipher.aes128Init(&key);
```

**Gotchas** — the key is read immediately; the round keys are copied into the
value.

#### `aes128EncryptBlock`

**Purpose** — encrypts one 16-byte block (FIPS-197).

**Signature** — `pub fn aes128EncryptBlock(a: *const Aes128, in: *const [16]u8, out: *[16]u8) void`

**Parameters**
- `a` — the expanded key.
- `in` — the 16-byte plaintext block.
- `out` — the 16-byte ciphertext block (may alias `in` only if the caller
  accepts the read-before-write order; use separate buffers to be safe).

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
var out: [16]u8 = undefined;
std_cipher.aes128EncryptBlock(&a, &block, &out);
```

**Gotchas** — raw ECB block encryption; use GCM for authenticated messages.

### `aes128GcmSeal`

**Purpose** — AES-128-GCM authenticated encryption (SP800-38D).

**When to use** — authenticated encryption with a 12-byte IV.

**Signature** — `pub fn aes128GcmSeal(key: *const [16]u8, iv: *const [12]u8, ad: []const u8, pt: []const u8, ct: []u8, tag: *[16]u8) !void`

**Parameters**
- `key` — the 16-byte AES key.
- `iv` — the 12-byte GCM IV (J0 is `IV‖0x00000001`).
- `ad` — additional authenticated data.
- `pt` — plaintext.
- `ct` — ciphertext destination; exactly `pt.len` bytes.
- `tag` — the 16-byte tag destination.

**Returns** — nothing; writes `ct` and `tag`.

**Errors**
- `error.Corrupt` — `ct.len != pt.len`.

**Example**
```zig
try std_cipher.aes128GcmSeal(&key, &iv, ad[0..], pt[0..], ct[0..], &tag);
```

**Gotchas** — the IV is exactly 12 bytes by this API; other GCM IV lengths are
not accepted. The tag covers `ad`, `ct`, and their bit lengths.

### `aes128GcmOpen`

**Purpose** — verifies and decrypts an AES-128-GCM message.

**Signature** — `pub fn aes128GcmOpen(key: *const [16]u8, iv: *const [12]u8, ad: []const u8, ct: []const u8, tag: *const [16]u8, pt: []u8) !void`

**Parameters**
- `key` — the 16-byte AES key.
- `iv` — the 12-byte IV used to seal.
- `ad` — the same additional data used to seal.
- `ct` — the ciphertext.
- `tag` — the received 16-byte tag.
- `pt` — plaintext destination; exactly `ct.len` bytes.

**Returns** — nothing; writes `pt` only when the tag matches.

**Errors**
- `error.Corrupt` — `pt.len != ct.len`.
- `error.AuthenticationFailed` — the recomputed tag differs.

**Example**
```zig
std_cipher.aes128GcmOpen(&key, &iv, ad[0..], ct[0..], &tag, pt[0..]) catch |err| {
    if (err == error.AuthenticationFailed) return; // reject; pt untouched
};
```

**Gotchas** — authenticate-before-decrypt. Never use the output on error. The
tag comparison is a full 16-byte accumulate, not an early-exit compare.

## Constant-time and memory notes

- **No heap / no arena.** Every function writes only through caller slices and
  stack-local scratch. The AES T-tables are file-scope `const` rodata; the GCM
  4-bit tables are stack-local (`GHash.tab`) and rebuilt per operation — only
  the AES T-tables are file-scope `const` rodata. `scripts/compiler/gate_cipher_rodata.sh`
  checks `_Te0`–`_Te3` and `_SBOX` are `R/r`, and the AES-GCM fixture asserts
  an arena's `used` is unchanged across a seal.
- **Poly1305** uses donna's 5×26-bit limbs with fixed loops and wrap
  arithmetic; no secret-dependent branch or table index on the block path.
- **AEAD** recomputes the tag over the full ciphertext and compares all 16
  bytes before decrypting.
- **AES** is the standard software T-table implementation (data-indexed S-box
  lookups); it is not a bitsliced constant-time AES. Do not claim otherwise.

## KAT provenance

| Surface | Vectors | Fixture |
|---|---|---|
| ChaCha20 block/XOR | RFC 8439 §2.3.2 / §2.4.2 | `stdlib_chacha_poly_xmod` |
| Poly1305 | RFC 8439 §2.5.2 (one-shot and split streaming) | `stdlib_chacha_poly_xmod` |
| ChaCha20-Poly1305 AEAD | RFC 8439 §2.8.2 (ciphertext + tag), open round-trip, tampered tag → `error.AuthenticationFailed` | `stdlib_chacha_poly_xmod` |
| AES-128 block | FIPS-197 Appendix C.1 | `stdlib_aes_gcm_xmod` |
| AES-128-GCM | NIST GCM spec test cases 1–4 (empty PT/AD, empty AD, multi-block, non-empty AD), open round-trip, tampered tag → `error.AuthenticationFailed`, arena-untouched check | `stdlib_aes_gcm_xmod` |
| T-table storage | `nm` section `R/r` for `_Te0`–`_Te3` and `_SBOX` | `scripts/compiler/gate_cipher_rodata.sh` |

## See also

- [`crypto.md`](crypto.md) — SHA-256/SHA-384/SHA-512, HMAC, HKDF, BLAKE2s,
  RSA verify; `std_cipher` itself is dependency-free.
- [`ecc.md`](ecc.md) — X25519 and ECDSA verify.
- [`rand.md`](rand.md) — xoshiro256\*\* for nonces and keys (caller-supplied;
  the module never reads entropy itself).
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
