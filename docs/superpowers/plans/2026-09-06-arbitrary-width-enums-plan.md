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
- Reference compiler `/tmp/fx_subfolder/zig1` per the SEEDMIG seed model (committed seed `release/seed/zig1-seed.tgz` = zig0-built reference binary md5 `3707d33b…` + self-emission C; fixed point `24da89b9…`; provenance `release/seed/CHANGELOG.md`). Forward rebuild path: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh-out>` — NEVER point `<fresh-out>` at `/tmp/fx_subfolder` (the script `rm -rf`s it); std lib (4 std `.zig`) is copied to `<fresh-out>/lib` by the script. `bash sf/scripts/build_release.sh` (zig0) remains usable ONLY while zig0 still compiles the current `sf/src` subset; the moment a task's `sf/src` needs syntax zig0 cannot parse, rebuild the reference from the seed (STOP-present on first such use). Bootstrap-staging constraint (binding): this plan's `sf/src` feature code must be written in constructs the current seed already understands; `sf/src` may adopt new enum syntax only after the Task-4 fixed-point re-baseline + Task-5 seed rotation. Fixture recipe: `.superpowers/sdd/task-LANGWINS-report.md` Step-4 (fresh dirs REQUIRED).
- Fastedit per docs/sf/AGENTS.md X.7. Report `.superpowers/sdd/task-PACKB3-report.md` (gitignored). Ledger `.superpowers/sdd/progress.md`. Memory agent `packb3-session`.
- Per-task evidence contract. STOP-present on divergence/ambiguity/plan-vs-evidence. Subagent-driven execution.
- **Seed rotation is part of the Task-5 docs-GATE commit** (SEEDMIG model): Task 5 additionally runs `bash scripts/seed/archive_seed.sh <Task-4 fixed-point binary> <fresh gen dir> release/seed/zig1-seed.tgz --update-changelog`, staging `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` alongside EXPECTED_FAIL.md + QUICK_REF.md (the seed rotates ONLY at this operator-approved closeout — never mid-plan).

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
- [ ] **Step 2: Self-compile round-trip.** hop1==hop2; record the NEW fixed point md5 (PACK-CORE/AGG-era seed, moved by the source growth) + 42-ish `.c`, 0 `error[`, 0 PANIC.
- [ ] **Step 3: STOP-present.** Re-baseline proposal (fixed point only; NO 4-MD5 gate re-baseline); L7 GREEN row + EXPECTED_FAIL/QUICK_REF docs update in Task 5 AFTER operator approval; seed rotation to the new fixed point also happens in Task 5 (never here). No commit, no docs touched.

---

### Task 5: Docs GATE (after operator approval)

- [ ] **Step 1: EXPECTED_FAIL.** Header bump; L7 `packed_enum_field_xmod` RESOLVED marker (contract `1 3 1 1`); historical RED verbatim; no other section touched.
- [ ] **Step 2: QUICK_REF.** Newest-first bullet: PACK-B3 landed (enum(uN) backing + packed-field), L7 GREEN + contract, 4-MD5 unchanged, fixed point re-baselined, EXPECTED_FAIL version.
- [ ] **Step 3: Commit.**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
# Seed rotation (SEEDMIG model): rotate the committed seed to the Task-4 fixed-point binary
bash scripts/seed/archive_seed.sh <Task-4-fixed-point-binary> <Task-4-fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog
git add release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
git commit -m "docs: GATE — enum(uN)/L7 GREEN + fixed-point re-baseline + seed rotation (PACK-B3)"
```

- [ ] **Step 4: Report + STOP-present plan close.** All packed ladder L0-L7 GREEN after PACK-CORE/AGG/B3; remaining follow-on: LIROPTPASS.

---

## Plan Self-Review

1. **Spec coverage:** backing type/introspect (T2), packed-field + enum ops (T3), battery + re-baseline STOP (T4), docs GATE (T5); success criteria → T2/T3/T4; plain-enum neutrality + out-of-range errors covered; token FIXME out of scope.
2. **Placeholder scan:** no TBD; census anchors resolved by record-only Task 1.
3. **Type/name consistency:** enum(uN) backing uses INTWIDTH names; contract `1 3 1 1`; report `task-PACKB3-report.md`; memory agent `packb3-session`.

---

## AMENDMENT — Task-2 review sign-off: @enumToInt general-path backing typing + fit-check normalization (2026-09-08, operator ruling)

**Scope:** post-Task-2 fix on the PACK-B3 tree (HEAD a8c656ad). Operator ruling (2026-09-08): "GO WITH AGENTS amend the plan for fixes as b)" → after analysis, **fix BOTH items (general path)** before continuing to Task 3.

**Task-2 review findings being fixed:**
- **Finding 1 (Important, semantic_analyzer.zig:2033-2041):** `@enumToInt` result is typed as the backing ONLY when the backing kind is `arb_uint_type`. Spec §4.3/task Step 2 require "result typed as the backing uN". Explicit `enum(u8)/u16/u32/u64` resolve to the PRIMITIVE u8..u64 types (not arb) and keep a legacy enum-typed result; default plain `enum` also keeps it. Root cause: `enum(u32)` and plain `enum` both store `TYPE_U32` in `EnumPayload.backing_type` (type_registry.zig:84; symbol_registrator.zig:172-175), so the payload cannot discriminate explicit-vs-default without a flag. The general-path fix adds an **explicit-backing flag** recorded at parse/registrator time so EVERY `enum(uN)` (u8/u16/u32/u64 and arb u1..u64) types its `@enumToInt` result as the backing type, while plain `enum` (no backing) stays legacy/byte-neutral.
- **Finding 2 (semantic_analyzer.zig:1009):** the packed-fit gate skips the fit check when a member value `mv < 0` (`if (mv >= 0)`). `EnumMember.value` is i64 and `evalConstI64Full` stores an explicit u64 literal in (2^63, 2^64) as a NEGATIVE i64, so `enum(u3){ a = 9223372036854775808 }` silently skips the check and truncates — a real silent-truncation hole violating the "no silent truncation" binding. Fix: **normalize to an unsigned comparison** — drop the `mv >= 0` skip and compare `@bitCast(u64, mv) > maxv`, so any ≥2^63 literal is correctly rejected for N<64 while u64 backing (maxv=2^64−1) still accepts every bit pattern; a genuinely negative authored tag (invalid for unsigned backing) is also rejected. Additionally handle the auto-consecutive wrap edge: after a u64-max explicit tag, `auto_val` (i64 `+1`) wraps to 0 — `enum(u64){ a = 18446744073709551615, b }` must not silently give b=0; catch the count/overflow (auto-consecutive member exceeding maxv) with the same clean error[3000].

**Binding requirements for the fix:**
- Plain `enum` (no backing / existing forms) emission UNCHANGED byte-identical — the new flag is only set when an explicit backing is authored; all legacy paths keep the enum-typed `@enumToInt` result.
- `@enumToInt` of an explicit `enum(uN)` of ANY width (primitive u8/u16/u32/u64 or arb u1..u64) → result typed as the backing type. `@intToEnum` unchanged (already enum-typed). Byte-neutrality gates hold (corpus has explicit `enum(u8)/u16/u32` forms — their `@enumToInt`-typed results must not alter any corpus program's emission; verify).
- Fit-check normalization closes the ≥2^63 silent hole AND the u64 auto-consecutive wrap edge with ONE clean error[3000] each, no cascade/ICE. Corpus has NO negative explicit enum tags (verified) so the unsigned compare cannot regress existing programs.
- 4-MD5 byte-identical (gol 302df36b/lisp 3591bad9/json 76056b97/mud 846106ac); golden 9/9; matrix 21/21; two-hop closure (fixed point moves per Ruling A — record, do NOT re-baseline); L7 stderr unchanged (1779f5dd). Reference rebuilt md5 to record. Stage only intended sf/src files; pre-existing dirty set never staged. Commit message verbatim: `fix: PACK-B3 Task-2 review — enum(uN) @enumToInt general-path backing typing + fit-check normalization (no silent truncation)`.
- After the fix: dispatch a fix subagent + task re-review over the fix diff (base a8c656ad), then mark Task 2 complete and proceed to Task 3.

---

## AMENDMENT — Task-4/5 criteria: zig0 retirement + N-hop determinism closure (operator ruling 2026-09-08)

**Operator rulings (binding, 2026-09-08):**
1. **zig0 is retired.** `enum(uN)` (this plan) is the first syntax zig0's frozen C++ front end cannot parse → `sf/src` is no longer zig0-compilable; `build_release.sh`'s zig0 path is dead for the current `sf/src` (kept in-tree, historical). From Task 5 onward the reference compiler is built **from the committed seed** (`zig1 → zig1_5`), never zig0. **Seed v4 is annotated in `release/seed/CHANGELOG.md` as the official self-hosted / zig0-retirement milestone.**
2. **Closure criterion = N-hop stabilization** (replaces the naive `seed→hop1==hop2` two-hop expectation). A committed seed can be one generation "flavored" behind the current `sf/src` after a self-affecting change, so `hop1 ≠ hop2` is **expected and correct**; the deterministic fixed point is reached by iterating `seed→g1→g2→…→gn` until `gn == gn+1`. Per the operator: "the compiler has to be compilable 2 or 3 times so whatever source we are compiling is consistent, any flaw isn't cascading into compilation — that's a risk that can be accepted." Bounded max 4 hops; fail loud if never stable.
3. **More rigorous testing onward.** Fixed-point closure proves self-consistency, NOT correctness (a wrong-but-stable compiler is invisible to it). The 4-MD5/golden/matrix/corpus external battery is the real oracle now that zig0 is gone. Standing rule: any feature adopted into `sf/src`'s own source must be pinned by a corpus/golden program so the external battery exercises it. At every plan closeout, run BOTH (A) N-hop self-consistency stabilization AND (B) behavioral identity — the seed-rebuilt compiler re-runs the full external battery byte-identical.
4. **Task-5 measurement compiler:** rebuild `/tmp/fx_subfolder/zig1` from the seed via the N-hop chain BEFORE v76 measurements → the reference becomes `f5c2f9d2` (fixed point, std reinstalled at `/tmp/fx_subfolder/lib`). The v76 EXPECTED_FAIL section MUST state the measurement compiler (`f5c2f9d2`) explicitly.

**Task 5 is superseded by the following steps (replacing the original Step 1-4 text):**
- [ ] **Step 0 (new): Reference rebuild from seed (N-hop).** From repo-root CWD: seed v3 (`release/seed/zig1-seed.tgz`, binary `e20bfb70`) `--dump-c89 sf/src/main.zig` → gcc `-m32` → g1; g1 → dump → gcc → g2; g2 → dump → gcc → g3. Require `g2 == g3 == f5c2f9d2` (the Task-4 STOP value; hop1 `1e96b989` ≠ hop2 is EXPECTED — seed is pre-PACK-B3-flavored). Install the converged binary as `/tmp/fx_subfolder/zig1` (md5 `f5c2f9d2…`), copy the 4 std `.zig` to `/tmp/fx_subfolder/lib/`. Record the N-hop chain in the report.
- [ ] **Step 1: EXPECTED_FAIL** v75→v76 — new top GREEN section: L7 `packed_enum_field_xmod` RESOLVED (contract `1 3 1 1`, fix commit `b040caab`), fixed-point re-baseline `e20bfb70 → f5c2f9d2`, 4-MD5 unchanged (`302df36b`/`3591bad9`/`76056b97`/`846106ac`), **measurement compiler `f5c2f9d2` stated explicitly**, zig0-retirement note (first feature zig0 cannot parse). RED history verbatim below; single hunk; no other section touched.
- [ ] **Step 2: QUICK_REF** — one newest-first bullet above the current-newest (PACK-AGG-AMENDMENT): PACK-B3 landed (enum(uN) backing + packed-field), L7 GREEN `1 3 1 1`, 4-MD5 unchanged, fixed point re-baselined `e20bfb70→f5c2f9d2`, N-hop closure note, zig0-retired note, EXPECTED_FAIL v76.
- [ ] **Step 3: Commit + seed rotation.** Rotate the committed seed to seed **v4** via `bash scripts/seed/archive_seed.sh <f5c2f9d2 binary> <g3 gen dir> release/seed/zig1-seed.tgz --update-changelog`; append the **zig0-retirement / official-self-hosted milestone annotation** to the v4 CHANGELOG entry. Stage exactly 4 files.
```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
git commit -m "docs: GATE — enum(uN)/L7 GREEN + fixed-point re-baseline + seed rotation + zig0 retirement (PACK-B3)"
```
- [ ] **Step 4: Report + STOP-present plan close** (all packed-ladder L0-L7 GREEN; PACK-B3 COMPLETE; next = LIROPTPASS; note build_from_seed.sh N-hop-criterion automation + AGENTS/QUICK_REF seed-era cite refresh as follow-ons, NOT this commit).
