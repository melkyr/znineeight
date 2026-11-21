# Phase 1 M2 Task 1 report — std_crypto additions

Status: COMPLETE — targeted fixtures PASS; full stdlib gate 315/315 + crosscheck 9/9 green

## Baseline

- Branch: `zig1_improvements`; HEAD before task: `0d61bb99` (`docs(sdd): M1 complete ledger`).
- Seed-built compiler: `/tmp/m1_build/zig1_5_clean`.
- `md5sum /tmp/m1_build/zig1_5_clean`:
  `21c957730d268f1e7883176fa5413b65` (matches context fixed point).
- Existing `stdlib_crypto_sha256_xmod` targeted run: PASS (harness environment sane).

## Fixtures written first (Step 1)

Added:
- `repro/mi_matrix/stdlib_hash_sha384_512_xmod/{main.zig,expected.txt,expected.rc}`
- `repro/mi_matrix/stdlib_crypto_prf_xmod/{main.zig,expected.txt,expected.rc}`
- `repro/mi_matrix/stdlib_rsa_verify_xmod/{main.zig,expected.txt,expected.rc}`

Pinned in `scripts/stdlib/expected_dirs.txt` at C-locale positions.

### Step 2 observed FAIL (module additions absent)

Command:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m1_build/zig1_5_clean \
  repro/mi_matrix/stdlib_hash_sha384_512_xmod \
  repro/mi_matrix/stdlib_crypto_prf_xmod \
  repro/mi_matrix/stdlib_rsa_verify_xmod
```

Observed (tail):

```
FAIL repro/mi_matrix/stdlib_hash_sha384_512_xmod (DUMP-RC2)
FAIL repro/mi_matrix/stdlib_crypto_prf_xmod (DUMP-RC2)
FAIL repro/mi_matrix/stdlib_rsa_verify_xmod (DUMP-RC2)
run_fixtures: 0 PASS / 3 FAIL over 3 dirs
```

## Implementation (Step 3)

Appended to `sf/src/std_crypto.zig` only; existing SHA-1/SHA-256/MD5/CRC-32/
RC4 and the 768-bit MSE `modpow` are untouched (no edits above the append
point).

- `Sha384`/`Sha512` streaming structs + `sha384Init/Update/Final` and
  `sha512Init/Update/Final` (64-bit words, 128-byte blocks, 16-byte length).
- `HmacSha256` struct + `hmacSha256Init/Update/Final` + one-shot
  `hmacSha256`.
- `hkdfExtract` / `hkdfExpand` (RFC 5869; >255 blocks -> `error.Corrupt`).
- `Blake2s` + `blake2sInit/Update/Final` (keyed/unkeyed, 32-bit, 10 rounds)
  + `hmacBlake2s` (keyed BLAKE2s form).
- `HashAlg` enum `{sha256, sha384, sha512}` and internal `hashData`/MGF1.
- Generic RSA verify: fixed `BigMaxWords = 128` (4096-bit), 512-byte operand
  scratch; right-to-left binary exponentiation in Montgomery form with fixed
  scratch; PKCS#1 v1.5 DigestInfo check (RFC 8017 §8.2.2); PSS with MGF1 over
  the selected hash (RFC 8017 §8.1.2).
- Every cryptographic negative path returns `error.BadSignature`; malformed
  lengths return `error.Corrupt`.

The compiler's sibling `lib/std_crypto.zig` was refreshed from the repo file
before running fixtures (`cp sf/src/std_crypto.zig /tmp/m1_build/lib/`); this
does not modify the repo.

### Targeted fixtures (Step 4, partial)

Command:

```
bash scripts/stdlib/run_fixtures.sh /tmp/m1_build/zig1_5_clean \
  repro/mi_matrix/stdlib_hash_sha384_512_xmod \
  repro/mi_matrix/stdlib_crypto_prf_xmod \
  repro/mi_matrix/stdlib_rsa_verify_xmod \
  repro/mi_matrix/stdlib_crypto_sha1_xmod \
  repro/mi_matrix/stdlib_crypto_sha256_xmod \
  repro/mi_matrix/stdlib_crypto_modpow_xmod \
  repro/mi_matrix/stdlib_crypto_md5_xmod \
  repro/mi_matrix/stdlib_crypto_crc32_xmod \
  repro/mi_matrix/stdlib_crypto_rc4_xmod \
  repro/mi_matrix/stdlib_crypto_stress_xmod
```

Observed:

```
PASS repro/mi_matrix/stdlib_hash_sha384_512_xmod
PASS repro/mi_matrix/stdlib_crypto_prf_xmod
PASS repro/mi_matrix/stdlib_rsa_verify_xmod
PASS repro/mi_matrix/stdlib_crypto_sha1_xmod
PASS repro/mi_matrix/stdlib_crypto_sha256_xmod
PASS repro/mi_matrix/stdlib_crypto_modpow_xmod
PASS repro/mi_matrix/stdlib_crypto_md5_xmod
PASS repro/mi_matrix/stdlib_crypto_crc32_xmod
PASS repro/mi_matrix/stdlib_crypto_rc4_xmod
PASS repro/mi_matrix/stdlib_crypto_stress_xmod
run_fixtures: 10 PASS / 0 FAIL over 10 dirs
```

### Full gate (Step 4)

Command:

```
bash scripts/stdlib/verify_stdlib.sh /tmp/m1_build/zig1_5_clean
```

Observed (tail; full log at `/tmp/m2t1/gate.log`):

```
run_fixtures: 315 PASS / 0 FAIL over 315 dirs
== std-lib crosscheck gate ==
PASS smoke (3 vectors)
PASS std_hpa (8 vectors)
PASS std_lz4 (20 vectors)
PASS std_noise (1 vectors)
PASS std_num (1 vectors)
PASS std_pathfind (2 vectors)
PASS std_physics (1 vectors)
PASS std_rand (2 vectors)
PASS std_zstd (30 vectors)
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

`run_fixtures.sh` runs every fixture three times and requires byte-identical
stdout, and diffs stdout/exit code against the committed goldens, so the 315
PASS row is also the determinism result for this gate.

Existing MSE fixtures are unchanged: `git diff --numstat` reports only
additions (`sf/src/std_crypto.zig` 838 insertions, 0 deletions;
`scripts/stdlib/expected_dirs.txt` 3 insertions, 0 deletions).

## Commits

- Code + fixtures: `2a2dc13828c6898d42a6a7783004c243c4153a22`
  (`feat(std_crypto): hash/PRF/RSA verify additions (Phase1 M2)`)
- Report: this commit (`docs(sdd): M2 T1 report`)

## Concerns

None. The generic 4096-bit Montgomery modexp was validated against the
OpenSSL-generated 2048-bit RSA vectors; PKCS#1 v1.5 (SHA-256, SHA-384) and
PSS/SHA-256 (salt 32/0) good cases pass, and all four corrupted-signature
cases return `error.BadSignature`.
