# Self-Compile 194-Error Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 194 residual self-compile gcc errors across 6 classes (V → R×6 → STOP → I → F → GATE), so each class's full-graph fixture flips GREEN with no functional regression and the self-compile count trends down-or-flat. NO `rc=0` hard gate.

**Architecture:** One read-only V task (collection-iteration verify) then six R fixtures in a row (one per error class), a STOP for operator review, I tasks per merged root cause, F tasks per root, a soft re-count check, then docs GATE. Runtime-identity is the gate, not byte-identity.

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

---

### Task I: investigate — pin upstream-correct fix per merged root cause

**Files:**
- Read: `sf/src/*.zig` (sites from the R reports)
- Create: `.superpowers/sdd/task-I-194-report.md` (report, no commit)

**Consumes:** V + R1-R6 reports + operator ruling (merged root causes). **Produces:** per-root-cause fix design.

- [ ] **Step 1: For each merged root cause, verify the mechanism**

Starting from the R probable mechanisms, trace the actual upstream cause in `sf/src`. Confirm or overturn each; cite exact file:line.

- [ ] **Step 2: Pin the fix design**

Name the exact function/line to change and the shape of the change (mirroring prior F-task discipline: minimal, upstream-consistent).

- [ ] **Step 3: Byte-identity reasoning**

For each fix, reason whether it can affect the 4 MD5s / corpus / matrix. Flag any that could change existing-correct output (the runtime-priority override governs).

- [ ] **Step 4: Flag design forks → STOP for operator ruling**

If any root cause has two valid fixes with different risk, present them and STOP.

- [ ] **Step 5: Write report**

Report at `.superpowers/sdd/task-I-194-report.md`. No commit (read-only).

---

### Task F: fix — apply the fixes

**Files:**
- Modify: `sf/src/*.zig` (the sites named in the I report)
- Report: `.superpowers/sdd/task-F-194-report.md`

**Consumes:** I report. **Produces:** each class fixture GREEN + no functional regression.

- [ ] **Step 1: Apply each fix**

Implement the I-report fixes via `edit`/`fastedit` (re-read before each edit, bottom-to-top).

- [ ] **Step 2: Rebuild + reinstall std**

```bash
bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```

- [ ] **Step 3: R fixtures GREEN**

Re-run each R fixture: dump + gcc -c. Expected: 0 errors, `.c` compiles.

- [ ] **Step 4: Runtime-identity gate (4 MD5s + matrix 21/21)**

Verify the 21-example matrix runs runtime-identical to base; for each of the 4 MD5 gates, if the MD5 changed, verify runtime-identical output and re-baseline (default). Benign emission diffs do not fail.

- [ ] **Step 5: Soft re-count observation**

Regenerate the self-compile error file (`bash scripts/self_compile/build_zig1_5.sh` → `cd /tmp/zig1_5/gen && gcc -c *.c 2>/tmp/emit_errs_194.txt`) and record the per-class counts vs the 194 baseline. Decreased-or-flat is the expectation; record whether each class went down, stayed, or rose. Not blocking.

- [ ] **Step 6: Commit**

Commit: `fix: self-compile 194-error residual classes (assign, zT-undeclared, request-member, no-member, pal, misc)`

---

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
