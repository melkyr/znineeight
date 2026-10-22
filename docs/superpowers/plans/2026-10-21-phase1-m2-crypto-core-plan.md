# Phase 1 M2 — Crypto Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the shared cryptographic foundation in std: hash/PRF/RSA-verify additions to `std_crypto`, a new `std_cipher` (ChaCha20/Poly1305/AEAD/AES-GCM), and a new `std_ecc` (X25519, P-256, P-384 verify) — everything TLS and WireGuard later need, RFC/NIST vector-pinned.

**Architecture:** Three std modules following the existing `std_crypto` contract (pure, no alloc, no errors except named verification failures, caller-provided state). Integer/limb arithmetic only (x87-safe); AES T-tables are `const` rodata. Spec §5.1–§5.3 are the binding contracts.

**Tech Stack:** Z98 (L5-style modules), C89 `ref/` ports where a portable reference exists (vendored with BSD attribution, LZ4 precedent), existing `run_fixtures.sh`/`run_crosscheck.sh` harness.

**Spec:** `docs/superpowers/specs/2026-10-21-phase1-tls-wireguard-design.md` §5.1, §5.2, §5.3, §7, §9, §10 rulings 10–12

## Global Constraints

- Z98 subset; emitted C89 builds mingw/MSVC6/OpenWatcom; no libm/C99/builtins/malloc in shipped code; no-CRT `-osw` stays linkable.
- Constant-time: no data-dependent branches/table indices in Poly1305, X25519, P-256/P-384 scalar paths.
- No f64 intermediates anywhere in arithmetic (x87 double-rounding class); conversions at API edges only, with edge KATs pinned.
- R6: no clock/env reads; randomness is caller-supplied xoshiro256\*\*.
- New files: `sf/src/std_cipher.zig`, `sf/src/std_ecc.zig`; extend `sf/src/std_crypto.zig` only; `std.zig` unchanged (by-path import).
- Gates per task (hybrid): targeted fixtures for the touched module + direct consumers + affected `run_crosscheck.sh` modules + 3× determinism. Full `verify_stdlib.sh` + full crosscheck is mandatory immediately after any change to existing module functions, shared harness/`expected_dirs.txt`, `std.zig`, or a cross-module contract, and at milestone closeout. Task 1 edits existing `std_crypto` → full gate; Task 1C-F is a compiler fix → full compiler battery + seed rotation; Tasks 2–3 are new modules → targeted-only until Task 4 closeout.
- Seed rotations: Task 1C-F rotates seed **v112** (40 lib files, unchanged copy list) with a **new** fixed point `F_new` = `45158dcede81125a39a2c2c58478e21e` (`hop2==hop3`, moving point — `hop1≠hop2` expected). Task 2 unblock wires `std_cipher` into both seed copy lists immediately (41 lib files; no seed rotation — v112 remains the 40-file compiler-fix seed). Task 4 closeout rotates seed **v113** (42 lib files: +`std_cipher`, +`std_ecc`) with fixed point `F_new` unchanged (`hop1==hop2`; std-only, compiler source unchanged). The prior anchor `21c95773…` is superseded by `F_new` (`45158dcede81125a39a2c2c58478e21e`, rotated at 1C-F).
- Commits `feat(std_crypto|std_cipher|std_ecc): … (Phase1 M2)`, `docs(std_lib): … (M2)`, `chore(seed): rotate (M2)`, `docs(sdd): … report`. STOP-present on any contract change.

## Review Focus

1. A signature-verify primitive that accepts a wrong signature silently (negative KATs required for every verify path — BadSignature must fire).
2. x87/limb conversion rounding: edge KATs (max/min limbs, 2^53 boundaries) must pin exact output.
3. Constant-time regressions (early-exit loops in scalar mult / Poly1305) — mutation check: no branch on secret-derived values.
4. AES T-tables counted into arena or stack (must be `const`; assert arena_used untouched).
5. SHA-384/512 truncation/length-field errors (64-bit length encoding) — FIPS vectors must cover ≥1-block messages.

---

### Task 1: `std_crypto` additions — SHA-384/512, HMAC-SHA256, HKDF, BLAKE2s, RSA verify

**Files:**
- Modify: `sf/src/std_crypto.zig` (append; existing SHA-1/SHA-256/MD5/CRC32/RC4/modpow untouched)
- Test: `repro/mi_matrix/stdlib_hash_sha384_512_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_crypto_prf_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_rsa_verify_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt` (sorted, C-locale)

**Interfaces:**
- Consumes: nothing new.
- Produces (spec §5.1 verbatim): `Sha384/Sha512` + init/update/final; `HmacSha256` + `hmacSha256`; `hkdfExtract`/`hkdfExpand`; `Blake2s` + `blake2sInit/Update/Final` + `hmacBlake2s`; `rsaVerifyPkcs1v15(n,e,hash_alg,hash,sig) !void`; `rsaVerifyPss(n,e,hash_alg,hash,salt_len,sig) !void`; `HashAlg` enum {sha256, sha384, sha512}; internal generic modexp (≤4096-bit `n`, fixed scratch — the existing 768-bit MSE `modpow` is NOT reused/modified).

- [ ] **Step 1:** Write failing fixtures first: FIPS 180-4 SHA-384/512 KATs (empty, "abc", 1-block, 2-block, 112-byte); RFC 4231 HMAC-SHA256 cases 1–7; RFC 5869 HKDF cases 1–3 + 7; RFC 7693 BLAKE2s KATs + keyed vectors; NIST CAVP RSA PKCS#1 v1.5 verify (2 known-good + 2 corrupted-sig cases) + PSS (SHA-256, salt 32/0) good+bad. Bad-signature cases must assert `error.BadSignature`.
- [ ] **Step 2:** Run — FAIL (module absent).
- [ ] **Step 3:** Implement to spec §5.1 signatures exactly. Generic modexp: fixed 512-byte operand scratch, right-to-left binary (verify-only; not constant-time-required since public exponent/modulus), PKCS#1 v1.5 padding check per RFC 8017 §8.2.2, PSS per §8.1.2 with MGF1 over the chosen HashAlg.
- [ ] **Step 4:** Run — PASS; full `verify_stdlib.sh` + `run_crosscheck.sh` green; existing MSE fixtures unchanged.
- [ ] **Step 5:** Commit `feat(std_crypto): hash/PRF/RSA verify additions (Phase1 M2)`.

### Task 1C-I: `const`-global rodata — investigation (report only)

**Trigger:** Task 2 STOP: source `const` T-tables are emitted as writable `.bss` + one-time `__module_init` copy; plan requires C `const` rodata. This is a compiler-correctness stopper and takes priority.

**Files:**
- Create: `.superpowers/sdd/2026-10-21-phase1-m2-crypto-core-plan/task-1c-i-report.md`
- No source/plan/spec edits in this task. Probes only under `/tmp`.

**Goal:** Produce the exact, no-tech-debt design and blast radius for emitting Z98 file-scope `const` values as C89 `static const` initializers (rodata), covering arrays of scalars, structs, and multi-dimensional arrays. Non-constant `const` initializers stay `.bss` + `__module_init`.

- [ ] **Step 1:** Enumerate every file-scope `const` shape in `sf/src`, `examples/z98`, `repro/mi_matrix`, and `scripts/stdlib/ref` (scalar literal, scalar constant-expression, 1-D array of scalars, multi-D array, struct/union, string literal, `const` with non-constant initializer). For each shape record today's emitted storage (`.bss`/`.rodata`/constant) and the required post-fix form.
- [ ] **Step 2:** Trace the complete data flow with file:line: parser `var_decl.flags` bits; `main.zig` `gv_is_storage`/`gv_has_ri` and `ModuleGlobalDecl` creation; `lowerModuleInit`/`store_global`; `emitGlobalExternDecls`; `emitModuleInitCalls`/`moduleHasRuntimeInit`; `emitArrayCopyLoop`/`emitArrayByteCopyLoop`; header extern declarations.
- [ ] **Step 3:** Specify the minimal exact design with no tech debt: how constness and initializer data reach the emitter; how C89 `static const` declarations/initializers are rendered for scalars, 1-D arrays, multi-D arrays, structs/unions, and nested combinations; how `__module_init`/`store_global` entries are skipped; how `has_runtime_init`/module-init ordering/extern headers are handled; how non-constant `const` stays `.bss`; how `const` globals referencing other consts are ordered.
- [ ] **Step 4:** Blast radius: list every affected emitted construct and expected pin/corpus/golden/examples/stdlib movement; state whether compiler self-emission changes; specify seed rotation and fixed-point consequence. Include the M2 seed-version consequence (compiler-fix rotation vs Task 4 closeout).
- [ ] **Step 5:** Test strategy (committed, non-vacuous): a dedicated compiler gate that asserts `nm` section type `R/r` (not `B/b`) for const scalar/array/struct/multi-D symbols, value-correct runtime fixture, negative cases where non-constant `const` remains `.bss`, header/extern `const` correctness, and full compiler battery commands. Identify exact test file locations/pattern.
- [ ] **Step 6:** Lateral issues list: `has_runtime_init`, `moduleHasRuntimeInit`, multi-D/struct initializer syntax, string literals, extern/header declarations, empty arrays, zero-length/partial initializers, const-only modules, dependency ordering, and any others found. Mark in-scope or explicitly out-of-scope with reason.
- [ ] **Step 7:** Commit only the report: `docs(sdd): M2 T1C-I report`.

**Stop conditions:** any `const` shape that cannot be represented as a C89 constant initializer; any need to change `std.zig`, an example, or an unrelated compiler pass; any blast-radius item that contradicts the plan. STOP-present with evidence.

### Task 1C-F: `const`-global rodata — fix + gates + seed rotation

**Depends on:** Task 1C-I. Implement the I report design exactly; do not improvise or defer shapes the I task proves in scope.

**Files (expected; final list from I report §9):**
- Create: `sf/src/const_init_eval.zig` (the one classification pass — `constInitEvaluate`)
- Modify: `sf/src/lir.zig`, `sf/src/main.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`
- Create/modify committed compiler gate + fixture(s) from I report
- Modify: seed scripts/counts as required for rotation

- [ ] **Step 1:** Add the const/initializer representation required by the I design.
- [ ] **Step 2:** Emit C89 `static const` initializers for all in-scope const shapes; remove their `__module_init`/`store_global` copies. Keep non-constant const as `.bss` + runtime init. **STOP-1 ruling (abstraction layer):** non-first-member union const initializers (C89 §3.5.7 initializes only the first member) → `constInitEvaluate` returns `null` → `.bss` fallback (correct values preserved); first-member unions, structs, multi-D arrays, and nested combinations → `static const` rodata. Documented C89 boundary; negative fixture asserts the fallback keeps correct values.
- [ ] **Step 3:** Add the committed rodata gate and fixture(s); prove non-vacuous by mutating emitters to `.bss` (must fail) and non-constant const (must stay `.bss`).
- [ ] **Step 4:** Full compiler battery: corpus frozen-1124 class file, goldens 5/5, mi_matrix 25+oob, examples 26/26 build+run, stdlib full gate, pins recorded old→new, markers, emit-support, hop closure. No unrelated fixes.
- [ ] **Step 5:** Rotate seed **v112** (compiler fix, 40-file copy list unchanged); record archive/manifest/binary/`F_new`; verify **`hop2==hop3`** (moving point — `hop1≠hop2` expected for the compiler change). Re-anchor the plan text from `21c9…` to `F_new`; update affected plan seed-version references (Task 4 → v113).
- [ ] **Step 6:** Commits: `fix(c89_emit): emit file-scope const values as C89 const rodata` + `docs(sdd): M2 T1C-F report`. No push.

### Task 2: `std_cipher` — ChaCha20, Poly1305, ChaCha20-Poly1305, AES-128-GCM

**Status:** UNBLOCKED — Task 1C-F landed. Wire `std_cipher` into both seed copy lists (no seed rotation; v112 remains 40 files), add the rodata `nm` gate, run targeted + full gates, then re-review the held commits `fe2c74d2` + `57181726`.

**Files:**
- Create: `sf/src/std_cipher.zig`
- Test: `repro/mi_matrix/stdlib_chacha_poly_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_aes_gcm_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Modify: `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (copy `std_cipher`; counts 40→41)
- Create: `scripts/compiler/gate_cipher_rodata.sh`

**Interfaces:**
- Consumes: `std_crypto` (nothing — pure primitives).
- Produces (spec §5.2 verbatim): `chacha20Init/Xor`; `poly1305Init/Update/Final` (donna 5×26-bit limbs); `chacha20Poly1305Seal/Open` (`error.AuthenticationFailed` on tag mismatch); `Aes128` + `aes128Init/EncryptBlock` (T-tables 4 KB `const`); `aes128GcmSeal/Open` with GHASH (4-bit tables).

- [ ] **Step 1:** Failing fixtures: RFC 8439 ChaCha20 block/XOR vectors, Poly1305 RFC 8439 §2.5.2 + donna-style vectors, AEAD §2.8.2 + a tamper-tag case (`AuthenticationFailed`); NIST GCM test vectors (AES-128: at least one per empty-AD/empty-PT/full case + one tamper case).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement; fully unroll the 20 ChaCha rounds; constant-time Poly1305 limb math (no 64-bit overflow traps — use `+%`/`*%` discipline as `std_crypto` does); GCM per SP800-38D.
- [ ] **Step 4:** Unblock + run — wire `std_cipher` into both seed copy lists (41 lib files; no seed rotation), rebuild from v112 seed, run targeted `std_cipher` fixtures + 3× determinism, assert T-tables are `R/r` rodata with `scripts/compiler/gate_cipher_rodata.sh`, then full `verify_stdlib.sh` + crosscheck. Commit the seed/gate change, append report, and re-review the held Task 2 commits.
- [ ] **Step 5:** Commit `feat(std_cipher): ChaCha20-Poly1305 + AES-128-GCM (Phase1 M2)`.

### Task 3: `std_ecc` — X25519, P-256, P-384 verify

**Files:**
- Create: `sf/src/std_ecc.zig`
- Test: `repro/mi_matrix/stdlib_x25519_xmod/{main.zig,expected.txt,expected.rc}`
- Test: `repro/mi_matrix/stdlib_ecc_verify_xmod/{main.zig,expected.txt,expected.rc}`
- Optional ref: `scripts/stdlib/ref/std_ecc/ref.c` (vendored portable X25519, BSD attribution) + `run_crosscheck.sh` wiring
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes: `std_rand.Xoshiro256` (P-256 keygen only).
- Produces (spec §5.3 verbatim): `x25519`/`x25519Base` (`error.WeakPublicKey` on all-zero); `p256Generate` (uncompressed 65-byte pub); `p256Ecdh`; `p256EcdsaVerify`; `p384EcdsaVerify` (verify-only, 97-byte uncompressed, SHA-384 hash).

- [ ] **Step 1:** Failing fixtures: RFC 7748 X25519 vectors (scalar mult + base + all-zero rejection); NIST CAVP P-256 ECDH shared-secret vectors; P-256 ECDSA verify good/bad (≥2 curve points each); P-384 ECDSA verify NIST CAVP good/bad (SHA-384). Bad cases assert `false`/error, never silent accept.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement: X25519 ref10-style 26-bit portable ladder; P-256 from **p256-m portable C** (port, do not write from scratch); P-384 verify from **BearSSL portable P-384** (or one shared generic EC engine for both curves — implementer's call, documented); constant-time scalar paths.
- [ ] **Step 4:** Run — PASS + targeted `std_ecc` fixtures + affected `run_crosscheck.sh` modules + 3× determinism. Full gate at Task 4 closeout.
- [ ] **Step 5:** Commit `feat(std_ecc): X25519 + P-256 + P-384 verify (Phase1 M2)`.

### Task 4: M2 closeout — docs + seed rotation

**Files:**
- Create: `sf/docs/std_lib/crypto.md`, `sf/docs/std_lib/cipher.md`, `sf/docs/std_lib/ecc.md`
- Modify: `STD_README.MD`, `README.md`, `docs/sf/QUICK_REF.md` (counts 41→42 std files, install list, module rows)
- Modify: `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh` (copy lists + counts)
- Rotate: `release/seed/` → **v113** (archive + `lib/manifest.md5`, 42 files)

- [ ] **Step 1:** Write the three docs (API contracts from spec §5.1–§5.3; constant-time and no-heap notes; KAT provenance table).
- [ ] **Step 2:** Truth-ups (STD_README domain/doc-index rows for the 3 modules; root README higher-layer list; QUICK_REF counts/install/verify line).
- [ ] **Step 3:** Seed scripts count update (`std_cipher` already wired at Task 2; add `std_ecc`); rotate seed **v113** (+`std_ecc`; 42 lib files); verify archive md5, manifest md5, binary/fixed point **`F_new`** unchanged (equals v112's `F_new`), **`hop1==hop2`** (std-only; compiler source unchanged) from rotated archive.
- [ ] **Step 4:** Full gate re-run (fixtures + crosscheck) on the rotated compiler.
- [ ] **Step 5:** Commits `docs(std_lib): crypto/cipher/ecc docs (M2)`, `chore(seed): rotate (M2)`, `docs(sdd): M2 closeout report`.
