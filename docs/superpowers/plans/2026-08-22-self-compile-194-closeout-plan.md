# Self-Compile 194-Error Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 194 residual self-compile gcc errors across 6 classes (V → R×6 → STOP → F-MIGRATE → I/F per merged group → GATE), so each class's full-graph fixture flips GREEN with no functional regression and the self-compile count trends down-or-flat. NO `rc=0` hard gate.

**Architecture:** One read-only V task (collection-iteration verify) then six R fixtures in a row (one per error class), a STOP for operator review (ruling recorded 2026-08-22: R5 migration first, C1 priority I/F, R1+R3 one I/F, R4+R6 one separate I/F), then F-MIGRATE (R5 `pal`→`pal_mod`), then I-A/F-A (C1), I-B/F-B (R1+R3 conflation root), I-C/F-C (R4+R6), soft re-count checks, then docs GATE. Runtime-identity is the gate, not byte-identity.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, gcc -m32 -std=c89, `bash sf/scripts/build_release.sh`, 4 MD5 gates, corpus 303, matrix 21/21.

## Global Constraints

- **Fixture fidelity rule:** each R fixture uses **valid Zig** and reproduces the **exact self-compile error text** (full-graph, 3+ module chain). Fixture is a diagnostic: if GREEN but self-compile errors remain, that proves full-graph-scale residual, not scope creep.
- **Per-task F gate (hard): fixture GREEN + no functional regression.** Runtime-identity is the gate, NOT byte-identity. Benign C-emission differences that do not affect functionality do not fail the gate.
- **Soft observation (not blocking):** self-compile class re-count decreased-or-flat (recorded; acceptable if fixture GREEN but count didn't drop, provided no functional regression).
- **Terminal gate: NO `rc=0` requirement.** Report final self-compile count as a metric; pass/fail = 21-example matrix + 4 MD5 gates runtime-identical.
- **4 MD5 gates (authoritative):** gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. MD5 differs → gate is runtime-identical; re-baseline is default response.
- **`sf/build/out_release/` WEDGED — NEVER touch.** All runs `timeout 120`; `--output-dir` must pre-exist.
- **Build:** `bash sf/scripts/build_release.sh` (gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`) + reinstall std (`cp sf/src/std.zig std_io.zig std_arena.zig std_net.zig /tmp/fx_subfolder/lib/`).
- **Editing:** `edit`/`fastedit` only. **Z98:** no anytype/@Type; concrete maps; `@intCast`; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue/confusion. Subagents mandatory. Commit messages verbatim per task.

---

### Task V: verify — collection-iteration slot-index-vs-value audit (read-only)

**Files:**
- Read: `sf/src/*.zig` (collection-iteration sites)
- Create: `.superpowers/sdd/task-V-194-report.md` (report, no commit)

**Consumes:** F-SWITCH root cause (switch-on-enum stored declared value instead of slot index). **Produces:** catalog of collection-iteration sites that store/read a slot index as a semantic value; live-vs-latent classification.

- [ ] **Step 1: Enumerate collection-iteration sites**

Search `sf/src/*.zig` for all loops that iterate a collection (map keys, list items, array entries) and use the index/position as a *semantic value* rather than a lookup key. The switch-on-enum bug class: `enum_value_table` iteration indexed by identifier-slot index instead of the member's declared value. Grep candidates: `enum_value_table`, `payload_idx`, `fields_start`, `members_start`, `u32ToU32Map`, `nameCache`, `resolved_type_table`, `call_arg_types`, `coercion_table`.

- [ ] **Step 2: Classify live vs latent**

For each site, determine whether it (a) produces a current self-compile gcc error (check the emitted-C pattern against `/tmp/emit_errs_e2down.txt`), or (b) is latent (would only bite on inputs not in sf/src). Mark each.

- [ ] **Step 3: Write report**

Report at `.superpowers/sdd/task-V-194-report.md`: site → file:line → iteration shape → live/latent → which R class (R1-R6) it maps to. No commit (read-only).

---

### Task R1: repro — `incompatible types when assigning` (86)

**Files:**
- Create: `repro/mi_matrix/emission_assign_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R1-194-report.md`

**Consumes:** the 86 assign errors (lower.c 59, semantic 8, type_resolver 6). **Produces:** full-graph RED fixture + probable mechanism.

- [ ] **Step 1: Identify the minimal trigger**

Sample the assign errors (`grep "incompatible types when assigning" /tmp/emit_errs_e2down.txt`). Two shapes: enum→enum (`Type`←`CoercionKind`, lower.c:40682) and `unsigned int`←`Slice/Opt`. Build a 3-module chain in which a same-named value crosses a module boundary and a temp is typed with the wrong of two types (probe: enum value used where a struct is expected, or a Slice stored into an `unsigned int`-typed temp).

- [ ] **Step 2: Verify RED = exact self-compile error text**

Run `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r1_194 <main>` then `cd /tmp/r1_194 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected: at least one `incompatible types when assigning` error textually matching a self-compile line. If not reproducible even full-graph, record that in the report (surface at STOP).

- [ ] **Step 3: Write NOTES.md + probable mechanism**

NOTES.md: fixture source, RED evidence, and the **probable mechanism** (e.g. "temp typed by first-seen type, later assigned different type") — explicitly framed as a starting hypothesis that I may overturn.

- [ ] **Step 4: Commit**

Commit: `repro: self-compile 194-error fixtures (assign class)`

---

### Task R2: repro — `zT_<n> undeclared` (68)

**Files:**
- Create: `repro/mi_matrix/emission_zT_undeclared_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R2-194-report.md`

**Consumes:** the 68 zT-undeclared errors (c89_emit 38, type_registry 17, symbol_reg 5). **Produces:** full-graph RED fixture + probable mechanism.

- [ ] **Step 1: Identify the minimal trigger**

Sample (`grep "zT_.*undeclared" /tmp/emit_errs_e2down.txt`). Shape: a temp referenced but its declaration skipped (the void-skip guard `c89_emit.zig:3076` `eff_type != 1`). Probe a construct that produces a temp whose effective type stays void — e.g. a function returning a void-typed expression used as a value, or a call whose result type is lost.

- [ ] **Step 2: Verify RED = exact error text**

Same recipe as R1. Expected: `'zT_<n>' undeclared` matching a self-compile line.

- [ ] **Step 3: Write NOTES.md + probable mechanism**

- [ ] **Step 4: Commit**

Commit: `repro: self-compile 194-error fixtures (zT undeclared class)`

---

### Task R3: repro — `request for member` (22)

**Files:**
- Create: `repro/mi_matrix/emission_request_member_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R3-194-report.md`

**Consumes:** the 22 request-for-member errors (lower.c 19, semantic 3), `.is_self`/`.result`/`.call_block_idx` (CallInfo/LirInst variant-payload). **Produces:** full-graph RED fixture + probable mechanism.

- [ ] **Step 1: Identify the minimal trigger**

Sample (`grep "request for member" /tmp/emit_errs_e2down.txt`). Shape: `.call_direct.result`-style field access on a temp whose type resolved to something not a struct (variant-payload conflation). Probe a tagged-union/struct where a nested variant field is accessed via a sibling's payload type.

- [ ] **Step 2: Verify RED = exact error text**

- [ ] **Step 3: Write NOTES.md + probable mechanism**

- [ ] **Step 4: Commit**

Commit: `repro: self-compile 194-error fixtures (request-member class)`

---

### Task R4: repro — `has no member` (8)

**Files:**
- Create: `repro/mi_matrix/emission_no_member_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R4-194-report.md`

**Consumes:** the 8 has-no-member errors (`EnumPayload has no member 'payload'` type_resolver 5, anon `f_2` c89_emit 3). **Produces:** full-graph RED fixture + probable mechanism.

- [ ] **Step 1: Identify the minimal trigger**

Sample (`grep "has no member" /tmp/emit_errs_e2down.txt`). Shapes: `.payload` on a type that isn't a tagged-union payload, and `.f_2` on an anon struct. Probe a tagged-union `.payload` access on a non-union, or an anon-struct field access via a wrong index.

- [ ] **Step 2: Verify RED = exact error text**

- [ ] **Step 3: Write NOTES.md + probable mechanism**

- [ ] **Step 4: Commit**

Commit: `repro: self-compile 194-error fixtures (no-member class)`

---

### Task R5: repro — `pal` undeclared (5)

**Files:**
- Create: `repro/mi_matrix/emission_pal_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R5-194-report.md`

**Consumes:** the 5 `'pal' undeclared` errors. **Produces:** full-graph RED fixture + probable mechanism.

- [ ] **Step 1: Identify the minimal trigger**

Sample (`grep "'pal'" /tmp/emit_errs_e2down.txt`). Shape: a global `pal` load whose type is lost. `pal` is a special builtin module. Probe a module-scope const that loads `pal` (e.g. a value-position use of a `pal` symbol) in a cross-module chain.

- [ ] **Step 2: Verify RED = exact error text**

- [ ] **Step 3: Write NOTES.md + probable mechanism**

- [ ] **Step 4: Commit**

Commit: `repro: self-compile 194-error fixtures (pal class)`

---

### Task R6: repro — misc (5)

**Files:**
- Create: `repro/mi_matrix/emission_misc_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-R6-194-report.md`

**Consumes:** the 5 misc errors (subscripted×3, too-few-args×1, aggregate×1). **Produces:** full-graph RED fixture(s) + probable mechanism.

- [ ] **Step 1: Identify the minimal trigger**

Sample (`grep -E "subscripted value|too few arguments|aggregate value" /tmp/emit_errs_e2down.txt`). Probe: a slice-typed temp used with `[]` (subscripted), a call with too few args, a struct used as scalar.

- [ ] **Step 2: Verify RED = exact error text**

- [ ] **Step 3: Write NOTES.md + probable mechanism**

- [ ] **Step 4: Commit**

Commit: `repro: self-compile 194-error fixtures (misc class)`

---

### STOP (operator review)

- [ ] **Step 1: Present all R reports + V report**

Present `.superpowers/sdd/task-V-194-report.md` + `task-R1..R6-194-report.md` to the operator. Each R carries its probable mechanism (starting hypothesis, may be wrong) and any unfixtureable-class note.

- [ ] **Step 2: Operator ruling**

Merge shared root causes across R's; re-scope or drop any unfixtureable class; amend the plan as directed. Do not proceed to I until the ruling is given.

**OPERATOR RULING (2026-08-22, recorded):** (1) **R5 = sf/src source migration FIRST** (`pal.` → `pal_mod.` in `semantic_analyzer.zig:290/:293/:844`, `symbol_registrator.zig:409-413`, `type_registry.zig:388-393/:405-410/:524-542` — the 3 files that import `pal_mod` but call bare `pal`), so the compiler is spec-compliant and emits no `pal` errors before anything else. Verified safe: zig0 resolves a module by global module-symbol namespace regardless of alias name; zig1 needs the explicit alias. A separate future note: a spec-invalid undeclared identifier should emit a diagnostic (zig1 currently drops to TYPE_VOID silently) — NOT in this plan's scope. (2) **C1 (LirInst tag-emission, 48 errors) gets its own I/F with PRIORITY.** (3) **R1+R3 fold into ONE I/F** (shared name-keyed conflation root; assign 86 + request-member 22). (4) **R4+R6 fold into ONE SEPARATE I/F** (no-member 8 + misc 5; R4 `.f_2` sub-shape + R6 aggregate sub-shape folded INTO that I step as required investigations). Rationale: two I/F groups avoid scope creep; R4/6 kept separate from R1/3 so each I/F stays focused.


---

### Task F-MIGRATE: fix R5 — migrate bare `pal` to `pal_mod` (FIRST)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (bare `pal.` at :290/:293/:844 → `pal_mod.`), `sf/src/symbol_registrator.zig` (:409-413), `sf/src/type_registry.zig` (:388-393/:405-410/:524-542)
- Report: `.superpowers/sdd/task-FMIGRATE-194-report.md`

**Consumes:** operator ruling (1). **Produces:** compiler spec-compliant — zero bare-`pal` references emitted; `emission_pal_xmod` GREEN + self-compile R5-class 5→0.

- [ ] **Step 1: Apply the source migration**

Via `edit`/`fastedit` (re-read region before each edit, bottom-to-top): in the 3 files that import `const pal_mod = @import("pal.zig")`, replace every bare `pal.` reference with `pal_mod.`. Confirm no file uses bare `pal` without importing `pal_mod`. Do NOT touch files that correctly use `const pal = @import("pal.zig")`.

- [ ] **Step 2: Grep for residual bare `pal`**

Run: `grep -rn '[^_]pal\.' sf/src/*.zig | grep -v 'pal_mod\.' | grep -v 'pal\.zig'` — expected: zero residual bare-`pal.` calls across sf/src.

- [ ] **Step 3: Rebuild + reinstall std**

```bash
bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```

- [ ] **Step 4: R5 fixture GREEN + self-compile pal-class re-count**

Dump + gcc `emission_pal_xmod` → 0 errors (GREEN). Then self-compile re-count: `bash scripts/self_compile/build_zig1_5.sh` → `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2>/tmp/emit_errs_migrate.txt`; grep `'pal' undeclared` count → 5→0. Record the full class split of the residual file (expected: 194 minus the pal-class 5 and the ~29 `zT_ = pal` R2 co-symptoms).

- [ ] **Step 5: Runtime-identity gate**

Verify matrix 21/21 runtime-identical to base `ad4e91b0`; 4 MD5 gates runtime-identical (byte-diff with runtime-identity = re-baseline default per operator). The migration is a pure alias rename — expected byte-neutral, verify anyway.

- [ ] **Step 6: Commit**

Commit: `fix: migrate bare pal to pal_mod (spec-compliant module alias)`

---

### Task I-A: investigate — C1 LirInst tag-emission (PRIORITY, 48 errors)

**Files:**
- Read: `sf/src/lower.zig:5370` (C1 site), `sf/src/c89_emit.zig` (tag-emission path)
- Create: `.superpowers/sdd/task-IA-194-report.md` (report, no commit)

**Consumes:** V report (C1 = LIVE F-SWITCH-shape, 48 errors: `zT_N.tag = zG_6BA597BC_LirInst` whole-type-global instead of variant's declared tag constant). **Produces:** fix design for C1.

- [ ] **Step 1: Trace the C1 emitter path**

Read `lower.zig:5370` (`var tg = @enumToInt(inst.tag)` context) and the emitted `lower_1EB7D337.c` `.tag = zG_6BA597BC_LirInst;` (48 hits). Pin why the whole-type global is emitted instead of the variant's declared tag constant (the F-SWITCH fix stored declared member values — is C1 the sibling that never got the same treatment?).

- [ ] **Step 2: Pin the fix design**

Name the exact function/line to change and the shape (mirroring F-SWITCH discipline). Confirm whether the fix is lower-side, emitter-side, or both.

- [ ] **Step 3: Byte-identity reasoning + write report**

Reason whether the fix can affect the 4 MD5s / corpus / matrix. Flag forks → STOP if two valid fixes with different risk. Report at `.superpowers/sdd/task-IA-194-report.md`. No commit.

---

### Task F-A: fix — C1 LirInst tag-emission (PRIORITY)

**Files:**
- Modify: `sf/src/*.zig` (sites named in the I-A report)
- Report: `.superpowers/sdd/task-FA-194-report.md`

**Consumes:** I-A report. **Produces:** C1 fixture/class closed — self-compile R1-class 48→0.

- [ ] **Step 1: Apply the I-A fix** via `edit`/`fastedit`.
- [ ] **Step 2: Rebuild + reinstall std** (`bash sf/scripts/build_release.sh` + std cp).
- [ ] **Step 3: Self-compile re-count** — R1 `incompatible types when assigning` count 86→38 (the 48 C1 errors gone); record full class split.
- [ ] **Step 4: Runtime-identity gate** — matrix 21/21 runtime-identical; 4 MD5s runtime-identical (re-baseline default on benign diff).
- [ ] **Step 5: Commit**

Commit: `fix: LirInst tag-emission emits variant declared tag constant (48 errors)`

---

### Task I-B: investigate — R1+R3 name-keyed conflation root (86+22)

**Files:**
- Read: `sf/src/c89_emit.zig:2667-2690` (hoist dedup by name_id), `:6155-6180` (dedup_names), `sf/src/lower.zig` (local_decl machinery)
- Create: `.superpowers/sdd/task-IB-194-report.md` (report, no commit)

**Consumes:** V report (B1-B7 name-conflation family) + R1/R3 reports. **Produces:** fix design for the shared root — same-named locals of different types collapse to one C local typed first-seen (R1: `incompatible types when assigning` 86; R3: `request for member` 22).

- [ ] **Step 1: Verify the shared root**

Confirm both classes trace to `emitHoistedDecls` keying locals by `name_id` only (V report B-family): R1 = two same-named locals of different types (Type vs CoercionKind, Slice vs u32); R3 = scalar vs struct (ci:usize vs CallInfo capture).

- [ ] **Step 2: Pin the fix design**

The key question: how to disambiguate hoisted locals that share a name_id but differ in type — extend the hoist dedup key (name_id + type_id? name_id + scope?) or the pre-existing capture-only disambiguation (`local_decl_is_capture`) to the hoist path. Name the exact function/line and change shape. This is the highest-risk design (it touches the emission dedup that the 4 MD5 gates exercise) — a byte-identity reasoning section is mandatory.

- [ ] **Step 3: Flag forks → STOP**

If the fix can change existing-correct output (any corpus dir with same-named same-type locals), present the options and STOP for ruling (runtime-priority override governs; a benign byte-diff would re-baseline).

- [ ] **Step 4: Write report** at `.superpowers/sdd/task-IB-194-report.md`. No commit.

---

### Task F-B: fix — R1+R3 name-keyed conflation root

**Files:**
- Modify: `sf/src/*.zig` (sites named in the I-B report)
- Report: `.superpowers/sdd/task-FB-194-report.md`

**Consumes:** I-B report (+ any STOP ruling). **Produces:** `emission_assign_xmod` + `emission_request_member_xmod` GREEN; self-compile R1 86→0 + R3 22→0.

- [ ] **Step 1: Apply the I-B fix** via `edit`/`fastedit`.
- [ ] **Step 2: Rebuild + reinstall std**.
- [ ] **Step 3: R1 + R3 fixtures GREEN** (dump + gcc → 0 errors).
- [ ] **Step 4: Self-compile re-count** — R1 →0, R3 →0; record full class split of the residual file.
- [ ] **Step 5: Runtime-identity gate** — matrix 21/21 runtime-identical; 4 MD5s runtime-identical (re-baseline default on benign diff per operator).
- [ ] **Step 6: Commit**

Commit: `fix: hoisted local disambiguation by type (name-keyed conflation, 108 errors)`

---

### Task I-C: investigate — R4+R6 no-member/misc (8+5)

**Files:**
- Read: `sf/src/c89_emit.zig` (name-keyed dedup sites, `.assign` array-copy :4273-4307, `emitMainWrapper` :2442-2482), `sf/src/lower.zig` (field-access paths)
- Create: `.superpowers/sdd/task-IC-194-report.md` (report, no commit)

**Consumes:** V report + R4/R6 reports. **Produces:** fix design for R4 (no-member 8) + R6 (misc 5), INCLUDING the two folded sub-shapes: R4 `.f_2` (2 errors, NOT reproduced in R — investigate the anon-payload field_id=2 lowering trigger) and R6 `aggregate value` (1 error, NOT cleanly reproduced — investigate the B5 `ct` shared root).

- [ ] **Step 1: Verify R4 root**

Confirm R4 = same name_id conflation (EnumPayload first-seen → later EUPayload fields fail). If the I-B fix lands first, confirm R4's dominant `.payload` shape (6 of 8) is closed by I-B's disambiguation; investigate the residual `.f_2` (2) as a distinct lowering issue (`field_id=2` on anon-payload, `fc.result`).

- [ ] **Step 2: Verify R6 root**

Confirm R6 subscripted (3) + too-few-args (1) mechanism; investigate the `aggregate value` sub-shape's B5 `ct` root (V report B5: `c89_emit.zig:4960/5046` `ct` slice vs `:5330` `ct` u32).

- [ ] **Step 3: Pin fix design + byte-identity reasoning**

Name exact functions/lines + change shapes. Flag any that could affect existing-correct output → STOP for ruling.

- [ ] **Step 4: Write report** at `.superpowers/sdd/task-IC-194-report.md`. No commit.

---

### Task F-C: fix — R4+R6 no-member/misc

**Files:**
- Modify: `sf/src/*.zig` (sites named in the I-C report)
- Report: `.superpowers/sdd/task-FC-194-report.md`

**Consumes:** I-C report (+ any STOP ruling). **Produces:** `emission_no_member_xmod` + `emission_misc_xmod` GREEN; self-compile R4 8→0 + R6 5→0.

- [ ] **Step 1: Apply the I-C fix** via `edit`/`fastedit`.
- [ ] **Step 2: Rebuild + reinstall std**.
- [ ] **Step 3: R4 + R6 fixtures GREEN** (dump + gcc → 0 errors).
- [ ] **Step 4: Self-compile re-count** — R4 →0, R6 →0; record full class split of the residual file.
- [ ] **Step 5: Runtime-identity gate** — matrix 21/21 runtime-identical; 4 MD5s runtime-identical (re-baseline default on benign diff per operator).
- [ ] **Step 6: Commit**

Commit: `fix: no-member + misc emission classes (8 + 5 errors)`


### Task GATE: reconcile docs + closeout

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATE-194-report.md`

**Consumes:** F result. **Produces:** reconciled tracking docs.

- [ ] **Step 1: Final gate sweep**

Re-verify 4 MD5s runtime-identical, corpus (303 + new fixtures), matrix 21/21, `test_analyzer_bin` "5 passed, 4 failed".

- [ ] **Step 2: Update EXPECTED_FAIL.md**

Version bump + closeout section: the 6 classes addressed, the V verify report summary, the final self-compile error count (recorded as a metric, not a gate), and any re-baselined MD5s.

- [ ] **Step 3: Update QUICK_REF.md**

Add a post-194-closeout baseline paragraph; note the self-compile count trend.

- [ ] **Step 4: Commit**

Commit: `docs: self-compile 194-error closeout GATE + reconciliation`
