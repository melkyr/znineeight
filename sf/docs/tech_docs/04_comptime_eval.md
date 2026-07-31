# 04 — Compile-Time Evaluation

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ComptimeVal` fields | 3 | bits (u64), width_bits (u8), sig (bool) |
| `ComptimeEval` fields | 7 | registry, store, interner, symbol_reg, size_of_id, align_of_id, int_cast_id |
| Builtin intrinsics (comptime-foldable) | 3 | @sizeOf, @alignOf, @intCast — the ONLY names interned by `comptimeEvalInit` |
| Builtin names interned by sema | 9 | @ptrCast, @ptrToInt, @intToPtr, @intCast, @floatCast, @intToFloat, @intToEnum, @sizeOf, @alignOf (+ `_` stub) — type assignment only |
| Builtin names interned by lowerer | 9 | @intCast, @intToFloat, `print`, @ptrCast, @ptrToInt, @intToPtr, @enumToInt, @sizeOf, @alignOf — LIR dispatch only |
| Non-foldable builtins | 6 | @ptrCast, @ptrToInt, @intToPtr, @floatCast, @intToFloat, @intToEnum — comptime eval returns `null`, handled by sema type rules + runtime LIR casts |
| Binary ops evaluated | 5 | add, sub, mul, div, mod |
| Literal kinds | 3 | int_literal, char_literal, bool_literal |
| Dispatch arms | 7 | int/char/bool/negate/binop/builtin/paren |

---

## Function Walkthrough

| Function | Line | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|-----------|---------|-----------|-------|-------------|---------------|---------|
| `comptimeEvalInit` | 28 | pub | Initialize `ComptimeEval` by interning `@sizeOf`, `@alignOf`, `@intCast` string names. Returns populated struct. | `main.zig` phase_ComptimeEvaluation (main.zig:328); unit tests (test_semantic_bin.zig) | `interner_mod.stringInternerIntern` | `interner` hash map, `ComptimeEval` fields | Three builtin IDs frozen at init; no dynamic registration. | `CE` (phase entry, main.zig:327) [inference] |
| `comptimeEvalResolveTypeArg` | 88 | private | Resolve a type argument AST node to a `TypeId` using `resolveTypeExprFull`. Returns `null` on `node_idx==0` or `TYPE_UNDEFINED`. | `comptimeEvalBuiltin` | `type_resolver.resolveTypeExprFull` | `store`, `registry`, `symbol_reg`, `interner` | Creates ephemeral `TypeResolveEnv` each call. No caching. | None [inference] |
| `comptimeEvalBuiltin` | 96 | private | Dispatch comptime-evaluable builtin calls. Handles `@sizeOf`, `@alignOf`, `@intCast`. Each resolves its type argument, then checks `ty.state==2` (resolved). | `comptimeEvalEvaluate` | `comptimeEvalResolveTypeArg`, `comptimeEvalEvaluate`, `ast_mod.astStoreGetExtraChildren` | `self.store`, `self.registry`, `self.interner` | Guards on `ty.state==2` (fully resolved). Returns null if type unresolved. | None [inference] |
| `comptimeEvalBuiltin` — `@sizeOf` | 97 | — | Extract first extra child as type arg, resolve, return `ty.size` as `ComptimeVal`. | (same as above) | same | `registry.types_items[t].size` | Always width_bits=0, sig=false (compile-time size is unsigned). | None [inference] |
| `comptimeEvalBuiltin` — `@alignOf` | 106 | — | Same pattern as `@sizeOf` but returns `ty.alignment`. | (same as above) | same | `registry.types_items[t].alignment` | Width=0, sig=false. | None [inference] |
| `comptimeEvalBuiltin` — `@intCast` | 115 | — | Resolve target type, evaluate inner expression, then truncate/sign-extend bits to target width. Computes mask, sign-extends if target is signed type. | (same as above) | `comptimeEvalEvaluate`, `comptimeEvalResolveTypeArg`, `ast_mod.astStoreGetExtraChildren` | `registry.types_items[t].size/kind` | Checks `ty.kind` for signed int kinds (i8/i16/i32/i64/isize). 64-bit full width passes through directly. | None [inference] |
| `comptimeEvalBinOp` | 41 | private | Evaluate binary arithmetic at compile time. Handles add/sub/mul/div/mod_op. Signed division uses sign-magnitude algorithm. | `comptimeEvalEvaluate` | `comptimeEvalEvaluate` (recursive for lhs/rhs) | `store.nodes`, lhs/rhs `ComptimeVal` | Width = max(lhs.width_bits, rhs.width_bits). Signed if either operand signed. Division-by-zero returns null. | None [inference] |
| `comptimeEvalBinOp` — signed div | 56 | — | Extract sign bits, compute absolute values, divide, apply sign to quotient. | (same as above) | none | local variables | Two's complement negation: `0 - val`. XOR sign bits for result sign. | None [inference] |
| `comptimeEvalBinOp` — signed mod | 69 | — | Same sign-magnitude approach as div, but returns remainder with dividend sign. | (same as above) | none | local variables | Divisor sign ignored; only dividend sign applied to remainder. | None [inference] |
| `comptimeEvalEvaluate` | 141 | pub | Main comptime evaluation dispatch. Walks AST node kind and returns `ComptimeVal` or null. | `main.zig` phase_ComptimeEvaluation (main.zig:333); recursively by itself; unit tests (test_semantic_bin.zig) | `comptimeEvalBinOp`, `comptimeEvalBuiltin`, `comptimeEvalEvaluate` (recursive) | `store.nodes`, `store.int_values` | `node_idx==0` returns null (null check). Recursive for paren_expr and negate. | None [inference] |
| `comptimeEvalEvaluate` — int_literal | 144 | — | Returns bits from `store.int_values[node.payload]`, width=0, sig=true. | (same as above) | none | `store.int_values` | width=0 means arbitrary precision — caller applies truncation. | None [inference] |
| `comptimeEvalEvaluate` — char_literal | 146 | — | Same bits as int_literal but width=8, sig=false. | (same as above) | none | `store.int_values` | Character treated as u8 value. | None [inference] |
| `comptimeEvalEvaluate` — bool_literal | 148 | — | Returns 1 or 0, width=1, sig=false. Based on `node.flags & 1`. | (same as above) | none | `node.flags` | Flags bit 0 = value. | None [inference] |
| `comptimeEvalEvaluate` — negate | 151 | — | Recursively evaluate inner, compute `0 - bits`, then mask/sign-extend to inner width. | (same as above) | `comptimeEvalEvaluate` | inner `ComptimeVal` | width=0 case returns sig=true (signed literal). Finite width applies mask + optional sign extension. | None [inference] |
| `comptimeEvalEvaluate` — binop | 171 | — | Dispatches to `comptimeEvalBinOp` for add/sub/mul/div/mod_op kinds. | (same as above) | `comptimeEvalBinOp` | `node.kind` | Forward `node_idx` and `node.kind` to binop handler. | None [inference] |
| `comptimeEvalEvaluate` — builtin_call | 175 | — | Dispatches to `comptimeEvalBuiltin` for builtin_call kind. | (same as above) | `comptimeEvalBuiltin` | `node.kind` | Only @sizeOf/@alignOf/@intCast are foldable. | None [inference] |
| `comptimeEvalEvaluate` — paren_expr | 177 | — | Unwraps parentheses: recurses on `node.child_0`. | (same as above) | `comptimeEvalEvaluate` | `node.child_0` | Trivial pass-through. | None [inference] |

---

## Data Flow

```
comptimeEvalEvaluate(node_idx)
  │
  ├─ int_literal ──→ store.int_values[node.payload] ──→ ComptimeVal{bits, width=0, sig=true}
  ├─ char_literal ──→ store.int_values[node.payload] ──→ ComptimeVal{bits, width=8, sig=false}
  ├─ bool_literal ──→ node.flags & 1 ──→ ComptimeVal{0|1, width=1, sig=false}
  ├─ negate ──→ comptimeEvalEvaluate(child_0) ──→ 0 - bits ──→ mask/sign-extend
  ├─ add/sub/mul/div/mod_op ──→ comptimeEvalBinOp(node_idx, kind)
  │     └─ comptimeEvalEvaluate(child_0) + comptimeEvalEvaluate(child_1)
  │           └─ width = max(l.width, r.width), sig = l.sig | r.sig
  │           └─ div/mod: signed → sign-magnitude, zero → null
  ├─ builtin_call ──→ comptimeEvalBuiltin(node)
  │     ├─ @sizeOf: resolveTypeArg → ty.size
  │     ├─ @alignOf: resolveTypeArg → ty.alignment
  │     └─ @intCast: resolveTypeArg + evaluate(inner) → mask/truncate/sign-ext
  └─ paren_expr ──→ comptimeEvalEvaluate(node.child_0)
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
The same node folds again identically at nodes 1104, 1256, 1313 (all `@sizeOf(JsonValue)`,
json.zig:178/220/233), each with a `CEV`.

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

## Known limitation of the fold pass

`phase_ComptimeEvaluation` iterates **every** `builtin_call` node in the whole store
(main.zig:330-337) and calls `comptimeEvalEvaluate` on each — there is no name pre-filter, so
the 3-arm `comptimeEvalBuiltin` is invoked even for `@ptrCast`/`@enumToInt` etc., and returns
`null` after checking all three interned IDs (comptime_eval.zig:96-138). Fold results are stored
keyed by AST node index in `ctx.comptime_values` (main.zig:104, 335) and consumed at
lower.zig:2393; a `@sizeOf`/`@alignOf` that failed to fold (type unresolved at fold time) would
ICE at lower.zig:2409-2412 (`iceUnresolvedComptime`) rather than degrade to a runtime call.
