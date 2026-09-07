# Packed Struct Aggregates (P4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend packed support to L3/L4/L5/L6 — nested packed-struct leaf fields, a new untagged `packed_union` TypeKind, `[N]Packed` arrays + packed storage globals, and packed by-value/cross-module — turning the committed L3/L4/L5/L6 packed RED fixtures GREEN with their locked byte-exact contracts.

**Architecture:** On top of PACK-CORE (packed `struct_type` flag + bit-layout side table + LIR `load_bitfield`/`store_bitfield` + single-member-struct carrier). Type layer gains a distinct `packed_union` TypeKind (untagged; members at bit 0; size = ceil(max bits/8)) and nested packed-struct field layout (accumulated leaf bit offsets); the emitter generalizes to union/nested/array/global/by-value. Executes AFTER PACK-CORE.

Design spec: `docs/superpowers/specs/2026-09-06-packed-struct-aggregates-design.md` (operator-approved).

## Global Constraints

- **Depends on PACK-CORE executed first** (which depends on INTWIDTH). Consumes: packed `struct_type` flag, bit-layout side table, LIR `load_bitfield`/`store_bitfield` + armed DCE/inst-switch sites, single-member-struct carrier (PACK-CORE spec §4.5 AMENDMENT 1).
- **`packed union` = a new `packed_union` TypeKind** (untagged). It is NOT a flag on `union_type` (which means tagged union).
- **`token.zig` tagged-union-in-packed FIXME is OUT of this plan** (separate future follow-on).
- Byte-neutral gates on every F task before the emitter layer lands: 4-MD5 (gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `846106ac`), golden 9/9, matrix 21/21, and the self-compile two-hop closure (hop1==hop2 — per PACK-CORE Ruling A, the fixed-point md5 moves on every `sf/src` edit; the closure is the gate, the value re-baselines only at the Task-5 STOP, operator-ruled, never silent).
- `examples/z98` originals, gate programs, goldens, `sf/build/`, `out_release/` untouched. Stage ONLY intended files. Pre-existing dirty/untracked set (2026-08-26 plan doc, `mnemoria/*`, `.zig1_*.tmp`, `build/`, `examples/z98/json_parser_upgraded/`) never staged.
- Reference compiler: `/tmp/fx_subfolder/zig1` per the SEEDMIG seed model. Committed seed at execution = **seed v1** (`release/seed/zig1-seed.tgz`, archive md5 `033a3018…`, 2,397,776 B): zig1 binary = PACK-CORE fixed point md5 `fd3e1c0e1787be22e2b2bc09e9916e4c`, self-emission C 41 `.c` + 42 `.h` (8,164,820 B), layout per SEEDMIG spec (zig1-seed/{zig1,gen,c_exit.c,runtime 5-file no net_prelude,lib 4 std,SEED_README.txt}); provenance `release/seed/CHANGELOG.md` v1 entry (2026-09-07, PACK-CORE rotation). Reference at execution: `/tmp/fx_subfolder/zig1` rebuilt to md5 `801fdc55…` (PACK-CORE Task-6 battery rebuild, canonical std reinstalled at `/tmp/fx_subfolder/lib`). Forward rebuild path: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <fresh-out>` — NEVER point `<fresh-out>` at `/tmp/fx_subfolder` (the script `rm -rf`s it); std lib (4 std `.zig`) is copied to `<fresh-out>/lib` by the script. `bash sf/scripts/build_release.sh` (zig0) remains usable ONLY while zig0 still compiles the current `sf/src` subset; the moment a task's `sf/src` needs syntax zig0 cannot parse, rebuild the reference from the seed (STOP-present on first such use). Bootstrap-staging constraint (binding): this plan's `sf/src` feature code must be written in constructs the current seed (`fd3e1c0e`-era) already understands; `sf/src` may adopt new packed syntax only after the Task-5 fixed-point re-baseline + Task-6 seed rotation. Fixture run/classify recipe: `.superpowers/sdd/task-LANGWINS-report.md` Step-4 (fresh-dir `rm -rf`+`mkdir -p` REQUIRED).
- Fastedit per docs/sf/AGENTS.md X.7. No python/sed/bulk transforms; no `git checkout` to erase.
- Report: `.superpowers/sdd/task-PACKAGG-report.md` (gitignored). Ledger: `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory`, agent `packagg-session`.
- Per-task evidence contract: status, commits, per-gate md5/evidence, fixture run-gate output, concerns. STOP-present on any divergence/ambiguity/plan-vs-evidence mismatch.
- Subagent-driven execution with the SDD skill.
- **Seed rotation is part of the Task-6 docs-GATE commit** (SEEDMIG model): Task 6 additionally runs `bash scripts/seed/archive_seed.sh <Task-5 fixed-point binary> <fresh gen dir> release/seed/zig1-seed.tgz --update-changelog`, staging `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` alongside EXPECTED_FAIL.md + QUICK_REF.md (the seed rotates ONLY at this operator-approved closeout — never mid-plan).

---

### Task 1: Record-only census + RED baseline (no commit)

**Files:**
- Record only: `.superpowers/sdd/task-PACKAGG-report.md` header + Task 1 section.

**Interfaces:**
- Produces: (a) baseline (HEAD, reference md5, 4-MD5 gates, fixed point, EXPECTED_FAIL version at execution); (b) the authoritative packed-aggregate edit-map at the current post-PACK-CORE HEAD; (c) RED reproduction of L3/L4/L5/L6.

- [ ] **Step 1: Baseline.** HEAD sha; `md5sum /tmp/fx_subfolder/zig1` (expect the PACK-CORE battery rebuild `801fdc55…`, canonical std reinstalled; if it differs STOP-present); 4-MD5 gate re-run (byte-identical `302df36b`/`3591bad9`/`76056b97`/`846106ac`); confirm the PACK-CORE fixed point `fd3e1c0e1787be22e2b2bc09e9916e4c` via a hop1==hop2 round-trip; record EXPECTED_FAIL header version (v73 at execution).

- [ ] **Step 2: RED reproduction.** For each `repro/mi_matrix/packed_{l3_nested,union,array_global,byvalue_module}_xmod` main.zig (+ types.zig where present) run the authoritative classify/run recipe → confirm the current RED-class state on the post-PACK-CORE compiler and record deterministically. Expected at PACK-CORE close (verify; do NOT assume): `l3_nested` = GREEN-guard class (clean `error[3000]` — the PACK-CORE B6 gate rejects the nested packed-struct field); `packed_union` = FAIL (packed-union path unparsed → parse error[2000]); `packed_array_global_xmod` + `packed_byvalue_module_xmod` = GCCFAIL (natural-member `.x` emission on the single-member carrier — the PACK-CORE Task-5 disclosure).

- [ ] **Step 3: Union census.** Map the union parse/resolution/emission path: how `union(enum)` (tagged) is parsed (union-decl path, tag), resolved (TypeKind), laid out (tag field + payload), and emitted — to place `packed union { … }` (untagged) + the new `packed_union` TypeKind with the lowest churn. Record how many sites dispatch on the union TypeKind and which would need a sibling arm.

- [ ] **Step 4: Nested + aggregate census.** Map: how a struct field's resolved type + bit width are available at layout time (side table), how leaf `o.inner.a` member accesses lower today (chained field_access → the PACK-CORE field path), how `[N]T` arrays of a value type are emitted (type name + stride), how storage globals (`var x: [N]T`) emit extern/def headers across modules (the netbind/std_net module-emission sites), and how by-value struct params/returns lower to C today (C89 struct-by-value precedent in the emitter). Record the store-drop/C4 generalization site (packed-typed base must keep whole-element global stores live).

- [ ] **Step 5: Report + ledger.** Edit-map + baseline into the report; ledger line. No commit.

---

### Task 2: `packed union` — parse + TypeKind + layout + introspect (byte-neutral)

**Files:**
- Modify (per Task-1 census): parser (expression-primary `packed union {…}` untagged path), type registry (new `packed_union` TypeKind + layout resolution: members at bit 0, `@bitSizeOf` = max member width, `@sizeOf` = ceil/8, `@alignOf` = 1), sema (member-type B6 gate + `&packed.field` reject).
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-1 union census.
- Produces: `packed union` parses/resolves/type-checks; L4 fixture frontend-accepted but still RED at run-gate until the emitter layer.

- [ ] **Step 1: Parse.** Add `packed union { … }` (no `(enum)` tag) to the expression-primary union path → packed-union AST node. Fixture `packed_union_xmod` (`const U = packed union { a: u4, b: u12 };`) parses cleanly.

- [ ] **Step 2: TypeKind + layout.** New `packed_union` TypeKind in type_registry (follow the tagged-union kind's registration shape). Layout resolution: every member `bit_offset` = 0, `bit_width` = `intWidthBits` (`bool`→1); `@bitSizeOf` = max member width; `@sizeOf` = `ceil(max/8)`; `@alignOf` = 1. Verify on a scratch probe: `@sizeOf(U)` = 2, `@bitSizeOf(U)` = 12.

- [ ] **Step 3: Sema B6.** Gate packed-union member types to the PACK-CORE set (bool/uN/iN + packed containers); reject the rest cleanly; `&packed.field` clean error. No ICE.

- [ ] **Step 4: Byte-neutrality gate.** Rebuild; 4-MD5 byte-identical; golden 9/9; self-compile fixed point unchanged; record the L4 fixture front-end state.

- [ ] **Step 5: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: packed union — parse + packed_union TypeKind + layout + introspect (PACK-AGG)"
```

- [ ] **Step 6: Report.** Union design, probe evidence, byte-neutrality, concerns. Ledger line.

---

### Task 3: Nested packed-struct fields (leaf) (byte-neutral)

**Files:**
- Modify (per Task-1 census): type/layout (nested field `bit_width` = inner total bits; leaf offsets = accumulated chain), sema (allow packed-struct fields nested; whole-sub-container-value use → clean diagnostic or census-decided handling, never silent), LIR (leaf access at accumulated `bit_offset`).
- Record: report + ledger.

**Interfaces:**
- Consumes: Task-1 nested census.
- Produces: `o.inner.a` leaf reads/writes carry the accumulated bit offset; L3 fixture frontend/lowering-correct but still RED at run-gate until the emitter layer.

- [ ] **Step 1: Nested layout.** A packed-struct field whose type is a packed `struct_type` records `bit_width` = inner total bits and occupies the accumulated bit range. Lowering a leaf `o.inner.a` resolves to `(inner_bit_offset + a_bit_offset)` → a single `load_bitfield`/`store_bitfield`. Verify the L3 chain math (Outer head@0 u2, inner@2 width 6 → inner.a@2 width 3, inner.b@5 width 3, tail@8 width 2; total 10 bits → size 2).

- [ ] **Step 2: Whole-sub-container policy.** Per the census, whole-sub-container value moves (`o.inner` as a value) are either rejected with a clean diagnostic or handled by the carrier struct-by-value path — pick the census-supported option and document it in the report; never silently mis-emit. The L3 fixture uses LEAF access only.

- [ ] **Step 3: Byte-neutrality gate.** Rebuild; 4-MD5 byte-identical; golden 9/9; self-compile fixed point unchanged; record the L3 fixture state.

- [ ] **Step 4: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: packed struct — nested packed-struct leaf fields (PACK-AGG)"
```

- [ ] **Step 5: Report.** Chain math, leaf/whole-sub-container policy, byte-neutrality, concerns. Ledger line.

---

### Task 4: Emitter — union/nested/array/global/by-value → L3/L4/L5/L6 GREEN

**Files:**
- Modify (per Task-1 census): c89_emit.zig (packed-union + nested access bodies at their bit offsets, `[N]Packed` arrays + packed global array extern/def, by-value native struct ops, store-drop generalization for packed bases).
- Record: report + ledger.

**Interfaces:**
- Consumes: Tasks 2-3 type/lowering support.
- Produces: L3/L4/L5/L6 GREEN byte-exact; fixed point moves (emitter-layer commit) → Task 5 re-baseline.

- [ ] **Step 1: Union/nested access.** Emit `store_bitfield`/`load_bitfield` bodies honoring the (possibly nested-accumulated, or zero for union) bit offsets and member widths; union members share the carrier bytes. Verify L4 (b=3000 → byte0..1; read a = low 4 bits = 8) and L3 (accumulated offsets).

- [ ] **Step 2: Arrays + globals.** `[N]Packed` emits as a struct-array of the carrier typedef (stride = `@sizeOf`, no padding); packed storage globals emit the carrier-array extern/def across modules (follow the netbind/std_net storage-global emission pattern); whole-element store `grid[i] = Cell{…}` = native struct-by-value and is kept live by the store-drop generalization (packed-typed base treated like the array case). Verify L5 byte-dump `&grid[0]` and `grid[3].x/.y`.

- [ ] **Step 3: By-value + cross-module.** Packed by-value param/return/assign use native C struct-by-value on the carrier typedef (no hidden-pointer wrapper). Cross-module layout identity: the same type id resolves to the same bit layout + same carrier typedef in both modules (the `types` module's `build`/`sum` and main agree). Verify L6: `@sizeOf(Pair)`=1 both modules, `sum(build(10,11))`=21, byte `0xBA`=186.

- [ ] **Step 4: GREEN gate.** Build, run the four fixtures via the authoritative recipe: byte-exact `2 5 6 3 3` / `2 8` / `1 33 3 4` / `1 21 186`, RUNRC=0, deterministic 3×.

- [ ] **Step 5: Regression.** 4-MD5 byte-identical; golden 9/9; matrix 21/21; corpus zero-asymmetric except the 4 packed dirs; EXPECTED_FAIL version-bump + GREEN rows are the Task-6 docs GATE.

- [ ] **Step 6: Commit.**

```bash
git add sf/src/<per-census>
git commit -m "feat: packed aggregates — union/nested/array/global/by-value emission (PACK-AGG)"
```

- [ ] **Step 7: Report.** GREEN evidence (4 fixtures ×3, md5s, emitted-C shapes incl. array/global/by-value), byte-neutrality on the common set, fixed-point-moved disclosure, concerns. Ledger line.

---

### Task 5: Full battery + fixed-point re-baseline STOP-present

**Files:**
- Record only.

- [ ] **Step 1: Battery.** golden 9/9 rc0 byte-identical; matrix 21/21; full corpus sweep (common set zero-asymmetric except the 4 packed dirs); 4-MD5 byte-identical.

- [ ] **Step 2: Self-compile round-trip.** hop1==hop2; record the NEW fixed point md5 (base = PACK-CORE-era seed v1 `fd3e1c0e…`, moved by this plan's emitter-layer commit) + 42-ish `.c`, 0 `error[`, 0 PANIC.

- [ ] **Step 3: STOP-present.** Re-baseline proposal (fixed point only; NO 4-MD5 gate re-baseline); L3/L4/L5/L6 GREEN rows need the EXPECTED_FAIL/QUICK_REF docs update in Task 6 AFTER operator approval; seed rotation to the new fixed point also happens in Task 6 (never here). No commit, no docs touched.

---

### Task 6: Docs GATE (after operator approval)

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (header bump + RESOLVED rows for the four fixtures with fixing commits + GREEN contracts; RED history preserved verbatim), `docs/sf/QUICK_REF.md` (newest-first baseline bullet).
- Record: report + ledger.

- [ ] **Step 1: EXPECTED_FAIL.** Version bump; four RESOLVED markers (contracts `2 5 6 3 3`/`2 8`/`1 33 3 4`/`1 21 186`); historical RED text verbatim below; no other section touched.

- [ ] **Step 2: QUICK_REF.** Newest-first bullet above the current-newest: PACK-AGG landed (packed union TypeKind + nested/array/global/by-value), L3-L6 GREEN + contracts, 4-MD5 unchanged, fixed point re-baselined, EXPECTED_FAIL version, token.zig FIXME deferred note.

- [ ] **Step 3: Commit.**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
# Seed rotation (SEEDMIG model): rotate the committed seed to the Task-5 fixed-point binary
bash scripts/seed/archive_seed.sh <Task-5-fixed-point-binary> <Task-5-fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog
git add release/seed/zig1-seed.tgz release/seed/CHANGELOG.md
git commit -m "docs: GATE — packed aggregates L3-L6 GREEN + fixed-point re-baseline + seed rotation (PACK-AGG)"
```

- [ ] **Step 4: Report + STOP-present plan close** (PACK-B3 L7 remains; token.zig FIXME deferred; operator-authority to continue).

---

## Plan Self-Review

1. **Spec coverage:** packed union parse/TypeKind/layout/introspect (T2), nested leaf + whole-sub-container policy (T3), emitter union/nested/array/global/by-value → L3-L6 GREEN (T4), battery + re-baseline STOP (T5), docs GATE (T6); success criteria → T4/T5; token.zig FIXME + PACK-B3 out of scope.
2. **Placeholder scan:** no TBD; census-dependent anchors resolved by record-only Task 1 (established pattern); contracts are the committed fixture values.
3. **Type/name consistency:** `packed_union` TypeKind; carrier = PACK-CORE single-member struct (AMENDMENT 1); contracts byte-exact; report file `task-PACKAGG-report.md`; memory agent `packagg-session`.
