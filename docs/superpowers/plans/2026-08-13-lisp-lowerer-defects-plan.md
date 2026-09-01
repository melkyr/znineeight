# lisp_interpreter Lowerer Defects Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three sema/lowerer-rooted defects gating `examples/z98/lisp_interpreter` (Defect A bare-union literal in struct literal → 5× `zT_N`; Defect B module-scope `?T = null` global typed `int` → 1× `Opt_49`; Defect C nested field-access store drops write-back → runtime SEGFAULT), achieving 21/21 examples end-to-end.

**Architecture:** Defects A+B fixed at sema as the upstream (operator ruling m0759/m0761), lowerer/emitter as downstream completion. Defect C (surfaced by F3's gate, operator ruling m0834: fix GENERAL nested-lvalue-field-store, add cross-module repro) is a lowerer lvalue-path gap. R (2 repros) → I (batched, DONE) → R2 (2 Defect-C repros) → I2 (Defect-C investigation) → combined STOP → F1 (Defect A, DONE) → F2 (Defect B, DONE) → F4 (Defect C) → F3 (gate sweep + fold further cleanup; STOP if another defect surfaces).

**Tech Stack:** Z98 compiler (`sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/main.zig`), zig1 at `/tmp/fx_subfolder/zig1` (out_release wedged), gcc -m32 C89, repro battery, tech docs.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-60) is MANDATORY before any build/compile/run. Copy the exact commands; do not improvise flags.
- **CRITICAL build environment:** `sf/build/out_release/` is WEDGED (any access hangs). **Compiler under test = `/tmp/fx_subfolder/zig1`.** The scripts already point there (uncommitted, operator-authorized). Do NOT touch out_release. Rebuild only if you change sf/src: `bash sf/scripts/build_release.sh`, gate on `=== [release] Done: /tmp/fx_subfolder/zig1 ===`.
- **Compile recipe:** `mkdir -p DIR && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir DIR <main.zig>`; gcc: `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c DIR/*.c` then link `zig_runtime.c zig_pal.c` (NO net_runtime.c).
- **Repro convention (post-F4):** repro `main.zig` uses `std.io.printInt(...)` with LOCAL `std.zig` + `std_io.zig` copies (byte-identical to `sf/src/std.zig`/`std_io.zig` — the resolver has no search-path, D1 precedent). Copy from `repro/mi_matrix/net_builtin_test/` (already has local copies). NO `__bootstrap_print_int` (migrated off in F4).
- **RUNTIME gate mandatory** (AGENTS §2.5.3): every fixed repro must run rc=0 AND print the expected output. Compile-only gates are FORBIDDEN.
- **4 MD5 gates:** gol `ff47d18d` (re-baselined F2, operator ruling m0809), lisp `c1cb748b` (re-baselined F2), json `376fd681` (re-baselined F2), mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT a gate). Byte-identical UNLESS operator-approved re-baseline with runtime proof (AMENDMENT B). **F2 re-baselines gol/lisp/json** (module-scope int-literal coercion now recorded — identical to function-body behavior; runtime byte-identical verified).
- **Corpus:** 242 dirs, OK=235/FAIL=3/GG=4 (post-F1/F2). FAIL must not increase. The 4 new repros (union_literal_nested_xmod, global_null_init_xmod, nested_field_store_xmod, nested_field_store_xmod2) are added to the OK count.
- **Defect C (surfaced at F3 gate, operator ruling m0834):** lisp_interpreter SEGFAULTS at run (rc=139) on a THIRD pre-existing defect — nested field-access store drops the write-back. `value.zig` `v.data.Cons.car = car` lowers `v.data.Cons` as an rvalue copy (lower.zig `lowerFieldStore` uses `lowerExpr(child_0)`), the store mutates throwaway locals, `v.data` never updated. **This is a GENERAL defect, not union-specific:** any `a.b.c = x` (2+ levels of field access in an lvalue) drops write-back. Valid Zig (oracle zig0 runs identical code rc=0). Fix scope = GENERAL nested-lvalue-field-store; cross-module must be covered too.
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

### Task R2: Create 2 Defect-C repros (nested field-store write-back)

**Files:**
- Create: `repro/mi_matrix/nested_field_store_xmod/lib.zig`, `main.zig`, `NOTES.md`, local `std.zig` + `std_io.zig` copies (same-module: Value type + store in one module)
- Create: `repro/mi_matrix/nested_field_store_xmod2/lib.zig`, `main.zig`, `NOTES.md`, local `std.zig` + `std_io.zig` copies (cross-module: Value type defined in lib.zig, store in main.zig)
- Report: `.superpowers/sdd/task-R2-lisp-report.md`

**Interfaces:**
- Consumes: F3's finding (Defect C), operator ruling m0834 (general fix + cross-module repro).
- Produces: 2 repros that RUN WRONG pre-fix (write-back dropped — print uninitialized value) and run CORRECT post-fix.

**Context:** `v.data.Cons.car = car` (2+ level field-access lvalue) drops the write-back. The repro must exercise a nested field store and READ the value back to prove whether the write landed. Use a struct-in-struct (not union-specific) to prove the GENERAL defect. Cross-module variant proves the type-registry-driven path fails identically.

- [ ] **Step 1: Create `nested_field_store_xmod/`** (same-module, struct-in-struct)

Copy local `std.zig` + `std_io.zig` from `repro/mi_matrix/net_builtin_test/`. Create `lib.zig`:
```zig
pub const Inner = struct {
    a: i32,
    b: i32,
};

pub const Outer = struct {
    tag: i32,
    inner: Inner,
};

pub fn build(v: i32) Outer {
    var o: Outer = undefined;
    o.tag = 1;
    o.inner.a = v;
    o.inner.b = v + @intCast(i32, 1);
    return o;
}
```
Create `main.zig`:
```zig
const std = @import("std.zig");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var o = lib_mod.build(@intCast(i32, 42));
    std.io.printInt(o.inner.a);
    std.io.printInt(o.inner.b);
}
```
Pre-fix: dump rc=0, gcc rc=0, run prints uninitialized garbage (write-back dropped — the store mutated throwaway locals). zig0 oracle (via /tmp copy) prints `4243`.

- [ ] **Step 2: Create `nested_field_store_xmod2/`** (cross-module)

Same `lib.zig` (Value types defined there). `main.zig`:
```zig
const std = @import("std.zig");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var o: lib_mod.Outer = undefined;
    o.tag = 1;
    o.inner.a = @intCast(i32, 7);
    o.inner.b = @intCast(i32, 8);
    std.io.printInt(o.inner.a);
    std.io.printInt(o.inner.b);
}
```
Pre-fix: dump rc=0, gcc rc=0, run prints garbage (write-back dropped — cross-module path identical). zig0 oracle prints `78`.

- [ ] **Step 3: Run zig0 oracle on /tmp copies**

zig0 writes beside the source — use /tmp copies. Expected: both print the correct values (oracle handles nested field-store).

- [ ] **Step 4: Write NOTES.md for each repro**

Mirror `net_builtin_test/NOTES.md` format: What it tests / The compiler gap (nested lvalue field-store write-back drop, lower.zig lowerFieldStore rvalue base) / Measured result (pre-fix garbage output) / Oracle verification / Expected classification (FAIL pre-fix → OK post-fix).

- [ ] **Step 5: Write the R-report**

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/nested_field_store_xmod/ repro/mi_matrix/nested_field_store_xmod2/
git commit -m "repro: nested field-access store write-back drop (same-module + cross-module)"
```

**Gate:** both repros RUN WRONG pre-fix (write-back dropped); zig0 oracle correct; NOTES.md written; committed.

---

### Task I2: Defect-C investigation — nested field-store write-back drop

**Files:**
- Investigate: `sf/src/lower.zig` (`lowerLValueAddr` :739, `lowerAssignLValue` :793, `lowerFieldStore` :844)
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md`
- Report: `.superpowers/sdd/I-lisp-defC-report.md`

**Interfaces:**
- Consumes: R2 repros, F3's finding, operator ruling m0834.
- Produces: exact locus + root cause, fix recommendation (general), blast radius (which existing repros/examples affected), tech-doc update.

**Context:** `lowerAssignLValue` (lower.zig:793) → `field_access` → `lowerFieldStore` (:844). `lowerFieldStore` computes `base_temp = lowerExpr(child_0)` for non-index bases (:860) — for a nested chain the base `v.data.Cons` is lowered as an rvalue copy, so the outer `store_field` mutates a throwaway local. `lowerLValueAddr` (:739) has NO `field_access` branch (only index/ident/deref/paren). Valid Zig; general (not union-specific); cross-module affected (type-driven). NO compiler source changes.

- [ ] **Step 1: Confirm the mechanism at HEAD**

Read `lower.zig:739-920` (`lowerLValueAddr`, `lowerAssignLValue`, `lowerFieldStore`). Trace the exact chain for `o.inner.a = v` (field_access(field_access(o, inner), a)): confirm the inner field_access `o.inner` is lowered via `lowerExpr` (rvalue copy) → write-back dropped. Confirm `lowerLValueAddr` has no field_access branch. Run `nested_field_store_xmod` → run prints garbage (pre-fix).

- [ ] **Step 2: Confirm cross-module**

Run `nested_field_store_xmod2` → same garbage output. Confirm the registry is module-agnostic (the defect fires identically).

- [ ] **Step 3: Determine the fix locus + approach**

Analyze: (a) extend `lowerLValueAddr` with a `field_access` branch (compute the address of the field within the base's address) AND route `lowerFieldStore`'s nested-base case through it (store through pointer), or (b) a dedicated nested-base address lowering inside `lowerFieldStore` (recurse: for base field_access, take its address then store_field on the pointer). Determine which matches the existing store_field emitter (c89_emit:4134) and addr_of handling (:4289). Recommend one with file:line.

- [ ] **Step 4: Assess blast radius**

Grep `examples/z98/` and `repro/mi_matrix/` for nested field-access lvalue assignments (`x.y.z =`, `x.y.z.w =`, 2+ levels). Which currently-OK repros/examples would change emission? Which of the 4 MD5 gates (gol/lisp/json/mud) use nested field-store? (lisp_interpreter does — but it's not an MD5 gate; `_curr` uses whole-value assign and is unaffected.) Report which gates would re-baseline.

- [ ] **Step 5: Update tech doc `07_lir_lowering.md`**

Document the lvalue/address path gap (field_access base), `[updated: 2026-08-13]`, corrected refs. Do NOT fix code.

- [ ] **Step 6: Write the I-report** — `.superpowers/sdd/I-lisp-defC-report.md`

- [ ] **Step 7: Report back — combined STOP**

Report mechanism (file:line), fix recommendation (a or b), blast radius. **STOP for operator ruling before F4.**

**Gate:** mechanism confirmed at HEAD with file:line; both repros reproduce garbage pre-fix; fix locus + approach determined; blast radius assessed; tech doc updated. No compiler source changes.

---

### Task F4: Fix Defect C — nested field-access store write-back (Option a, operator-ruled)

**Files:**
- Modify: `sf/src/lower.zig` (extend `lowerLValueAddr` with a `field_access` branch + route `lowerFieldStore` nested-base through it)
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md` to FIXED
- Test: `repro/mi_matrix/nested_field_store_xmod/`, `repro/mi_matrix/nested_field_store_xmod2/`

**Interfaces:**
- Consumes: I2 ruling, R2 repros, operator ruling m0872 (approach a — fix the primitive, not the consumer).
- Produces: nested field-access lvalue stores write back correctly (any 2+ level chain, same-module + cross-module); `&field` (address_of on a field_access) no longer ICEs.

**Context (Option a, operator-ruled):** The root cause is ONE incomplete primitive — `lowerLValueAddr` (lower.zig:739) is the universal "lvalue → address" function but has NO `field_access` branch (falls through to `iceAddrOfLValueUnsupported` :777). This one gap causes TWO bugs: (1) `lowerFieldStore` (:844) falls back to `lowerExpr` (rvalue copy :860) → nested store write-back dropped; (2) `&o.inner` (address_of :1723) ICEs error[3043]. Approach (a) completes the primitive, fixing both; the proven ptr-base `store_field` emitter (c89_emit:4183-4202, handles struct AND union pointees) does the rest. This is the upstream-proper, scalable, maintainable fix (single root cause, one home for address logic) vs approach (b) which would patch only the consumer and leave the `&field` ICE.

- [ ] **Step 1: Write the failing test (red)**

`nested_field_store_xmod/` + `nested_field_store_xmod2/` are the tests. Run pre-fix: dump rc=0, gcc rc=0, run prints garbage. Red state confirmed.

- [ ] **Step 2: Implement the fix (Option a)**

In `lower.zig`, extend `lowerLValueAddr` (:739) with a `field_access` branch: compute the address of the field within the base's address (emit an addr-of-field form — `&base.field`; the LIR/emission may need a small addition to `addr_of`-adjacent emission in c89_emit.zig). Then route `lowerFieldStore`'s nested-base case through it: for a base that is itself a field_access/index_access/deref lvalue, use `base_temp = lowerLValueAddr(child_0, ptr_type)` instead of `lowerExpr(child_0)`. Verify the ptr-base `store_field` emitter path (:4183-4202) produces `base->inner.a = v;`. Ensure single-level field stores (`o.tag = 1`, base = ident/ptr) are unchanged — they already work. Ensure `index_access` bases still work (`arr[i].f = x`, the existing :850-858 path).

- [ ] **Step 3: Build + verify repros green**

Rebuild zig1. `nested_field_store_xmod` prints `4243`, `nested_field_store_xmod2` prints `78` (dump/gcc/link/run rc=0). Inspect emitted C: `o.inner.a = v;` stored through the address, not a local copy. Also verify `&o.inner` no longer ICEs (a small throwaway test).

- [ ] **Step 4: Verify no regression + 4 MD5 gates**

F1/F2 repros still green. Corpus sweep — no new FAIL. 4 MD5 gates: gol/lisp/json/mud byte-identical (I2 audit: 0 of 4 gates use nested field-store) — if any re-baseline, report + re-baseline per AMENDMENT B. Also verify lisp_interpreter run no longer SEGFAULTS.

- [ ] **Step 5: Update tech doc `07_lir_lowering.md` to FIXED**

- [ ] **Step 6: Commit**

```bash
git add sf/src/lower.zig sf/src/c89_emit.zig sf/docs/tech_docs/07_lir_lowering.md
git commit -m "fix: nested field-access store write-back (nested_field_store_xmod)"
```

**Gate:** both repros green (dump/gcc/link/run rc=0, correct values); `&field` no longer ICEs; lisp_interpreter no longer SEGFAULTS at run; F1/F2 repros still green; 4 MD5s byte-identical or re-baselined per AMENDMENT B; tech doc updated.

---

### Task R3: Create Defect-D repro (sizeOf/alignOf struct-with-union) — ADDED per operator ruling m0898

**Files:**
- Create: `repro/mi_matrix/sizeof_struct_union_xmod/main.zig`, `lib.zig`, `NOTES.md`
- Report: `.superpowers/sdd/task-R3-lisp-report.md`

**Interfaces:**
- Consumes: Defect-D investigation findings (report `.superpowers/sdd/I-lisp-defD-report.md` — the explore-agent diagnosis of the dummy dep-graph edges).
- Produces: a minimal red/green gate for F5 (the layout-ordering fix).

**Context:** Defect D — `@sizeOf`/`@alignOf` return 1/1 for a struct containing a bare union (Value=1/1, JsonValue=8) because the layout topological sort lays the struct out before its union/enum field types are sized (dummy `0->tid` dep edges from symbol_registrator.zig:78; field type_ids are TYPE_VOID placeholders at registration). The repro must isolate the ordering symptom: a struct containing a bare union where the union type is declared AFTER the struct (so the LIFO worklist pops the struct first) — `@sizeOf`/`@alignOf` must be correct post-fix.

- [ ] **Step 1: Write the repro**

`repro/mi_matrix/sizeof_struct_union_xmod/lib.zig`:
```zig
pub const Tag = enum { A, B, C };

pub const Data = union {
    I: i64,
    S: []const u8,
    F: f64,
};

pub const Value = struct {
    tag: Tag,
    data: Data,
};

pub fn compute(n: i32) i32 {
    var v = Value{ .tag = Tag.A, .data = Data{ .I = @intCast(i64, n) } };
    var s = @sizeOf(Value);
    var a = @alignOf(Value);
    var r: i32 = 0;
    r = r + @intCast(i32, s);
    r = r + @intCast(i32, a);
    return r;
}
```

`repro/mi_matrix/sizeof_struct_union_xmod/main.zig`:
```zig
const lib_mod = @import("lib.zig");
const std = @import("std.zig");

pub fn main() void {
    std.io.printInt(lib_mod.compute(@intCast(i32, 0)));
}
```

**Expected:** Value size = 24 (i64-aligned union), alignment = 8. `compute(0)` returns `24 + 8 = 32`. Pre-fix: returns `1 + 1 = 2` (or another wrong value). Verify the exact pre-fix number by running.

- [ ] **Step 2: Run it pre-fix — confirm the wrong value**

Run: `mkdir -p /tmp/r3 && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r3 repro/mi_matrix/sizeof_struct_union_xmod/main.zig 2>/tmp/r3/err; cd /tmp/r3 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog && timeout 10 ./prog`
Expected: prints a wrong value (`2` if size collapses to 1/1). Record the actual.

- [ ] **Step 3: Run zig0 oracle on a /tmp copy**

zig0 writes beside the source — copy to /tmp. zig0 can't parse post-F4 std_io builtins, so the oracle main.zig uses `__bootstrap_print_int` (documented convention). Expected: prints `32` (correct). This is the post-fix reference.

- [ ] **Step 4: Write NOTES.md**

Mirror the sibling repro format: What it tests / The compiler gap (dummy dep edges, symbol_registrator.zig:78, type_resolver layout ordering, `size==0→1/1` :130) / Measured result (pre-fix value) / Oracle verification (zig0 `32`) / Expected classification.

- [ ] **Step 5: Write the R-report + commit**

Write `.superpowers/sdd/task-R3-lisp-report.md`. Commit:
```bash
git add repro/mi_matrix/sizeof_struct_union_xmod/
git commit -m "repro: @sizeOf/@alignOf struct-with-union layout ordering (sizeof_struct_union_xmod)"
```

**Gate:** wrong pre-fix value recorded; zig0 oracle `32`; NOTES.md + report written; committed.

---

### Task F5: Fix Defect D — layout dependency graph ordering (Option B, operator-ruled)

**Files:**
- Modify: `sf/src/type_resolver.zig` (new `typeResolverBuildDependencyGraph` — real `field_type -> container_tid` edges, after field types are resolved)
- Modify: `sf/src/main.zig` (invoke it in `phase_TypeResolution` between name-resolution (:312) and resolve (:314))
- Modify (docs): `sf/docs/tech_docs/03_type_resolution.md` to FIXED
- Test: `repro/mi_matrix/sizeof_struct_union_xmod/`, `repro/mi_matrix/xmod_amp_arena_union_store/`

**Interfaces:**
- Consumes: Defect-D investigation (report `.superpowers/sdd/I-lisp-defD-report.md`), operator ruling m0898 (Option B), R3 repro.
- Produces: layout topological sort respects field-type dependencies → `@sizeOf`/`@alignOf` correct for ALL types (struct-with-union, struct-with-enum, any field ordering); lisp_interpreter Value + json_parser_workaround JsonValue sizes correct.

**Context (Option B, operator-ruled):** Root cause = the dependency graph driving layout ordering carries dummy edges (`symbol_registrator.zig:78` adds `0->tid`; real `field_type->tid` edges CAN'T be added at registration because field type_ids are still TYPE_VOID placeholders). The field types get resolved LATER (`resolveAggregateFieldTypesAll`, type_resolver.zig:1078-1096). Fix: build the real graph AFTER that resolution, in the resolver (which already owns layout + `fieldEmbedsByValue`/`requiresFullDef` helpers at :324-344). This is the general fix — correct layout ordering for every struct, not a union-specific patch. The readers (comptime_eval.zig:120/129), layout math (:104-224), and C emitter are all correct and need no change.

- [ ] **Step 1: Write the failing test (red)**

`sizeof_struct_union_xmod/` is the test. Run pre-fix: prints `2` (wrong). Red state.

- [ ] **Step 2: Implement the fix (Option B)**

In `sf/src/type_resolver.zig`, add a function `typeResolverBuildDependencyGraph` that, given the resolver's registry + the now-resolved field type_ids, adds a real edge `field_type -> container_tid` for each field that **embeds by value** (struct/union/tagged_union/enum/array/tuple/optional/error_union), skipping pointer/slice fields (always-resolved, fixed 4/8 size — avoids false self-reference cycles). Mirror the existing `fieldEmbedsByValue` (:324-333) / `requiresFullDef` (:335-344) semantics for "embeds by value". A field whose type is TYPE_VOID/UNDEFINED/primitive/resolved already needs no edge. Self-referential types via pointers must NOT create cycles (the cycle guard at :307-321 is the safety net — verify it still functions).

In `sf/src/main.zig`, `phase_TypeResolution` (around :302-337): call `typeResolverBuildDependencyGraph` AFTER `typeResolverResolveNames` (:312, which runs `resolveAggregateFieldTypesAll`) and BEFORE `typeResolverResolve` (:314/315, which does layout). This ensures layout ordering uses the real dependencies.

Verify the fix handles: struct-before-union declaration order (the Defect D case), struct-before-enum, pointer-self-reference, and the existing corpus layouts (no layout regressions — all examples must still compile with correct sizes).

- [ ] **Step 3: Build + verify repros green**

Rebuild zig1 (`bash sf/scripts/build_release.sh`, gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`). `sizeof_struct_union_xmod` prints `32`. `xmod_amp_arena_union_store` (struct-with-union `@sizeOf`) — verify its sizes are now correct (it was a closest minimal repro). Also verify lisp_interpreter + json_parser_workaround `@sizeOf` values are correct (they use arenas sized by `@sizeOf` — check the emitted C for the correct constants, e.g. lisp Value size ~36, JsonValue ~28).

- [ ] **Step 4: Verify no regression + 4 MD5 gates**

F1/F2/F4 repros still green (42/1/4243/78). Corpus sweep — no new FAIL, and ideally `xmod_amp_arena_union_store` runtime becomes correct (was arena-corrupted). 4 MD5 gates: gol/lisp/json/mud byte-identical — BUT if any gate's emitted C changes (because a `@sizeOf` constant in its source was previously wrong), re-baseline per AMENDMENT B with runtime proof. The lisp gate (`lisp_interpreter_curr`) uses `@sizeOf(Value)` — if Value has no union, its size was already correct, so no change expected; VERIFY.

- [ ] **Step 5: Update tech doc `03_type_resolution.md` to FIXED**

Document: the real dependency-graph build (after field-type resolution), the embeds-by-value edge rule, corrected refs, `[updated: 2026-08-13]`.

- [ ] **Step 6: Commit**

```bash
git add sf/src/type_resolver.zig sf/src/main.zig sf/docs/tech_docs/03_type_resolution.md
git commit -m "fix: layout dependency graph respects field-type order (sizeof_struct_union_xmod)"
```

**Gate:** repro green (prints `32`); xmod_amp_arena_union_store sizes correct; lisp_interpreter + json_parser_workaround `@sizeOf` constants correct in emitted C; F1/F2/F4 repros still green; 4 MD5s byte-identical or re-baselined per AMENDMENT B; corpus no new FAIL; tech doc updated.

---

### Task R4: Create Defect-E repro (bare-union C emission layout) — ADDED per operator ruling m0915

**Files:**
- Create: `repro/mi_matrix/union_emission_layout_xmod/main.zig`, `lib.zig`, `NOTES.md`
- Report: `.superpowers/sdd/task-R4-lisp-report.md`

**Interfaces:**
- Consumes: Defect-E finding (surfaced in F5 — union emitted as stacked C struct, 36B, vs `@sizeOf` union-max 16B → arena overflow → SEGFAULT).
- Produces: a minimal red/green gate for F6 (the union-emission fix).

**Context:** Defect E — a bare `union { I: i64, S: []const u8, F: f64 }` is emitted to C as `struct { i64 I; Slice S; f64 F; }` (ALL variants stacked, ~36B) by `emitUnionType` (c89_emit.zig:1528-1553, line 1536 writes `"struct "`) instead of a real C `union` (max member, 16B). Since `@sizeOf` correctly returns the union-max (16) post-Defect-D-fix, arena allocators sized by `@sizeOf` overflow when the runtime stores the 36B struct → memory corruption → SEGFAULT (lisp_interpreter, json_parser_workaround).

- [ ] **Step 1: Write the repro**

`repro/mi_matrix/union_emission_layout_xmod/lib.zig`:
```zig
pub const Tag = enum { A, B, C };

pub const Data = union {
    I: i64,
    S: []const u8,
    F: f64,
};

pub const Value = struct {
    tag: Tag,
    data: Data,
};

pub fn makeValue(n: i32) Value {
    return Value{ .tag = Tag.A, .data = Data{ .I = @intCast(i64, n) } };
}
```

`repro/mi_matrix/union_emission_layout_xmod/main.zig`:
```zig
const lib_mod = @import("lib.zig");
const std = @import("std.zig");

pub fn main() void {
    var v = lib_mod.makeValue(@intCast(i32, 7));
    std.io.printInt(@intCast(i32, v.data.I));
    std.io.printInt(@intCast(i32, @sizeOf(lib_mod.Data)));
}
```

**Expected:** `v.data.I` reads back `7`; `@sizeOf(Data)` = 8 (union max of i64/f64/slice, all 8 on 32-bit). Pre-fix: `v.data.I` reads `7` correctly (struct layout preserves it, field ordering) but `@sizeOf(Data)` = 8 while the C `struct` is 24B — the mismatch. **Better discriminator:** print `@sizeOf(lib_mod.Value)` too — pre-fix Value C struct is 28B (Tag 4 + pad + Data 24) but `@sizeOf(Value)` = 16 (post-Defect-D). The mismatch (16 vs 28) is the corruption vector. Verify the exact emitted-C struct sizes in /tmp.

- [ ] **Step 2: Run it pre-fix — confirm the layout mismatch**

Run: `mkdir -p /tmp/r4 && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r4 repro/mi_matrix/union_emission_layout_xmod/main.zig 2>/tmp/r4/err; cd /tmp/r4 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog && timeout 10 ./prog`
Inspect the emitted `Data` typedef in the C: confirm it's `struct { i64 I; ... }` (stacked) NOT `union { ... }`. Record the emitted struct size (`sizeof(struct Data)` via a throwaway C check) vs `@sizeOf(Data)` = 8. The mismatch is the red state.

- [ ] **Step 3: Run zig0 oracle on a /tmp copy**

zig0 writes beside the source — copy to /tmp, oracle main.zig uses `__bootstrap_print_int`. Expected: zig0 emits a real C `union { i64 I; Slice S; f64 F; }` for Data → `@sizeOf(Data)` = 8 matches the runtime struct (8) → no mismatch. Record the oracle emitted union.

- [ ] **Step 4: Write NOTES.md**

Mirror the sibling format: What it tests / The compiler gap (emitUnionType c89_emit.zig:1528-1553 writes `struct` at :1536; `@sizeOf` union-max vs C stacked struct → arena overflow) / Measured result (emitted struct size vs @sizeOf, the mismatch) / Oracle verification (zig0 real union) / Expected classification.

- [ ] **Step 5: Write the R-report + commit**

Write `.superpowers/sdd/task-R4-lisp-report.md`. Commit:
```bash
git add repro/mi_matrix/union_emission_layout_xmod/
git commit -m "repro: bare-union C emission layout mismatch (union_emission_layout_xmod)"
```

**Gate:** emitted-C `struct`-vs-union mismatch recorded (size discrepancy); zig0 oracle emits real union; NOTES.md + report written; committed.

---

### Task F6: Fix Defect E — emit bare unions as C unions (operator-ruled m0915)

**Files:**
- Modify: `sf/src/c89_emit.zig` (`emitUnionType` at :1528-1553)
- Modify (docs): `sf/docs/tech_docs/08_c89_emission.md` to FIXED
- Test: `repro/mi_matrix/union_emission_layout_xmod/`, `repro/mi_matrix/sizeof_struct_union_xmod/`

**Interfaces:**
- Consumes: Defect-E finding, R4 repro, operator ruling m0915.
- Produces: bare unions emit as real C `union` (max-member layout) matching `@sizeOf`; lisp_interpreter + json_parser_workaround no longer SEGFAULT from arena overflow.

**Context (mechanism confirmed, operator ruling m0944 = option 2 — 3-site fix + helper):** `emitUnionType` (c89_emit.zig:1528-1553) writes `"struct "` at :1536 and stacks ALL variants as fields — identical to `emitStructType`. A bare union must emit a C `union { ... }` (all members at offset 0, size = max member). **The fix is NOT a single keyword change** (verified: one-keyword swap fails gcc with `error: 'zT_..._Data' defined as wrong kind of tag`). The `struct` keyword appears in 3 sites for named aggregates, and the C89 tag namespace (struct/union/enum tags share ONE namespace) requires ALL 3 to agree: (1) `emitUnionType` definition :1536, (2) `emitSharedHeader` forward-decl/typedef :1130, (3) `emitSpecialTypes` forward-decl/typedef :1260. References are kind-agnostic (`getCTypeName` returns a bare mangled name via :744-745 — no keyword), so the reference path needs no change. The tagged-union/struct sites (:1435/:1467/:1503) stay `struct`; the anonymous wrapper sites (:1773/:1808/:1816/:1834/:1840) have no tag namespace. **Per operator ruling: introduce ONE helper `aggregateKeyword(kind)` returning `"union "` for union_type else `"struct "`, used at all 3 sites — single source of truth, closes the recurring keyword/site split-brain class.** Field access already works via `emitFieldAssign` union branch (:260-274) and `store_field` union branch (:4202-4223) which emit `.member` — valid for both struct and union. The topo-sort already handles union_type.

- [ ] **Step 1: Write the failing test (red)**

`union_emission_layout_xmod/` is the test. Pre-fix: emitted C has `struct zT_..._Data { i64 I; ... }` (stacked, ~24B) while `@sizeOf(Data)` = 8. Red.

- [ ] **Step 2: Implement the fix (option 2 — 3-site + helper)**

In `sf/src/c89_emit.zig`:
1. Add a helper near `getCTypeName` (:542):
```zig
fn aggregateKeyword(kind: TypeKind) []const u8 {
    if (kind == TypeKind.union_type) return "union ";
    return "struct ";
}
```
2. `emitUnionType` (:1528-1553): change the `"struct "` write at :1536 to `aggregateKeyword(ty.kind)` (ty is in scope at :1530).
3. `emitSharedHeader` (:1130): change `"typedef struct "` to emit `"typedef "` + `aggregateKeyword(ty.kind)` + cname (ty is in scope at :1120-1121, guarded on struct/tagged_union/union).
4. `emitSpecialTypes` (:1260): same change (ty is in scope at :1250-1251, same guard).

Verify the rest of `emitUnionType` (field loop emitting `type name;` per member) is correct for a C union (it is — union members are `type name;`). Verify `emitTypeDefinition` (:1587) dispatches union_type to `emitUnionType` (it does). Verify a nested bare union inside a struct (`Value { tag, data }`) emits `union` inside the struct — valid C. **Do NOT change:** the tagged_union `struct` sites (:1435/:1467) or struct site (:1503) or the anonymous wrapper sites (:1773+). Those are correct.

- [ ] **Step 3: Build + verify repros green**

Rebuild zig1. `union_emission_layout_xmod`: emitted C has `union zT_..._Data { ... }` (both the forward-decl typedef AND the definition agree), `@sizeOf(Data)` = 8 matches runtime struct, prints `7` + `8`. `sizeof_struct_union_xmod` still prints `24`. Verify the emitted `Value` struct now matches `@sizeOf(Value)` = 16 (Tag 4 + pad + union 8 → 16). Verify gcc compiles clean (no "wrong kind of tag").

- [ ] **Step 4: Verify no regression + 4 MD5 gates**

F1/F2/F4/F5 repros still green (42/1/4243/78/24). Corpus sweep — no new FAIL. 4 MD5 gates: gol/lisp/json/mud — **these MAY re-baseline** if any gate example uses a bare union (the emitted C typedef changes from struct to union). Check each: if lisp_interpreter_curr uses tagged unions (not bare), no change expected; VERIFY each. Re-baseline per AMENDMENT B with runtime proof if needed.

- [ ] **Step 5: Update tech doc `08_c89_emission.md` to FIXED** — union emission, corrected refs, `[updated: 2026-08-13]`.

- [ ] **Step 6: Commit**

```bash
git add sf/src/c89_emit.zig sf/docs/tech_docs/08_c89_emission.md
git commit -m "fix: bare unions emit as C unions, matching sizeOf layout (union_emission_layout_xmod)"
```

**Gate:** repro green (real `union` in C, `@sizeOf` matches runtime struct size); sizeof_struct_union_xmod still 24; F1/F2/F4 repros green; 4 MD5s byte-identical or re-baselined per AMENDMENT B; corpus no new FAIL; tech doc updated.

---

### Task F3: Gate sweep + full matrix reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v30 — closeout, lisp_interpreter CLEARED)
- Modify: `docs/sf/QUICK_REF.md` (corpus baseline + MD5 table)
- Modify: `sf/docs/tech_docs/05/07/08` (final line-ref verification)
- Report: `.superpowers/sdd/task-F3-lisp-report.md`

**Interfaces:**
- Consumes: F1-F2-F4-F5-F6 fixes, all 21 examples, all repros.
- Produces: final manifest reflecting 21/21 examples end-to-end.

- [ ] **Step 1: Run full 21-example matrix** — lisp_interpreter must be dump/gcc/link/run rc=0 AND functionally correct (evaluates `nil`/`true`/`+`/`(quote 5)`/`cons` — no silent eval failure, no SEGFAULT; Defects D+E fixed so its `@sizeOf(Value)` matches the C union layout and the arena doesn't overflow). json_parser_workaround must run rc=0 (its F4-exposed SEGFAULT resolved by Defect D+E fixes).
- [ ] **Step 2: Verify 4 MD5 gates** (gol ff47d18d, lisp c1cb748b, json 376fd681 — post-F2 re-baseline, mud fd0fdaa4).
- [ ] **Step 3: Verify test_analyzer_bin PASS.**
- [ ] **Step 4: Update EXPECTED_FAIL.md v30** (lisp_interpreter row CLEARED — functionally OK, 5 repros added incl. sizeof_struct_union_xmod, follow-up #3 resolved).
- [ ] **Step 5: Update QUICK_REF.md baseline.**
- [ ] **Step 6: Final tech doc line-ref verification.**
- [ ] **Step 7: Commit.**

**Gate:** lisp_interpreter dump/gcc/link/run rc=0 AND functionally correct (21/21 examples); json_parser_workaround run rc=0 (no SEGFAULT); 4 MD5s byte-identical; test_analyzer_bin PASS; manifest + QUICK_REF + tech docs consistent. **If ANOTHER pre-existing defect surfaces, STOP and present — do not fold silently.**

---

## Post-Plan

- **The 3 Important latents + 6 Minors from the std-lib final review** remain tracked (WSAStartup Win gap, D2 std_arena instance bug, untested Win arms, etc.) — not this plan's scope.
- **The other EXPECTED_FAIL.md follow-ups** (TU payload-read, scratch-arena optimization, cross-module enum switch-case drop) remain open.
- **Merge decision** for the std-lib builtins branch (3b9e3bf2..12dead9d, READY TO MERGE) + the uncommitted /tmp build-script redirect — still pending operator.
