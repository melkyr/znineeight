# Arbitrary-Width Enums (P5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add general `enum(uN)` (explicit arbitrary-width integer backing via the INTWIDTH registry) usable standalone and as a `packed struct` field — turning the committed L7 `packed_enum_field_xmod` RED fixture GREEN with contract `1 3 1 1`, while plain `enum` stays byte-identical.

**Architecture:** The enum type gains an explicit N-bit backing from INTWIDTH (`intWidthBits`/`intIsSigned`/carrier rules); enum values ride the backing-int representation, so no new LIR op is needed. Standalone `@enumToInt`/`@intToEnum`/`@sizeOf`/`@bitSizeOf`/`@alignOf` honor the backing width; as a packed-struct field, `enum(uN)` uses the PACK-CORE bit-field path at width N. Executes AFTER INTWIDTH and PACK-CORE.

Design spec: `docs/superpowers/specs/2026-09-06-arbitrary-width-enums-design.md` (operator-approved).

## Global Constraints

- Depends on INTWIDTH + PACK-CORE executed first. Consumes: the uN registry/width model; the packed bit-layout side table + LIR `load_bitfield`/`store_bitfield`; the single-member-struct carrier (PACK-CORE spec §4.5 AMENDMENT 1).
- Byte-neutral gates on every F task before the emission/backing layer lands: 4-MD5 (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`), golden 9/9, matrix 21/21, self-compile hop identity (fixed point moves only at the Task 5 re-baseline STOP, operator-ruled).
- Plain `enum` (no backing / existing forms) byte-identical — no silent re-baseline.
- `examples/z98` originals, gate programs, goldens, `sf/build/`, `out_release/` untouched; stage ONLY intended files; pre-existing dirty/untracked set never staged.
- Reference compiler `/tmp/fx_subfolder/zig1` (post-INTWIDTH+POST-PACK-CORE md5 at execution; std lib reinstalled at `/tmp/fx_subfolder/lib`). Fixture recipe: `.superpowers/sdd/task-LANGWINS-report.md` Step-4 (fresh dirs REQUIRED).
- Fastedit per docs/sf/AGENTS.md X.7. Report `.superpowers/sdd/task-PACKB3-report.md` (gitignored). Ledger `.superpowers/sdd/progress.md`. Memory agent `packb3-session`.
- Per-task evidence contract. STOP-present on divergence/ambiguity/plan-vs-evidence. Subagent-driven execution.

---

### Task 1: Record-only census + RED baseline (no commit)

- [ ] **Step 1: Baseline.** HEAD sha; reference md5; 4-MD5 gates; fixed point; EXPECTED_FAIL version at execution.
- [ ] **Step 2: RED reproduction.** `packed_enum_field_xmod` classify/run → RED + current front-end state on the post-PACK-CORE compiler.
- [ ] **Step 3: Enum census.** Map the full enum machinery at the executed HEAD: enum parse forms (`enum`, `enum(uN)`?, `union(enum)`), type representation (backing type field? member value storage i64 at type_registry.zig:87-era), `@enumToInt`/`@intToEnum`/`.tag`/enum-literal resolution, `@sizeOf`/`@alignOf`/`@bitSizeOf` of an enum today, enum switch case-value lowering, and the runtime/checked conversion precedent (`@intToEnum` out-of-range behavior). Record which sites assume a fixed backing and would need the width.
- [ ] **Step 4: INTWIDTH/PACK-CORE interfaces.** Confirm the executed uN registry names (`intWidthBits`/`intIsSigned`/carrier) and the packed-field acceptance gate to extend (enum(uN) accepted, bit width N).
- [ ] **Step 5: Report + ledger.** Edit-map + baseline. No commit.

---

### Task 2: enum(uN) type/backing + introspect (byte-neutral)

- [ ] **Step 1: Type layer.** Enum gains an explicit backing-width field (N from the `uN` registry when `enum(uN)`); plain `enum` keeps its current backing. Layout: default tags 0..count-1, explicit values with fit check (`count-1` ≤ `2^N - 1`); out-of-range → clean error[3000].
- [ ] **Step 2: Sema/introspect.** `@sizeOf(Color)` = backing carrier size (u3 → 1); `@bitSizeOf(Color)` = N; `@alignOf` = backing align; `@enumToInt` result typed as the backing uN; `@intToEnum` typed as the enum. Standalone probes compile.
- [ ] **Step 3: Byte-neutrality gate.** Plain enums + the whole non-enum(uN) corpus: 4-MD5 byte-identical; golden 9/9; fixed point unchanged.
- [ ] **Step 4: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: enum(uN) — arbitrary-width backing + introspect (PACK-B3)"
```

- [ ] **Step 5: Report.** Enum machinery mapping, probe evidence, byte-neutrality, concerns. Ledger line.

---

### Task 3: enum(uN) in packed fields + @enumToInt/@intToEnum on the backing → L7 GREEN

- [ ] **Step 1: Packed-field acceptance.** PACK-CORE's packed-field gate accepts `enum(uN)` fields; layout records field `bit_width` = N; field read/write through `load_bitfield`/`store_bitfield` like an `uN` field.
- [ ] **Step 2: Enum member ops on the backing.** Enum literal/store, compare, switch case-value, `.tag`, and `@enumToInt`/`@intToEnum` operate at width N (mask/checked-cast per the INTWIDTH emission rules). Verify L7 emission: on=true@0, color=green=1@1..3 → byte 3.
- [ ] **Step 3: GREEN gate.** L7 run-gate byte-exact `1 3 1 1`, RUNRC=0, deterministic 3×; standalone enum(uN) probes correct.
- [ ] **Step 4: Regression.** 4-MD5 byte-identical; golden 9/9; matrix 21/21; corpus zero-asymmetric except the 1 packed dir. EXPECTED_FAIL version-bump + GREEN row are the Task-5 docs GATE.
- [ ] **Step 5: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: enum(uN) packed fields + backing-width enum ops (PACK-B3)"
```

- [ ] **Step 6: Report.** GREEN evidence ×3, emitted-C shapes, regression, fixed-point-moved disclosure, concerns. Ledger line.

---

### Task 4: Full battery + fixed-point re-baseline STOP-present

- [ ] **Step 1: Battery.** golden 9/9; matrix 21/21; full corpus (common set zero-asymmetric except the L7 dir); 4-MD5 byte-identical.
- [ ] **Step 2: Self-compile round-trip.** hop1==hop2; record the NEW fixed point md5 (moved by the source growth) + 42-ish `.c`, 0 `error[`, 0 PANIC.
- [ ] **Step 3: STOP-present.** Re-baseline proposal (fixed point only; NO 4-MD5 gate re-baseline); L7 GREEN row + EXPECTED_FAIL/QUICK_REF docs update in Task 5 AFTER operator approval. No commit, no docs touched.

---

### Task 5: Docs GATE (after operator approval)

- [ ] **Step 1: EXPECTED_FAIL.** Header bump; L7 `packed_enum_field_xmod` RESOLVED marker (contract `1 3 1 1`); historical RED verbatim; no other section touched.
- [ ] **Step 2: QUICK_REF.** Newest-first bullet: PACK-B3 landed (enum(uN) backing + packed-field), L7 GREEN + contract, 4-MD5 unchanged, fixed point re-baselined, EXPECTED_FAIL version.
- [ ] **Step 3: Commit.**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — enum(uN)/L7 GREEN + fixed-point re-baseline (PACK-B3)"
```

- [ ] **Step 4: Report + STOP-present plan close.** All packed ladder L0-L7 GREEN after PACK-CORE/AGG/B3; remaining follow-on: LIROPTPASS.

---

## Plan Self-Review

1. **Spec coverage:** backing type/introspect (T2), packed-field + enum ops (T3), battery + re-baseline STOP (T4), docs GATE (T5); success criteria → T2/T3/T4; plain-enum neutrality + out-of-range errors covered; token FIXME out of scope.
2. **Placeholder scan:** no TBD; census anchors resolved by record-only Task 1.
3. **Type/name consistency:** enum(uN) backing uses INTWIDTH names; contract `1 3 1 1`; report `task-PACKB3-report.md`; memory agent `packb3-session`.
