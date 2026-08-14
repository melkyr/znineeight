# 04 — Compile-Time Evaluation [updated: 2026-08-14 — `@isWindows` 4th foldable builtin + `host_is_windows` config-const flip point documented (comptime_eval.zig:19/156-162); prior 2026-08-06 — F1/F2 bitwise+shift ops, F8 ident_expr const-chain + depth guard; lowerer intern-count cross-ref 9→12 (varargs builtins)]

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ComptimeVal` fields | 3 | bits (u64), width_bits (u8), sig (bool) |
| `ComptimeEval` fields | 8 | registry, store, interner, symbol_reg, size_of_id, align_of_id, int_cast_id, **is_windows_id** (2026-08-14) |
| Builtin intrinsics (comptime-foldable) | 4 | @sizeOf, @alignOf, @intCast, **@isWindows** (2026-08-14) — the ONLY names interned by `comptimeEvalInit` |
| Builtin names interned by sema | 9 | @ptrCast, @ptrToInt, @intToPtr, @intCast, @floatCast, @intToFloat, @intToEnum, @sizeOf, @alignOf (+ `_` stub) — type assignment only |
| Builtin names interned by lowerer | 12 | @intCast, @intToFloat, `print`, @ptrCast, @ptrToInt, @intToPtr, @enumToInt, @sizeOf, @alignOf + **@cVaStart, @cVaArg, @cVaEnd** (2026-08-06 varargs) — LIR dispatch only |
| Non-foldable builtins | 6 | @ptrCast, @ptrToInt, @intToPtr, @floatCast, @intToFloat, @intToEnum — comptime eval returns `null`, handled by sema type rules + runtime LIR casts |
| Binary ops evaluated | 10 | add, sub, mul, div, mod, bit_and, bit_or, bit_xor, shl, shr |
| Unary ops evaluated | 3 | negate, bit_not (bool_not/others → null) |
| Extra operands | 1 | ident_expr const-chain (depth-16 guarded, F8) |
| Literal kinds | 3 | int_literal, char_literal, bool_literal |
| Dispatch arms | 9 | int/char/bool/negate/bit_not/binop/builtin/paren/ident_expr |

---

## Function Walkthrough

| Function | Line | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|-----------|---------|-----------|-------|-------------|---------------|---------|
| `comptimeEvalInit` | 28 | pub | Initialize `ComptimeEval` by interning `@sizeOf`, `@alignOf`, `@intCast`, `@isWindows` string names (4 names; `@isWindows` added 2026-08-14). Returns populated struct. | `main.zig` phase_ComptimeEvaluation (main.zig:328); unit tests (test_semantic_bin.zig) | `interner_mod.stringInternerIntern` | `interner` hash map, `ComptimeEval` fields | Three builtin IDs frozen at init; no dynamic registration. | `CE` (phase entry, main.zig:327) [inference] |
| `comptimeEvalResolveTypeArg` | 88 | private | Resolve a type argument AST node to a `TypeId` using `resolveTypeExprFull`. Returns `null` on `node_idx==0` or `TYPE_UNDEFINED`. | `comptimeEvalBuiltin` | `type_resolver.resolveTypeExprFull` | `store`, `registry`, `symbol_reg`, `interner` | Creates ephemeral `TypeResolveEnv` each call. No caching. | None [inference] |
| `comptimeEvalBuiltin` | 96 | private | Dispatch comptime-evaluable builtin calls. Handles `@sizeOf`, `@alignOf`, `@intCast`, `@isWindows`. Each resolves its type argument, then checks `ty.state==2` (resolved). | `comptimeEvalEvaluate` | `comptimeEvalResolveTypeArg`, `comptimeEvalEvaluate`, `ast_mod.astStoreGetExtraChildren` | `self.store`, `self.registry`, `self.interner` | Guards on `ty.state==2` (fully resolved). Returns null if type unresolved. | None [inference] |
| `comptimeEvalBuiltin` — `@sizeOf` | 97 | — | Extract first extra child as type arg, resolve, return `ty.size` as `ComptimeVal`. | (same as above) | same | `registry.types_items[t].size` | Always width_bits=0, sig=false (compile-time size is unsigned). | None [inference] |
| `comptimeEvalBuiltin` — `@alignOf` | 106 | — | Same pattern as `@sizeOf` but returns `ty.alignment`. | (same as above) | same | `registry.types_items[t].alignment` | Width=0, sig=false. | None [inference] |
| `comptimeEvalBuiltin` — `@intCast` | 115 | — | Resolve target type, evaluate inner expression, then truncate/sign-extend bits to target width. Computes mask, sign-extends if target is signed type. | (same as above) | `comptimeEvalEvaluate`, `comptimeEvalResolveTypeArg`, `ast_mod.astStoreGetExtraChildren` | `registry.types_items[t].size/kind` | Checks `ty.kind` for signed int kinds (i8/i16/i32/i64/isize). 64-bit full width passes through directly. | None [inference] |
| `comptimeEvalBinOp` | 41 | private | Evaluate binary arithmetic at compile time. Handles add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr (the last 5 added by F1, 2026-08-06). Signed division uses sign-magnitude algorithm. | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs/rhs) | `store.nodes`, lhs/rhs `ComptimeVal` | Width = max(lhs.width_bits, rhs.width_bits). Signed if either operand signed. Division-by-zero returns null. Shift amount >= 64 returns null. | None [inference] |
| `comptimeEvalBinOp` — signed div | 56 | — | Extract sign bits, compute absolute values, divide, apply sign to quotient. | (same as above) | none | local variables | Two's complement negation: `0 - val`. XOR sign bits for result sign. | None [inference] |
| `comptimeEvalBinOp` — signed mod | 69 | — | Same sign-magnitude approach as div, but returns remainder with dividend sign. | (same as above) | none | local variables | Divisor sign ignored; only dividend sign applied to remainder. | None [inference] |
| `comptimeEvalEvaluate` | 141 | pub | Main comptime evaluation dispatch. Walks AST node kind and returns `ComptimeVal` or null. Thin wrapper delegating to `comptimeEvalEvaluateDepth(node_idx, 0)`. | `main.zig` phase_ComptimeEvaluation; recursively by itself; unit tests (test_semantic_bin.zig) | `comptimeEvalEvaluateDepth` | `store.nodes`, `store.int_values` | Entry point; all recursion flows through the depth-guarded variant. | None [inference] |
| `comptimeEvalEvaluateDepth` | 158 | private | Depth-guarded evaluation core. Same dispatch as `comptimeEvalEvaluate` plus an `ident_expr` const-chain arm (F8). | `comptimeEvalEvaluate`, recursively by itself/binop/builtin | `comptimeEvalBinOp`, `comptimeEvalBuiltin`, `comptimeEvalEvaluateDepth` (recursive), `symbolRegistryQualifiedLookup` | `store.nodes`, `store.int_values`, `store.identifiers`, `symbol_reg` | `node_idx==0` returns null. `depth >= 16` returns null (const-cycle guard). Recursive for paren_expr, negate, bit_not, binop, builtin, and ident_expr chains. | None [inference] |
| `comptimeEvalEvaluate` — int_literal | 144 | — | Returns bits from `store.int_values[node.payload]`, width=0, sig=true. | (same as above) | none | `store.int_values` | width=0 means arbitrary precision — caller applies truncation. | None [inference] |
| `comptimeEvalEvaluate` — char_literal | 146 | — | Same bits as int_literal but width=8, sig=false. | (same as above) | none | `store.int_values` | Character treated as u8 value. | None [inference] |
| `comptimeEvalEvaluate` — bool_literal | 148 | — | Returns 1 or 0, width=1, sig=false. Based on `node.flags & 1`. | (same as above) | none | `node.flags` | Flags bit 0 = value. | None [inference] |
| `comptimeEvalEvaluate` — negate/bit_not | 167/181 | — | Recursively evaluate inner, compute `0 - bits` (negate) or `~bits` (bit_not), then mask/sign-extend to inner width. | (same as above) | `comptimeEvalEvaluateDepth` | inner `ComptimeVal` | width=0 case returns sig=true (signed literal). Finite width applies mask + optional sign extension. | None [inference] |
| `comptimeEvalEvaluate` — binop | 189 | — | Dispatches to `comptimeEvalBinOp` for add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr kinds (the bitwise/shift kinds added F1). | (same as above) | `comptimeEvalBinOp` | `node.kind` | Forward `node_idx`, `node.kind`, and current depth to binop handler. | None [inference] |
| `comptimeEvalEvaluate` — builtin_call | 195 | — | Dispatches to `comptimeEvalBuiltin` for builtin_call kind. | (same as above) | `comptimeEvalBuiltin` | `node.kind` | Only @sizeOf/@alignOf/@intCast are foldable. | None [inference] |
| `comptimeEvalEvaluate` — paren_expr | 197 | — | Unwraps parentheses: recurses on `node.child_0`. | (same as above) | `comptimeEvalEvaluateDepth` | `node.child_0` | Trivial pass-through. | None [inference] |
| `comptimeEvalEvaluate` — ident_expr (F8) | 199 | — | Const-chain resolution: look up `name_id` via `symbolRegistryQualifiedLookup` across all module tables; if the symbol is a `const` (`flags & 0x01 == 0`) with a non-empty init (`decl.child_1 != 0`), recurse into that init at `depth+1`. Returns null on `depth >= 16` (const-cycle guard) or no matching const. Mirrors the array-size `evalConstU32Full` chain (type_resolver.zig:579-598). | (same as above) | `comptimeEvalEvaluateDepth` (recursive), `symbolRegistryQualifiedLookup` | `store.identifiers`, `symbol_reg`, `store.nodes` | Enables `const B: i32 = A + 5` to fold from `const A: i32 = 30` (comptime_const_chain repro, F8). | None [inference] |

---

## Data Flow

```
comptimeEvalEvaluate(node_idx)
  └─ comptimeEvalEvaluateDepth(node_idx, depth=0)     ← every recursion carries depth (F8)
       ├─ int_literal ──→ store.int_values[node.payload] ──→ ComptimeVal{bits, width=0, sig=true}
       ├─ char_literal ──→ store.int_values[node.payload] ──→ ComptimeVal{bits, width=8, sig=false}
       ├─ bool_literal ──→ node.flags & 1 ──→ ComptimeVal{0|1, width=1, sig=false}
       ├─ negate ──→ EvaluateDepth(child_0) ──→ 0 - bits ──→ mask/sign-extend
       ├─ bit_not ──→ EvaluateDepth(child_0) ──→ ~bits
       ├─ add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr ──→ comptimeEvalBinOp(node_idx, kind, depth)
       │     └─ EvaluateDepth(child_0) + EvaluateDepth(child_1)
       │           └─ width = max(l.width, r.width), sig = l.sig | r.sig
       │           └─ div/mod: signed → sign-magnitude, zero → null
       │           └─ shl/shr: shift amount >= 64 → null
       ├─ builtin_call ──→ comptimeEvalBuiltin(node, depth)
       │     ├─ @sizeOf: resolveTypeArg → ty.size
       │     ├─ @alignOf: resolveTypeArg → ty.alignment
       │     └─ @intCast: resolveTypeArg + EvaluateDepth(inner) → mask/truncate/sign-ext
       ├─ paren_expr ──→ EvaluateDepth(node.child_0)
       └─ ident_expr (F8) ──→ symbolRegistryQualifiedLookup(name_id) across module tables
             └─ if const (flags & 0x01 == 0) and init present → EvaluateDepth(decl.child_1, depth+1)
             └─ depth >= 16 → null (const-cycle guard)
```

**Init flow:**
```
comptimeEvalInit(registry, store, interner, symbol_reg)
  └─ interner.stringInternerIntern("@sizeOf")   → size_of_id
  └─ interner.stringInternerIntern("@alignOf")  → align_of_id
  └─ interner.stringInternerIntern("@intCast")   → int_cast_id
```

---

## Debugging

- **Null return** — any evaluation that returns `null` means the node is NOT stored in
  `ctx.comptime_values` (main.zig:334-337), so LIR lowering falls back to a runtime cast
  (lower.zig:2419+, marker `B`/`I`/`P`/`F`) instead of an `int_const`. Null causes include: type
  argument unresolved (`ty.state != 2`), division by zero, unhandled node kind, `node_idx == 0`,
  and any builtin not in the 3-name set. The semantic analyzer still assigns a result *type* to
  the node regardless (semantic_analyzer.zig:1216-1240).
- **Wrong width** — `@intCast` width computed as `ty.size * 8`. If the type is unresolved or has wrong size, the mask/sign-extend will be wrong.
- **Signedness mismatch** — `@intCast` determines signedness from `ty.kind`. If `ty.kind` doesn't match one of the signed int kinds, the result is unsigned even if the type is signed.
- **Division by zero** — both `div` and `mod_op` return `null` when divisor is zero. This is distinct from a runtime SIGFPE.
- **Enum literal evaluation** — not handled in this module; enum literals are resolved by the semantic analyzer, not comptime evaluated here.

---

## Builtin Internment: 3 in comptime_eval, not 8

`comptimeEvalInit` (comptime_eval.zig:28-39) interns **exactly three** names — `@sizeOf`,
`@alignOf`, `@intCast` — into `size_of_id`/`align_of_id`/`int_cast_id`. There is **no 8-name
intern set** in this module. The "8 builtins" the task context hypothesised belongs to the
**semantic analyzer**, which interns a 9-name set at `semanticAnalyzerInit`
(semantic_analyzer.zig:64-83): `@ptrCast`, `@ptrToInt`, `@intToPtr`, `@intCast`, `@floatCast`,
`@intToFloat`, `@intToEnum`, `@sizeOf`, `@alignOf` (plus a `_` stub → `_stub_0`). The LIR
lowerer independently interns an overlapping 9-name set at `lowererInit` (lower.zig:257-274):
`@intCast`, `@intToFloat`, `print`, `@ptrCast`, `@ptrToInt`, `@intToPtr`, `@enumToInt`,
`@sizeOf`, `@alignOf`.

| Interned name | comptime_eval.zig | semantic_analyzer.zig | lower.zig |
|---------------|:-----------------:|:---------------------:|:---------:|
| `@sizeOf` | ✓ (fold to `ty.size`) | ✓ (type → TYPE_INT_LIT) | ✓ (fold/int_const) |
| `@alignOf` | ✓ (fold to `ty.alignment`) | ✓ (type → TYPE_INT_LIT) | ✓ (fold/int_const) |
| `@intCast` | ✓ (fold constant inner) | ✓ (type-value cast) | ✓ (runtime int_cast) |
| `@ptrCast` | — | ✓ (type-value cast) | ✓ (runtime ptr_cast) |
| `@ptrToInt` | — | ✓ (→ TYPE_USIZE) | ✓ (runtime ptr_to_int) |
| `@intToPtr` | — | ✓ (type-value cast) | ✓ (runtime int_to_ptr) |
| `@floatCast` | — | ✓ (type-value cast) | — |
| `@intToFloat` | — | ✓ (type-value cast) | ✓ (runtime int_to_float) |
| `@intToEnum` | — | ✓ (type-value cast) | — |
| `@enumToInt` | — | — | ✓ (lower arg directly) |
| `print` | — | — | ✓ (fn-call lower) |

Evidence: source `[inference]` — comptime_eval.zig:29-34, semantic_analyzer.zig:64-83,
lower.zig:257-274.

---

## Boundary: where comptime eval ends and sema/lowering takes over

The pipeline has **one** comptime-value fold pass and **two** type/dispatch passes; the fold
pass is purely a *value* pre-computation, not a type system.

```
phase_ComptimeEvaluation (main.zig:326-339)         marker "CE" (main.zig:327)
  │  for each builtin_call node: comptimeEvalEvaluate(node_idx)
  │    └─ success → ctx.comptime_values[node_idx] = v.bits   (main.zig:335)
  │    └─ null   → not stored (skipped silently)

phase_SemanticAnalysis (main.zig:343+)              marker "RS" (main.zig:344)
  └─ semanticAnalyzerResolveExpr builtin_call arm (semantic_analyzer.zig:1216-1240)
       ├─ @sizeOf/@alignOf          → result type TYPE_INT_LIT (line 1218)
       ├─ type-value casts (@intCast/@ptrCast/@intToPtr/@floatCast/@intToFloat/@intToEnum)
       │     └─ resolve inner expr + resolve target type (line 1225-1228)
       ├─ @ptrToInt                 → TYPE_USIZE (line 1229-1232)
       └─ other                     → resolve arg expr (line 1234)
       (computes TYPES only — does NOT recompute the constant value)

phase_LIRLowering (lower.zig, builtin_call arm at lower.zig:2381-2481)
  ├─ @ptrToInt (line 2383)          → ptr_to_int LIR
  ├─ comptime_values lookup (lower.zig:2393)
  │     ├─ HIT → emit int_const LIR + marker "CEV" (lower.zig:2405) ← the fold is CONSUMED here
  │     └─ MISS, then:
  ├─ @sizeOf/@alignOf (lower.zig:2409) → iceUnresolvedComptime (must have folded; ICE if not)
  ├─ @enumToInt (lower.zig:2413)    → "E", lower inner directly
  └─ ≥2 children (lower.zig:2419)   → marker "B" + "I"(intCast)/"P"(ptrCast)/"F"(other) + runtime cast LIR
```

So the semantic analyzer never evaluates comptime constants — it only assigns result **types**.
The actual constant *value* computed by `comptimeEvalEvaluate` is consumed one phase later, in
LIR lowering, where the `comptime_values` map lookup (lower.zig:2393) turns a folded builtin
into an `int_const` LIR instruction (marker `CEV`). A builtin the comptime evaluator cannot fold
(`null`) is either a type-only builtin (@sizeOf/@alignOf that nevertheless **did** fold) or a
runtime cast (@ptrCast, @intCast with runtime args, @enumToInt, @ptrToInt, ...) lowered to the
corresponding LIR cast instruction.

### `@sizeOf` boundary trace [fprintf]

json_parser: `@sizeOf(JsonValue)` at json.zig:62 (size 16 — matches the P3 layout table
`JsonValue | 25 | 16`, 03_type_resolution.md:702). The instrumented zig1
(`fprintf` added to the generated C89 `comptimeEvalEvaluate`/`lowerExprImpl` paths) prints:

```
[P4CE] node=481 name=@sizeOf
[P4CE] node=481 FOLDED bits=16
...
[P4LW] builtin node=481 name=@sizeOf      ← lowering sees the builtin_call
LEX:n481k31
GBL:i481k31R19[P4LW] builtin node=481 name=@sizeOf
CT:t13r26
CEV                                   ← int_const folded, comptime value consumed
```

`[fprintf]` + `[markers]`; run: `/tmp/z1/zig1 --markers --dump-c89 examples/z98/json_parser/main.zig`.
The `[P4CE]`/`[P4LW]` lines are reconstructed from the instrumented run — the `.mrk` files
contain only the marker-stream side. These node numbers and the fold values are from the
`/tmp/z1` instrumented run, which reproduces the P0 marker sections byte-identically; the fold
values are cross-checked against the P3 layout table.
The @sizeOf builtin folds again at nodes 1104, 1256, 1313 (json.zig:178/220/233; 178 and 233
are `@sizeOf(JsonValue)` = 16, 220 is `@sizeOf(JsonItem)`).

### `@ptrCast` boundary trace [fprintf]

mud_server: `@ptrCast(*u8, &read_fds)` at mud_server/main.zig:127. `@ptrCast` is NOT in the
3-name comptime set, so `comptimeEvalBuiltin` falls through every arm to `return null`
(comptime_eval.zig:138). The instrumented run shows:

```
[P4CE] node=346 name=@ptrCast
[P4CE] node=346 NULL                       ← not foldable, not stored in comptime_values
...
[P4LW] builtin node=346 name=@ptrCast      ← lowering instead emits a runtime ptr_cast
GBL:i346k31R41BPLEX:n345k29                ← "B"+"P" marker block (lower.zig:2419-2422)
```

`[fprintf]` + `[markers]`; all 6 mud_server `@ptrCast` sites (main.zig:127/128/134/140/148/182)
are `NULL` at comptime and lower to runtime `ptr_cast` (`B`/`P` markers, lower.zig:2421-2422).

### `@intCast` — folds only when the inner argument is a constant

`@intCast(u8, 1)` (constant inner) folds; `@intCast(usize, n)` (runtime inner) does not,
because `comptimeEvalEvaluate` recurses into `ec[1]` (comptime_eval.zig:118) and returns `null`
for any non-foldable inner node kind. mud_server, initRooms (main.zig:63-66):

```
[P4CE] node=140 name=@intCast
[P4CE] node=140 FOLDED bits=1            ← @intCast(u8,1), .north
[P4CE] node=144 name=@intCast
[P4CE] node=144 FOLDED bits=0            ← @intCast(u8,0), .south
...
[P4CE] node=490 name=@intCast
[P4CE] node=490 NULL                     ← runtime inner (e.g. @intCast(usize, n))
```

`[fprintf]`.

---

## Evidence: 4 Working Examples (Deep-Dive P4)

Traces: `/tmp/dd/*.mrk` (P0, `zig1 --markers --dump-c89`). The ComptimeEvaluation phase is
bounded by markers `CE` (main.zig:327) and `RS` (main.zig:344). Per-example counts
`[markers]` (grep `-a '^CEV$'` / `-a '^CE$'`):

| Example | `CE` | `CEV` (fold consumed) | `@sizeOf` | `@alignOf` | `@intCast` | `@ptrCast` | other |
|---------|:----:|:----:|:--------:|:---------:|:---------:|:---------:|:------:|
| mud_server | 1 | 18 | 0 | 0 | 23 (18 fold / 5 null) | 6 (all null) | — |
| game_of_life | 1 | 44 | 0 | 0 | 50 (44 fold / 6 null) | 0 | — |
| lisp_interpreter_curr | 1 | 10 | 3 (all fold) | 3 (all fold) | 14 (4 fold / 10 null) | 17 (all null) | @ptrToInt 2 (null), @enumToInt 1 (null) |
| json_parser | 1 | 4 | 4 (all fold) | 0 | 1 (null) | 8 (all null) | @enumToInt 2 (null) |

Notes:
- `@sizeOf`/`@alignOf` **always fold** here because the type argument resolves (state==2) — the
  only failure mode is `ty.state != 2` (comptime_eval.zig:102/111).
- `@intCast` folds only for constant inner exprs; the `@intCast(usize, n)`-style runtime
  conversions in all four examples are `NULL` at comptime and lower to runtime `int_cast` LIR.
- `@ptrCast`, `@ptrToInt`, `@enumToInt` are **never** comptime-evaluable (not in the 3-name set);
  all fold attempts print `NULL`. This confirms the tech doc's earlier claim "handles 3 builtins"
  is **accurate for `comptime_eval.zig`** — the other interned names belong to sema/lowering.

### lisp @sizeOf/@alignOf values [fprintf]

The 3 fold sites resolve to the expected layout sizes (cross-checked against the P3 layout table,
03_type_resolution.md:707/710):

| Node | Builtin | Folds to | Source | Expected size/align (P3) |
|:----:|---------|:--------:|--------|:-------------------------:|
| 2196 / 2201 | `@sizeOf(*Value)` / `@alignOf(*Value)` | 4 / 4 | eval.zig:152 | ptr = 4 |
| 2966 / 2968 | `@sizeOf(EnvNode)` / `@alignOf(EnvNode)` | 20 / 4 | env.zig:34 | 20 / 4 |
| 3566 / 3568 | `@sizeOf(Value)` / `@alignOf(Value)` | 16 / 8 | value.zig:14 | 16 / 8 |

### Q4. Comptime blocks / comptime variables in the examples

**None.** `grep -rn 'comptime'` over `examples/z98/{mud_server,game_of_life,lisp_interpreter_curr,json_parser}/` returns zero
hits (all four are single `main.zig` plus plain `.zig` modules with no `comptime` keyword). So the
comptime evaluator is exercised **only** via `builtin_call` nodes with constant arguments —
there is no `comptime { }` block or `comptime var` in any example. `[inference]` (grep over
example sources).

### Q5. Is "handles 3 builtins" accurate?

**Yes for `comptime_eval.zig`** — it interns exactly 3 names (comptime_eval.zig:29-34) and
`comptimeEvalBuiltin` (comptime_eval.zig:96-139) has fold arms for exactly those 3. The task
context's "8 interned builtins" is a misattribution: the 9-name intern set lives in
`semanticAnalyzerInit` (semantic_analyzer.zig:64-83) and an overlapping 9-name set in
`lowererInit` (lower.zig:257-274). The remaining 5-6 names the task context listed (@ptrCast,
@ptrToInt, @intToPtr, @floatCast, @intToFloat, @intToEnum) are handled by sema's
`semanticAnalyzerIsTypeValueCast` (semantic_analyzer.zig:126-134) and lowered as runtime casts —
never folded. `[inference]` + `[fprintf]` (all fold attempts for these names print `NULL`).

---

## Fold-pass coverage (F3/F8 expansion) — [updated: 2026-08-06]

`phase_ComptimeEvaluation` (main.zig:330-360) no longer folds only `builtin_call` nodes. Since F3
(commit `94853c65`, 2026-08-06) it also folds **`const var_decl` init expressions** that are bare
binary/unary nodes: for each module-scope `const` whose `child_1` init kind is one of the 12
arithmetic ops (AstKind 33-42 or 62/64), it calls `comptimeEvalEvaluate(init_node)` and stores the
result in `ctx.comptime_values[init_node]`. The lowerer's binary/unary `comptime_values` guards
(F4/F5) then consume those folds as `int_const` LIR. Since F8 (commit `bf5d3636`) the evaluator
itself resolves `ident_expr` operands through const chains (depth-16 guarded), so
`const B = A + 5` folds even when `A` is a named const.

**Coverage boundaries (unchanged):**
- Only `builtin_call` nodes still go through the 3-arm `comptimeEvalBuiltin` — there is no name
  pre-filter, so `@ptrCast`/`@enumToInt` etc. are invoked and return `null` after checking the
  three interned IDs (comptime_eval.zig:96-152).
- Fold results are stored keyed by AST node index in `ctx.comptime_values` (main.zig:104) and
  consumed at lower.zig:2393 / the F4/F5 binary+unary guards; a `@sizeOf`/`@alignOf` that failed
  to fold (type unresolved at fold time) would ICE at lower.zig:2409-2412 (`iceUnresolvedComptime`)
  rather than degrade to a runtime call.
- A const chain longer than the depth-16 guard silently falls back to runtime arithmetic
  (guarded, not fixed) — no current repro or gate triggers it.

---

## `host_is_windows` — single config-const flip point [updated: 2026-08-14]

`@isWindows` is the 4th comptime-foldable builtin. Its **value** is decided by a module-level
const, the single flip point for the entire compiler's target-platform sense:

- **`sf/src/comptime_eval.zig:19`** — `const host_is_windows: bool = false;`
- **`sf/src/comptime_eval.zig:156-162`** — `comptimeEvalBuiltin` `@isWindows` arm returns
  `ComptimeVal{ .bits = host_is_windows ? 1 : 0, .width_bits = 1, .sig = false }`.

The other two `@isWindows` sites assign only the result **type** (`TYPE_BOOL`), never the value,
so they need no config:
- `semantic_analyzer.zig:1429-1430` — sema `builtin_call` arm → `TYPE_BOOL`.
- `lower.zig:2834-2836` — lowerer sets the fold temp type to `TYPE_BOOL`; the value comes from the
  `ctx.comptime_values` map populated by this module.

**Operator directive: config const, no CLI.** Recommendation (for F1): keep the flip in
`comptime_eval.zig` but promote it to a documented `pub const` (or, cleaner, move to a dedicated
`sf/src/config.zig` with `pub const host_is_windows: bool = false;` imported here) so it is the
single, discoverable, well-named source of truth. No `@isWindows` folding exists in any other file.
