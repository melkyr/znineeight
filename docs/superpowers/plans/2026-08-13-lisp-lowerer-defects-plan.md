# lisp_interpreter Lowerer Defects Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two sema-rooted lowerer defects gating `examples/z98/lisp_interpreter` (bare-union literal in struct literal → 5× `zT_N` undeclared; module-scope `?T = null` global init typed `int` → 1× `Opt_49` mismatch), achieving 21/21 examples end-to-end.

**Architecture:** Both defects fixed at sema as the upstream (operator ruling m0759/m0761), with lowerer/emitter changes only as the necessary downstream completion. R (2 repros) → I (batched confirmation + blast radius + tech docs) → combined STOP → F1 (Defect A) → F2 (Defect B) → F3 (gate sweep + fold further cleanup; STOP if a third defect surfaces).

**Tech Stack:** Z98 compiler (`sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/main.zig`), zig1 at `/tmp/fx_subfolder/zig1` (out_release wedged), gcc -m32 C89, repro battery, tech docs.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **CRITICAL build environment:** `sf/build/out_release/` is WEDGED (any access hangs). **Compiler under test = `/tmp/fx_subfolder/zig1`.** The scripts already point there (uncommitted, operator-authorized). Do NOT touch out_release. Rebuild only if you change sf/src: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: /tmp/fx_subfolder/zig1 ===`.
- **Compile recipe:** `mkdir -p DIR && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir DIR <main.zig>`; gcc: `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c DIR/*.c` then link `zig_runtime.c zig_pal.c` (NO net_runtime.c).
- **Repro convention (post-F4):** repro `main.zig` uses `std.io.printInt(...)` with LOCAL `std.zig` + `std_io.zig` copies (byte-identical to `sf/src/std.zig`/`std_io.zig` — the resolver has no search-path, D1 precedent). Copy from `repro/mi_matrix/net_builtin_test/` (already has local copies). NO `__bootstrap_print_int` (migrated off in F4).
- **RUNTIME gate mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 AND print the expected output. Compile-only gates are FORBIDDEN.
- **4 MD5 gates:** gol `b246a2fecc0b5ff4402912c49970cdae`, lisp `141994cc81ab4bbb89722b7d30af419d`, json `f50ce1e6800d9e1365c019e46ac61292`, mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT a gate). Byte-identical UNLESS operator-approved re-baseline with runtime proof (AMENDMENT B).
- **Corpus:** 240 dirs, OK=233/FAIL=3/GG=4. FAIL must not increase. The 2 new repros are added to the OK count.
- **Tech-doc maintenance (AGENTS §1.1.1):** every I-task and source-changing F-task MUST update the corresponding `sf/docs/tech_docs/*.md` — corrected line refs, descriptions, `[updated: 2026-08-13]` annotation. Check INDEX.md Table A.
- **Editing:** `edit` (exact strings) or `fastedit` (line ranges; re-read region immediately before each edit; bottom-to-top). NO sed/python bulk transforms. NO scope creep.
- **The plan is the ONLY authority.** Plan says A → do A. If you believe X/Y is better, STOP and present. On any issue, STOP.
- **I-tasks report then STOP for combined operator ruling.** F-tasks do NOT start until the ruling.
- **F3: if a THIRD pre-existing defect surfaces** once lisp_interpreter fully compiles (the F1 lesson — clearing one block exposed builtins.zig), STOP and present. Do not silently expand scope.
- **Build-mode standing orders:** no compression in build session, plan-only authority, STOP on issues, subagents, fastedit, explain QUICK_REF to subagents, use timeouts.

---

### Task R: Create 2 repros (union_literal_nested_xmod, global_null_init_xmod)

**Files:**
- Create: `repro/mi_matrix/union_literal_nested_xmod/lib.zig`, `main.zig`, `NOTES.md`, local `std.zig` + `std_io.zig` copies
- Create: `repro/mi_matrix/global_null_init_xmod/lib.zig`, `main.zig`, `NOTES.md`, local `std.zig` + `std_io.zig` copies
- Report: `.superpowers/sdd/task-R-lisp-report.md`

**Interfaces:**
- Consumes: the defect loci (spec §2): Defect A = `union_type` gap in sema resolveStructInit/lower field-loop/emitFieldAssign; Defect B = missing coercion in main.zig:400-441 global-init path.
- Produces: 2 repros that gcc-FAIL pre-fix with the exact lisp_interpreter error classes, green post-fix.

**Context:** The 2 defects gate lisp_interpreter. The repros isolate each defect at minimal size so F1/F2 have regression guards.

- [ ] **Step 1: Create `union_literal_nested_xmod/`**

Copy local `std.zig` + `std_io.zig` from `repro/mi_matrix/net_builtin_test/`. Create `lib.zig`:
```zig
pub const Inner = union {
    Int: i64,
    Sym: i32,
};

pub const Tag = enum { A, B };

pub const Wrapper = struct {
    tag: Tag,
    data: Inner,
};

pub fn makeWrapper(v: i64) Wrapper {
    return Wrapper{ .tag = Tag.A, .data = Inner{ .Int = v } };
}
```
Create `main.zig`:
```zig
const std = @import("std.zig");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var w = lib_mod.makeWrapper(@intCast(i64, 42));
    std.io.printInt(@intCast(i32, w.data.Int));
}
```
Verify pre-fix: dump rc=0, gcc compile rc≠0 (`'zT_N' undeclared` — the inner union literal construction dropped).

- [ ] **Step 2: Create `global_null_init_xmod/`**

Copy local `std.zig` + `std_io.zig`. Create `lib.zig`:
```zig
const Node = struct { v: i32, next: ?*Node };

var g: ?*Node = null;

pub fn get() ?*Node {
    return g;
}
```
Create `main.zig`:
```zig
const std = @import("std.zig");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var p = lib_mod.get();
    if (p == null) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
}
```
Verify pre-fix: dump rc=0, gcc compile rc≠0 (`incompatible types when assigning to type 'zT_..._Opt_NN' from type 'int'`).

- [ ] **Step 3: Run zig0 oracle on /tmp copies**

zig0 writes beside the source — use /tmp copies. Expected: both compile clean (the oracle handles both constructs).

- [ ] **Step 4: Write NOTES.md for each repro**

Mirror `repro/mi_matrix/net_builtin_test/NOTES.md` format: What it tests / The compiler gap (file:line loci from the spec) / Measured result (pre-fix gcc errors) / Oracle verification / Expected classification (FAIL pre-fix → OK post-fix).

- [ ] **Step 5: Write the R-report**

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/union_literal_nested_xmod/ repro/mi_matrix/global_null_init_xmod/
git commit -m "repro: bare-union-in-struct-literal + global-null-init lowerer defects"
```

**Gate:** both repros gcc-FAIL pre-fix with the documented error classes; zig0 oracle clean; NOTES.md written; committed.

---

### Task I: Batched investigation (2 sub-investigations, one combined STOP)

**Files:**
- Investigate: `sf/src/semantic_analyzer.zig` (`:1029`), `sf/src/lower.zig` (`:3283-3423`, `:1267-1302`), `sf/src/c89_emit.zig` (`:188`, `:4202`), `sf/src/main.zig` (`:400-441`)
- Modify (docs): `sf/docs/tech_docs/05_semantic_analysis.md`, `07_lir_lowering.md`, `08_c89_emission.md`
- Reports: `.superpowers/sdd/I-lisp-defA-report.md`, `.superpowers/sdd/I-lisp-defB-report.md`

**Interfaces:**
- Consumes: the 2 repros, the spec §2 loci.
- Produces: mechanism confirmation at HEAD, MD5 blast radius, tech-doc updates, fix recommendations.

**Context:** The explore investigation found the loci; the I-tasks re-confirm at HEAD, reproduce on the repros, verify blast radius, update tech docs. NO compiler source changes.

- [ ] **Step 1: Confirm Defect A at HEAD**

Read `semantic_analyzer.zig:1029-1094` (resolveStructInit), `lower.zig:3283-3423` (struct_init field loop), `c89_emit.zig:188-293` (emitFieldAssign) + `:4202-4209` (store_field union branch). Confirm: `union_type` missing in all three struct-literal-path sites; store_field already handles it. Run `union_literal_nested_xmod` → gcc error `'zT_N' undeclared` confirmed.

- [ ] **Step 2: Confirm Defect B at HEAD**

Read `main.zig:400-441` (global-init sema), `semantic_analyzer.zig:1862-1867` (function-body coercion record), `lower.zig:1267-1302` (null branch + fallback), `c89_emit.zig:605` + `:4502-4514` (null→int) + `:3932` (store_global). Confirm: global-init path never records coercion. Run `global_null_init_xmod` → gcc error `incompatible types ... Opt_NN from int` confirmed.

- [ ] **Step 3: Assess MD5 blast radius**

Grep all 4 gate example dirs (`examples/z98/game_of_life/`, `lisp_interpreter_curr/`, `json_parser/`, `mud_server/`) for: (a) bare `union { ... }` literals used as struct-literal field values, (b) module-scope `var x: ?T = null` / `= undefined` globals. Expected: none → all 4 MD5s byte-identical post-fix. Report which (if any) would change.

- [ ] **Step 4: Update tech docs**

`05_semantic_analysis.md` (resolveStructInit union_type gap), `07_lir_lowering.md` (struct-init field loop + module-init null path), `08_c89_emission.md` (emitFieldAssign union_type) — each `[updated: 2026-08-13]`, corrected refs. Document current behavior + the gap. Do NOT fix code.

- [ ] **Step 5: Write the I-reports**

- [ ] **Step 6: Report back — combined STOP**

Report both mechanisms (file:line), blast radius, recommended fixes (A: 3-layer union_type; B: sema coercion record). **STOP for operator ruling before F1/F2.**

**Gate:** both mechanisms confirmed at HEAD with file:line; both repros reproduce the exact gcc errors; MD5 blast radius assessed; tech docs updated. No compiler source changes.

---

### Task F1: Fix Defect A — union_type in the struct-literal path

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (`:1029` add `union_type` branch to `resolveStructInit`)
- Modify: `sf/src/lower.zig` (`:3363-3421` add `union_type` branch to struct_init field loop)
- Modify: `sf/src/c89_emit.zig` (`:188` `emitFieldAssign` add `union_type` branch)
- Modify (docs): `sf/docs/tech_docs/05_semantic_analysis.md`, `07_lir_lowering.md`, `08_c89_emission.md` to FIXED
- Test: `repro/mi_matrix/union_literal_nested_xmod/`

**Interfaces:**
- Consumes: I Defect-A report, R repro.
- Produces: bare-union literals resolve + lower + emit correctly in struct literals.

**Context:** Defect A = `union_type` missing at the 3 struct-literal-path sites. sema is the upstream (resolves to TYPE_VOID today); lower + emitter complete the flow. Mirror the existing `struct_type` branch at each site.

- [ ] **Step 1: Write the failing test (red)**

`union_literal_nested_xmod/` is the test. Run pre-fix: dump rc=0, gcc rc≠0 (`'zT_N' undeclared`). This is the red state.

- [ ] **Step 2: Implement the sema fix**

In `semantic_analyzer.zig:1029` `semanticAnalyzerResolveStructInit`, add a `union_type` branch mirroring the `struct_type` branch (`:1066-1093`): resolve the struct-init node to the union type, push per-field expected types, record coercion for the field inits. Verify against the actual source — mirror the struct_type branch's exact structure (field iteration, `pushExpectedType`, `tryRecordCoercion`).

- [ ] **Step 3: Implement the lower fix**

In `lower.zig:3283-3423` struct_init field loop, add a `union_type` branch (after the `tagged_union_type` and `struct_type` branches) emitting the field assignment, mirroring the struct_type branch (resolve field name_id → assign_field with the field index).

- [ ] **Step 4: Implement the emitter fix**

In `c89_emit.zig:188` `emitFieldAssign`, add a `union_type` branch. Read the sibling `store_field` union handling at `:4202-4209` — mirror its union field-access emission (`base.field`). Ensure the C output assigns the union member correctly.

- [ ] **Step 5: Build + verify repro green**

Rebuild zig1. `union_literal_nested_xmod`: dump rc=0, gcc rc=0, link rc=0, run rc=0 printing `42`. Inspect emitted C: the inner union literal now has its construction (`zT_9.data.Int = 42;` etc.), no undeclared temp.

- [ ] **Step 6: Verify no regression + 4 MD5 gates**

F2's repro not yet fixed (that's F2) — but ensure F1 doesn't break the corpus: spot-check a couple examples still compile. 4 MD5 gates byte-identical.

- [ ] **Step 7: Update tech docs to FIXED**

- [ ] **Step 8: Commit**

```bash
git add sf/src/semantic_analyzer.zig sf/src/lower.zig sf/src/c89_emit.zig sf/docs/tech_docs/05_semantic_analysis.md sf/docs/tech_docs/07_lir_lowering.md sf/docs/tech_docs/08_c89_emission.md
git commit -m "fix: bare-union literals in struct literals lower correctly (union_literal_nested_xmod)"
```

**Gate:** repro green (dump/gcc/link/run rc=0, prints 42); 4 MD5s byte-identical; tech docs updated.

---

### Task F2: Fix Defect B — coercion record for module-scope null global init (Option 2: record lives in sema)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig` (add pub fn `semanticAnalyzerResolveModuleVarDecl`)
- Modify: `sf/src/main.zig` (`:400-441` call the new fn instead of hand-rolling resolve)
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md` to FIXED
- Test: `repro/mi_matrix/global_null_init_xmod/`

**Interfaces:**
- Consumes: I Defect-B report, R repro, operator ruling (Option 2 — coercion recording belongs in sema, not main.zig).
- Produces: module-scope `var x: ?T = null` (and `= undefined`) global inits emit `set_optional_null` typed as the optional.

**Context (Option 2, operator-ruled m0792):** Defect B = the module-scope global-init sema path (`main.zig:400-441`) resolves the init but never records a coercion. The function-body var_decl path (`semantic_analyzer.zig:1862-1867`) records `coercionTableAdd(..., wrap_optional_null, decl_type)`. The coercion-record logic uses sema-private helpers (`errLitSrcType` sema:722, `classifyCoercion` coercion.zig:85, `tryRecordCoercion` sema:697) — main.zig physically cannot call them, and duplicating them there would split-brain the coercion rules across two files. **Fix: add a pub sema fn that owns the resolve + coercion record; main.zig delegates to it.** The existing lowerer null branch (`lower.zig:1267-1296`) then emits `set_optional_null` typed as the optional.

- [ ] **Step 1: Write the failing test (red)**

`global_null_init_xmod/` is the test. Run pre-fix: dump rc=0, gcc rc≠0 (`incompatible types ... Opt_NN from int`). Red state confirmed.

- [ ] **Step 2: Add the pub sema fn**

In `sf/src/semantic_analyzer.zig`, add (near the var_decl handling, e.g. after `semanticAnalyzerResolveStmtIter`):

```zig
pub fn semanticAnalyzerResolveModuleVarDecl(self: *SemanticAnalyzer, decl_idx: u32) u32 {
    var decl = self.store.nodes.items[@intCast(usize, decl_idx)];
    if (decl.child_1 == @intCast(u32, 0)) return @intCast(u32, type_mod.TYPE_UNDEFINED);
    var decl_type: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
    if (decl.child_0 != @intCast(u32, 0)) {
        var rt = rtt_mod.resolvedTypeTableGet(self.type_table, decl.child_0);
        if (rt) |t| { decl_type = t; }
    }
    pushExpectedType(self, decl_type);
    var it = semanticAnalyzerResolveExpr(self, decl.child_1);
    popExpectedType(self);
    if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED) and it != decl_type) {
        var ck = coercion_mod.classifyCoercion(self.registry, errLitSrcType(self, decl.child_1, decl_type, it), decl_type);
        if (ck != coercion_mod.CoercionKind.none) {
            coercion_mod.coercionTableAdd(self.coercion_table, decl.child_1, ck, decl_type);
        }
    }
    return it;
}
```

Verify the exact identifiers (`errLitSrcType`, `classifyCoercion`, `coercionTableAdd`, `pushExpectedType`/`popExpectedType`, `rtt_mod`) match the surrounding code — read the function-body var_decl block `:1862-1867` and `errLitSrcType` `:722` first and mirror them.

- [ ] **Step 3: Rewire main.zig to call it**

In `sf/src/main.zig:400-441`, replace the hand-rolled `pushExpectedType`/`semanticAnalyzerResolveExpr`/`popExpectedType` block (around `:409-411`) with:

```zig
var init_type = sa_mod.semanticAnalyzerResolveModuleVarDecl(&sa, decls[di]);
```

Keep the rest of the block exactly as-is (the `ident_expr` `nameCachePut`, `int_lit` re-resolution, `resolvedTypeTableSet` — those are module-scope symbol-registration concerns that stay in main.zig).

- [ ] **Step 4: Build + verify repro green**

Rebuild zig1. `global_null_init_xmod`: dump rc=0, gcc rc=0, link rc=0, run rc=0 printing `1`. Inspect emitted C: `zG_... = <Opt temp>` where the temp is the optional type with `.has_value = 0`, not `int`.

- [ ] **Step 5: Verify no regression + 4 MD5 gates**

F1 repro still green. 4 MD5 gates byte-identical.

- [ ] **Step 6: Update tech doc to FIXED**

- [ ] **Step 7: Commit**

```bash
git add sf/src/semantic_analyzer.zig sf/src/main.zig sf/docs/tech_docs/07_lir_lowering.md
git commit -m "fix: module-scope optional null globals emit set_optional_null (global_null_init_xmod)"
```

**Gate:** repro green (dump/gcc/link/run rc=0, prints 1); F1 repro still green; 4 MD5s byte-identical; tech doc updated.

---

### Task F3: Gate sweep + full matrix reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v30 — closeout, lisp_interpreter CLEARED)
- Modify: `docs/sf/QUICK_REF.md` (corpus baseline + MD5 table)
- Modify: `sf/docs/tech_docs/05/07/08` (final line-ref verification)
- Report: `.superpowers/sdd/task-F3-lisp-report.md`

**Interfaces:**
- Consumes: F1-F2 fixes, all 21 examples, all repros.
- Produces: final manifest reflecting 21/21 examples end-to-end.

- [ ] **Step 1: Run full 21-example matrix** — lisp_interpreter must be dump/gcc/link/run rc=0.
- [ ] **Step 2: Verify 4 MD5 gates** (gol b246a2fe, lisp 141994cc, json f50ce1e6, mud fd0fdaa4).
- [ ] **Step 3: Verify test_analyzer_bin PASS.**
- [ ] **Step 4: Update EXPECTED_FAIL.md v30** (lisp_interpreter row CLEARED, 2 repros added, follow-up #3 resolved).
- [ ] **Step 5: Update QUICK_REF.md baseline.**
- [ ] **Step 6: Final tech doc line-ref verification.**
- [ ] **Step 7: Commit.**

**Gate:** lisp_interpreter dump/gcc/link/run rc=0 (21/21 examples); 4 MD5s byte-identical; test_analyzer_bin PASS; manifest + QUICK_REF + tech docs consistent. **If a THIRD pre-existing defect surfaces in lisp_interpreter, STOP and present — do not fold silently.**

---

## Post-Plan

- **The 3 Important latents + 6 Minors from the std-lib final review** remain tracked (WSAStartup Win gap, D2 std_arena instance bug, untested Win arms, etc.) — not this plan's scope.
- **The other EXPECTED_FAIL.md follow-ups** (TU payload-read, scratch-arena optimization, cross-module enum switch-case drop) remain open.
- **Merge decision** for the std-lib builtins branch (3b9e3bf2..12dead9d, READY TO MERGE) + the uncommitted /tmp build-script redirect — still pending operator.
