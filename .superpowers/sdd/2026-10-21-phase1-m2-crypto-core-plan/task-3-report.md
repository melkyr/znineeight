# M2 Task 3 report — `std_ecc` (X25519, P-256, P-384 verify)

Status: COMPLETE. Branch `zig1_improvements`; base HEAD
`78e5833e docs(plan): Phase1 seed version cascade after M2 T2`.
Seed not rotated. `run.err` untouched. No compiler/`std.zig` edits.

## Delivered

- `sf/src/std_ecc.zig`
  - `x25519`, `x25519Base` (RFC 7748 clamp; all-zero output →
    `error.WeakPublicKey`)
  - `p256Generate`, `p256Ecdh`
  - `p256EcdsaVerify`, `p384EcdsaVerify`
- `repro/mi_matrix/stdlib_x25519_xmod/{main.zig,expected.txt,expected.rc}`
- `repro/mi_matrix/stdlib_ecc_verify_xmod/{main.zig,expected.txt,expected.rc}`
- `scripts/stdlib/expected_dirs.txt` (both fixture dirs)
- `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`
  (`std_ecc` wired into both copy lists; counts 41→42)

## Source provenance / port choice

The task allows “one documented shared generic EC engine” for P-256/P-384.
I used BearSSL's portable i31 prime-curve engine for both curves rather than
porting p256-m plus a second P-384 implementation.

Sources obtained under `/tmp` (not added to the repo):

```
git clone --depth 1 https://www.bearssl.org/git/BearSSL /tmp/bearssl-src
git clone --depth 1 https://github.com/mpg/p256-m.git /tmp/p256-m-src
```

Ported from BearSSL `src/ec/ec_prime_i31.c` and
`src/int/i31_{add,sub,montmul,modpow,decode,decmod,encode,iszero,ninv31,rshift}.c`,
with curve constants/generators/orders from `src/ec/ec_secp256r1.c` and
`src/ec/ec_secp384r1.c`. BearSSL MIT notice is reproduced in the module header.

X25519 uses the SUPERCOP `crypto_scalarmult/curve25519/ref10` 10-limb
(26/25-bit alternating) field arithmetic and Montgomery ladder (files fetched
from the `floodyberry/supercop` mirror into `/tmp/ref10-old`). Public-domain
ref10 provenance is recorded in the module header.

p256-m was used only as an independent cross-check of the CAVP ECDH and ECDSA
vectors during development, not as shipped code.

Implementation notes:
- X25519 ladder is fixed-iteration, branchless `fe_cswap`, ref10 carry bounds;
  no secret-dependent branches/indices.
- The generic engine's point ladder is BearSSL's constant-time 2-bit window
  interpreter (`CCOPY`, no secret branches).
- BearSSL exponentiation was kept semantically identical to `br_i31_modpow`
  (plain output), with a local fixed-exponent routine that keeps intermediates
  in Montgomery form. The initial version misread `MINV(d,a,b)` as inverting
  `a`; fixed to invert `d` (BearSSL's contract).
- No heap, libm, C99, compiler builtins or f64 arithmetic. Emitted C89 builds
  under the fixture gcc flag-set.

## Fixture vectors

- RFC 7748 §5.2: Alice/Bob base points + shared secret; one-iteration
  non-base `scalar=u=09…00`; all-zero output rejection.
- NIST CAVP KAS ECC CDH P-256, Ephemeral Unified initiator ZZOnly COUNT 0/1.
- NIST CAVP SigVer P-256/SHA-256: 2 accepts, 2 rejects.
- NIST CAVP SigVer P-384/SHA-384: 2 accepts, 2 rejects.
- `p256Generate` determinism from a fixed xoshiro256** seed + cross-ECDH
  shared-secret agreement between two generated key pairs.

Bad signatures are asserted false; a silent accept panics.

## Gate evidence

### 1. Targeted fixtures with a manually staged 41-file compiler (`/tmp/m2_t2_build/zig1_5_clean`)

The `/tmp/m2_t2_build` tree was the Task 2 build with `std_ecc.zig` copied
into its `lib/` by hand for early fixture development. It is NOT a clean
pre-wiring seed; the authoritative post-wiring rebuild is §2–§3 below.

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t2_build/zig1_5_clean \
    repro/mi_matrix/stdlib_x25519_xmod repro/mi_matrix/stdlib_ecc_verify_xmod
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

### 2. Seed v112 rebuild after copy-list wiring

```
$ rm -rf /tmp/m2_t3_build
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m2_t3_build
...
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m2_t3_build ===
rc=0

$ ls /tmp/m2_t3_build/lib/*.zig | wc -l
42
$ ls /tmp/m2_t3_build/lib/std_ecc.zig
/tmp/m2_t3_build/lib/std_ecc.zig
$ md5sum /tmp/m2_t3_build/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t3_build/zig1_5_clean
```

### 3. Targeted rerun on the rebuilt compiler

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t3_build/zig1_5_clean \
    repro/mi_matrix/stdlib_x25519_xmod repro/mi_matrix/stdlib_ecc_verify_xmod
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

### 4. Explicit 3× targeted determinism

Three full targeted invocations on the rebuilt compiler:

```
=== targeted run 1 ===
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
=== targeted run 2 ===
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
=== targeted run 3 ===
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

Standalone binaries (built with `/tmp/m2_t3_build/zig1_5_clean`) run 3×
byte-identically:

```
x:
7a89335d143be1b09385ef1bc64a6d21a42b89908bc1a5b722bd5625f58f7e6c  x.1.out
7a89335d143be1b09385ef1bc64a6d21a42b89908bc1a5b722bd5625f58f7e6c  x.2.out
7a89335d143be1b09385ef1bc64a6d21a42b89908bc1a5b722bd5625f58f7e6c  x.3.out
x25519 ok
e:
848846786845d9ef102cdf2d13fe80393ed42e03f05e948375a9ef2fb2d19fb8  e.1.out
848846786845d9ef102cdf2d13fe80393ed42e03f05e948375a9ef2fb2d19fb8  e.2.out
848846786845d9ef102cdf2d13fe80393ed42e03f05e948375a9ef2fb2d19fb8  e.3.out
ecc verify ok
```

### 5. Hygiene

```
$ git diff --check
(no output; rc=0)
$ bash -n scripts/seed/build_from_seed.sh && bash -n scripts/seed/archive_seed.sh
shell-syntax-ok
```

## Crosscheck

`scripts/stdlib/ref/std_ecc/ref.c` was not added. The required gate is the KAT
fixtures above; a C reference would need vendored p256-m + BearSSL sources and
new crosscheck vectors, and was not necessary to validate the shipped module.
Full `verify_stdlib.sh`/crosscheck remains Task 4 closeout per plan.

## Concerns / notes

- The shared BearSSL i31 engine is the plan-permitted alternative to
  p256-m+BearSSL P-384; it is documented in the module header.
- `p256Ecdh` uses `error.InvalidPrivateKey` / `error.InvalidPublicKey`; only
  `error.WeakPublicKey` was named by the spec.
- `p256Generate` loops until the xoshiro-derived candidate is in `[1, n-1]`
  (same acceptance test as BearSSL/p256-m keygen).
- No seed rotation; v112 archive remains the compiler-fix seed as required.

## Fix round 1

Review findings addressed:

1. **HIGH — default `-fsafe` shift traps.** The BearSSL i31 helpers used raw
   left shifts whose high bits are intentionally discarded. Under `-fsafe`
   Z98 traps on such shifts; the fixture passed only with `-ffast`.
   Added `shlMasked(x, sh) = ((x & (0xFFFFFFFF >> sh)) << sh)` and used it in:
   - `i31Decode`
   - `i31DecodeMod`
   - `i31Encode`
   - `i31Rshift`

   The mask is branchless, so constant-time behavior is preserved. No API
   changes.
2. **LOW — ECDSA `r == 0`.** Added the missing range check alongside `s == 0`;
   both `r` and `s` must now be in `[1, n-1]`.
3. **LOW — negative validation fixtures.** Added KATs for:
   - `r = 0`, `s = 0`, `r = n`, `s = n` (P-256; `r = 0` also P-384)
   - invalid public-key tag (`0x05` instead of `0x04`)
   - off-curve public key (flipped Y bit)
   - X/Y coordinate equal to the field prime `p` (P-256 X/Y and P-384 X)
   - ECDH zero private key and private key equal to `n`
   - ECDH peer with bad tag, off-curve point, and X equal to `p`
   All assert `false`/`error.InvalidPublicKey`/`error.InvalidPrivateKey`.
4. **LOW — report accuracy.** §1 above now labels `/tmp/m2_t2_build` as a
   manually staged development tree, not a clean pre-wiring seed.

### Seed rebuild (unchanged seed, current module)

```
$ rm -rf /tmp/m2_t3_build
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m2_t3_build
...
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m2_t3_build ===
rc=0

$ ls /tmp/m2_t3_build/lib/*.zig | wc -l
42
$ md5sum /tmp/m2_t3_build/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t3_build/zig1_5_clean
$ cmp -s sf/src/std_ecc.zig /tmp/m2_t3_build/lib/std_ecc.zig
cmp_lib=0
```

### Targeted `-ffast` (harness) on rebuilt 42-lib compiler

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t3_build/zig1_5_clean \
    repro/mi_matrix/stdlib_x25519_xmod repro/mi_matrix/stdlib_ecc_verify_xmod
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs
```

### Direct default `-fsafe` emit/build/run (harness unchanged)

For each fixture, emitted with no `-ffast`:

```
$ /tmp/m2_t3_build/zig1_5_clean -o /tmp/m2_t3_safe2/<dir> \
    repro/mi_matrix/<dir>/main.zig
emit_rc=0
$ gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -I <out> -c <out>/*.c
gcc_rc=0
$ (cd <out> && sh build_target.sh linux <out>/prog)
build_rc=0
$ timeout 120 <out>/prog   # run 3×
run1_rc=0
run2_rc=0
run3_rc=0
expected_cmp=0
```

Observed `-fsafe` outputs (3 runs each, byte-identical):

```
x25519:
7a89335d143be1b09385ef1bc64a6d21a42b89908bc1a5b722bd5625f58f7e6c  run1.out
7a89335d143be1b09385ef1bc64a6d21a42b89908bc1a5b722bd5625f58f7e6c  run2.out
7a89335d143be1b09385ef1bc64a6d21a42b89908bc1a5b722bd5625f58f7e6c  run3.out
x25519 ok

ecc verify:
848846786845d9ef102cdf2d13fe80393ed42e03f05e948375a9ef2fb2d19fb8  run1.out
848846786845d9ef102cdf2d13fe80393ed42e03f05e948375a9ef2fb2d19fb8  run2.out
848846786845d9ef102cdf2d13fe80393ed42e03f05e948375a9ef2fb2d19fb8  run3.out
ecc verify ok
```

### Hygiene

```
$ git diff --check
(no output; rc=0)
$ bash -n scripts/seed/build_from_seed.sh && bash -n scripts/seed/archive_seed.sh
shell-syntax-ok
```

The public API and all previously passing KAT outputs are unchanged. Seed was
not rotated; compiler/`std.zig` and the shared harness were not modified.
