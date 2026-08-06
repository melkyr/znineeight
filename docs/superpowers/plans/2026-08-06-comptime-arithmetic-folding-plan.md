# Comptime Arithmetic Folding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement constant folding for all 12 binary/unary arithmetic operations at module scope (currently only `@intCast(...)` triggers comptime evaluation).

**Architecture:** Five-phase plan. Phase 0 creates 3 defensive repros. Phase 1 is a standalone I-task investigating all 3 pipeline gaps with tech docs, marker debugging, and blast radius analysis — then STOPS for operator ruling. Phases 2-4 implement fixes based on I-task findings.

**Design spec:** `docs/superpowers/specs/2026-08-06-comptime-arithmetic-folding-design.md`

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89)

## Global Constraints

- Build in /tmp via the QUICK_REF bootstrap recipe (NOT `sf/build/out_release/` — that folder causes timeouts):
  ```bash
  OUT=/tmp/zb
  rm -rf "$OUT" && mkdir -p "$OUT"
  ./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
  ```
  Gate: 0 gcc errors (`error:` count == 0).
- 4 MD5 baselines: mud `4644ad1349c55af80fa1a18fe0e17989`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `dd56cd23984d2533eebd244ffe593791`, json `900cb401779aab11bcf22ce35100323c`. Mud+gol byte-identical; lisp/json re-baselined from P3-6 error-code registry (F-5 AMENDMENT B precedent). Byte-identity for all 4 required.
- Corpus: current 200 repros (OK=193/FAIL=3/green-guards=4, raw FAIL=7). 3 new repros → 203 pre-fix (OK 193→195, FAIL 3→4, green-guards 4; raw FAIL 7→8 — repro 3 counts FAIL, repros 1+2 count OK with emission-gap annotation). Post-fix F4 → 196/3/4 @203 (raw FAIL=7). FAIL count must not increase (only the new zero-size-array repro adds a FAIL, removed by F3).
- test_analyzer_bin PASS. build_test.sh baseline-identical (5/4 or current state). test_semantic_bin pre-existing broken (operator ruling A).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep. NO python/sed.
- Z98 idioms: `@intCast` everywhere, `var msg: []const u8 = "text";` before PAL, if/else-if chains.
- QUICK_REF.md reference mandatory for all gates.

---

### Task P0: Create 3 Defensive Repros

**Files:**
- Create: `repro/mi_matrix/comptime_binop_not_folded/main.zig`
- Create: `repro/mi_matrix/comptime_binop_not_folded/NOTES.md`
- Create: `repro/mi_matrix/comptime_lower_ignores_fold/main.zig`
- Create: `repro/mi_matrix/comptime_lower_ignores_fold/NOTES.md`
- Create: `repro/mi_matrix/comptime_array_size_gap/main.zig`
- Create: `repro/mi_matrix/comptime_array_size_gap/NOTES.md`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Scope:** Create 3 repros proving each pipeline gap. Repro 1 and Repro 2 share the same source logic (12 ops) with different verification. Repro 3 tests array-size mul/div/mod. All expected to FAIL per current compiler.

- [ ] **Step 1: Create Repro 1 (`comptime_binop_not_folded`)**

```bash
mkdir -p repro/mi_matrix/comptime_binop_not_folded
```

`repro/mi_matrix/comptime_binop_not_folded/main.zig`:
```zig
@cInclude("<stdio.h>")
extern fn printf(fmt: [*]const u8, ...) i32;

const A: i32 = 30;
const B: i32 = 10;
const VADD: i32 = A + B;
const VSUB: i32 = A - B;
const VMUL: i32 = A * B;
const VDIV: i32 = A / B;
const VMOD: i32 = A % B;
const VNEG: i32 = -A;
const VAND: i32 = A & B;
const VOR:  i32 = A | B;
const VXOR: i32 = A ^ B;
const VSHL: i32 = A << 2;
const VSHR: i32 = A >> 2;
const VNOT: i32 = ~A;

pub fn main() void {
    var fmt_all: [*]const u8 = "%d %d %d %d %d %d %d %d %d %d %d %d\n";
    _ = printf(fmt_all, VADD, VSUB, VMUL, VDIV, VMOD,
               VNEG, VAND, VOR, VXOR, VSHL, VSHR, VNOT);
}
```

Expected output: `40 20 300 3 0 -30 10 30 20 120 7 -31`

NOTES.md documents: pre-fix gap (runtime arithmetic emitted, not int_const), post-fix expectation (int_const in __module_init), verification via `grep -c '[\*\/\%]'` in emitted C > 0.

- [ ] **Step 2: Create Repro 2 (`comptime_lower_ignores_fold`)**

```bash
mkdir -p repro/mi_matrix/comptime_lower_ignores_fold
```

Same main.zig source as Repro 1 (copy verbatim). NOTES.md documents the lowerer-specific gap: even after Gap 1 fix populates comptime_values, lowerer binary/unary handlers at `lower.zig:1218-1298` and `:1433` emit `BIN_*`/`BIT_*`/unary LIR unconditionally. Compare with `builtin_call` handler at `:2456` which does check comptime_values.

- [ ] **Step 3: Create Repro 3 (`comptime_array_size_gap`)**

```bash
mkdir -p repro/mi_matrix/comptime_array_size_gap
```

`repro/mi_matrix/comptime_array_size_gap/main.zig`:
```zig
const ROWS: usize = 80;
const COLS: usize = 50;
const CELLS: [ROWS * COLS]u8 = undefined;
const HALF:  [ROWS / 2]u8 = undefined;
const REM:   [ROWS % 6]u8 = undefined;

pub fn main() void {}
```

NOTES.md documents: pre-fix gcc `error: ISO C forbids zero-size array` (type_resolver.zig misses mul/div/mod in array size eval), post-fix expected gcc-clean with correct array sizes (4000, 40, 2).

- [ ] **Step 4: Update EXPECTED_FAIL.md**

Add 3 new rows to the classification table with measured pre-fix state:
- `comptime_binop_not_folded` — **OK with emission-gap annotation** (gcc-clean, runtime output correct, but emitted C shows runtime arithmetic instead of int_const — gap proven by C89 inspection). Counted OK in totals, per the `load_global_array_copy`/`comptime_neg_int` precedent of counting runtime/emission-gap repros as OK.
- `comptime_lower_ignores_fold` — **OK with emission-gap annotation** (same).
- `comptime_array_size_gap` — **FAIL** (gcc `error: ISO C forbids zero-size array`). Counted FAIL until F3 fixes it.

Update totals: 200→203 (OK 193→195, FAIL 3→4, green-guards 4; raw FAIL 7→8). Document the new bucket. Post-fix F4 reclassifies repro 3 OK → final 196/3/4 @203 (raw FAIL 7).

- [ ] **Step 5: Verify + commit**

```bash
# Build /tmp compiler, classify all 3 repros
# Confirm Repro 3 FAILs gcc (zero-size array)
# Confirm Repros 1+2 gcc-clean (runtime output correct, gap is in C89 inspection)

git add repro/mi_matrix/comptime_binop_not_folded/ repro/mi_matrix/comptime_lower_ignores_fold/ repro/mi_matrix/comptime_array_size_gap/ repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "repro(P0): 3 defensive repros for comptime arithmetic folding gaps"
```

---

### Task I1: Investigate Comptime Arithmetic Pipeline Gaps

**Files:** investigation → `.superpowers/sdd/I-comptime-arithmetic-report.md`

**Pre-requisites:** P0 (repros exist).

**Scope:** Full pipeline investigation of 3 gaps (main.zig phase_ComptimeEvaluation visitor, lower.zig comptime_values guard, type_resolver.zig array size ops) plus comptime_eval.zig missing bitwise/shift ops. Read tech docs, marker-debug, trace end-to-end, determine exact file:line edit targets, blast radius, risk.

- [ ] **Step 1: Read tech docs**

Read: `sf/docs/tech_docs/04_comptime_eval.md`, `05_semantic_analysis.md`, `07_lir_lowering.md`, `09_pipeline_orchestration.md`, `03_type_resolution.md`, `08_c89_emission.md`, INDEX.md. Understand the pipeline contract for comptime evaluation: what phases exist, who owns what, standard edit patterns.

- [ ] **Step 2: Build scratch compiler for marker debugging**

```bash
OUT=/tmp/pci
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
```

- [ ] **Step 3: Gap 1 — phase_ComptimeEvaluation node visitor**

Add markers in `phase_ComptimeEvaluation` (main.zig:339-352) confirming only `builtin_call` nodes are visited. Build a minimal repro `const X: i32 = 30 * 10;` and verify the `mul` node never reaches `comptimeEvalEvaluate`. Check: what other AST kinds could profitably be visited? var_decl with `child_1` as binary/unary op? Or switch on kind in the loop?

- [ ] **Step 4: Gap 2 — lowerer binary/unary handler comptime_values guard**

Read lower.zig binary op handlers: `:1218-1246` (add/sub), `:1247-1273` (mul/div/mod), `:1274-1298` (bit_and/bit_or/bit_xor). Read unary handler: `:1433` (bit_not). Also check: `:1413-1432` (negate). Confirm none check `comptime_values`. Compare with `builtin_call` handler at `:2456-2471` which DOES check. Document the guard pattern: `if (self.comptime_values != null) { if (self.comptime_values.?get(node_idx)) |val| { return emitIntConst(val); } }`.

- [ ] **Step 5: Gap 3 — type_resolver array size eval**

Read `resolveArrayType` at type_resolver.zig:869-909. Confirm int_literal (`:879`), add/sub with evalConstU32Full (`:881-887`), ident_expr following const chains (`:888-893`). Confirm mul/div/mod_op are NOT handled → `arr_len = 0` from `:878`. Markers: print arr_len after resolution for `[ROWS * COLS]u8` → 0.

- [ ] **Step 6: comptime_eval.zig — missing bitwise/shift ops**

Read comptime_eval.zig:41-86 (comptimeEvalBinOp). Confirm add/sub/mul/div/mod_op handled (52-82). Confirm bit_and/bit_or/bit_xor/shl/shr return null (fall off end). Read evaluate function (141-182): confirm negate handled (unary minus) but bit_not NOT handled. Determine exact insertion points for the 6 new ops.

- [ ] **Step 7: Blast radius analysis**

Verify 4 MD5 baselines contain zero bare const binary/unary ops (only const-decl with literals or @intCast). Search corpus: `grep -r 'const.*=.*[\*\+\-/]' repro/mi_matrix/*/main.zig` — confirm zero existing repros affected. Verify all changes are additive (new folding does not change existing behavior).

- [ ] **Step 8: Determine exact edit targets**

For each gap, list file:line with exact code needed. Minimum 4 files:
- `comptime_eval.zig` — 6 new ops in BinOp + 1 in Evaluate
- `main.zig` — phase_ComptimeEvaluation visits var_decl with foldable init
- `lower.zig` — comptime_values guard on 12 op handlers
- `type_resolver.zig` — mul/div/mod_op in array-size eval

Assess optional: bitwise/shift in array-size handler (unlikely in real code, defer unless operator rules otherwise).

- [ ] **Step 9: Risk assessment**

Zero blast radius (additive folding). Risks: (1) operator precedence in new comptime ops (u64 eval, signed/unsigned width rules), (2) shift overflow (<< 64+ bits), (3) division by zero (already guarded), (4) interaction with global-init order (folded consts must emit before uses — verify emitGlobalDecls ordering).

- [ ] **Step 10: Report + STOP**

Write `.superpowers/sdd/I-comptime-arithmetic-report.md` with all findings, exact edit targets, blast radius, risk assessment. STOP for operator ruling before any implementation.

---

### Task F1: Fix comptime_eval.zig — Add Missing Bitwise/Shift Ops

**Pre-requisites:** I1 complete, operator ruling.

**Files:** `sf/src/comptime_eval.zig`

**Scope:** Add `bit_and`, `bit_or`, `bit_xor`, `shl`, `shr` to `comptimeEvalBinOp`. Add `bit_not` to `comptimeEvalEvaluate`.

(Exact code TBD from I1 findings — plan amended after I1.)

- [ ] **Step 1: Add bit_and/bit_or/bit_xor/shl/shr to comptimeEvalBinOp**

Insert at `comptime_eval.zig:~82` (after mod_op block, before `return null`):

```zig
if (op_kind == AstKind.bit_and) return ComptimeVal{ .bits = lv & rv, .width_bits = maxw, .sig = false };
if (op_kind == AstKind.bit_or)  return ComptimeVal{ .bits = lv | rv, .width_bits = maxw, .sig = false };
if (op_kind == AstKind.bit_xor) return ComptimeVal{ .bits = lv ^ rv, .width_bits = maxw, .sig = false };
if (op_kind == AstKind.shl)     return ComptimeVal{ .bits = lv << rv, .width_bits = maxw, .sig = false };
if (op_kind == AstKind.shr)     return ComptimeVal{ .bits = lv >> rv, .width_bits = maxw, .sig = false };
```

- [ ] **Step 2: Add bit_not to comptimeEvalEvaluate**

In the evaluate function (`~:160` unary handler), add `bit_not` alongside `negate`:

```zig
} else if (node.kind == AstKind.bit_not) {
    var inner = comptimeEvalEvaluate(self, node.child_0);
    if (inner) |v| return ComptimeVal{ .bits = ~v.bits, .width_bits = v.width_bits, .sig = false };
    return null;
```

- [ ] **Step 3: Verify + commit**

Build /tmp compiler. Verify `@intCast(i32, 30 & 10)` now folds via builtin_call path (proves new ops work in comptime_eval). 4 MD5s byte-identical.

```bash
git add sf/src/comptime_eval.zig
git commit -m "feat(F1): add bit_and/bit_or/bit_xor/shl/shr/bit_not to comptime evaluation"
```

---

### Task F2: Fix main.zig + lower.zig — Wire Comptime Folding Pipeline

**Pre-requisites:** F1 complete.

**Files:** `sf/src/main.zig`, `sf/src/lower.zig`

**Scope:** Expand phase_ComptimeEvaluation to visit var_decl init expressions (Gap 1). Add comptime_values guards to all 12 lowerer binary/unary op handlers (Gap 2).

(Exact code TBD from I1 findings — plan amended after I1.)

- [ ] **Step 1: Expand phase_ComptimeEvaluation in main.zig**

In the node loop (`main.zig:339-352`), add a branch that visits `var_decl` nodes where `child_1 != 0` (has init) and the init is a binary/unary op kind. Call `comptimeEvalEvaluate` on `child_1` and populate `comptime_values` under the `var_decl` node's `child_1` index (or under the var_decl node index itself — determined by I1).

- [ ] **Step 2: Add comptime_values guards to lowerer binary op handlers**

For each of the 6 binary op handler groups in lower.zig (`:1218-1246` add/sub, `:1247-1273` mul/div/mod, `:1274-1298` bit_and/bit_or/bit_xor), insert a comptime_values check BEFORE emitting the LIR instruction:

```zig
if (self.comptime_values != null) {
    if (self.comptime_values.?.get(node_idx)) |val| {
        var temp = self.nextTemp(self.nodeType(node_idx));
        return self.emitIntConst(temp, val);
    }
}
```

- [ ] **Step 3: Add comptime_values guards to lowerer unary op handlers**

Same guard pattern for negate (`:1413-1432`) and bit_not (`:1433`).

- [ ] **Step 4: Verify repros 1+2 post-fix**

Build /tmp compiler. Verify Repro 1 (`comptime_binop_not_folded`): emitted C has `int_const` in `__module_init` for all 12 ops. Verify Repro 2 (`comptime_lower_ignores_fold`): same. Both gcc-clean + runtime output correct. 4 MD5s byte-identical.

- [ ] **Step 5: Commit**

```bash
git add sf/src/main.zig sf/src/lower.zig
git commit -m "feat(F2): wire comptime folding for bare const binary/unary ops"
```

---

### Task F3: Fix type_resolver.zig — Array Size mul/div/mod

**Pre-requisites:** F2 complete.

**Files:** `sf/src/type_resolver.zig`

**Scope:** Add mul/div/mod_op to array size evaluation in resolveArrayType (Gap 3).

(Exact code TBD from I1 findings — plan amended after I1.)

- [ ] **Step 1: Add mul/div/mod_op to resolveArrayType size eval**

At `type_resolver.zig:~888-893` (after ident_expr chain following), add handling for mul, div, mod_op mirroring the add/sub pattern:

```zig
} else if (init_kind == AstKind.mul or init_kind == AstKind.div or init_kind == AstKind.mod_op) {
    var c0 = evalConstU32Full(... child_0 ...);
    var c1 = evalConstU32Full(... child_1 ...);
    if (c0 != null and c1 != null) {
        if (init_kind == AstKind.mul) arr_len = c0.? * c1.?;
        else if (init_kind == AstKind.div) { if (c1.? == 0) { ... error ... } else { arr_len = c0.? / c1.?; } }
        else { if (c1.? == 0) { ... error ... } else { arr_len = c0.? % c1.?; } }
    }
```

- [ ] **Step 2: Verify Repro 3 post-fix**

Build /tmp compiler. Verify `comptime_array_size_gap`: dump rc=0, gcc-clean (no zero-size array error), arrays have correct sizes. 4 MD5s byte-identical.

- [ ] **Step 3: Commit**

```bash
git add sf/src/type_resolver.zig
git commit -m "feat(F3): add mul/div/mod to array size comptime evaluation"
```

---

### Task F4: Gate Sweep + Docs

**Pre-requisites:** F3 complete.

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `sf/docs/tech_docs/*.md`

**Scope:** Full gate battery: corpus re-classify 3 repros OK, 4 MD5s re-verify, QUICK_REF update, tech docs update (AGENTS.md §1.1.1).

- [ ] **Step 1: Re-classify 3 repros as OK in EXPECTED_FAIL.md**

Update each repro row to OK. Update totals: OK=196/FAIL=3/green-guards=4 @203 (raw FAIL=7). Document fix commits.

- [ ] **Step 2: Update QUICK_REF.md**

Update corpus gate section to reflect 203 repros. Document comptime-arithmetic note.

- [ ] **Step 3: Full gate sweep**

```bash
# Build /tmp compiler
# Verify all 3 repros: dump rc=0, gcc-clean, runtime correct
# Verify 4 MD5s byte-identical
# Current corpus total 203: 196+3+4=203
# test_analyzer_bin PASS
```

- [ ] **Step 4: Tech docs update (AGENTS §1.1.1)**

Update `04_comptime_eval.md` with new bitwise/shift ops. Update `09_pipeline_orchestration.md` with expanded phase visitor. Update `07_lir_lowering.md` with comptime_values guard. Update `03_type_resolution.md` with array size mul/div/mod. Add `[updated: 2026-08-06]` annotations.

- [ ] **Step 5: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md sf/docs/tech_docs/04_comptime_eval.md sf/docs/tech_docs/07_lir_lowering.md sf/docs/tech_docs/09_pipeline_orchestration.md sf/docs/tech_docs/03_type_resolution.md
git commit -m "docs(F4): gate sweep + tech docs for comptime arithmetic folding"
```

---

## Amendments Record

None yet.
