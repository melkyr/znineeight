# Phase 1 M2 Task 4 report — docs + seed v113 closeout

Status: COMPLETE — three docs written; user-facing docs truthed up; seed
rotated v112 → v113; full gate green on the rotated compiler.

- Branch `zig1_improvements`; base HEAD `db145998` (`docs(plan): M2 T4
  user-facing count truth-up`).
- Plan authority: `docs/superpowers/plans/2026-10-21-phase1-m2-crypto-core-plan.md`
  Task 4; spec §5.1–§5.3; `task-4-brief.md` / `task-4-context.md`.
- Closeout fixed point: `F_new` = `45158dcede81125a39a2c2c58478e21e`.
- Seed: **v113**, 42 lib files (`std.zig` + 41 `std_*.zig`).
- No source, `std.zig`, fixture, harness, or copy-list contents were changed.
- `run.err` left untracked/uncommitted.

Commits (in order):

| # | subject | sha |
|---|---|---|
| 1 | `docs(std_lib): crypto/cipher/ecc docs (M2)` | `fe5b3c035537686ed65ac2cc69565984c198ed01` |
| 2 | `chore(seed): rotate (M2)` | `aad59d57cff44a2e3b2012a6e55cfddeb2e63975` |
| 3 | `docs(sdd): M2 closeout report` | this report commit |

## 1. New domain docs

Created:

- `sf/docs/std_lib/crypto.md` — `std_crypto`: existing SHA-1/SHA-256/MD5/
  CRC-32/RC4/`modpow`, plus M2 SHA-384/512, HMAC-SHA256 (one-shot + streaming),
  HKDF extract/expand, BLAKE2s/HMAC-BLAKE2s, `HashAlg`, and RSA PKCS#1 v1.5 /
  PSS verify.
- `sf/docs/std_lib/cipher.md` — `std_cipher`: ChaCha20, Poly1305,
  ChaCha20-Poly1305 AEAD, AES-128, AES-128-GCM.
- `sf/docs/std_lib/ecc.md` — `std_ecc`: X25519/X25519Base, P-256
  keygen/ECDH/ECDSA verify, P-384 ECDSA verify.

Each doc follows the existing `sf/docs/std_lib/*.md` shape: module table,
overview, quick start, per-function API entries with source-exact signatures,
parameters, returns, errors, examples, gotchas, constant-time/no-heap notes, a
KAT provenance table, and "See also". Signatures were cross-checked against
the sources:

```
$ grep -n "^pub fn\|^pub const" sf/src/std_crypto.zig sf/src/std_cipher.zig sf/src/std_ecc.zig
```

Recorded contracts:

- `std_crypto` / `std_cipher` are pure and import nothing; `std_ecc` imports
  only `std_rand` for `p256Generate`. None allocate.
- `std_crypto` errors: `error.Corrupt` for malformed lengths / unusable RSA
  inputs and `error.BadSignature` for failed verification; `HashAlg` makes
  `UnsupportedAlgorithm` unrepresentable. RSA is verify-only, generic modexp
  cap 4096-bit.
- `std_cipher` errors: `error.Corrupt` for length mismatch and
  `error.AuthenticationFailed` for a bad tag; `Open` authenticates before
  decrypting. AES T-tables are file-scope `const` C89 rodata (`R/r`,
  `scripts/compiler/gate_cipher_rodata.sh`); GHASH uses 4-bit tables. AES is
  explicitly documented as the classic software T-table construction (not
  bitsliced); Poly1305/AEAD comparisons avoid secret-dependent branches.
- `std_ecc`: X25519 RFC 7748 clamp + all-zero `error.WeakPublicKey`;
  `InvalidPrivateKey` / `InvalidPublicKey` for P-256 ECDH; ECDSA verify is
  `bool` (false = reject) with explicit nonzero/range checks; P-384 is
  verify-only; uncompressed keys are 65/97 bytes; ref10 / BearSSL i31
  provenance, integer-only, constant-time scalar paths.

## 2. Truth-ups

`STD_README.MD`:

- L5 row names cryptography and adds `std_cipher`, `std_ecc`.
- "Which module" rows split hashes/PRF, RSA verify, cipher, and ECC onto the
  three new docs.
- Domain-docs index adds `crypto.md`, `cipher.md`, `ecc.md`; `codecs.md`
  remains for base64/hex/UTF-8/parse/LZ4 and points at `crypto.md` for the
  legacy crypto primitives. Section date updated to `2026-10-22 — M2`.

`README.md`:

- Higher-layer list adds `std_cipher` and `std_ecc`.
- Standard-library paragraph records the M2 crypto/cipher/ECC capabilities.
- Section date updated to `2026-10-22 — M2`.

`docs/sf/QUICK_REF.md`:

- Current seed block: **v113**, archive md5
  `92d39942ed3d08a6543d29d5fafc5a95`, binary/fixed point
  `45158dcede81125a39a2c2c58478e21e`, `gen/` 47 `.c` + 48 `.h`
  (10,691,275 bytes), `lib/` 42 std `.zig` + `manifest.md5`
  (`b4c3059de37b3f5de2948ebc019e18a9`); notes `std_cipher` / `std_ecc`.
- Inventory: **41** `std_*.zig` + `std.zig` = **42**; list adds the two
  modules; `build_from_seed.sh` installs all 42.
- Install recipe adds `sf/src/std_cipher.zig` and `sf/src/std_ecc.zig`.
- Verify/gate count updated to the observed **320/0** fixtures (the brief said
  318; see Concerns) and discovery pin to 320 dirs (310 stdlib + 10 usage).
- Added M2 bullets for `std_crypto` additions, `std_cipher`, `std_ecc`.

## 3. Seed copy-list check (no edits)

Both copy lists already contained `std_cipher.zig` and `std_ecc.zig`; the
actual `sf/src` set matches both lists exactly.

```
$ a=$(grep "for f in std.zig std_io.zig" scripts/seed/archive_seed.sh); \
  printf '%s\n' "$a" | grep -o 'std[0-9a-z_]*\.zig' | sort | uniq > /tmp/list_archive.txt
$ b=$(grep 'cp "\$ROOT"/sf/src/std.zig' scripts/seed/build_from_seed.sh); \
  printf '%s\n' "$b" | grep -o 'std[0-9a-z_]*\.zig' | sort | uniq > /tmp/list_build.txt
$ ls sf/src/std*.zig | xargs -n1 basename | sort > /tmp/list_actual.txt
$ echo "actual=$(wc -l < /tmp/list_actual.txt) archive=$(wc -l < /tmp/list_archive.txt) build=$(wc -l < /tmp/list_build.txt)"
actual=42 archive=42 build=42
$ diff /tmp/list_actual.txt /tmp/list_archive.txt && echo archive_matches
archive_matches
$ diff /tmp/list_actual.txt /tmp/list_build.txt && echo build_matches
build_matches
$ grep -E 'std_cipher\.zig|std_ecc\.zig' /tmp/list_archive.txt /tmp/list_build.txt
/tmp/list_archive.txt:std_cipher.zig
/tmp/list_archive.txt:std_ecc.zig
/tmp/list_build.txt:std_cipher.zig
/tmp/list_build.txt:std_ecc.zig
```

## 4. Seed rotation v112 → v113

Pre-rotation state: v112 archive md5
`578993ec772dcf2e715f705da9e451aa`, binary/fixed point `F_new`, 40 lib
files. Used the existing `F_new` binary and its self-emission gen dir:

```
$ md5sum /tmp/m2_t3_build/zig1_5_clean /tmp/m2_t3_build/hop2/zig1_hop2
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t3_build/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t3_build/hop2/zig1_hop2
```

Rotation command (run at docs-commit HEAD `fe5b3c03`, so the CHANGELOG
provenance HEAD is the docs commit):

```
$ bash scripts/seed/archive_seed.sh \
    /tmp/m2_t3_build/zig1_5_clean /tmp/m2_t3_build/hop2 \
    release/seed/zig1-seed.tgz --update-changelog
...
[archive] gcc-only rebuild of archive C md5 (fixed point): 45158dcede81125a39a2c2c58478e21e
[archive] wrote release/seed/zig1-seed.tgz (archive md5 92d39942ed3d08a6543d29d5fafc5a95)
--- CHANGELOG entry ---
## 2026-10-22 — seed v113 (HEAD fe5b3c03)
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (42 std files; md5 `b4c3059de37b3f5de2948ebc019e18a9`) |
| archive md5 | `92d39942ed3d08a6543d29d5fafc5a95` |
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

Archive checks:

```
$ md5sum release/seed/zig1-seed.tgz
92d39942ed3d08a6543d29d5fafc5a95  release/seed/zig1-seed.tgz
$ tar tzf release/seed/zig1-seed.tgz | grep -E '^zig1-seed/lib/std_(cipher|ecc)\.zig$'
zig1-seed/lib/std_cipher.zig
zig1-seed/lib/std_ecc.zig
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | wc -l
42
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | md5sum
b4c3059de37b3f5de2948ebc019e18a9  -
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/zig1 | md5sum
45158dcede81125a39a2c2c58478e21e  -
```

Archive `lib/manifest.md5` rows for the new modules:

```
1d31712ee09ecfcebbe6e644b9637633  std_cipher.zig
d7b9529ca2aa7f763367ec027f5a7dbf  std_ecc.zig
```

Fresh rebuilt binary and archive-C reconstruction:

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m2_t4_seed
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m2_t4_seed ===
$ md5sum /tmp/m2_t4_seed/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t4_seed/zig1_5_clean
$ ls /tmp/m2_t4_seed/lib/std*.zig | wc -l
42

$ bash scripts/seed/build_from_seed.sh --reconstruct-only \
    release/seed/zig1-seed.tgz /tmp/m2_t4_recon
[seed] reconstructed binary md5: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m2_t4_recon ===
$ md5sum /tmp/m2_t4_recon/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t4_recon/zig1_5_clean
```

## 5. Full gate on the rotated compiler

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_seed/zig1_5_clean
...
run_fixtures: 320 PASS / 0 FAIL over 320 dirs
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
----------------------------------------
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK
```

Targeted `std_ecc` and default-mode gates:

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/m2_t4_seed/zig1_5_clean \
    repro/mi_matrix/stdlib_x25519_xmod repro/mi_matrix/stdlib_ecc_verify_xmod
PASS repro/mi_matrix/stdlib_x25519_xmod
PASS repro/mi_matrix/stdlib_ecc_verify_xmod
----------------------------------------
run_fixtures: 2 PASS / 0 FAIL over 2 dirs

$ bash scripts/stdlib/run_ecc_safe.sh /tmp/m2_t4_seed/zig1_5_clean
PASS repro/mi_matrix/stdlib_x25519_xmod (md5=487ac9bd6b86f6d40cfc3255ce49aacf rc=0)
PASS repro/mi_matrix/stdlib_ecc_verify_xmod (md5=548f98572f83c67de2d8988e60a5b391 rc=0)
----------------------------------------
run_ecc_safe: 2 PASS / 0 FAIL over 2 dirs
```

## 6. Concerns

1. **Fixture count is 320, not the brief's 318.** Task 2's gate was 318
   before Task 3 added and pinned `stdlib_x25519_xmod` +
   `stdlib_ecc_verify_xmod` (`git show 8af805dc -- scripts/stdlib/expected_dirs.txt`;
   the pin now has 320 entries: 310 `stdlib_*` + 10 `stdlib_test/*`). No pin or
   fixture was changed here; the docs/report use the observed 320/0.
2. `run.err` remains untracked as instructed.
3. No source/compiler/fixture changes were made; only docs, the seed archive,
   its CHANGELOG entry, and the QUICK_REF seed block moved.
