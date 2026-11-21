# Elliptic curves — `std_ecc`

| | |
|---|---|
| **Modules** | `std_ecc` |
| **Layers** | `L5` — pure algorithm layer: X25519, P-256 keygen/ECDH/ECDSA verify, P-384 ECDSA verify |
| **Import (by path)** | `const std_ecc = @import("std_ecc.zig");` |
| **Consumes** | `std_rand` (`Xoshiro256`) for P-256 key generation only |

`std_ecc` is not re-exported through `std`; import it by path.

## Module overview

`std_ecc` is an **integer-only**, **allocation-free** elliptic-curve module
for the TLS/WireGuard verify-and-ECDH surface. It imports only `std_rand`
(caller-supplied state for P-256 keygen); it reads no clock, environment, or
address (R6), uses no heap or arena, no `libm`, no C99, no compiler builtins,
and no f64 intermediates. Same inputs always give the same bytes/verdict.

**Algorithms and provenance**

- **X25519** is the ref10 10-limb (26/25-bit alternating) Montgomery ladder
  from SUPERCOP `crypto_scalarmult/curve25519/ref10` (public domain / CC0,
  D. J. Bernstein et al.), with the RFC 7748 clamp applied inside the ladder
  and all-zero output rejected as `error.WeakPublicKey`.
- **P-256 and P-384** share one generic prime-curve engine ported from
  BearSSL's portable `ec_prime_i31.c` and `i31_*` primitives (Copyright © 2016
  Thomas Pornin, MIT licence; notice reproduced in `sf/src/std_ecc.zig`). The
  only arithmetic change is that modular exponentiation stays in Montgomery
  form throughout, because the exponents are public curve constants.
- **P-256** supports key generation, ECDH, and ECDSA verify. **P-384 is
  verify-only** (no keygen or ECDH): client ECDHE groups stay X25519 +
  secp256r1, and P-384 is needed for chain signature verification.

**Constant-time scalar paths.** Scalar multiplication uses a fixed ladder /
fixed sequence with mask-based conditional swaps; there are no
secret-dependent branches or table indices in the X25519 ladder or the P-256 /
P-384 scalar-multiplication paths. Public-key decoding and ECDSA public-value
checks may branch on public data.

**Encodings.** P-256 public keys are uncompressed 65-byte values
(`0x04 ‖ X ‖ Y`, 32 bytes each). P-384 keys are uncompressed 97-byte values
(`0x04 ‖ X ‖ Y`, 48 bytes each). ECDSA inputs are fixed-width big-endian
scalars; the caller supplies the already-computed hash (SHA-256 for P-256,
SHA-384 for P-384).

## Quick start

X25519 shared secret, then P-256 ECDSA verification.

```zig
const std = @import("std");
const std_ecc = @import("std_ecc.zig");
const std_rand = @import("std_rand.zig");

pub fn main() void {
    var alice_priv: [32]u8 = undefined;
    var alice_pub: [32]u8 = undefined;
    // fill alice_priv from a CSPRNG in real code
    std_ecc.x25519Base(&alice_priv, &alice_pub) catch return;

    var shared: [32]u8 = undefined;
    std_ecc.x25519(&alice_priv, &bob_pub, &shared) catch return;

    if (!std_ecc.p256EcdsaVerify(
        &peer_pub65, &hash32, &sig_r32, &sig_s32,
    )) {
        return; // reject
    }

    var rng = std_rand.xoshiroInit(0xDEADBEEF);
    var priv: [32]u8 = undefined;
    var pub65: [65]u8 = undefined;
    std_ecc.p256Generate(&rng, &priv, &pub65);
}
```

## API

### `x25519`

**Purpose** — computes the X25519 scalar multiplication `out = scalar · u`.

**When to use** — ECDH with an X25519 peer, or any raw RFC 7748 operation
where the caller already has the u-coordinate.

**Signature** — `pub fn x25519(scalar: *const [32]u8, u: *const [32]u8, out: *[32]u8) !void`

**Parameters**
- `scalar` — the 32-byte scalar; the RFC 7748 clamp (clear low 3 bits, clear
  bit 255, set bit 254) is applied internally. The caller's array is not
  modified.
- `u` — the peer's 32-byte little-endian Montgomery u-coordinate.
- `out` — the 32-byte shared u-coordinate.

**Returns** — nothing; writes `out`.

**Errors**
- `error.WeakPublicKey` — the result is all zero (RFC 7748 low-order-point
  rejection).

**Example**
```zig
var shared: [32]u8 = undefined;
try std_ecc.x25519(&private_key, &peer_public, &shared);
```

**Gotchas** — the clamp is included, so pass the raw private scalar; do not
clamp it yourself. All-zero output is rejected, never returned. The function
is constant-time with respect to the scalar.

### `x25519Base`

**Purpose** — X25519 scalar multiplication by the curve base point `u = 9`.

**When to use** — deriving an X25519 public key from a private scalar.

**Signature** — `pub fn x25519Base(scalar: *const [32]u8, out: *[32]u8) !void`

**Parameters**
- `scalar` — the 32-byte private scalar; clamped internally.
- `out` — the 32-byte public key.

**Returns** — nothing; writes `out`.

**Errors**
- `error.WeakPublicKey` — the all-zero output case (practically unreachable for
  a clamped scalar and the base point, but part of the shared contract).

**Example**
```zig
var pub_key: [32]u8 = undefined;
try std_ecc.x25519Base(&private_key, &pub_key);
```

**Gotchas** — equivalent to `x25519(scalar, {9, 0, …, 0}, out)` with the clamp
included.

### `p256Generate`

**Purpose** — generates a P-256 key pair from the caller's xoshiro256\*\*
state.

**When to use** — ephemeral or long-term P-256 key generation where the caller
owns the RNG state and its seeding policy.

**Signature** — `pub fn p256Generate(rng: *std_rand.Xoshiro256, priv: *[32]u8, pub_out: *[65]u8) void`

**Parameters**
- `rng` — caller-owned xoshiro256\*\* state; advanced by the draws.
- `priv` — the 32-byte private-scalar destination (big-endian, in `[1, n-1]`).
- `pub_out` — the 65-byte uncompressed public-key destination.

**Returns** — nothing; writes both outputs. Draws a candidate, rejects it if it
is zero or ≥ the curve order, and repeats.

**Errors** — none. The loop always terminates for a functioning RNG.

**Example**
```zig
var rng = std_rand.xoshiroInit(seed);
var priv: [32]u8 = undefined;
var pub65: [65]u8 = undefined;
std_ecc.p256Generate(&rng, &priv, &pub65);
```

**Gotchas** — determinism is the caller's responsibility: the same RNG seed
and draw sequence produce the same key. Seed the RNG from a real entropy source
in production (R6 keeps `std_ecc` itself deterministic).

### `p256Ecdh`

**Purpose** — P-256 ECDH: multiplies the peer's uncompressed public point by
the caller's private scalar.

**When to use** — deriving a 32-byte shared secret with a P-256 peer.

**Signature** — `pub fn p256Ecdh(priv: *const [32]u8, peer_pub: *const [65]u8, out: *[32]u8) !void`

**Parameters**
- `priv` — the 32-byte private scalar in `[1, n-1]`.
- `peer_pub` — the peer's 65-byte uncompressed public key
  (`0x04 ‖ X ‖ Y`).
- `out` — the 32-byte shared X-coordinate destination.

**Returns** — nothing; writes the shared secret.

**Errors**
- `error.InvalidPrivateKey` — `priv` is zero or ≥ the curve order.
- `error.InvalidPublicKey` — the peer point is malformed/off-curve, the
  multiplication yields the point at infinity, or decoding fails.

**Example**
```zig
var shared: [32]u8 = undefined;
try std_ecc.p256Ecdh(&private_key, &peer_pub65, &shared);
```

**Gotchas** — only uncompressed keys are accepted; a compressed (33-byte) key
is rejected. The ECDH output is the X-coordinate only, as specified; feed it
through the protocol's KDF rather than using it directly.

### `p256EcdsaVerify`

**Purpose** — verifies a P-256 ECDSA signature over a caller-supplied SHA-256
hash.

**When to use** — certificate/chain signature verification and TLS
`ecdsa_secp256r1_sha256` CertificateVerify messages.

**Signature** — `pub fn p256EcdsaVerify(pub_uncompressed: *const [65]u8, hash32: *const [32]u8, r: *const [32]u8, s: *const [32]u8) bool`

**Parameters**
- `pub_uncompressed` — the 65-byte uncompressed public key.
- `hash32` — SHA-256(message) for the signed message.
- `r`, `s` — the signature scalars, 32 bytes big-endian each.

**Returns** — `true` only when the signature is valid; `false` for every
malformed, out-of-range, or non-verifying input.

**Errors** — none; invalid signatures are `false`, never a silent accept.

**Example**
```zig
if (!std_ecc.p256EcdsaVerify(&pub65, &hash32, &sig_r, &sig_s)) return; // reject
```

**Gotchas** — `r` and `s` must be nonzero and `< n`; the implementation checks
both explicitly (a zero-`r`/zero-`s` acceptance is a tested negative). The hash
is not computed for you. The point must be a valid uncompressed P-256 point.

### `p384EcdsaVerify`

**Purpose** — verifies a P-384 ECDSA signature over a caller-supplied SHA-384
hash. Verify-only: there is no P-384 keygen or ECDH.

**When to use** — verifying P-384 certificate-chain signatures
(`ecdsa_secp384r1_sha384`).

**Signature** — `pub fn p384EcdsaVerify(pub_uncompressed: *const [97]u8, hash48: *const [48]u8, r: *const [48]u8, s: *const [48]u8) bool`

**Parameters**
- `pub_uncompressed` — the 97-byte uncompressed public key
  (`0x04 ‖ X ‖ Y`, 48-byte coordinates).
- `hash48` — SHA-384(message) for the signed message.
- `r`, `s` — the signature scalars, 48 bytes big-endian each.

**Returns** — `true` only when the signature is valid; `false` otherwise.

**Errors** — none; invalid signatures are `false`.

**Example**
```zig
if (!std_ecc.p384EcdsaVerify(&pub97, &hash48, &sig_r, &sig_s)) return; // reject
```

**Gotchas** — verify-only by design. `r`/`s` are range-checked and must be
nonzero. Do not assume a P-384 ECDH/keygen API exists.

## Constant-time and memory notes

- **No heap / no arena.** All state is fixed-size stack scratch; the caller
  owns every input/output buffer.
- **No f64** anywhere in the arithmetic (x87 double-rounding class is excluded).
  Field/limb arithmetic is integer-only.
- **X25519**: ref10 10-limb ladder with mask-based conditional swaps and a
  fixed 255-bit loop; no secret-dependent branch or table index.
- **P-256 / P-384**: BearSSL i31 shared engine; scalar multiplication runs a
  fixed sequence over the scalar bits with masked selection. Public-value
  decoding/range checks may branch on public data.
- **Errors are named:** `WeakPublicKey`, `InvalidPrivateKey`,
  `InvalidPublicKey`. ECDSA verify reports `false` rather than an error union;
  callers must treat `false` as rejection.

## KAT provenance

| Surface | Vectors | Fixture |
|---|---|---|
| X25519 base/shared/iteration | RFC 7748 §5.2 (Alice/Bob public keys, both shared secrets, one-iteration `s=u=9`), all-zero output → `error.WeakPublicKey` | `stdlib_x25519_xmod` |
| P-256 ECDH | NIST CAVP KAS ECC CDH P-256 shared-secret vectors (2) | `stdlib_ecc_verify_xmod` |
| P-256 ECDSA verify | NIST CAVP SigVer P-256/SHA-256 (2 good, 2 bad) plus malformed-point / zero-scalar negatives | `stdlib_ecc_verify_xmod` |
| P-384 ECDSA verify | NIST CAVP SigVer P-384/SHA-384 (2 good, 2 bad) plus zero-scalar negatives | `stdlib_ecc_verify_xmod` |
| P-256 keygen | deterministic seeded xoshiro256\*\* keygen + cross-ECDH | `stdlib_ecc_verify_xmod` |
| `-fsafe` mode | the two fixtures above emitted with the compiler default (no `-ffast`), 3 runs each | `scripts/stdlib/run_ecc_safe.sh` |

## See also

- [`crypto.md`](crypto.md) — SHA-256/384/512, HMAC, HKDF, RSA verify.
- [`cipher.md`](cipher.md) — ChaCha20-Poly1305 and AES-128-GCM.
- [`rand.md`](rand.md) — xoshiro256\*\* state used by `p256Generate`.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
