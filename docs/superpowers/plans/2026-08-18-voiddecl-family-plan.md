# Self-Compile VOID-decl Family Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate and fix the 4 suspected distinct root causes behind the 9 residual self-compile `error[3000]` "cannot declare variable of type void" sites, so self-compile advances past semantic analysis.

**Architecture:** Investigation-first cadence (operator-mandated): 4 repros each with a type-kind matrix sweep → 4 read-only investigations → one consolidated STOP ruling → 4 placeholder fixes → GATE → whole-branch review. Root cause (not symptom) decides each fix.

**Tech Stack:** Z98 dialect (no `anytype`/`@Type`), C89 emission, zig0 bootstrap, compiler under test `/tmp/fx_subfolder/zig1`.

## Global Constraints

- 4 MD5 gates byte-identical unless operator re-baselines (single-file `--dump-c89 | md5sum`, lisp from repo root): gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, mud `a1d0dd55aada9c3fd904ae33f54de32e`, json `fc357296537347a0ef58af49b5a40081`.
- Corpus 277 dirs OK=267/FAIL=6/ICE=0/CRASH=0/GG=4 — no regression. Corpus recipe MUST be per-module (`--dump-c89 --output-dir DIR` then gcc each `.c`; stdout-concat falsely fails fn_ptr_struct_field).
- 21-example matrix 21/21. test_analyzer_bin '5 passed, 4 failed' baseline.
- Z98 dialect: no `anytype`/`@Type`. edit/fastedit ONLY for source. Never touch `sf/build/out_release/`.
- Repros are new fixture dirs only; use the EXISTING `/tmp/fx_subfolder/zig1` (do NOT rebuild during R/I tasks). Fixture convention: bare `@import("std")` + `std.io.printInt`; RED = `error[3000]`/void fallback; GREEN = dump/gcc/run rc=0 + expected output; `main.zig` + `NOTES.md` committed per fixture; timeout-gated.
- Verification MUST scan the whole tree/closure for the defect class, never stop at first error.
- Zig-spec claims MUST be verified online before acceptance.
- I-tasks: READ-ONLY — instrumentation only on a `/tmp` copy, report + revert (tree clean).

---

### Task R1: repro value-position if (shape A) + matrix

**Files:**
- Create: `repro/mi_matrix/voiddecl_ifexpr_xmod/{main.zig,NOTES.md}`

**Context:** `lower.zig:4410` — `var cmp_op = if (pattern.kind == AstKind.range_inclusive) BIN_LE else BIN_LT;` (`BIN_LT=@intCast(u8,12)`, `BIN_LE=@intCast(u8,13)`, lower.zig:50-51). Non-optional value-position `if (bool) A else B` resolves to void.

- [ ] **Step 1: Write the failing fixture**

`main.zig`:
```zig
const std = @import("std");
pub fn main() void {
    var kind: u32 = 0;
    var cmp_op = if (kind == 1) 13 else 12;
    std.io.printInt(cmp_op);
}
```

- [ ] **Step 2: Run RED baseline**

Run from the fixture dir: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
Expected: rc=2, `error[3000]: cannot declare variable of type void`, 0-byte `.c` (or void-fallback evidence per NOTES).

- [ ] **Step 3: GREEN control**

Control (in `/tmp`, not committed): same program with `var cmp_op: u32 = 13;` → rc=0, gcc rc=0, run prints `13`.

- [ ] **Step 4: Type-kind matrix sweep**

In NOTES.md, record for each variant (dump rc + verdict):
1. cond bool (`kind == 1`) ✓ RED (the trigger)
2. cond optional (`if (o) 13 else 12` where `o: ?u32`)
3. branches u8 const (13/12) ✓ RED
4. branches enum consts (`E.a`/`E.b`)
5. branches bool consts (`true`/`false`)
6. branches struct values (`S{...}`/`S{...}`)

- [ ] **Step 5: NOTES.md**

Record: purpose, fixture sources verbatim, RED baseline (rc + stderr), GREEN control, matrix table (each variant rc + verdict), blast-radius lead (which sibling forms fail vs pass — feeds I-IFEXPR), post-fix expectation.

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/voiddecl_ifexpr_xmod/
git commit -m "repro: value-position if (bool) A else B resolves void (voiddecl_ifexpr_xmod)"
```

---

### Task R2: repro switch-expression + enum annotation (shape B) + matrix

**Files:**
- Create: `repro/mi_matrix/voiddecl_switchexpr_xmod/{main.zig,NOTES.md}`

**Context:** `symbol_registrator.zig:258` (live :257-264) — `var type_kind: TypeKind = switch (init_node.kind) { … };` where `TypeKind = enum(u8)` (type_registry.zig:41). Value-position switch with enum-typed annotation resolves to void.

- [ ] **Step 1: Write the failing fixture**

`main.zig`:
```zig
const std = @import("std");
const E = enum(u8) { first, second };
pub fn main() void {
    var kind: u32 = 0;
    var t: E = switch (kind) {
        0 => E.first,
        else => E.second,
    };
    std.io.printInt(@intCast(u32, @enumToInt(t)));
}
```

- [ ] **Step 2: Run RED baseline**

Run from the fixture dir: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
Expected: rc=2, `error[3000]: cannot declare variable of type void`, 0-byte `.c`.

- [ ] **Step 3: GREEN control**

Control (in `/tmp`): `var t: E = E.first;` → rc=0, run prints `0`.

- [ ] **Step 4: Type-kind matrix sweep**

In NOTES.md, record for each variant:
1. enum annotation (`var t: E = switch …`) ✓ RED (the trigger)
2. switch assigned to inferred var (`var t = switch (x) { 0 => 13, else => 12 };` — int arms, no annotation)
3. switch arms returning struct values
4. switch arms returning union values
5. switch as a fn-argument expression (not var-decl)

- [ ] **Step 5: NOTES.md**

Record: purpose, fixture sources, RED baseline, GREEN control, matrix table, blast-radius lead, post-fix expectation.

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/voiddecl_switchexpr_xmod/
git commit -m "repro: value-position switch-expression with enum annotation resolves void (voiddecl_switchexpr_xmod)"
```

---

### Task R3: repro u64 bitwise-and + intCast (shape C) + matrix

**Files:**
- Create: `repro/mi_matrix/voiddecl_u64cast_xmod/{main.zig,NOTES.md}`

**Context:** `symbol_registrator.zig:357` (live :356) — `var name_id: u32 = @intCast(u32, node.payload & @intCast(u64, 0xFFFFFFFF));` where `node.payload` is u64 (post-F1). u64 `&` / `@intCast(u32, u64)` / large literal typing resolves to void.

- [ ] **Step 1: Write the failing fixture**

`main.zig`:
```zig
const std = @import("std");
pub fn main() void {
    var p: u64 = 0xFFFFFFFF00000000;
    var n: u32 = @intCast(u32, p & @intCast(u64, 0xFFFFFFFF));
    std.io.printInt(n);
}
```

- [ ] **Step 2: Run RED baseline**

Run from the fixture dir: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
Expected: rc=2, `error[3000]: cannot declare variable of type void`, 0-byte `.c`.

- [ ] **Step 3: GREEN control**

Control (in `/tmp`): `var n: u32 = 0;` → rc=0, run prints `0`.

- [ ] **Step 4: Type-kind matrix sweep**

In NOTES.md, record for each variant:
1. `@intCast(u32, p & @intCast(u64, 0xFFFFFFFF))` ✓ RED (the trigger)
2. `p & @intCast(u64, 0xFFFFFFFF)` alone assigned to `var q: u64`
3. u64 `|` (`p | @intCast(u64, 0xFF)`)
4. u64 `^`
5. `@intCast(u64, u32_expr)` (reverse direction)
6. literal `0xFFFFFFFFFFFFFFFF` (64-bit literal typing)
7. `@intCast(u32, p)` without the `&` (does plain u64→u32 cast work?)

- [ ] **Step 5: NOTES.md**

Record: purpose, fixture sources, RED baseline, GREEN control, matrix table, blast-radius lead (is it the `&` operator, the `@intCast` narrowing, or literal typing?), post-fix expectation.

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/voiddecl_u64cast_xmod/
git commit -m "repro: u64 bitwise-and + @intCast narrow resolves void (voiddecl_u64cast_xmod)"
```

---

### Task R4: repro cross-module struct/tagged-union (shapes D+E) + matrix

**Files:**
- Create: `repro/mi_matrix/voiddecl_xmodtype_xmod/{main.zig,mod.zig,NOTES.md}`

**Context:** `main.zig:588` — `var sem_ctx: SemanticContext = SemanticContext{ … }` (struct with pointer fields, cross-module: lower.zig → main.zig); `lower.zig:5218` etc — `var inst = blk.insts.items[ii];` where `LirInst` is a tagged `union(enum)` (lir.zig:22) reached via multi-hop field access on `BasicBlock` (lir.zig:144). Cross-module struct/tagged-union refs in annotation + field-access resolve to void.

- [ ] **Step 1: Write the failing fixture**

`mod.zig`:
```zig
pub const Item = union(enum) { num: u32, none: void };
pub const InstList = struct { items: [*]Item, len: u32 };
pub const Blk = struct { insts: InstList };
pub const Inner = struct { v: u32 };
pub const Ctx = struct { store: *Inner, v: u32 };
pub fn makeBlk() Blk {
    var b = Blk{ .insts = InstList{ .items = undefined, .len = 0 } };
    return b;
}
pub fn makeCtx() Ctx {
    var c = Ctx{ .store = undefined, .v = 7 };
    return c;
}
```

`main.zig`:
```zig
const std = @import("std");
const mod = @import("mod.zig");
pub fn main() void {
    var c: mod.Ctx = mod.Ctx{ .store = undefined, .v = 7 };
    var blk = mod.makeBlk();
    var inst = blk.insts.items[0];
    std.io.printInt(c.v);
}
```

- [ ] **Step 2: Run RED baseline**

Run from the fixture dir: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
Expected: rc=2, one or more `error[3000]: cannot declare variable of type void` (at `var c` and/or `var inst`), 0-byte `.c`.

- [ ] **Step 3: GREEN control**

Control (in `/tmp`): same program minus the two failing declarations (`var c` fixed to `var c: mod.Ctx = mod.makeCtx();` becomes `var c = mod.makeCtx();`; `var inst` removed) → verify which single construct trips.

- [ ] **Step 4: Type-kind matrix sweep**

In NOTES.md, record for each variant:
1. struct annotation + struct-literal init (`var c: mod.Ctx = mod.Ctx{…}`) ✓ RED (shape D)
2. struct inferred (`var c = mod.makeCtx();`)
3. tagged-union field-access inferred (`var inst = blk.insts.items[0]`) ✓ RED (shape E)
4. union type in annotation (`var it: mod.Item = …`)
5. plain enum cross-module annotation
6. error-set cross-module annotation
7. array/slice cross-module annotation
8. field-access depth: 1 hop (`blk.insts`) vs 2 hops (`blk.insts.items`) vs 3 (`blk.insts.items[i]`)

- [ ] **Step 5: NOTES.md**

Record: purpose, fixture sources, RED baseline (which declarations fire), GREEN control isolation (shape D alone vs E alone), matrix table, blast-radius lead, post-fix expectation.

- [ ] **Step 6: Commit**

```bash
git add repro/mi_matrix/voiddecl_xmodtype_xmod/
git commit -m "repro: cross-module struct/tagged-union refs resolve void (voiddecl_xmodtype_xmod)"
```

---

### Task I-IFEXPR (read-only investigation)

**Consumes:** R1 NOTES.md matrix. **Produces:** root cause + blast radius for F1.

- [ ] **Step 1: Trace the resolution path**

In `sf/src/semantic_analyzer.zig`, trace `semanticAnalyzerResolveExpr` on the value-position `if (cond) A else B` node (`AstKind.if_expr`). Identify where the void fallback fires (Q1VF path at :424-426 or a sibling). Compare against the F-PARSERGAP fix (value-position `if (opt) |cap|`) to see why the optional-capture form works but the plain bool form does not.

- [ ] **Step 2: Locus + blast radius**

Report exact file:line for the if_expr arm, why `it` collapses to TYPE_VOID (both branches? the cond?), and the minimal fix locus. Byte-identity reasoning (which inputs change).

- [ ] **Step 3: Report + revert**

Write `.superpowers/sdd/task-I-IFEXPR-report.md`; zero source changes; tree clean.

---

### Task I-SWITCHEXPR (read-only investigation)

**Consumes:** R2 NOTES.md matrix. **Produces:** root cause + blast radius for F2.

- [ ] **Step 1: Trace the resolution path**

Trace `semanticAnalyzerResolveExpr` on the value-position `switch` node. Identify the switch-expr arm, how the result type is derived (from arm values? from expected-type annotation?), and where void fallback fires. Compare with switch-as-statement (which works — `lexerSkipWSC` compiles).

- [ ] **Step 2: Locus + blast radius**

Report exact file:line, whether the enum annotation is the trigger or the switch-value mechanism, minimal fix locus, byte-identity reasoning.

- [ ] **Step 3: Report + revert**

Write `.superpowers/sdd/task-I-SWITCHEXPR-report.md`; zero source changes; tree clean.

---

### Task I-U64CAST (read-only investigation)

**Consumes:** R3 NOTES.md matrix. **Produces:** root cause + blast radius for F3.

- [ ] **Step 1: Trace the resolution path**

Trace binary `&` (`AstKind.bitand` or equivalent) with u64 operands, the `@intCast(u32, u64)` narrowing, and large-literal (`0xFFFFFFFF`) typing. Identify whether the void collapse is in the `&` operator arm, the intCast, or the literal's integer_literal_type. Check post-F1 changes: `AstNode.payload` u32→u64 means all `node.payload & …` sites now operate on u64.

- [ ] **Step 2: Locus + blast radius**

Report exact file:line for each suspect layer, which is the true root, minimal fix, byte-identity reasoning (only u64 `&`/cast inputs change).

- [ ] **Step 3: Report + revert**

Write `.superpowers/sdd/task-I-U64CAST-report.md`; zero source changes; tree clean.

---

### Task I-XMODTYPE (read-only investigation)

**Consumes:** R4 NOTES.md matrix. **Produces:** root cause + blast radius for F4.

- [ ] **Step 1: Trace the resolution path**

Trace (a) cross-module struct annotation + struct-literal init (`var s: T = T{…}` where T is from another module), (b) multi-hop field access to a tagged-union element (`blk.insts.items[i]`). Identify where the module-qualified lookup fails (symbolRegistryQualifiedLookup / Q1VF) and why small cross-module struct-return repros (R1 ladder r1, GREEN) pass but these fail. This is the R2 ladder lead ("cross-module type ref trips at N=3"); pin whether it's the tagged-union kind, the pointer-field struct, or the field-access depth.

- [ ] **Step 2: Locus + blast radius**

Report exact file:line, the discriminating condition, minimal fix, byte-identity reasoning, and the full closure scan (how many additional sites in `sf/src` share the class — whole-tree scan, never stop at first error).

- [ ] **Step 3: Report + revert**

Write `.superpowers/sdd/task-I-XMODTYPE-report.md`; zero source changes; tree clean.

---

### Task STOP: consolidated ruling

- [ ] **Step 1:** Present all 4 I-task reports + R1-R4 matrix results.
- [ ] **Step 2:** Operator rules: F1-F4 fix specs (fill placeholders below), any scope adjustments, any re-baseline decisions.
- [ ] **Step 3:** Record rulings as a plan AMENDMENT (committed).

---

### Task F1 (placeholder — shape A, filled by STOP)

Fix the value-position `if (bool) A else B` void collapse per I-IFEXPR. Gates: R1 RED→GREEN, 4 MD5s byte-identical, corpus unchanged, matrix/analyzer baseline, self-compile frontier re-check (tree-wide).

### Task F2 (placeholder — shape B, filled by STOP)

Fix the value-position `switch` + enum-annotation void collapse per I-SWITCHEXPR. Gates: R2 RED→GREEN, 4 MD5s, corpus, matrix/analyzer, self-compile frontier.

### Task F3 (placeholder — shape C, filled by STOP)

Fix the u64 `&` / `@intCast` narrow / large-literal void collapse per I-U64CAST. Gates: R3 RED→GREEN, 4 MD5s, corpus, matrix/analyzer, self-compile frontier.

### Task F4 (placeholder — shape D+E, filled by STOP)

Fix the cross-module struct/tagged-union ref void collapse per I-XMODTYPE. Gates: R4 RED→GREEN, 4 MD5s, corpus, matrix/analyzer, self-compile frontier, whole-closure scan (0 same-class sites).

---

### Task GATE: final sweep + reconciliation

- [ ] **Step 1:** Corpus sweep = prior 277 + R1-R4 dirs (281), per-module recipe, classify (OK/FAIL/ICE/CRASH/GG).
- [ ] **Step 2:** 4 MD5s, 21-matrix, test_analyzer — all baseline.
- [ ] **Step 3:** EXPECTED_FAIL version bump + closeout (mechanism records from 4 I-tasks, 4 fixes, R fixtures, new self-compile status). QUICK_REF baseline update.
- [ ] **Step 4:** Record next self-compile blocker (if any) — do NOT fix.

---

### Task M-FINAL: final whole-branch review

- [ ] **Step 1:** `bash <skilldir>/scripts/review-package b86279d4 HEAD` → .diff.
- [ ] **Step 2:** Dispatch final reviewer (requesting-code-review/code-reviewer.md template).
- [ ] **Step 3:** Fix wave for Critical/Important findings (ONE fixer), re-review.

---

## AMENDMENT (2026-08-18, operator ruling after R1 BLOCKED)

**R1 finding (evidence over plan):** the brief's literal-form fixture (`var cmp_op = if (kind == 1) 13 else 12;`) is GREEN (rc=0, prints 12), not RED. The actual trigger for shape A is **untyped module-level `const`** referenced in an inferred `var` init in value position: bare (`var x = A;`), binary-op operand (`var x = A + B;`), or as both if-branches (`if (c) A else B`). This matches the real `lower.zig:4410` site exactly (`BIN_LE`/`BIN_LT` are untyped module consts at lower.zig:50-51). Annotating the const (`: u8`) or the var (`: u32`) downgrades to warning/GREEN. Cross-module untyped consts (`mod.A`) also RED. Full 22-probe evidence: `repro/mi_matrix/voiddecl_ifexpr_xmod/NOTES.md`, `.superpowers/sdd/task-R1-voiddecl-report.md`.

**Operator ruling:** R1 becomes a two-fixture task — (1) literal form committed as a GREEN control/negative fixture documenting the literal-does-not-trigger finding, AND (2) module-const form committed as the RED trigger fixture. Both under `repro/mi_matrix/voiddecl_ifexpr_xmod/` (or sibling dir if cleaner).

**I-IFEXPR pivot (binding):** the if-expr is the carrier, NOT the poison. Investigate **const resolution** — untyped `const X = <expr>` resolving to void in value position (what makes the reference void) — not the if-expr bool/cond mechanics per se. Locus lead: symbol/type resolution of untyped module-level consts (TYPE_VOID collapse when referenced from an inferred var init), compare annotated-const/annotated-var GREEN paths.

---

## AMENDMENT 2 (2026-08-18, operator ruling after all 4 I-tasks + audit cleared)

**R-LADDER + 4 I-TASKS COMPLETE, ALL APPROVED** (see ledger). Two DISTINCT roots behind the 9 self-compile error[3000] sites:

- **ROOT 1 — untyped module-level const/var collapse** (shapes A/B/C/D): `symbol_registrator.zig:235` starts `sym_type_id = 0`; only set for import/type-decl/ident-alias/array-slice-many_ptr inits, NEVER general value-expression inits. Value-position ref → `TYPE_VOID` via SVO `semantic_analyzer.zig:291` / Q1VF `:424-426` → var-decl hard error `:1915-1921`. Covers **4 sites**: main.zig:588, symbol_registrator:258/:357, lower.zig:4410. Verified independently by I-IFEXPR, I-SWITCHEXPR, I-U64CAST.
- **ROOT 2 — tagged-union `.tag` discriminator gap** (shape E): `resolveFieldAccess` tagged_union_type branch `semantic_analyzer.zig:473-476` + variant loop `:570-586` + NF fallback `:588-591` never searches the discriminator → `TYPE_VOID`. Fix = return `tp.tag_type` when `field_name_id == interner("tag")`. Covers **5 lower.zig sites**: 5218/5275/5319/5395/5403. Verified by I-XMODTYPE (R4 matrix row-8 blind spot confirmed: chain GREEN up to `.tag`).
- **NEW BLOCKER (post-fix exposure):** `error[3043]` unslice_slice_expr ICE at `lower.zig:722-739` — exposed only after Roots 1+2 clear the 9. Not part of the void family.

### OPERATOR RULINGS (binding, 2026-08-18)
1. **REJECT lazy resolve-and-backfill at consumption** (the `:291`/`:424-426` fallback design) — "the biggest sin on zig0"; fallbacks are NOT allowed on a prod-grade compiler.
2. **MANDATE "front immediate resolution"**: resolve module-level const/var init types at DECLARATION time, upstream, order-independent. No lazy fallback.
3. **NO leaking pass logic into `main.zig`** (orchestrator). The resolution pass lives in its own `.zig` file. Existing leaking logic (`main.zig:448-455` nameCachePut ident block, `resolveStmtTypes` `:475-525`) is to be moved INTO the pass.
4. F fixes MUST address root causes upstream — no patches, no fallbacks.
5. **ICE gets its own separated R/I/F task** appended at the end of this plan (repro → investigate → fix).

### Task I-FRONTRES (NEW, read-only — Root 1 front-resolution design decision)

**Consumes:** I-IFEXPR/I-SWITCHEXPR/I-U64CAST/I-XMODTYPE reports. **Produces:** the definitive Root-1 fix design (mechanism + locus + pass placement) for F1.

**Decision framing (binding input):** the operator pre-selected the dedicated semantic-analyzer pass (Approach B). This task validates that choice against the alternatives and pins the exact implementation:

- **Approach A — extend the type-resolver prepass (`resolveNamedTypeExpressions`):** lives in type_resolver.zig, runs pre-`typeResolverBuild`. PRO: no new pass/phase. CON: `resolveTypeExprFull` is a TYPE-expr resolver, not a VALUE-expr resolver (returns `TYPE_UNDEFINED` on `@intCast`/enum-member/cross-module-type/binary/struct-literal — exactly the failing forms); runs BEFORE the type registry is built so cross-module types unavailable (cannot fix shape D structurally); single linear pass (no fixpoint → cross-module const chains still order-fail); risks reimplementing sema inside the type resolver (the "leaking logic" smell).
- **Approach B — dedicated pass using the semantic-analyzer resolver (operator-selected):** a new pass (own `.zig` file or `pub fn` in semantic_analyzer.zig) running AFTER type resolution (`main.zig:344`) and BEFORE fn-body sema, walking all modules' module-level `var_decl` inits, resolving each via the existing `semanticAnalyzerResolveExpr`/`semanticAnalyzerResolveModuleVarDecl`, writing `sym.type_id` + `nameCachePut`, iterating to fixpoint for cross-module const chains. PRO: reuses the ONE real value-expr resolver (no second typing implementation); runs after types exist (fixes D/E structurally); order-independent; REMOVES leaking logic from main.zig. CON: new orchestration surface; must isolate side effects (coercion table / enum_value_table / error_code_registry appends + diagnostics) — proposed: throwaway scratch `SemanticAnalyzer` context per module, diagnostics suppressed, side tables discarded; heavier but module-level init count is small.

- [ ] **Step 1:** Verify the pass placement is correct: AFTER `typeResolverResolve` (`main.zig:344`) and BEFORE `phase_SemanticAnalysis` fn-body loop (`main.zig:421`). Confirm `semanticAnalyzerResolveExpr` can be invoked with a throwaway context at that point (read `semanticAnalyzerInit` main.zig:411 signature + `semanticAnalyzerResolveModuleVarDecl` semantic_analyzer.zig:2128-2146).
- [ ] **Step 2:** Confirm the exact side-effect isolation needed: which of coercion_table/enum_value_table/error_code_registry/call_arg_types/call_param_map the throwaway context should bind vs leave unbound; whether diagnostics from the pass must be suppressed (or deduped) to avoid duplicate-warning regressions; whether the later real sema run re-resolves module inits (idempotent) or must skip them.
- [ ] **Step 3:** Pin the fixpoint termination bound for cross-module const chains (acyclic const graph → bounded iterations; match `constAliasPrepass`'s Kahn intent).
- [ ] **Step 4:** Report: `.superpowers/sdd/task-I-FRONTRES-report.md` with the validated design (mechanism, locus, new-file-vs-function placement, exact main.zig call-site + which leaking blocks to remove, side-effect contract, fixpoint bound, byte-identity reasoning, discriminating test). Zero source changes; tree clean; revert any /tmp instrumentation.

### Task F1 (RE-MAPPED — Root 1, front immediate resolution)

Implement the validated I-FRONTRES design: a dedicated front-resolution pass (own file) that resolves every module-level `var_decl` init type via the semantic-analyzer resolver and writes `sym.type_id` + `nameCachePut`, order-independent fixpoint. Remove the leaking `main.zig:448-455` ident nameCachePut block + `resolveStmtTypes` into the pass. NO fallback added at `:291`/`:424-426`. Gates: R1-R4 RED→GREEN (all four fixtures), 4 MD5s byte-identical, corpus unchanged, matrix/analyzer baseline, self-compile frontier re-check (tree-wide) — expect the 4 Root-1 sites (main.zig:588, symbol_registrator:258/:357, lower.zig:4410) cleared; the 5 Root-2 sites remain until F2.

### Task F2 (RE-MAPPED — Root 2, tagged-union `.tag`)

Add the discriminator to field-access resolution: in the `resolveFieldAccess` tagged_union_type branch (`semantic_analyzer.zig:473-476`/`:570-591`), when `field_name_id == interner("tag")` return `tp.tag_type` (`TaggedUnionPayload.tag_type`, type_registry.zig:83). Root-cause fix, not a fallback. Gates: R4-E + re-created `.tag` probe fixture GREEN, 4 MD5s byte-identical, corpus unchanged, matrix/analyzer baseline, self-compile — expect the 5 Root-2 lower.zig sites (5218/5275/5319/5395/5403) cleared; verify total error[3000]==0 (not just tracked 9).

### Task R-ICE (NEW, appended — error[3043] slice_expr repro)

Create `repro/mi_matrix/parsergap_slice_expr_xmod/{main.zig,NOTES.md}` reproducing the `error[3043] internal: unsupported slice_expr form/base` ICE (lower.zig:722-739). RED = rc=3 ICE (exit code 3, flushAndExit), 0-byte .c. GREEN control = a supported slice form. NOTES.md: purpose, fixture, RED baseline verbatim, control, post-fix expectation. Fixture only, no sf/src changes, no rebuild.

### Task I-ICE (NEW, appended — read-only)

Trace the `slice_expr` lowering path (`lower.zig:3849+`): what base forms hit `iceSliceUnsupported`, which slice_expr forms ARE supported (array `[0..]`/`[a..b]`/`[a..]`, slice `[0..len]`, etc.), where the gap is, blast radius (whole-closure scan of slice_expr uses in sf/src), exact fix locus, byte-identity reasoning. Report: `.superpowers/sdd/task-I-ICE-report.md`. Zero source changes; tree clean.

### Task F-ICE (NEW, appended)

Fix the slice_expr gap per I-ICE. Gates: R-ICE RED→GREEN, 4 MD5s byte-identical, corpus unchanged, matrix/analyzer baseline, self-compile frontier re-check (tree-wide), whole-closure scan (0 same-class sites).

### Task GATE (AMENDED)

Corpus sweep = prior 277 + R1-R4 dirs + R-ICE dir (282); EXPECTED_FAIL version bump + closeout (2 roots, 4 I-task mechanism records, F1/F2, R-ICE/I-ICE/F-ICE, new self-compile status); QUICK_REF baseline; record next self-compile blocker (do NOT fix).

### Task M-FINAL (unchanged)

Whole-branch review, BASE = b86279d4, requesting-code-review template + fix wave.

### AMENDMENT 3 — operator ruling 2026-08-19: json MD5 re-baseline (F1 gate)

**Ruling (question tool):** Re-baseline json. F1 gate becomes **"3 MD5s byte-identical (gol/lisp/mud) + json re-baselined to `9720478c937409a29fe23ae0199821cf` with runtime-identity proof"** (precedent B-F2 `066c9997→fc357296`, F3 all-four).

**Rationale:** the front-resolution pass types json_parser's untyped module `var g_arena = std.arena.create(1048576)`, so 5 temp decls in emitted C change `unsigned int` → `Arena*` (void-collapse artifact removal). Runtime-identical (rc=0, byte-identical stdout), corpus classification unchanged. The old `fc357296…` json baseline is superseded. GATE + QUICK_REF must carry the new value + the `[F1 re-baselined … → 9720478c…]` forward-pointer on any historical references.

**Source:** validated design in `.superpowers/sdd/task-I-FRONTRES-report.md` (read-only, tree clean, HEAD `70735d9b`).

### AMENDMENT 4 — operator ruling 2026-08-19: F-ICE re-scope + F-REJECT (slice_expr sub-classes)

**Context:** I-ICE (approved) mapped the slice_expr ICE (`error[3043]`, `iceSliceUnsupported` lower.zig:722-739) into TWO genuinely-different sub-classes with different fix loci, plus an invalid-Zig scalar-base case. R-ICE's fixture (`n[1..]` scalar base) is a DIFFERENT sub-class than the real self-compile blocker (node 172203 = zero-length-array `[0]u32` slice) and has ZERO instances in sf/src. The plan's F-ICE gate "R-ICE RED→GREEN" is therefore unmet by the 3-loci fix alone.

**Operator ruling (question tool, 2026-08-19):** (1) F-ICE re-scoped to the self-compile 3-loci fix. (2) The scalar-base slice is INVALID Zig (cannot slice a scalar integer) — "zig0 compiles zig1" only proves constructs IN zig1 source are valid, and `n[1..]` is not in sf/src. Correct handling = a separate CLEAN-REJECT task (sema base-is-sliceable validation → proper diagnostic, not ICE, not support). (3) "lets do the clean reject path".

**F-ICE (RE-SCOPED) — 3-loci self-compile fix:**
1. `type_resolver.zig:1002` — zero-length array support (drops `arr_len == 0` for `[0]u32` → `dummy` unregistered → VOID base → ICE at source_manager.zig:135/137).
2. `semantic_analyzer.zig:2120-2124` — array-init element resolution (resolve all `ec[i]`, not just `ec[0]`) — PRIMARY root-cause fix for the 12 sub-class (a) sites.
3. `lower.zig:3907` — sentinel fix (`TYPE_UNDEFINED`==18 collides with legal temp index 18; use `TEMP_NONE` 0xFFFFFFFF) for the 12 sub-class (b) open-ended `[0..]` fn-call-arg sites.
**Gate:** self-compile `error[3043]` → 0 (node 172203 + all 24 closure sites), PLUS a NEW committed repro `parsergap_zeroarr_slice_xmod` (the real `[0]u32[0..]` form). R-ICE scalar-base fixture stays RED here (unchanged). 4 MD5s byte-identical (gol/lisp/mud + json `9720478c…`), corpus +1 dir, matrix 21/21, test_analyzer 5/4.

**F-REJECT (NEW, after F-ICE) — scalar-base clean reject:**
Sema `semanticAnalyzerResolveSliceExpr` gains a base-is-sliceable check (array/slice/many-ptr allowed; scalar/other rejected with a proper `error[2000]`-class diagnostic). The ICE becomes unreachable for scalar base and stays a genuine invariant guard.
**Gate:** R-ICE fixture `rc=3 ICE` → `rc=2 error[2000]` (0-byte .c, no `internal:` message). 4 MD5s byte-identical, corpus unchanged, matrix 21/21, test_analyzer 5/4.

**GATE (re-amended):** record F-ICE (3 loci) + F-REJECT + next blocker = PANIC `c89_emit.zig:5002` (`width_bits = @intCast(u8, size*8)` u8 overflow on 40-byte tagged-union temp), recorded NOT fixed. Corpus = prior + `parsergap_zeroarr_slice_xmod` dir.

**M-FINAL:** unchanged, BASE = b86279d4.

---

### AMENDMENT 5 — operator ruling 2026-08-19: F-ICE scope-deviation ratification + `.payload` latent R/I/F cluster

**F-ICE scope-deviation RATIFIED.** The F-ICE implementer added 2 upstream sema root-cause fixes beyond the brief's 3 mandated loci to satisfy the `error[3043]→0` gate (commit `fd56da3b`):
- **Fix A** — `semantic_analyzer.zig:2115-2141` array-init element resolution: the old resolver returned the annotated array type immediately (annotation `child_0`→array_type early-return) without resolving element sub-expressions, leaving them without `resolved_type_table` entries. Now resolves ALL `ec[i]` (capturing `annot_tid` separately), then returns `annot_tid` if set else the derived array type. Root cause of the 12 sub-class (a) sites.
- **Fix B** — `semantic_analyzer.zig:841-852` FN3 fn-call arg resolution: the FN3 branch (callee not a function type) previously returned `TYPE_VOID` without resolving args; the 10 `itoa_mod.itoa(…, buf[0..])` sites hit FN3 so their slice args never resolved → `se_rt==null` → ICE. Now resolves all args (discarding results) via the existing `pushExpectedType/resolve/popExpectedType` idiom (same as FN1 `:821-826` / FN4 varargs `:891-899`).
- **Rationale (operator-ratified):** the 3 loci empirically clear only 6/24 sites — I-ICE's sub-class attribution was wrong (the 12 "sentinel collision" itoa sites are actually the FN3 missing-arg-resolution path, proven by mutual exclusion: Fix B cleared exactly those 10, Locus 3 cleared only parser:540 + c89_emit:6037). Both fixes are ruling-4-compliant root causes (no patches/fallbacks), restore the resolver's child-resolution invariant, and are byte-identity-proven across the standard gate surface. FN2 (`:831`, `callee_type==0`) was checked and is defensive dead code (ResolveExpr returns literal 0 only for `node_idx==0`, impossible for a well-formed fn_call) — NOT a live gap.
- **Gate met:** self-compile `error[3043]`→0 whole-tree; 4 MD5s byte-identical (json held `9720478c…`); corpus +1 dir (`parsergap_zeroarr_slice_xmod`, RED rc=3→GREEN prints `0`); matrix 21/21; test_analyzer 5/4; R-ICE scalar-base fixture STAYS RED (rc=3 ICE unchanged, separate F-REJECT sub-class).
- **Next blocker (recorded, NOT fixed):** PANIC `c89_emit.zig:5002` `width_bits = @intCast(u8, size*8)` u8 overflow on 40-byte tagged-union temp.

**NEW `.payload` latent R/I/F cluster (same-class as F2 `.tag`):**
`x.payload` on a tagged union resolves to `TYPE_VOID` (documented latent, `TU_FIELD_PAYLOAD` type_registry.zig:38, currently 0 sites in sf/src) — the exact analog of the `.tag` gap F2 fixed at `semantic_analyzer.zig:475-481`.
- **R-PAYLOAD (repro):** `repro/mi_matrix/voiddecl_payload_xmod/` — tagged-union `union(enum) { a: u32, b: void }` var, read `x.payload`, RED rc=2 `error[3000]`-class (void) or resolved-void, GREEN control = `.tag` read. Fixture convention bare `@import("std")` + `std.io.printInt`, main.zig + NOTES.md committed, timeout-gated. Commit msg: `repro: tagged-union .payload accessor resolves void (voiddecl_payload_xmod)`.
- **I-PAYLOAD (read-only):** trace `resolveFieldAccess` tagged_union_type branch (semantic_analyzer.zig:473-481 region) for `field_name_id == interner("payload")`; confirm `tp.tag_type` fix pattern applies symmetrically (payload = the field type of the active variant); blast radius = whole-closure scan for `.payload` reads (expect 0 in sf/src); locus + byte-identity reasoning. Report `.superpowers/sdd/task-I-PAYLOAD-report.md`. NOTE: unlike F2's fixed-width `.tag`, `.payload`'s type depends on the active variant — design must handle (e.g. emit variant-field type via existing loop `:577-593` which already resolves variant fields — the gap is only that the `.payload` *name* isn't mapped).
- **F-PAYLOAD:** implement per I-PAYLOAD ruling; gates = R-PAYLOAD RED→GREEN, 4 MD5s byte-identical, corpus +1 dir, matrix 21/21, test_analyzer 5/4, self-compile frontier re-check.
- Placed AFTER the current F-REJECT → GATE sequence (out of the current critical path; 0 live sites).

**GATE (re-amended 2):** record F-ICE (3 loci + Fix A + Fix B ratified) + F-REJECT + R/I/F-PAYLOAD status + next blockers = PANIC `c89_emit.zig:5002` width_bits u8 overflow (recorded NOT fixed) + `.payload` latent (0 sites, R/I/F-PAYLOAD cluster). Corpus = prior + `parsergap_zeroarr_slice_xmod` + `voiddecl_payload_xmod` dirs.

---

### AMENDMENT 6 — operator ruling 2026-08-20: F-PAYLOAD design (post-I-PAYLOAD critical evaluation)

**Context:** I-PAYLOAD (DONE_WITH_CONCERNS, report `.superpowers/sdd/task-I-PAYLOAD-report.md`) traced the `.payload` gap and proposed a 2-locus fix. The controller critically evaluated the report for upstreamness + correctness against live source (verified: `lower.zig:1018-1029` store side ALREADY maps `.payload`→`TU_FIELD_PAYLOAD`; `:2450-2461` read side has NO such mapping and falls through to `:2497 return tid` with no load; `c89_emit.zig:4521-4546` load_field TU_FIELD_PAYLOAD resolves `res_ty` from the result temp's hoisted type then scans variants for `vfe.type_id == res_ty` → `.payload.<variant>._0`). Operator ruled the following F-PAYLOAD design:

**F-PAYLOAD — 2-locus fix (ENDORSED):**
1. **Locus 1 (sema):** `semantic_analyzer.zig`, `tagged_union_type` branch, insert after the `.tag` block (`:475-481`), before `fields_start/fields_count` read (`:482-483`). Mirror `.tag` symmetrically: `field_name_id == interner("payload")` → loop `fe_items[fields_start .. fields_start+fields_count]` for the first non-void variant field type, `resolvedTypeTableSet(node_idx, fe.type_id)`, `return fe.type_id`; all-void union falls through to `TYPE_VOID` (kept). **MUST mirror the array→ptr conversion from `:583-586`** (array-typed variant → `ptr(elem)`) so array-typed variants behave identically to `x.a` (controller-flagged gap 1).
2. **Locus 2 (lower):** `lower.zig`, field_access value path, tagged-union branch (`:2450-2461`), after the variant-name loop, before the struct/union `else` (`:2462`). If `field_name_id == interner("payload")` and `fa_box[0] != TYPE_VOID`: `sf_nid = nameMapGet(self, base_temp)`; `emitInst(load_field { name_id = sf_nid, base = base_temp, field_id = TU_FIELD_PAYLOAD, result = tid })`; `return tid`. (`tid` = the `fa_box[0]`-typed temp from `:2417`; emission then produces `tid = x.payload.<variant>._0` via result-temp-type match.)

**Sema-only fix is REJECTED** (silent no-load → uninitialized temp = fallback-like, violates ruling 4). Locus 2 is the symmetric completion of the existing store mapping — root cause, not patch.

**Documented dialect limitation (mandatory):** `.payload`'s static type = first non-void variant field type (deterministic). On a MIXED-type union (`{a: u32, b: i64}`) the single static type is inherently arbitrary — if the runtime active variant differs from the first non-void variant, the emitted `.payload.<first>._0` reads the wrong width. Latent (0 sites in sf/src); recorded as a dialect limitation, not fixed further here.

**`.tag` read-load symmetry — NOT in scope (operator):** F2 fixed `.tag` sema-only; bare `.tag` value-reads (outside switch) still no-load (pre-existing, disclosed in I-PAYLOAD §5). F-PAYLOAD fixes `.payload` reads only; the `.tag` read-load asymmetry is accepted + recorded as a separate latent (do NOT fix here).

**Gates:** R-PAYLOAD fixture RED→GREEN (compile gate: dump rc=0, gcc rc=0; fixture uses `undefined` so runtime prints are NOT the gate); 4 MD5s byte-identical (gol `9cf758d9…`/lisp `88dcb7f9…`/mud `a1d0dd55…`/json `9720478c…`, lisp from repo root); corpus +1 dir (`voiddecl_payload_xmod` flips to OK); matrix 21/21; test_analyzer 5/4; self-compile frontier re-check (error[3000]==0/error[3043]==0 must hold). Byte-identity holds by construction (0 `.payload` reads in sf/src/gates/corpus except the fixture).

**Commit message:** `fix: resolve tagged-union .payload accessor (voiddecl-family F-PAYLOAD)`
