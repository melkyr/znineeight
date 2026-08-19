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
