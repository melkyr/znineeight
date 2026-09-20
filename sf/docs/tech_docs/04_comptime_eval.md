# 04 — Compile-Time Evaluation [updated: 2026-09-20 — refreshed against the 7-name foldable-builtin set (`@sizeOf`/`@alignOf`/`@offsetOf`/`@bitOffsetOf`/`@bitSizeOf`/`@intCast`/`@isWindows`), arbitrary-width/enum-backing folds, and the CLI-driven `host_is_windows`; line references and dated evidence removed]

> Covers: `comptime_eval.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ComptimeVal` fields | 3 | bits (u64), width_bits (u32), sig (bool) |
| `ComptimeEval` fields | 12 | registry, store, interner, symbol_reg, size_of_id, align_of_id, offset_of_id, bit_size_of_id, bit_offset_of_id, int_cast_id, is_windows_id, host_is_windows |
| Builtin intrinsics (comptime-foldable) | 7 | @sizeOf, @alignOf, @offsetOf, @bitOffsetOf, @bitSizeOf, @intCast, @isWindows — the ONLY names interned by `comptimeEvalInit` |
| Builtin names interned by sema | 35 | `@ptrCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@volatileCast`, `@bitCast`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@enumToInt`, `@as`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf` + runtime/console/async builtins (+ `_` stub) — type assignment only |
| Builtin names interned by lowerer | 37 | `@intCast`, `@intToFloat`, `print`, `@ptrCast`, `@volatileCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@enumToInt`, `@intToEnum`, `@as`, `@bitCast`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@cVaStart`, `@cVaArg`, `@cVaEnd` + runtime/console/async builtins — LIR dispatch only |
| Non-foldable builtins | 27 | every other interned builtin name (pointer/cast/introspection/runtime/console/async) — comptime eval returns `null`, handled by sema type rules + runtime LIR |
| Binary ops evaluated | 10 | add, sub, mul, div, mod, bit_and, bit_or, bit_xor, shl, shr |
| Unary ops evaluated | 2 | negate, bit_not (bool_not/others → null) |
| Extra operands | 1 | ident_expr const-chain (depth-16 guarded) |
| Literal kinds | 3 | int_literal, char_literal, bool_literal |
| Dispatch arms | 9 | int/char/bool/negate/bit_not/binop/builtin/paren/ident_expr |
| Const-chain depth cap | 16 | ident_expr chain returns null at depth ≥ 16; the array-size const evaluator in `type_resolver.zig` emits located `error[3050]` on a cycle/unfoldable size |

---

## Function Walkthrough

| Function | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|-----------|---------|-----------|-------|-------------|---------------|---------|
| `comptimeEvalInit` | pub | Initialize `ComptimeEval` by interning `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@intCast`, `@isWindows` string names (7 names). Returns populated struct with `host_is_windows=false`. | `main.zig` phase_ComptimeEvaluation; unit tests (test_semantic_bin.zig) | `interner_mod.stringInternerIntern` | `interner` hash map, `ComptimeEval` fields | Seven builtin IDs frozen at init; no dynamic registration. | None [inference] |
| `comptimeEvalResolveTypeArg` | private | Resolve a type argument AST node to a `TypeId` using `resolveTypeExprFull`. Returns `null` on `node_idx==0` or `TYPE_UNDEFINED`. | `comptimeEvalBuiltin` | `type_resolver.resolveTypeExprFull` | `store`, `registry`, `symbol_reg`, `interner` | Creates an ephemeral `TypeResolveEnv` (`MODULE_ID_NONE`, no diag, no local consts) each call. No caching. | None [inference] |
| `comptimeEvalBuiltin` | private | Dispatch comptime-evaluable builtin calls across the 7 interned IDs. | `comptimeEvalEvaluateDepth` | `comptimeEvalResolveTypeArg`, `comptimeEvalEvaluateDepth`, `ast_mod.astStoreNodeExtraChildAt/Count` | `self.store`, `self.registry`, `self.interner` | Guards on `ty.state==2` (fully resolved); returns null for any other name. | None [inference] |
| `comptimeEvalBuiltin` — `@sizeOf` | — | Extract first extra child as type arg, resolve, return `ty.size` as `ComptimeVal`. | (same as above) | same | `registry.types_items[t].size` | Always width_bits=0, sig=false (compile-time size is unsigned). | None [inference] |
| `comptimeEvalBuiltin` — `@alignOf` | — | Same pattern as `@sizeOf` but returns `ty.alignment`. | (same as above) | same | `registry.types_items[t].alignment` | Width=0, sig=false. | None [inference] |
| `comptimeEvalBuiltin` — `@offsetOf` / `@bitOffsetOf` | — | Require ≥2 extra children: resolve type arg (extra child 0), take extra child 1 as a literal field name. For a struct, look up the field; packed struct uses `packed_fields[fi].bit_offset` (`@bitOffsetOf` = bit offset, `@offsetOf` = bit offset/8), unpacked struct uses `fields[fi].offset` (`@bitOffsetOf` = offset*8). For a packed union, returns 0. | (same as above) | `typeRegistryGetStructFields`, `typeRegistryGetPackedBitFields`, `typeRegistryGetUnionFields` | `registry` field arrays, `store.string_values` | Field name must be an `AstKind.string_literal`; struct must be resolved (`state==2`). | None [inference] |
| `comptimeEvalBuiltin` — `@bitSizeOf` | — | Resolve type; base `ty.size*8`. Packed struct → `typeRegistryGetPackedTotalBits`; packed union → `typeRegistryGetPackedUnionTotalBits`; integer → `typeRegistryIntWidthBits`; enum → backing type's width bits; bool → 1. | (same as above) | `typeRegistryGetPackedTotalBits`, `typeRegistryGetPackedUnionTotalBits`, `typeRegistryIsInteger`, `typeRegistryIntWidthBits`, `typeRegistryEnumBackingType` | `registry.types_items` | Arbitrary-width and `enum(uN)`-backing aware. | None [inference] |
| `comptimeEvalBuiltin` — `@intCast` | — | Resolve target type, evaluate inner expression, then truncate/sign-extend bits to target width. Integer targets use `typeRegistryIntWidthBits` + `typeRegistryIntIsSigned`; non-integer targets use `ty.size*8` unsigned. ≥64-bit width passes through directly; otherwise mask + sign-extend. | (same as above) | `comptimeEvalEvaluateDepth`, `comptimeEvalResolveTypeArg`, `typeRegistryIsInteger`, `typeRegistryIntWidthBits`, `typeRegistryIntIsSigned` | `registry.types_items[t]` | Arbitrary-width and enum-backed signed ints are handled via the registry helpers. | None [inference] |
| `comptimeEvalBuiltin` — `@isWindows` | — | Returns `self.host_is_windows ? 1 : 0`, width=1, sig=false. | (same as above) | none | `self.host_is_windows` | Value set by `main.zig` from `cli.target_is_windows`. | None [inference] |
| `comptimeEvalBinOp` | private | Evaluate binary arithmetic at compile time. Handles add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr. Signed division uses a sign-magnitude algorithm. | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs/rhs) | `store.nodes`, lhs/rhs `ComptimeVal` | Width = max(lhs.width_bits, rhs.width_bits). Signed if either operand signed. Division-by-zero returns null. Shift amount >= 64 returns null. | None [inference] |
| `comptimeEvalBinOp` — signed div | — | Extract sign bits, compute absolute values, divide, apply sign to quotient. | (same as above) | none | local variables | Two's complement negation: `0 - val`. XOR sign bits for result sign. | None [inference] |
| `comptimeEvalBinOp` — signed mod | — | Same sign-magnitude approach as div, but returns remainder with dividend sign. | (same as above) | none | local variables | Divisor sign ignored; only dividend sign applied to remainder. | None [inference] |
| `comptimeEvalEvaluate` | pub | Main comptime evaluation entry point. Thin wrapper delegating to `comptimeEvalEvaluateDepth(node_idx, 0)`. | `main.zig` phase_ComptimeEvaluation; recursion; unit tests (test_semantic_bin.zig) | `comptimeEvalEvaluateDepth` | `store.nodes`, `store.int_values` | Entry point; all recursion flows through the depth-guarded variant. | None [inference] |
| `comptimeEvalEvaluateDepth` | private | Depth-guarded evaluation core. Nine dispatch arms, including the `ident_expr` const-chain arm. | `comptimeEvalEvaluate`, recursively by itself/binop/builtin | `comptimeEvalBinOp`, `comptimeEvalBuiltin`, `comptimeEvalEvaluateDepth` (recursive), `symbolRegistryQualifiedLookup` | `store.nodes`, `store.int_values`, `store.identifiers`, `symbol_reg` | `node_idx==0` returns null. `depth >= 16` returns null (const-chain guard). Recursive for paren_expr, negate, bit_not, binop, builtin, and ident_expr chains. | None [inference] |
| `comptimeEvalEvaluate` — int_literal | — | Returns bits from `store.int_values[node.payload]`, width=0, sig=true. | (same as above) | none | `store.int_values` | width=0 means arbitrary precision — caller applies truncation. | None [inference] |
| `comptimeEvalEvaluate` — char_literal | — | Same bits as int_literal but width=8, sig=false. | (same as above) | none | `store.int_values` | Character treated as u8 value. | None [inference] |
| `comptimeEvalEvaluate` — bool_literal | — | Returns 1 or 0, width=1, sig=false. Based on `node.flags & 1`. | (same as above) | none | `node.flags` | Flags bit 0 = value. | None [inference] |
| `comptimeEvalEvaluate` — negate/bit_not | — | Recursively evaluate inner, compute `0 - bits` (negate) or `~bits` (bit_not); negate masks/sign-extends to inner width. | (same as above) | `comptimeEvalEvaluateDepth` | inner `ComptimeVal` | width=0 case returns sig=true (signed literal). Finite width applies mask + optional sign extension. `bit_not` keeps the inner width with sig=false. | None [inference] |
| `comptimeEvalEvaluate` — binop | — | Dispatches to `comptimeEvalBinOp` for add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr kinds. | (same as above) | `comptimeEvalBinOp` | `node.kind` | Forwards `node_idx`, `node.kind`, and current depth to the binop handler. | None [inference] |
| `comptimeEvalEvaluate` — builtin_call | — | Dispatches to `comptimeEvalBuiltin` for the builtin_call kind. | (same as above) | `comptimeEvalBuiltin` | `node.kind` | 7 names foldable; every other name returns null. | None [inference] |
| `comptimeEvalEvaluate` — paren_expr | — | Unwraps parentheses: recurses on `node.child_0`. | (same as above) | `comptimeEvalEvaluateDepth` | `node.child_0` | Trivial pass-through. | None [inference] |
| `comptimeEvalEvaluate` — ident_expr | — | Const-chain resolution: look up `name_id` via `symbolRegistryQualifiedLookup` across all module tables; if the symbol is a `const` (symbol `flags & 0x01 == 0`) with a non-empty init (`decl.child_1 != 0`), recurse into that init at `depth+1`. Returns null on `depth >= 16` (const-chain guard) or no matching const. | (same as above) | `comptimeEvalEvaluateDepth` (recursive), `symbolRegistryQualifiedLookup` | `store.identifiers`, `symbol_reg`, `store.nodes` | Enables `const B: i32 = A + 5` to fold from `const A: i32 = 30`. | None [inference] |

---

## Data Flow

```
comptimeEvalEvaluate(node_idx)
  └─ comptimeEvalEvaluateDepth(node_idx, depth=0)     ← every recursion carries depth
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
       │     ├─ @offsetOf/@bitOffsetOf: resolveTypeArg + field name → offset / bit offset
       │     ├─ @bitSizeOf: resolveTypeArg → size*8 / packed bits / int width / enum backing / 1
       │     ├─ @intCast: resolveTypeArg + EvaluateDepth(inner) → mask/truncate/sign-ext
       │     └─ @isWindows: host_is_windows ? 1 : 0
       ├─ paren_expr ──→ EvaluateDepth(node.child_0)
       └─ ident_expr ──→ symbolRegistryQualifiedLookup(name_id) across module tables
             └─ if const (symbol flags & 0x01 == 0) and init present → EvaluateDepth(decl.child_1, depth+1)
             └─ depth >= 16 → null (const-chain guard)
```

**Init flow:**
```
comptimeEvalInit(registry, store, interner, symbol_reg)
  └─ interner.stringInternerIntern("@sizeOf")       → size_of_id
  └─ interner.stringInternerIntern("@alignOf")      → align_of_id
  └─ interner.stringInternerIntern("@offsetOf")     → offset_of_id
  └─ interner.stringInternerIntern("@bitSizeOf")    → bit_size_of_id
  └─ interner.stringInternerIntern("@bitOffsetOf")  → bit_offset_of_id
  └─ interner.stringInternerIntern("@intCast")      → int_cast_id
  └─ interner.stringInternerIntern("@isWindows")    → is_windows_id
  └─ host_is_windows = false               (main.zig overrides from cli.target_is_windows)
```

---

## Debugging

- **Null return** — any evaluation that returns `null` means the node is NOT stored in
  `ctx.comptime_values`, so LIR lowering falls back to a runtime form instead of an `int_const`.
  Null causes include: type argument unresolved (`ty.state != 2`), division/mod by zero, shift
  amount ≥ 64, unhandled node kind, `node_idx == 0`, a const chain deeper than 16, and any builtin
  not in the 7-name fold set. The semantic analyzer still assigns a result *type* to the node
  regardless.
- **Wrong width** — `@intCast` width comes from `typeRegistryIntWidthBits` for integer targets
  (arbitrary-width and `enum(uN)` backing included) and `ty.size * 8` otherwise. An unresolved
  type or wrong size makes the mask/sign-extend wrong.
- **Signedness** — `@intCast` determines signedness from `typeRegistryIntIsSigned`, so
  arbitrary-width signed ints are handled; non-integer targets are treated as unsigned.
- **Division by zero** — both `div` and `mod_op` return `null` when the divisor is zero. This is distinct from a runtime SIGFPE.
- **Shift guard** — `shl`/`shr` return `null` when the shift amount is ≥ 64.
- **Enum literal evaluation** — not handled in this module; enum literals are resolved by the semantic analyzer, not comptime evaluated here.

---

## Builtin Internment: 7 in comptime_eval

`comptimeEvalInit` interns **exactly seven** names — `@sizeOf`, `@alignOf`, `@offsetOf`,
`@bitSizeOf`, `@bitOffsetOf`, `@intCast`, `@isWindows` — into
`size_of_id`/`align_of_id`/`offset_of_id`/`bit_size_of_id`/`bit_offset_of_id`/`int_cast_id`/`is_windows_id`.
There is no 8-name intern set in this module. The "8 builtins" the task context hypothesised
belongs to the **semantic analyzer**, which interns a 35-name set at `semanticAnalyzerInit`
(including a `_` stub → `_stub_0`), and the LIR lowerer independently interns a 37-name set at
`lowererInit`.

| Interned name | comptime_eval.zig | semantic_analyzer.zig | lower.zig |
|---------------|:-----------------:|:---------------------:|:---------:|
| `@sizeOf` | ✓ (fold to `ty.size`) | ✓ (type → TYPE_INT_LIT) | ✓ (fold/int_const) |
| `@alignOf` | ✓ (fold to `ty.alignment`) | ✓ (type → TYPE_INT_LIT) | ✓ (fold/int_const) |
| `@offsetOf` | ✓ (fold struct field offset) | ✓ (type → TYPE_INT_LIT) | ✓ (fold/int_const) |
| `@bitOffsetOf` | ✓ (fold packed bit offset) | ✓ (type → TYPE_INT_LIT) | ✓ (fold/int_const) |
| `@bitSizeOf` | ✓ (fold packed/int/enum/bool width) | ✓ (type → TYPE_INT_LIT) | ✓ (fold/int_const) |
| `@intCast` | ✓ (fold constant inner) | ✓ (type-value cast) | ✓ (runtime int_cast) |
| `@isWindows` | ✓ (fold host flag) | ✓ (→ TYPE_BOOL) | ✓ (fold/int_const) |
| `@ptrCast` | — | ✓ (type-value cast) | ✓ (runtime ptr_cast) |
| `@volatileCast` | — | ✓ (type-value cast) | ✓ (runtime volatile_cast) |
| `@bitCast` | — | ✓ (same-size int check) | ✓ (runtime int_cast) |
| `@ptrToInt` / `@intFromPtr` | — | ✓ (→ TYPE_USIZE) | ✓ (runtime ptr_to_int) |
| `@intToPtr` / `@ptrFromInt` | — | ✓ | ✓ (runtime int_to_ptr) |
| `@fieldParentPtr` | — | ✓ | ✓ (ptr arithmetic) |
| `@floatCast` | — | ✓ (type-value cast) | — |
| `@intToFloat` | — | ✓ (type-value cast) | ✓ (runtime int_to_float) |
| `@intToEnum` | — | ✓ (type-value cast) | ✓ |
| `@enumToInt` | — | ✓ | ✓ (lower arg directly) |
| `@as` | — | ✓ (type-value cast) | ✓ (lower inner) |
| `@cVaStart` / `@cVaArg` / `@cVaEnd` | — | — | ✓ (va_start / va_arg / va_end) |
| runtime / console builtins | — | ✓ (`@putChar`, `@stdoutWrite`, `@stderrWrite`, `@getChar`, `@exit`, `@panic`, `@sleepMs`, `@consoleClear`, `@consoleGotoxy`, `@consoleSetColor`) | ✓ |
| async builtins | — | ✓ (`@asyncFrameSize`, `@asyncInit`, `@asyncResume`, `@asyncSuspend`) | ✓ |
| `print` | — | — | ✓ (fn-call lower) |

> The full sema/lower builtin inventories and their dispatch rules live in `05_semantic_analysis.md`
> and `07_lir_lowering.md`; this table only marks which names each module interns.

---

## Boundary: where comptime eval ends and sema/lowering takes over

The pipeline has **one** comptime-value fold pass and **two** type/dispatch passes; the fold
pass is purely a *value* pre-computation, not a type system.

```
phase_ComptimeEvaluation (main.zig)                 marker "CE"
  │  ce = comptimeEvalInit(...); ce.host_is_windows = ctx.cli.target_is_windows
  │  sweep all AST nodes:
  │    builtin_call → comptimeEvalEvaluate(node_idx)
  │      └─ success → ctx.comptime_values[node_idx] = v.bits
  │      └─ null   → not stored (skipped silently)
  │    const var_decl with binary/unary init → fold init node, store under the init node

phase_SemanticAnalysis (main.zig)                   marker "RS"
  └─ semanticAnalyzerResolveExpr builtin_call arm (semantic_analyzer.zig)
       ├─ @sizeOf/@alignOf/@offsetOf/@bitSizeOf/@bitOffsetOf → result type TYPE_INT_LIT
       ├─ type-value casts (@intCast/@ptrCast/@intToPtr/@floatCast/@intToFloat/@intToEnum/@as/@volatileCast/@bitCast)
       │     └─ resolve inner expr + resolve target type
       ├─ @ptrToInt/@intFromPtr    → TYPE_USIZE
       ├─ @ptrFromInt              → target pointer type (diagnostic if not inferable)
       ├─ @isWindows               → TYPE_BOOL
       └─ runtime/console/async builtins → their fixed result types
       (computes TYPES only — does NOT recompute the constant value)

phase_LIRLowering (lower.zig, builtin_call arm)
  ├─ comptime_values lookup
  │     ├─ HIT → emit int_const LIR + marker "CEV" ← the fold is CONSUMED here
  │     │        (@intCast uses the resolved target type; @isWindows uses TYPE_BOOL)
  │     └─ MISS, then:
  ├─ @sizeOf/@alignOf/@offsetOf/@bitSizeOf/@bitOffsetOf → iceUnresolvedComptime (must have folded; ICE if not)
  ├─ @enumToInt               → "E", lower inner directly
  ├─ @bitCast                 → int_cast LIR to the resolved destination type
  └─ other builtins           → their runtime LIR forms
```

So the semantic analyzer never evaluates comptime constants — it only assigns result **types**.
The actual constant *value* computed by `comptimeEvalEvaluate` is consumed one phase later, in
LIR lowering, where the `comptime_values` map lookup turns a folded builtin into an `int_const`
LIR instruction (marker `CEV`). A builtin the comptime evaluator cannot fold (`null`) is either a
type-only builtin (@sizeOf/@alignOf that nevertheless **did** fold) or a runtime builtin
(@ptrCast, @intCast with runtime args, @enumToInt, @ptrToInt, ...) lowered to the corresponding
LIR form.

---

## Fold-pass coverage (F3/F8 expansion) — [updated: 2026-09-20]

`phase_ComptimeEvaluation` (`main.zig`) does not fold only `builtin_call` nodes. Since F3 it also
folds **module-scope `const var_decl` init expressions** that are bare binary/unary nodes: for each
`const` (`var_decl` with `flags & 1 == 0`) whose `child_1` init kind is one of the 12 arithmetic ops
(AstKind 33–42 `add`…`shr`, or 62 `negate` / 64 `bit_not`), it calls `comptimeEvalEvaluate(init_node)`
and stores the result in `ctx.comptime_values[init_node]`. The lowerer's binary/unary
`comptime_values` guards consume those folds as `int_const` LIR. Since F8 the evaluator itself
resolves `ident_expr` operands through const chains (depth-16 guarded), so `const B = A + 5` folds
even when `A` is a named const.

**Coverage boundaries:**
- Only `builtin_call` nodes go through `comptimeEvalBuiltin` — there is no name pre-filter, so
  `@ptrCast`/`@enumToInt` etc. are invoked and return `null` after checking the seven interned IDs.
- Fold results are stored keyed by AST node index in `ctx.comptime_values` and consumed by the
  lowerer's `comptime_values` lookups; a `@sizeOf`/`@alignOf`/`@offsetOf`/`@bitSizeOf`/`@bitOffsetOf`
  that failed to fold (type unresolved at fold time) ICEs via `iceUnresolvedComptime` rather than
  degrade to a runtime call.
- A const chain longer than the depth-16 guard silently falls back to runtime arithmetic
  (guarded, not fixed) — no current repro or gate triggers it.

---

## `host_is_windows` — single target-platform flip point

`@isWindows` is a comptime-foldable builtin whose **value** is decided at fold time from the
`ComptimeEval.host_is_windows` field. The field is initialized `false` by `comptimeEvalInit` and set
once per compilation:

- **`comptime_eval.zig`** — `ComptimeEval.host_is_windows: bool`; the `@isWindows` arm returns
  `ComptimeVal{ .bits = self.host_is_windows ? 1 : 0, .width_bits = 1, .sig = false }`.
- **`main.zig` `phase_ComptimeEvaluation`** — `ce.host_is_windows = ctx.cli.target_is_windows` before
  the AST sweep. `target_is_windows` is the single flip point, set from the CLI: `-osw` (Windows),
  `-osl` (Linux), or `--target windows|linux` (anything else exits with an error).

`config.zig`'s `pub const host_is_windows` is currently **unwired** — nothing imports `config.zig`;
see `00_shared_infra.md` §13.

The other two `@isWindows` sites assign only the result **type** (`TYPE_BOOL`), never the value, so
they need no platform input:
- `semantic_analyzer.zig` `builtin_call` arm → `TYPE_BOOL`.
- `lower.zig` `builtin_call` arm — when the `comptime_values` lookup hits and the callee is
  `@isWindows`, the fold temp type is set to `TYPE_BOOL`; the value comes from the map populated by
  this module.

No `@isWindows` value folding exists in any other file.

---

## Known Issues

1. **Silent const-chain depth cap** (`comptime_eval.zig`): the `ident_expr` arm returns `null` once
   `depth >= 16`. A cyclic or over-deep const chain therefore falls back to runtime arithmetic with
   no diagnostic from this module. The located `error[3050]` (`ERR_3050_ARRAY_SIZE_NOT_CONSTANT`)
   is emitted only by the array-size const evaluator (`evalConstU32Full` in `type_resolver.zig`),
   not by the fold pass.

2. **`@offsetOf`/`@bitOffsetOf` require a literal field name** (`comptime_eval.zig`): the second
   extra child must be an `AstKind.string_literal`. A field name reached indirectly (alias, const)
   silently yields `null` rather than folding.

3. **Division / shift guards return `null`** (`comptime_eval.zig`): `div`/`mod_op` by zero and
   `shl`/`shr` with a shift amount ≥ 64 fold to `null` with no diagnostic; the runtime path then
   handles (or traps on) them.

4. **Enum literals are not comptime-evaluated here**: `enum_literal` nodes are resolved by the
   semantic analyzer, so they never fold in this module.

5. **`config.zig` is unwired**: the `@isWindows` value comes from the CLI (`ctx.cli.target_is_windows`),
   not from `config.zig`; see `00_shared_infra.md` §13.

