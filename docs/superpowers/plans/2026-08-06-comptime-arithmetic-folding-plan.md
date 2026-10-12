# Comptime Arithmetic Folding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement constant folding for all 12 binary/unary arithmetic operations at module scope (currently only `@intCast(...)` triggers comptime evaluation).

**Architecture:** Phase 0 creates defensive repros. Phase 1 is a standalone I-task investigating all 3 pipeline gaps (STOP for operator ruling — done, rulings received). Phases 2-9 implement fixes based on I1 findings: F1/F2 comptime_eval.zig ops, F3 main.zig const-only folding, F4/F5 lower.zig guards, F6 type_resolver array size, F7 u64>32-bit fold bug (operator ruling I1-A, serious), F8 ident_expr const-chain fold (operator ruling I1-B), F9 gate sweep + docs.

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
- Corpus: current 200 repros (OK=193/FAIL=3/green-guards=4, raw FAIL=7). 4 new repros → 204 pre-fix (OK 193→196, FAIL 3→4, green-guards 4; raw FAIL 7→8 — the 3 comptime repros count OK with emission/runtime-gap annotations per operator ruling, the varargs repro counts FAIL). Post-fix F4: repro 3's runtime-gap resolved by F3 (already OK) → 196/4/4 @204 (raw FAIL=8). FAIL count must not increase (only the new varargs repro adds a FAIL, out of scope).
- test_analyzer_bin PASS. build_test.sh baseline-identical (5/4 or current state). test_semantic_bin pre-existing broken (operator ruling A).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep. NO python/sed.
- Z98 idioms: `@intCast` everywhere, `var msg: []const u8 = "text";` before PAL, if/else-if chains.
- QUICK_REF.md reference mandatory for all gates.

---

### Task P0: Create 3 Defensive Repros + varargs tracking repro

**Files:**
- Create: `repro/mi_matrix/comptime_binop_not_folded/main.zig`
- Create: `repro/mi_matrix/comptime_binop_not_folded/NOTES.md`
- Create: `repro/mi_matrix/comptime_lower_ignores_fold/main.zig`
- Create: `repro/mi_matrix/comptime_lower_ignores_fold/NOTES.md`
- Create: `repro/mi_matrix/comptime_array_size_gap/main.zig`
- Create: `repro/mi_matrix/comptime_array_size_gap/NOTES.md`
- Create: `repro/mi_matrix/fn_varargs_unsupported/main.zig` (tracking repro, operator ruling P0-D)
- Create: `repro/mi_matrix/fn_varargs_unsupported/NOTES.md`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`

**Scope:** Create 3 repros proving each pipeline gap. Repro 1 and Repro 2 share the same source logic (12 ops) with different verification. Repro 3 tests array-size mul/div/mod. Plus 1 tracking repro for the varargs parse gap discovered during P0 (operator ruling P0-D). All 3 comptime repros classify OK-with-gap-annotation per operator rulings; the varargs repro classifies FAIL.

- [ ] **Step 1: Create Repro 1 (`comptime_binop_not_folded`)**

```bash
mkdir -p repro/mi_matrix/comptime_binop_not_folded
```

`repro/mi_matrix/comptime_binop_not_folded/main.zig` (CORRECTED source — plan's original varargs form does not compile; this is the operator-approved correction, ruling P0-C):
```zig
@cInclude("<stdio.h>");
extern fn printf(fmt: [*]const u8, a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32, j: i32, k: i32, l: i32) i32;

const VADD: i32 = 30 + 10;
const VSUB: i32 = 30 - 10;
const VMUL: i32 = 30 * 10;
const VDIV: i32 = 30 / 10;
const VMOD: i32 = 30 % 10;
const VNEG: i32 = -30;
const VAND: i32 = 30 & 10;
const VOR:  i32 = 30 | 10;
const VXOR: i32 = 30 ^ 10;
const VSHL: i32 = 30 << 2;
const VSHR: i32 = 30 >> 2;
const VNOT: i32 = ~30;

pub fn main() void {
    var fmt_all: [*]const u8 = "%d %d %d %d %d %d %d %d %d %d %d %d\n";
    _ = printf(fmt_all, VADD, VSUB, VMUL, VDIV, VMOD,
               VNEG, VAND, VOR, VXOR, VSHL, VSHR, VNOT);
}
```

Expected output: `40 20 300 3 0 -30 10 30 20 120 7 -31`

NOTES.md documents: pre-fix gap (runtime arithmetic emitted, not int_const), post-fix expectation (int_const in __module_init), verification via `grep -c '[\*\/\%]'` in emitted C > 0, and the P0-C source correction (inlined literals + fixed-arity printf).

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

NOTES.md documents: pre-fix **silent miscompile** — array types resolve `TYPE_UNDEFINED` (type_resolver.zig:869-911 misses mul/div/mod → arr_len=0), consts degrade to uninitialized `int` globals, gcc-clean. Operator ruling P0-E: counted **OK with runtime-gap annotation** (gcc-exit classifier says OK; real semantic gap). Post-fix F3 expected: correct array types `u8[4000]`/`u8[40]`/`u8[2]` (runtime gap resolved).

- [ ] **Step 3b: Create tracking repro (`fn_varargs_unsupported`)**

```bash
mkdir -p repro/mi_matrix/fn_varargs_unsupported
```

`repro/mi_matrix/fn_varargs_unsupported/main.zig` (tracking repro for the varargs parse gap discovered in P0):
```zig
extern fn printf(fmt: [*]const u8, ...) i32;

pub fn main() void {}
```

NOTES.md documents: `error[2000]: expected identifier but found token` at `...` — parser.zig has no varargs support. Counted **FAIL** (frontend parse gap, 0 `.c`). Out of comptime-arithmetic scope; tracked as known gap.

- [ ] **Step 4: Update EXPECTED_FAIL.md**

Add 4 new rows to the classification table with measured pre-fix state:
- `comptime_binop_not_folded` — **OK with emission-gap annotation** (gcc-clean, runtime output correct, but emitted C shows runtime arithmetic instead of int_const — gap proven by C89 inspection). Counted OK in totals, per the `load_global_array_copy`/`comptime_neg_int` precedent of counting runtime/emission-gap repros as OK.
- `comptime_lower_ignores_fold` — **OK with emission-gap annotation** (same).
- `comptime_array_size_gap` — **OK with runtime-gap annotation** (gcc-clean silent miscompile — array types resolve TYPE_UNDEFINED, consts degrade to uninitialized int globals). Counted OK per operator ruling P0-E.
- `fn_varargs_unsupported` — **FAIL** (error[2000], 0 `.c`, varargs unsupported). Counted FAIL, out of scope.

Update totals: 200→204 (OK 193→196, FAIL 3→4, green-guards 4; raw FAIL 7→8). Document the new bucket. Post-fix F3 resolves repro 3's runtime-gap (already OK) → 196/4/4 @204 (raw FAIL=8).

- [ ] **Step 5: Verify + commit**

```bash
# Build /tmp compiler, classify all 4 repros
# Confirm Repro 3 gcc-clean (silent miscompile: int-drop, OK+runtime-gap per P0-E)
# Confirm Repros 1+2 gcc-clean (runtime output correct, emission gap in __module_init)
# Confirm varargs repro FAILs (error[2000])

git add repro/mi_matrix/comptime_binop_not_folded/ repro/mi_matrix/comptime_lower_ignores_fold/ repro/mi_matrix/comptime_array_size_gap/ repro/mi_matrix/fn_varargs_unsupported/ repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "repro(P0): 3 comptime-arithmetic defensive repros + varargs tracking repro"
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

### Task F1: Fix comptime_eval.zig — Add 5 Missing Binary Bitwise/Shift Ops

**Pre-requisites:** I1 complete, operator ruling.

**Files:** `sf/src/comptime_eval.zig`

**Scope:** Add `bit_and`, `bit_or`, `bit_xor`, `shl`, `shr` to `comptimeEvalBinOp`. Code validated by I1 prototype (report §6).

- [ ] **Step 1: Add bit_and/bit_or/bit_xor/shl/shr to comptimeEvalBinOp**

Insert after the `mod_op` block, before the closing `}` at `comptime_eval.zig:83` (exact validated code from I1 §6):

```zig
            if (op_kind == AstKind.bit_and) return ComptimeVal{ .bits = lv & rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.bit_or) return ComptimeVal{ .bits = lv | rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.bit_xor) return ComptimeVal{ .bits = lv ^ rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.shl) {
                if (rv >= @intCast(u64, 64)) return null;
                return ComptimeVal{ .bits = lv << rv, .width_bits = maxw, .sig = use_signed };
            }
            if (op_kind == AstKind.shr) {
                if (rv >= @intCast(u64, 64)) return null;
                return ComptimeVal{ .bits = lv >> rv, .width_bits = maxw, .sig = use_signed };
            }
```

The `rv >= 64` guards prevent shift overflow (falls back to runtime, unchanged behavior).

- [ ] **Step 2: Verify + commit**

Build /tmp compiler. Verify `@intCast(i32, 30 & 10)` now folds via builtin_call path (proves new ops work in comptime_eval). 4 MD5s byte-identical.

```bash
git add sf/src/comptime_eval.zig
git commit -m "feat(F1): add bit_and/bit_or/bit_xor/shl/shr to comptime evaluation"
```

---

### Task F2: Fix comptime_eval.zig — Add bit_not + Extend Dispatch List

**Pre-requisites:** F1 complete.

**Files:** `sf/src/comptime_eval.zig`

**Scope:** Add `bit_not` branch to `comptimeEvalEvaluate` AND extend the binop dispatch list to route bitwise/shift to `comptimeEvalBinOp`. **The dispatch-list extension is mandatory** — without it the F1 ops are dead code (I1's first prototype bug). Code validated by I1 §6.

- [ ] **Step 1: Add bit_not branch to comptimeEvalEvaluate**

Mirror the `negate` branch (comptime_eval.zig:151-170), insert before line 171, using `~cv.bits` instead of `0 - cv.bits`:

```zig
            } else if (node.kind == AstKind.bit_not) {
                var bnv = comptimeEvalEvaluate(self, node.child_0);
                if (bnv) |bv| {
                    var bnb = ~bv.bits;
                    return ComptimeVal{ .bits = bnb, .width_bits = bv.width_bits, .sig = false };
                }
                return null;
```

- [ ] **Step 2: Extend the binop dispatch list**

In `comptimeEvalEvaluate`, the binop dispatch (comptime_eval.zig:171-173) currently routes only add/sub/mul/div/mod_op to `comptimeEvalBinOp`. Extend it to also route `bit_and`, `bit_or`, `bit_xor`, `shl`, `shr`:

```zig
            } else if (node.kind == AstKind.add or node.kind == AstKind.sub or node.kind == AstKind.mul or
                       node.kind == AstKind.div or node.kind == AstKind.mod_op or
                       node.kind == AstKind.bit_and or node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
                       node.kind == AstKind.shl or node.kind == AstKind.shr) {
                var bv2 = comptimeEvalBinOp(self, node_idx, node.kind);
                if (bv2) |b2| { return b2; }
                return null;
```

(Adjust to the exact existing dispatch structure — read comptime_eval.zig:141-182 first.)

- [ ] **Step 3: Verify + commit**

Build /tmp compiler. Verify all 12 ops fold via `@intCast` chains. 4 MD5s byte-identical.

```bash
git add sf/src/comptime_eval.zig
git commit -m "feat(F2): add bit_not and route bitwise/shift ops to comptime binop evaluation"
```

---

### Task F3: Fix main.zig — Const-Only var_decl Init Folding

**Pre-requisites:** F1, F2 complete.

**Files:** `sf/src/main.zig`

**Scope:** Expand `phase_ComptimeEvaluation` to evaluate const `var_decl` inits whose child_1 is a foldable binary/unary node, storing under `child_1`'s node index. **Const-only (`flags & 0x01 == 0`) is REQUIRED** — folding mutable-var literal inits breaks the gol MD5 baseline (`var dy = -1`). Code validated by I1 §3.

- [ ] **Step 1: Insert the var_decl branch in phase_ComptimeEvaluation**

At `main.zig:345-351`, after the existing `builtin_call` branch, add (exact validated code from I1 §3):

```zig
        } else if (node.kind == AstKind.var_decl and node.child_1 != 0) {
            if ((node.flags & @intCast(u8, 1)) == @intCast(u8, 0)) {
                var init_n = ctx.store.nodes.items[@intCast(usize, node.child_1)];
                var ik = @intCast(u32, @enumToInt(init_n.kind));
                if ((ik >= @intCast(u32, 33) and ik <= @intCast(u32, 42)) or
                    ik == @intCast(u32, 62) or ik == @intCast(u32, 64)) {
                    var val2 = ce_mod.comptimeEvalEvaluate(&ce, node.child_1);
                    if (val2) |v2| {
                        hash_mod.u32ToU64MapPut(&ctx.comptime_values, node.child_1, v2.bits);
                    }
                }
            }
        }
```

Kinds 33-42 = add..shr (10 binops), 62 = negate, 64 = bit_not (AstKind values, ast.zig:1-99). Verify the exact enum ordinal values against `sf/src/ast.zig` before coding.

- [ ] **Step 2: Verify + commit**

Build /tmp compiler. 4 MD5s byte-identical (const-only restriction must preserve gol). Corpus unchanged.

```bash
git add sf/src/main.zig
git commit -m "feat(F3): fold const var_decl binop/unary inits in comptime evaluation phase"
```

---

### Task F4: Fix lower.zig — comptime_values Guards on 10 Binary Handlers

**Pre-requisites:** F3 complete.

**Files:** `sf/src/lower.zig`

**Scope:** Add `comptime_values` guards to the 10 binary op handlers (add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr) with the INT_LIT→I32 remap. Code validated by I1 §4.

- [ ] **Step 1: Add guards to the 10 binary handlers**

At `lower.zig:1218` (add), `:1236` (sub), `:1247` (mul), `:1258` (div), `:1266` (mod_op), `:1274` (bit_and), `:1282` (bit_or), `:1290` (bit_xor), `:1298` (shl), `:1306` (shr). Each currently starts `var lhs = lowerExpr(self, node.child_0);`. Restructure: compute `rtype` FIRST (via `resolvedTypeTableGet`), insert the guard, then lower operands. Validated pattern (`XXX`/`BIN_XXX` per op):

```zig
    } else if (node.kind == AstKind.XXX) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_XXX, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
```

The `add` handler has a `slice_type` debug block + `M4a:r` markers after `lowerExpr(lhs)` — keep them (they sit after the guard). The INT_LIT→I32 remap is REQUIRED (negative folds would otherwise emit unsigned and break gcc).

- [ ] **Step 2: Verify + commit**

Build /tmp compiler. Verify Repro 1 (`comptime_binop_not_folded`): emitted `__module_init` has `int_const` for all 12 ops (grep `[\*\/\%]` == 0 in `__module_init`), runtime prints `40 20 300 3 0 -30 10 30 20 120 7 -31`. 4 MD5s byte-identical.

```bash
git add sf/src/lower.zig
git commit -m "feat(F4): comptime_values guards on 10 binary op handlers with INT_LIT->I32 remap"
```

---

### Task F5: Fix lower.zig — comptime_values Guards on 2 Unary Handlers

**Pre-requisites:** F4 complete.

**Files:** `sf/src/lower.zig`

**Scope:** Add `comptime_values` guards to negate (`:1420`) and bit_not (`:1433`), placed BEFORE `lowerExpr(child_0)` (I1 found placing bit_not's guard after left a dead operand temp). Code validated by I1 §4.

- [ ] **Step 1: Add guards to negate and bit_not**

For both handlers, the type box (`ng_box`/`bn_box`) is already computed before `lowerExpr`. Insert the guard after the box, before `var val = lowerExpr(self, node.child_0);`:

```zig
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = ng_box[0];            /* or bn_box[0] */
            if (ft == type_mod.TYPE_INT_LIT or ft == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
```

`bool_not` (:1428) is OUT OF SCOPE (comptimeEvalEvaluate returns null for it — no fold possible).

- [ ] **Step 2: Verify + commit**

Build /tmp compiler. Repro 1+2 runtime correct, no dead operand temps in `__module_init`. 4 MD5s byte-identical.

```bash
git add sf/src/lower.zig
git commit -m "feat(F5): comptime_values guards on negate and bit_not unary handlers"
```

---

### Task F6: Fix type_resolver.zig — Array Size mul/div/mod

**Pre-requisites:** none (independent of F1-F5).

**Files:** `sf/src/type_resolver.zig`

**Scope:** Add mul/div/mod_op to array size evaluation in `resolveArrayType` (Gap 3). Code validated by I1 §5.

- [ ] **Step 1: Add mul/div/mod_op to resolveArrayType size eval**

At `type_resolver.zig:887-888`, insert between the add/sub branch (ends line 887) and the ident_expr branch (line 888), exact validated code from I1 §5:

```zig
                } else if (sz_node.kind == AstKind.mul or sz_node.kind == AstKind.div or sz_node.kind == AstKind.mod_op) {
                    var lhs = evalConstU32Full(env, sz_node.child_0);
                    var rhs = evalConstU32Full(env, sz_node.child_1);
                    if (lhs != @intCast(u32, 0xFFFFFFFF) and rhs != @intCast(u32, 0xFFFFFFFF) and rhs != @intCast(u32, 0)) {
                        if (sz_node.kind == AstKind.mul) arr_len = lhs * rhs;
                        else if (sz_node.kind == AstKind.div) arr_len = lhs / rhs;
                        else arr_len = lhs % rhs;
                    }
                }
```

The `rhs != 0` guard prevents div/mod-by-zero (keeps arr_len=0 → TYPE_UNDEFINED, matching existing zero-size behavior). Optional bitwise/shift size ops: DEFER per I1 (unlikely in real code).

- [ ] **Step 2: Verify Repro 3 post-fix**

Build /tmp compiler. Verify `comptime_array_size_gap`: dump rc=0, gcc-clean, arrays resolve `u8[4000]`/`u8[40]`/`u8[2]`. 4 MD5s byte-identical.

- [ ] **Step 3: Commit**

```bash
git add sf/src/type_resolver.zig
git commit -m "feat(F6): add mul/div/mod to array size comptime evaluation"
```

---

### Task F7: Fix u64 Const Fold >2^32 Bug (repro + proper fix)

**Pre-requisites:** F4, F5 complete. Operator ruling I1-A: this is a serious bug — create a repro and fix it properly.

**Files:** `sf/src/lower.zig` (and/or `sf/src/main.zig`), new repro dir

**Scope:** A u64-annotated const whose folded value exceeds 2^32 (e.g. `const X: u64 = 3000000000 * 2;`) resolves the binop node to TYPE_INT_LIT, so the F4/F5 guard types the temp I32 and the int_const emitter masks to 32 bits → wrong value. Must repro and fix properly.

- [ ] **Step 1: Create repro `comptime_u64_fold_overflow`**

```bash
mkdir -p repro/mi_matrix/comptime_u64_fold_overflow
```

`repro/mi_matrix/comptime_u64_fold_overflow/main.zig` (follow the P0 repro conventions: `@cInclude("<stdio.h>");` + fixed-arity extern fn printf, inlined literals):
```zig
@cInclude("<stdio.h>");
extern fn printf(fmt: [*]const u8, a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32, j: i32, k: i32, l: i32) i32;

const X: u64 = 3000000000 * 2;
const Y: u32 = 3000000000;   // fits u32 (below 2^32), folds fine
const Z: u64 = 4294967295 + 1;  // = 2^32, exceeds 32 bits

pub fn main() void {
    var fmt: [*]const u8 = "%lu %lu %lu\n";
    _ = printf(fmt, X, Y, Z);
}
```

NOTE: verify `%lu` and u64 printf arg passing work in this environment (the C emitter + gcc). If u64 printf is problematic, use `__bootstrap_print_int`-style PAL output or print via two i32 halves. The KEY is the repro must demonstrate the masked-32-bit wrong value pre-fix.

**Pre-fix expectation:** X (6000000000) and Z (4294967296) print WRONG (masked to 32 bits: 1705032704 and 0). Y (3000000000) prints correct. Classification: **FAIL or OK-with-runtime-gap** — determine empirically. If gcc-clean with wrong output, it's OK-with-runtime-gap; if gcc rejects, it's FAIL.

- [ ] **Step 2: Investigate the proper fix**

The core problem: the folded temp's type must match the DECLARED type of the const (u64), not the binop's resolved INT_LIT. Investigate how to thread the declared type:
- **Option A:** In the F4/F5 guard, when `rtype == TYPE_INT_LIT`, look up the enclosing var_decl's declared type. But the guard only has `node_idx` (the binop), not the var_decl — may require threading.
- **Option B:** In F3 (main.zig phase), when storing the folded value, ALSO store the declared type (from the var_decl's resolved type table entry) in a parallel map keyed by child_1. The guard reads both.
- **Option C:** Broaden the INT_LIT remap: if the value exceeds 32 bits, use u64 instead of I32.

Investigate which is cleanest given the pipeline (resolved_types table, var_decl type resolution, what's available at each point). Determine blast radius. Document exact file:line + code.

- [ ] **Step 3: Implement the approved fix**

Per your investigation. Must handle: value fits in 32 bits (I32/u32 fine), value exceeds 32 bits (needs u64 type so the emitter doesn't mask). Verify `const X: u64 = 3000000000 * 2` prints 6000000000 and `const Z: u64 = 4294967295 + 1` prints 4294967296.

- [ ] **Step 4: Verify + commit**

Build /tmp compiler. Repro prints correct values. 4 MD5s byte-identical. Corpus: repro classifies OK (or documented). Update EXPECTED_FAIL.md.

```bash
git add sf/src/lower.zig repro/mi_matrix/comptime_u64_fold_overflow/ repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix(F7): fold u64 consts >32 bits at their declared type (comptime_u64_fold_overflow)"
```

---

### Task F8: Add ident_expr Const-Chain Folding

**Pre-requisites:** F1-F5 complete. Operator ruling I1-B: include now.

**Files:** `sf/src/comptime_eval.zig`

**Scope:** Make `comptimeEvalEvaluate` handle `ident_expr` operands by following const chains, so `const B = A + 5;` (where `const A: i32 = 30;`) folds. The `ComptimeEval` struct already holds `symbol_reg` (per I1 §10) — investigate how the array-size path (`evalConstU32Full`, type_resolver.zig:579-598) follows const chains and mirror it.

- [ ] **Step 1: Investigate the const-chain mechanism**

Read `evalConstU32Full` (type_resolver.zig:579-598): how it uses `symbolLookupAllModules` + `(cs.flags & 0x01)==0` const check + recursion into `decl.child_1`. Determine how `ComptimeEval` can access the same symbol table (`self.symbol_reg`?). Determine the ident_expr → symbol → const init → evaluate path.

- [ ] **Step 2: Add ident_expr branch to comptimeEvalEvaluate**

In `comptimeEvalEvaluate` (comptime_eval.zig:141-182), add an `ident_expr` branch that resolves the name to a const symbol and recursively evaluates its init (with depth guard to prevent infinite recursion on cycles). Mirror the array-size const-chain pattern. Exact code per your investigation.

- [ ] **Step 3: Verify + commit**

Build /tmp compiler. Create a probe `const A: i32 = 30; const B: i32 = A + 5;` → verify B folds to 35 (emitted int_const). 4 MD5s byte-identical (existing repros use literal operands, so no corpus change — but verify no regression). Consider adding a defensive repro if a natural one exists (may be optional — the operator's concern was correctness, not necessarily a new corpus entry).

```bash
git add sf/src/comptime_eval.zig
git commit -m "feat(F8): fold ident_expr const-chain operands in comptime evaluation"
```

---

### Task F9: Gate Sweep + Docs

**Pre-requisites:** F6, F7, F8 complete.

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `sf/docs/tech_docs/*.md`

**Scope:** Full gate battery: clear the emission/runtime-gap annotations on the comptime repros (already OK), verify varargs repro stays FAIL, 4 MD5s re-verify, QUICK_REF update, tech docs update (AGENTS.md §1.1.1).

- [ ] **Step 1: Update EXPECTED_FAIL.md repro rows**

Update the comptime repro rows: emission-gap/runtime-gap annotations cleared (gaps resolved by F1-F8). `fn_varargs_unsupported` stays FAIL (out of scope). Update totals to the final measured state (base 204; +comptime_u64_fold_overflow if it's a new repro; expected ~196/4/4 or 197/4/4 @205). Document fix commits.

- [ ] **Step 2: Update QUICK_REF.md**

Update corpus gate section to reflect the final repro count. Document comptime-arithmetic note.

- [ ] **Step 3: Full gate sweep**

```bash
# Build /tmp compiler
# Verify repros 1+2: emitted C now has int_const (no runtime arithmetic) — grep '[\*\/\%]' == 0 in __module_init
# Verify repro 3: arrays resolve u8[4000]/u8[40]/u8[2]
# Verify u64 repro (F7): prints 6000000000 / 3000000000 / 4294967296
# Verify varargs repro: stays FAIL error[2000]
# Verify 4 MD5s byte-identical
# Full corpus classifier run — FAIL count must not increase vs baseline
# test_analyzer_bin PASS
```

- [ ] **Step 4: Tech docs update (AGENTS §1.1.1)**

Update `04_comptime_eval.md` with new bitwise/shift ops + ident_expr const-chain. Update `09_pipeline_orchestration.md` with expanded phase visitor. Update `07_lir_lowering.md` with comptime_values guard + I32 remap. Update `03_type_resolution.md` with array size mul/div/mod. Add `[updated: 2026-08-06]` annotations.

- [ ] **Step 5: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md sf/docs/tech_docs/04_comptime_eval.md sf/docs/tech_docs/07_lir_lowering.md sf/docs/tech_docs/09_pipeline_orchestration.md sf/docs/tech_docs/03_type_resolution.md
git commit -m "docs(F9): gate sweep + tech docs for comptime arithmetic folding"
```

---

## Amendments Record

- **AMENDMENT P0-A (2026-08-06, operator ruling):** Repro 1+2 classify **OK with emission-gap annotation** (gcc-clean; gap is runtime arithmetic in emitted C, proven by C89 inspection). Not FAIL, per the gcc-exit classifier and the `load_global_array_copy`/`comptime_neg_int` precedent.
- **AMENDMENT P0-B (2026-08-06, operator ruling):** Repro 1+2's plan-verbatim source does NOT compile on current zig1 (varargs `...` unsupported by parser, `@cInclude` requires `;`, const-only-refs lack storage-global decls). Operator ruled: **accept the corrected source** (inlined literals `30 + 10`, fixed-arity `printf(fmt, a..l)`, `@cInclude("<stdio.h>");`) — preserves the tested gap and turns GREEN post-F1/F2.
- **AMENDMENT P0-D (2026-08-06, operator ruling):** Create a 4th tracking repro `fn_varargs_unsupported` for the varargs parse gap discovered during P0 (parser.zig has no `...` support → error[2000]). Counted FAIL, out of comptime scope.
- **AMENDMENT P0-E (2026-08-06, operator ruling):** Repro 3 (`comptime_array_size_gap`) measured result is NOT `ISO C forbids zero-size array` — it's a **silent miscompile** (array types resolve TYPE_UNDEFINED → consts degrade to uninitialized `int` globals, gcc-clean). Operator ruled: classify **OK with runtime-gap annotation** (gcc-exit classifier says OK). F3 resolves the runtime-gap (already OK, no count change).
- **Totals after P0:** 204 repros = OK 196 / FAIL 4 / green-guards 4 (raw FAIL 8). FAILs = field_store_drop, test_stub_0, self_embed_optional_cycle, fn_varargs_unsupported. Post-F3/F4: 196/4/4 @204 unchanged (only annotations cleared).
- **AMENDMENT I1-A (2026-08-06, operator ruling):** u64-annotated consts whose folded value exceeds 2^32 get typed I32 and masked to 32 bits (wrong). Operator: "create a repro, then amend the plan to address the bug properly. That's a serious bug." → Task F7 (repro `comptime_u64_fold_overflow` + proper fix).
- **AMENDMENT I1-B (2026-08-06, operator ruling):** `ident_expr` operands (`const B = A + 5`) don't fold — include now → Task F8 (const-chain folding in comptimeEvalEvaluate).
- **AMENDMENT I1-C (2026-08-06, operator ruling):** split implementation into 6 tasks per the I1 report's F1-F6 edit plan (was F1/F2/F3 by file). Plus F7/F8 from I1-A/I1-B, and F9 = gate sweep + docs (was F4).
