# Phase 1 M2 Task 4 report — docs + seed closeout

Status: COMPLETE — three docs written; user-facing docs truthed up. The
initial seed rotation v112 → v113 is **superseded by Fix round 1** (below),
which fixes the RSA-PSS `-fsafe` defect and rotates **v114**. Final seed:
v114.

> The section below records the initial closeout as it happened (v113). See
> **Fix round 1** for the final v114 state and current gate evidence.

- Branch `zig1_improvements`; base HEAD `db145998` (`docs(plan): M2 T4
  user-facing count truth-up`).
- Plan authority: `docs/superpowers/plans/2026-10-21-phase1-m2-crypto-core-plan.md`
  Task 4; spec §5.1–§5.3; `task-4-brief.md` / `task-4-context.md`.
- Closeout fixed point: `F_new` = `45158dcede81125a39a2c2c58478e21e`.
- Seed at the initial closeout: **v113**, 42 lib files (`std.zig` + 41
  `std_*.zig`); superseded by **v114** in Fix round 1.
- At the initial closeout, no source, `std.zig`, fixture, harness, or
  copy-list contents were changed (Fix round 1 then changed `std_crypto`).
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
3. At the initial v113 closeout, no source/compiler/fixture changes were
   made; only docs, the seed archive, its CHANGELOG entry, and the QUICK_REF
   seed block moved. Fix round 1 changes `std_crypto.zig` and adds the
   `-fsafe` crypto gate, then rotates v114.

## Fix round 1

Status: COMPLETE — operator option 1. RSA-PSS top-mask fixed for `-fsafe`;
committed `-fsafe` crypto gate added; crypto/seed docs truthed up; seed
rotated v113 → **v114**.

### 1. Defect reproduction (before fix)

```
$ bash scripts/stdlib/run_ecc_safe.sh /tmp/m2_t3_build/zig1_5_clean \
    repro/mi_matrix/stdlib_rsa_verify_xmod
scripts/stdlib/run_ecc_safe.sh: line 43: ... Trace/breakpoint trap ...
FAIL repro/mi_matrix/stdlib_rsa_verify_xmod (RUN1-RC133(EXPECTED0))
    scratch: /tmp/stdlib_ecc_safe.6MNdUC
    run stderr: panic: integer cast overflow in @intCast
--- repro/mi_matrix/stdlib_rsa_verify_xmod/expected.txt
+++ /tmp/stdlib_ecc_safe.6MNdUC/run1.out
@@ -1 +0,0 @@
-crypto rsa verify ok
-----------------------------------------
run_ecc_safe: 0 PASS / 1 FAIL over 1 dirs
failed: repro/mi_matrix/stdlib_rsa_verify_xmod:RUN1-RC133(EXPECTED0)
```

### 2. Fix

`sf/src/std_crypto.zig` `pssCheck`: the top mask is now computed in `u32` and
truncated, so `unused` 1..8 never overflows `u8`:

```zig
if (unused > 0) {
    var shift: u32 = @intCast(u32, 8 - unused);
    var wide: u32 = @intCast(u32, 0xFF) << shift;
    var topmask: u8 = @intCast(u8, wide & 0xFF);
    if ((em[0] & topmask) != 0) return false;
}
...
if (unused > 0) {
    var shift_clear: u32 = @intCast(u32, unused);
    var wide_clear: u32 = @intCast(u32, 0xFF) >> shift_clear;
    var clearmask: u8 = @intCast(u8, wide_clear & 0xFF);
    db[0] = db[0] & clearmask;
}
```

The same widening is applied to `clearmask` so `unused == 8` cannot hit a
shift-width `-fsafe` trap. Values for every valid case are identical; no
PKCS#1/PSS behavior changed.

New `scripts/stdlib/run_crypto_safe.sh <zig1> [dir...]` (executable): default
`repro/mi_matrix/stdlib_rsa_verify_xmod`; emits with the compiler default
(no `-ffast`), builds via `build_target.sh linux`, runs 3× from a scratch CWD,
compares rc/stdout to `expected.txt`/`expected.rc`, and fails loudly on
EMIT/BUILD/RUN trap, rc mismatch, or stdout mismatch. `run_fixtures.sh` was not
changed.

```
$ bash -n scripts/stdlib/run_crypto_safe.sh
script_syntax_ok
$ bash scripts/stdlib/run_crypto_safe.sh /tmp/m2_t4_fix_build/zig1_5_clean
PASS repro/mi_matrix/stdlib_rsa_verify_xmod (md5=a0db74fd539ee462c187f631219994ea rc=0)
----------------------------------------
run_crypto_safe: 1 PASS / 0 FAIL over 1 dirs
```

### 3. Docs accuracy

`sf/docs/std_lib/crypto.md`:

- `hkdfExpand`: a **single** call derives all requested key material (up to
  8160 bytes); removed the "call for each output block" guidance.
- HKDF provenance: RFC 5869 A.1–A.3 (SHA-256) plus a SHA-256 vector using
  A.7's **inputs**; A.7 itself is the SHA-1 case.
- BLAKE2s: `out_len` is mixed into the initial state but is not enforced at
  init; `blake2sFinal` writes `min(out.len, 32)`, so callers must pass a
  matching `out.len`.
- Added the `scripts/stdlib/run_crypto_safe.sh` row to the KAT table.

The fixture header/labels now say "RFC 5869 A.1–A.3 SHA-256 + A.7-inputs
SHA-256" (comment/label only; no fixture behavior change).

README/STD_README/QUICK_REF current-state truth-ups:

- README current fixed point is now `45158dce…` / seed **v114** (47 module
  `.c` + 48 `.h`); the old `553a39b4…` / v27 chain is labelled historical.
- The M1 `21c957…` / seed v111 memory rows and recipes are labelled **M1
  measured** / historical; no new memory numbers were invented; current
  fixed-point memory is explicitly not re-measured.
- QUICK_REF seed block is v114 with archive md5
  `d65fbb411296eaae68f5abcbdf91efbd`, manifest md5
  `35c97d7f19e39aae52e082e7fc3c2fc3`, 42 libs, `F_new`.
- STD_README has a "Shipped seed" paragraph with the same v114 provenance.

### 4. Build from v112 with the fixed std_crypto

```
$ git show db145998:release/seed/zig1-seed.tgz > /tmp/m2_t4_v112_seed.tgz
$ md5sum /tmp/m2_t4_v112_seed.tgz
578993ec772dcf2e715f705da9e451aa  /tmp/m2_t4_v112_seed.tgz
$ bash scripts/seed/build_from_seed.sh /tmp/m2_t4_v112_seed.tgz /tmp/m2_t4_fix_build
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m2_t4_fix_build ===
$ ls /tmp/m2_t4_fix_build/lib/std*.zig | wc -l
42
```

Full gate on that fixed compiler:

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_fix_build/zig1_5_clean
...
run_fixtures: 320 PASS / 0 FAIL over 320 dirs
...
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK

$ bash scripts/stdlib/run_ecc_safe.sh /tmp/m2_t4_fix_build/zig1_5_clean
PASS repro/mi_matrix/stdlib_x25519_xmod (md5=487ac9bd6b86f6d40cfc3255ce49aacf rc=0)
PASS repro/mi_matrix/stdlib_ecc_verify_xmod (md5=548f98572f83c67de2d8988e60a5b391 rc=0)
----------------------------------------
run_ecc_safe: 2 PASS / 0 FAIL over 2 dirs
```

### 5. Seed rotation v113 → v114

Rotated at fix-commit HEAD `27722aea` using the `F_new` binary and its
self-emission gen dir:

```
$ bash scripts/seed/archive_seed.sh \
    /tmp/m2_t4_fix_build/zig1_5_clean /tmp/m2_t4_fix_build/hop2 \
    release/seed/zig1-seed.tgz --update-changelog
...
[archive] gcc-only rebuild of archive C md5 (fixed point): 45158dcede81125a39a2c2c58478e21e
[archive] wrote release/seed/zig1-seed.tgz (archive md5 d65fbb411296eaae68f5abcbdf91efbd)
## 2026-10-22 — seed v114 (HEAD 27722aea)
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (42 std files; md5 `35c97d7f19e39aae52e082e7fc3c2fc3`) |
| archive md5 | `d65fbb411296eaae68f5abcbdf91efbd` |
[archive] prepended entry to /workspace/znineeight/release/seed/CHANGELOG.md
```

Archive checks:

```
$ md5sum release/seed/zig1-seed.tgz
d65fbb411296eaae68f5abcbdf91efbd  release/seed/zig1-seed.tgz
$ tar tzf release/seed/zig1-seed.tgz | grep -E '^zig1-seed/lib/std_(crypto|cipher|ecc)\.zig$'
zig1-seed/lib/std_crypto.zig
zig1-seed/lib/std_cipher.zig
zig1-seed/lib/std_ecc.zig
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | wc -l
42
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/manifest.md5 | md5sum
35c97d7f19e39aae52e082e7fc3c2fc3  -
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/zig1 | md5sum
45158dcede81125a39a2c2c58478e21e  -
$ tar xOf release/seed/zig1-seed.tgz zig1-seed/lib/std_crypto.zig | grep -n "wide_clear\|wide: u32"
1524:        var wide: u32 = @intCast(u32, 0xFF) << shift;
1535:        var wide_clear: u32 = @intCast(u32, 0xFF) >> shift_clear;
```

Fresh build from v114:

```
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m2_t4_v114_build
[seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
[seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m2_t4_v114_build ===
$ md5sum /tmp/m2_t4_v114_build/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t4_v114_build/zig1_5_clean
$ ls /tmp/m2_t4_v114_build/lib/std*.zig | wc -l
42
```

Archive-C reconstruction:

```
$ bash scripts/seed/build_from_seed.sh --reconstruct-only \
    release/seed/zig1-seed.tgz /tmp/m2_t4_v114_recon
[seed] reconstructed binary md5: 45158dcede81125a39a2c2c58478e21e
=== [seed] Done: /tmp/m2_t4_v114_recon ===
$ md5sum /tmp/m2_t4_v114_recon/zig1_5_clean
45158dcede81125a39a2c2c58478e21e  /tmp/m2_t4_v114_recon/zig1_5_clean
```

### 6. Gate on the rotated compiler

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/m2_t4_v114_build/zig1_5_clean
...
run_fixtures: 320 PASS / 0 FAIL over 320 dirs
...
run_crosscheck: 9 PASS / 0 FAIL over 9 modules
STDLIB GATE OK

$ bash scripts/stdlib/run_crypto_safe.sh /tmp/m2_t4_v114_build/zig1_5_clean
PASS repro/mi_matrix/stdlib_rsa_verify_xmod (md5=a0db74fd539ee462c187f631219994ea rc=0)
----------------------------------------
run_crypto_safe: 1 PASS / 0 FAIL over 1 dirs

$ bash scripts/stdlib/run_ecc_safe.sh /tmp/m2_t4_v114_build/zig1_5_clean
PASS repro/mi_matrix/stdlib_x25519_xmod (md5=487ac9bd6b86f6d40cfc3255ce49aacf rc=0)
PASS repro/mi_matrix/stdlib_ecc_verify_xmod (md5=548f98572f83c67de2d8988e60a5b391 rc=0)
----------------------------------------
run_ecc_safe: 2 PASS / 0 FAIL over 2 dirs
```

### 7. Commits

| # | subject | sha |
|---|---|---|
| 1 | `fix(std_crypto): safe PSS topmask under -fsafe (M2)` | `27722aea55cf3e680e3702ce309ce378c8af005d` |
| 2 | `chore(seed): rotate v114 (M2 PSS fix)` | `f95c35104880ba2ffdc59962dc6dfb0fa5e63e30` |
| 3 | `docs(std_lib): M2 crypto truth-ups + seed v114` | `8a5cd320ca9fe8bb4a44dc6e71590ef1de665f55` |
| 4 | `docs(sdd): M2 T4 fix round 1` | this report commit |

No `std_cipher` / `std_ecc` behavior or fixtures changed; no compiler change;
no push; `run.err` left untracked.

## Final-review doc fixes

Docs-only, no rerun, no seed rotation, no code/test changes.

- `sf/docs/std_lib/cipher.md`: corrected the GCM-table note — the 4-bit tables
  are stack-local (`GHash.tab`) and rebuilt per operation; only the AES
  T-tables are file-scope `const` rodata.
- `sf/docs/std_lib/crypto.md`: corrected the RSA PSS `-fsafe` KAT row — the
  top-mask path runs in all modes; `-fsafe` is what traps on the masked-shift
  overflow.

Committed as `docs(std_lib): M2 final-review doc fixes`.
