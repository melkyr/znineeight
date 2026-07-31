# 04 — Compile-Time Evaluation

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ComptimeVal` fields | 3 | bits (u64), width_bits (u8), sig (bool) |
| `ComptimeEval` fields | 7 | registry, store, interner, symbol_reg, size_of_id, align_of_id, int_cast_id |
| Builtin intrinsics | 3 | @sizeOf, @alignOf, @intCast |
| Binary ops evaluated | 5 | add, sub, mul, div, mod |
| Literal kinds | 3 | int_literal, char_literal, bool_literal |
| Dispatch arms | 7 | int/char/bool/negate/binop/builtin/paren |

---

## Function Walkthrough

| Function | Line | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|------|-----------|---------|-----------|-------|-------------|---------------|---------|
| `comptimeEvalInit` | 28 | pub | Initialize `ComptimeEval` by interning `@sizeOf`, `@alignOf`, `@intCast` string names. Returns populated struct. | `main.zig` compiler setup, semantic analyzer init | `interner_mod.stringInternerIntern` | `interner` hash map, `ComptimeEval` fields | Three builtin IDs frozen at init; no dynamic registration. | None [inference] |
| `comptimeEvalResolveTypeArg` | 88 | private | Resolve a type argument AST node to a `TypeId` using `resolveTypeExprFull`. Returns `null` on `node_idx==0` or `TYPE_UNDEFINED`. | `comptimeEvalBuiltin` | `type_resolver.resolveTypeExprFull` | `store`, `registry`, `symbol_reg`, `interner` | Creates ephemeral `TypeResolveEnv` each call. No caching. | None [inference] |
| `comptimeEvalBuiltin` | 96 | private | Dispatch comptime-evaluable builtin calls. Handles `@sizeOf`, `@alignOf`, `@intCast`. Each resolves its type argument, then checks `ty.state==2` (resolved). | `comptimeEvalEvaluate` | `comptimeEvalResolveTypeArg`, `comptimeEvalEvaluate`, `ast_mod.astStoreGetExtraChildren` | `self.store`, `self.registry`, `self.interner` | Guards on `ty.state==2` (fully resolved). Returns null if type unresolved. | None [inference] |
| `comptimeEvalBuiltin` — `@sizeOf` | 97 | — | Extract first extra child as type arg, resolve, return `ty.size` as `ComptimeVal`. | (same as above) | same | `registry.types_items[t].size` | Always width_bits=0, sig=false (compile-time size is unsigned). | None [inference] |
| `comptimeEvalBuiltin` — `@alignOf` | 106 | — | Same pattern as `@sizeOf` but returns `ty.alignment`. | (same as above) | same | `registry.types_items[t].alignment` | Width=0, sig=false. | None [inference] |
| `comptimeEvalBuiltin` — `@intCast` | 115 | — | Resolve target type, evaluate inner expression, then truncate/sign-extend bits to target width. Computes mask, sign-extends if target is signed type. | (same as above) | `comptimeEvalEvaluate`, `comptimeEvalResolveTypeArg`, `ast_mod.astStoreGetExtraChildren` | `registry.types_items[t].size/kind` | Checks `ty.kind` for signed int kinds (i8/i16/i32/i64/isize). 64-bit full width passes through directly. | None [inference] |
| `comptimeEvalBinOp` | 41 | private | Evaluate binary arithmetic at compile time. Handles add/sub/mul/div/mod_op. Signed division uses sign-magnitude algorithm. | `comptimeEvalEvaluate` | `comptimeEvalEvaluate` (recursive for lhs/rhs) | `store.nodes`, lhs/rhs `ComptimeVal` | Width = max(lhs.width_bits, rhs.width_bits). Signed if either operand signed. Division-by-zero returns null. | None [inference] |
| `comptimeEvalBinOp` — signed div | 56 | — | Extract sign bits, compute absolute values, divide, apply sign to quotient. | (same as above) | none | local variables | Two's complement negation: `0 - val`. XOR sign bits for result sign. | None [inference] |
| `comptimeEvalBinOp` — signed mod | 69 | — | Same sign-magnitude approach as div, but returns remainder with dividend sign. | (same as above) | none | local variables | Divisor sign ignored; only dividend sign applied to remainder. | None [inference] |
| `comptimeEvalEvaluate` | 141 | pub | Main comptime evaluation dispatch. Walks AST node kind and returns `ComptimeVal` or null. | semantic analyzer during type resolution, constant expression contexts | `comptimeEvalBinOp`, `comptimeEvalBuiltin`, `comptimeEvalEvaluate` (recursive) | `store.nodes`, `store.int_values` | `node_idx==0` returns null (null check). Recursive for paren_expr and negate. | None [inference] |
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

- **Null return** — any evaluation that returns `null` causes the semantic analyzer to fall back to runtime evaluation. Look for: type argument unresolved (`ty.state != 2`), division by zero, unhandled node kind, `node_idx == 0`.
- **Wrong width** — `@intCast` width computed as `ty.size * 8`. If the type is unresolved or has wrong size, the mask/sign-extend will be wrong.
- **Signedness mismatch** — `@intCast` determines signedness from `ty.kind`. If `ty.kind` doesn't match one of the signed int kinds, the result is unsigned even if the type is signed.
- **Division by zero** — both `div` and `mod_op` return `null` when divisor is zero. This is distinct from a runtime SIGFPE.
- **Enum literal evaluation** — not handled in this module; enum literals are resolved by the semantic analyzer, not comptime evaluated here.
