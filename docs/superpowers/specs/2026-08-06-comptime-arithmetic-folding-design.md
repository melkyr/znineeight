# Comptime Arithmetic Folding — Design Spec

**Date:** 2026-08-06
**Status:** Draft

## Goal

zig1 does not constant-fold bare binary/unary arithmetic at module scope. `const X: i32 = 30 * 10;` emits a runtime multiplication in `__module_init` instead of an `int_const` LIR instruction. ComptimeEvaluation phase only visits `builtin_call` nodes; the lowerer never checks the `comptime_values` map for binary ops; and the type resolver's array-size handler is missing `mul`/`div`/`mod_op`.

Implement proper comptime constant folding for all 12 supported binary/unary operations (`+ - * / % & | ^ << >> ~` and unary `-`) across all three pipeline stages.

## Architecture

Three independent pipeline gaps. Fix all three with additive-only changes — nothing existing is broken, only new folding is added.

```
Gap 1: phase_ComptimeEvaluation (main.zig) — skips bare binary/unary consts
        → visit var_decl init expressions that are binary/unary ops, call
          comptimeEvalEvaluate on child_1, populate comptime_values map

Gap 2: lowerer binary/unary handlers (lower.zig) — never consult comptime_values
        → add comptime_values guard before emitting BIN_*/BIT_*/unary LIR,
          emit int_const when folded

Gap 3: type_resolver array-size (type_resolver.zig) — only handles add/sub
        → add mul, div, mod_op to evalConstU32Full fallback chain
```

Plus: comptime_eval.zig currently only handles `add/sub/mul/div/mod_op` — add `bit_and/bit_or/bit_xor/shl/shr` to `comptimeEvalBinOp` and `bit_not` to `comptimeEvalEvaluate`.

## Gaps Discovered

### Gap 1 — phase_ComptimeEvaluation skips bare binary ops

**File:** `sf/src/main.zig:339-352`
**Mechanism:** `phase_ComptimeEvaluation` iterates all AST nodes but only processes `AstKind.builtin_call` (line 345). Bare `add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr/negate/bit_not` nodes at module scope are never visited by `comptimeEvalEvaluate`. The `comptime_values` map stays empty for these nodes.
**Impact:** All 12 ops emit runtime arithmetic in `__module_init` instead of `int_const`. gcc optimizes this away at -O0 so runtime behavior is correct, but the value is not available at compile time for downstream uses (array sizes, type computations).

### Gap 2 — lowerer ignores comptime_values for binary/unary ops

**File:** `sf/src/lower.zig:1218-1298` (binary), `:1433` (bit_not)
**Mechanism:** The lowerer's binary op handlers (`BIN_ADD`/`BIN_SUB`/`BIN_MUL`/`BIN_DIV`/`BIN_MOD` at `:1218-1273`, `BIT_AND`/`BIT_OR`/`BIT_XOR` at `:1274-1298`) emit LIR instructions unconditionally. No check for `comptime_values` map entries. Compare with `builtin_call` handler at `:2456` which does check. The `negate` and `bit_not` unary handlers also lack the guard.
**Impact:** Even if Gap 1 were fixed (map populated), the lowerer would still emit runtime ops. Both gaps must close for folding to work.

### Gap 3 — type_resolver array size missing mul/div/mod

**File:** `sf/src/type_resolver.zig:869-909`
**Mechanism:** `resolveArrayType` size computation handles `int_literal` (`:879`), `add`/`sub` with `evalConstU32Full` on both operands (`:881-887`), and `ident_expr` following const chains (`:888-893`). `mul`, `div`, `mod_op`, `bit_and`, `bit_or`, `bit_xor`, `shl`, `shr` are NOT handled — falls through to `arr_len = 0` (initialized at `:878`).
**Impact:** `[80 * 50]u8` produces a zero-length C array. gcc rejects with "ISO C forbids zero-size array." Also affects `@sizeOf` computations and const array init sizing.

### comptime_eval.zig — missing bitwise/shift ops

**File:** `sf/src/comptime_eval.zig:52-82`
**Mechanism:** `comptimeEvalBinOp` handles `add/sub/mul/div/mod_op` but NOT `bit_and/bit_or/bit_xor/shl/shr`. `comptimeEvalEvaluate` handles `negate` (unary minus) via the direct `-lv` path but NOT `bit_not`. These ops are parsable and semantically handled by sema and lowerer — they just lack comptime folding.
**Impact:** Even if Gap 1 and Gap 2 are fixed, bitwise and shift ops still won't fold at comptime because `comptimeEvalBinOp` returns `null` for them.

## Repro Design (3 new, to `repro/mi_matrix/`)

### Repro 1: `comptime_binop_not_folded` (Gap 1)

Covers all 12 ops:

```zig
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
    print_int(VADD); print_int(VSUB); print_int(VMUL);
    print_int(VDIV); print_int(VMOD);
    print_int(VNEG); print_int(VAND); print_int(VOR);
    print_int(VXOR); print_int(VSHL); print_int(VSHR);
    print_int(VNOT);   // 13 values concat
}
```

**Pre-fix gate:** `grep -c '[\*\/\%\&\|\^\~]'` in emitted C > 0 inside `__module_init` — proves runtime arithmetic emitted. Runtime output is numerically correct (gcc folds).

**Post-fix gate:** emitted `__module_init` has `int_const` for all 13 assignments. No runtime arithmetic in init. Same output.

### Repro 2: `comptime_lower_ignores_fold` (Gap 2)

Same source as Repro 1, separate verification step. After Gap 1 fix only, `comptime_values` map is populated but lowerer still emits `BIN_*`/`BIT_*` LIR. Post-Gap-2 fix, lowerer emits `int_const`.

### Repro 3: `comptime_array_size_gap` (Gap 3)

```zig
const ROWS: usize = 80;
const COLS: usize = 50;
const CELLS: [ROWS * COLS]u8 = undefined;    // mul → size 0 (gap)
const HALF:  [ROWS / 2]u8 = undefined;         // div → size 0 (gap)
const REM:   [ROWS % 6]u8 = undefined;         // mod → size 0 (gap)

pub fn main() void {
    print_int(ROWS * COLS);  // runtime 4000 (not a gate, confirmation only)
}
```

**Pre-fix gate:** dump rc=0, gcc `error: ISO C forbids zero-size array` or similar. FAIL in corpus.

**Post-fix gate:** gcc-clean, arrays have correct sizes (4000, 40, 2).

## I-Task Design

**Deliverable:** `.superpowers/sdd/I-comptime-arithmetic-report.md`

**Scope:**
1. Read tech docs: `04_comptime_eval.md`, `05_semantic_analysis.md`, `07_lir_lowering.md`, `09_pipeline_orchestration.md`, `03_type_resolution.md`, `08_c89_emission.md`, INDEX.md
2. Build scratch compiler in `/tmp` for marker debugging
3. **Gap 1 trace:** Add markers in `phase_ComptimeEvaluation` to confirm which node kinds are visited. Trace `const X: i32 = 30 * 10` from parser through sema through lower through emit. Confirm comptime_values never populated for mul node.
4. **Gap 2 trace:** Add markers in lowerer binary/unary handlers. Confirm `BIN_*` emitted without comptime_values check. Compare with builtin_call handler at `lower.zig:2456`.
5. **Gap 3 trace:** Marker-trace `resolveArrayType` for `[ROWS * COLS]u8`. Confirm arr_len=0 produced.
6. **comptime_eval.zig:** Confirm `bit_and/bit_or/bit_xor/shl/shr` return `null` from `comptimeEvalBinOp`. Confirm `bit_not` not handled in evaluate.
7. **Blast radius:** Verify 4 MD5 baselines have zero bare const binary ops. Verify corpus has zero existing repros with this pattern. Confirm all changes are additive.
8. **Exact edit targets:** List each file:line with the exact code change needed.
9. **Risk assessment:** Zero blast radius (additive folding). Risk = new code introduces bugs in folding logic (operator precedence, unsigned silent wrap, shift overflow).

## F-Tasks (derived from I-task)

Minimum 4 edits, clusterable:

| Edit | File | What |
|------|------|------|
| E1 | `comptime_eval.zig` | Add bit_and/bit_or/bit_xor/shl/shr to BinOp; bit_not to Evaluate |
| E2 | `main.zig` | phase_ComptimeEvaluation visits var_decl with foldable init → populate comptime_values |
| E3 | `lower.zig` | comptime_values guard on all 12 binary/unary op handlers |
| E4 | `type_resolver.zig` | Add mul/div/mod_op to array-size evalConstU32Full |

Optional: also add bitwise/shift to array-size handler (lower priority, unusual in real code).

## Gates

- Build 0 gcc errors (bootstrap in `/tmp`)
- 4 MD5s: mud `4644ad13...`, gol `d0d3051d...` byte-identical; lisp `dd56cd23...`, json `900cb401...` byte-identical
- Corpus: 3 new repros → OK (200→203). Zero FAIL/ICE/CRASH increase
- Each repro post-fix: emitted C has `int_const` in `__module_init`, no runtime arithmetic
- Repro 3 post-fix: gcc-clean, arrays have correct non-zero sizes
- test_analyzer_bin PASS (pre-existing baseline)
