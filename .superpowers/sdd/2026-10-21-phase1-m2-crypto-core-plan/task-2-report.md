# Phase 1 M2 Task 2 report — std_cipher

Status: COMPLETE — targeted gate green; emitted T-table section concern noted below

## Baseline

- Branch: `zig1_improvements`; HEAD: `bf490eb9`.
- Seed-built compiler: `/tmp/m1_build/zig1_5_clean`.
- `md5sum /tmp/m1_build/zig1_5_clean`:
  `21c957730d268f1e7883176fa5413b65` (matches context fixed point).
- `run.err` is pre-existing untracked and untouched.

## Step 1 — fixtures written first

Added:
- `repro/mi_matrix/stdlib_chacha_poly_xmod/{main.zig,expected.txt,expected.rc}`
  (RFC 8439 §2.3.2 block, §2.4.2 XOR, §2.5.2 Poly1305 + streaming split,
  §2.8.2 AEAD seal/open, tampered-tag negative).
- `repro/mi_matrix/stdlib_aes_gcm_xmod/{main.zig,expected.txt,expected.rc}`
  (FIPS-197 AES-128 block; NIST GCM spec cases 1-4: empty PT/AD, empty AD,
  full blocks, non-empty AD; tampered-tag negative; arena `used` unchanged
  across a seal).

Pinned in `scripts/stdlib/expected_dirs.txt` at C-locale positions
(`stdlib_aes_gcm_xmod` before `stdlib_analyzer_*`;
`stdlib_chacha_poly_xmod` after `stdlib_capture_*`).

## Step 2 — observed FAIL (module absent)

Command:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m1_build/zig1_5_clean \
  repro/mi_matrix/stdlib_chacha_poly_xmod \
  repro/mi_matrix/stdlib_aes_gcm_xmod
```

Observed:

```
FAIL repro/mi_matrix/stdlib_chacha_poly_xmod (DUMP-RC2)
    dump stderr: error[3048]: could not resolve imported file 'std_cipher.zig'
FAIL repro/mi_matrix/stdlib_aes_gcm_xmod (DUMP-RC2)
    dump stderr: error[3048]: could not resolve imported file 'std_cipher.zig'
run_fixtures: 0 PASS / 2 FAIL over 2 dirs
```

## Step 3 — implementation

Created `sf/src/std_cipher.zig` (pure, no imports, caller-provided state):

- `chacha20Init` / `chacha20Xor`: RFC 8439 state; 20 rounds are fully
  unrolled (10 explicit double-round groups, 80 explicit quarter-round
  calls).
- `Poly1305` + `poly1305Init/Update/Final`: donna 5x26-bit limbs, all limb
  arithmetic uses `+%`/`*%`, final reduction is a branchless constant-time
  select, no data-dependent branches or table indices.
- `chacha20Poly1305Seal/Open`: RFC 8439 §2.8, Poly1305 over
  AD/pad/CT/pad/LE64 lengths; `Open` authenticates before decrypting and
  returns `error.AuthenticationFailed` on a tag mismatch.
- `Aes128` + `aes128Init/EncryptBlock`: FIPS-197 key schedule and four
  256-entry u32 T-tables (4 KiB total) declared file-scope `const`.
- `aes128GcmSeal/Open`: SP800-38D, GHASH with a 16-entry 4-bit table built
  from `H`, 96-bit-IV `J0`, 32-bit counter increment, bit-length block, and
  authenticate-before-decrypt `Open` returning `error.AuthenticationFailed`.

The compiler emits pointer-to-array `[N]u8` parameters as raw `unsigned
char *` and then indexes them as `(*p)[i]` (invalid C89). Internal helpers
therefore take slices; all public signatures remain the spec §5.2 ones.

## Step 4 — targeted results

Module copied to the seed compiler's sibling lib for fixture runs (repo
unchanged):

```
cp sf/src/std_cipher.zig /tmp/m1_build/lib/std_cipher.zig
```

Targeted gate (new fixtures + existing crypto fixtures):

```
bash scripts/stdlib/run_fixtures.sh /tmp/m1_build/zig1_5_clean \
  repro/mi_matrix/stdlib_chacha_poly_xmod \
  repro/mi_matrix/stdlib_aes_gcm_xmod \
  repro/mi_matrix/stdlib_crypto_crc32_xmod \
  repro/mi_matrix/stdlib_crypto_md5_xmod \
  repro/mi_matrix/stdlib_crypto_modpow_xmod \
  repro/mi_matrix/stdlib_crypto_prf_xmod \
  repro/mi_matrix/stdlib_crypto_rc4_xmod \
  repro/mi_matrix/stdlib_crypto_sha1_xmod \
  repro/mi_matrix/stdlib_crypto_sha256_xmod \
  repro/mi_matrix/stdlib_crypto_stress_xmod
```

Observed:

```
PASS repro/mi_matrix/stdlib_chacha_poly_xmod
PASS repro/mi_matrix/stdlib_aes_gcm_xmod
PASS repro/mi_matrix/stdlib_crypto_crc32_xmod
PASS repro/mi_matrix/stdlib_crypto_md5_xmod
PASS repro/mi_matrix/stdlib_crypto_modpow_xmod
PASS repro/mi_matrix/stdlib_crypto_prf_xmod
PASS repro/mi_matrix/stdlib_crypto_rc4_xmod
PASS repro/mi_matrix/stdlib_crypto_sha1_xmod
PASS repro/mi_matrix/stdlib_crypto_sha256_xmod
PASS repro/mi_matrix/stdlib_crypto_stress_xmod
run_fixtures: 10 PASS / 0 FAIL over 10 dirs
```

The RFC/NIST vectors and both tampered-tag cases are asserted inside the
fixtures. The negative paths explicitly check:

```
ck(err == error.AuthenticationFailed, "...")
```

and the fixtures only print `ok` after all checks pass.

Discovery pin check (no fixture execution):

```
bash scripts/corpus/list_corpus_dirs.sh \
  | grep -E '^repro/mi_matrix/stdlib_[^/]*/$|^stdlib_test/[^/]*/$' \
  | sed 's:/$::' | LC_ALL=C sort  > /tmp/actual_dirs.txt
grep -vE '^[[:space:]]*(#|$)' scripts/stdlib/expected_dirs.txt \
  | LC_ALL=C sort > /tmp/pin_dirs.txt
diff -u /tmp/pin_dirs.txt /tmp/actual_dirs.txt
```

Observed: `PIN OK (317 dirs)` (no diff).

### Determinism (explicit 3x)

Both fixture programs were built once and run three times from a scratch
CWD. All three stdout files are byte-identical:

```
chacha_poly run1 rc=0 out=cipher chacha ok
chacha_poly run2 rc=0 out=cipher chacha ok
chacha_poly run3 rc=0 out=cipher chacha ok
02ff14d0e5f7e609d54d9015a6533fd60b1fef4c90ce8bb6ea7666a4e72208de  run1.out
02ff14d0e5f7e609d54d9015a6533fd60b1fef4c90ce8bb6ea7666a4e72208de  run2.out
02ff14d0e5f7e609d54d9015a6533fd60b1fef4c90ce8bb6ea7666a4e72208de  run3.out

aes_gcm run1 rc=0 out=cipher aes gcm ok
aes_gcm run2 rc=0 out=cipher aes gcm ok
aes_gcm run3 rc=0 out=cipher aes gcm ok
ab97bf47517f189c3945f06a8b6d13189aec64cb0b4bcbac765644f13f9a40e1  run1.out
ab97bf47517f189c3945f06a8b6d13189aec64cb0b4bcbac765644f13f9a40e1  run2.out
ab97bf47517f189c3945f06a8b6d13189aec64cb0b4bcbac765644f13f9a40e1  run3.out
```

The harness also runs each fixture 3x internally and compares stdout; both
fixtures passed that check.

### Overflow-safe (`-fsafe`) build

Both fixtures were also emitted without `-ffast`, compiled, and run:

```
chacha_poly safe rc=0 out=cipher chacha ok
aes_gcm safe rc=0 out=cipher aes gcm ok
```

### T-table / arena check

`stdlib_aes_gcm_xmod` initialises a caller arena, records `ar.used`, runs
`aes128GcmSeal`, and asserts `ar.used` is unchanged. The fixture PASSes, so
the seal neither allocates from nor consumes the arena.

Source declares the tables file-scope `const`; 4 tables x 256 x u32 =
4096 B, plus the 256 B S-box. Object inspection of the emitted C:

```
nm -S --size-sort std_cipher.o | grep -E 'Te[0-3]|SBOX'
00000040 00000100 B SBOX
00000940 00000400 B Te2
00000540 00000400 B Te3
00000140 00000400 B Te0
00000d40 00000400 B Te1
```

Concern: zig1 currently lowers global `const` aggregate literals to
writable static storage (`.bss`) plus a one-time `__module_init` copy; it
does not emit C `const` initialisers for arrays (see I-R11 Option C, never
implemented). The source and 4 KiB/static/arena gates are satisfied, but
the emitted object places the tables in `.bss`, not `.rodata`. Changing
that would require a compiler-emitter change, which this task forbids.
