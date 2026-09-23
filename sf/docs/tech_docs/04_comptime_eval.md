# 04 — Compile-Time Evaluation [updated: 2026-09-23 — Task 2 (ComptimeInt core + arithmetic): `ComptimeVal` is now `{ v: ComptimeInt, kind: u8, float_bits: u64 }` with `ComptimeInt { mag: [8]u32, len: u8, neg: bool }` (256-bit fixed-cap little-endian magnitude, exact-or-unfoldable) and kinds `KIND_INT`/`KIND_BOOL`/`KIND_FLOAT` replacing `width_bits`/`sig`/`WIDTH_FLOAT`. add/sub/mul/div/mod/negate/bitand/bitor/bitxor/bitnot/shl/shr are exact limb ops (`ci*`, all `pub`), Zig-truncating division with floor `>>` and infinite two's-complement bitwise semantics; results needing > 256 magnitude bits, division by zero, and negative/oversized shift counts return null (unfoldable). `comptimeValFitsType` became the exact `comptimeIntFitsType`; `@intCast`/`@as` fold the exact value after an exact range check (messages/location preserved); `@intToFloat` converts from limbs (no `comptimeEvalOperandSigned`); comparison/logical folds keep their pre-Task-3 semantics via `kind` and a 64-bit `ciValToOldBits` adapter; the fold table stays `U32ToU64Map` until Task 5 (`comptimeValStoreU64` materialises bool/float/int, skipping ints outside `[i64 min, u64 max]`). Fixture `repro/mi_matrix/stdlib_comptime_bigint_arith_xmod` (Zig-0.15.2-oracle-checked) + standalone `repro/comptime_bigint_arith.z98`; fixed point `cd38f316…` → `e4246b19…`] [updated: 2026-09-23 — Task 9D fix round 3 (operator ruling m1293 (b)): the comparison fold is now CONSERVATIVE. An operand's signedness is taken only from a declared integer type, a literal's own sign / `negate`, or an explicit `@intCast`/`@as` target; any other shape — e.g. an arithmetic expression over a const — makes the whole comparison UNFOLDABLE (null). `comptimeEvalOperandCompareSigned` now reports determinability through an out-param and never falls back to `cv.sig`; `comptimeEvalSignClass` classifies `0 - X` as the negation of X (the one arithmetic shape with a definite sign). Bounded divergence, documented in `repro/mi_matrix/comptime_compare_diverge_reject_xmod` and `EXPECTED_FAIL.md` v199: Zig evaluates `(umax - 1) > 0`, `umax > (0 + 0)`, `(a + 1) == 2`, etc. at arbitrary precision and accepts; Z98 declines and rejects `error[3059]`] [updated: 2026-09-23 — Task 9D fix round 2: the comparison signedness is computed PER OPERAND (new `comptimeEvalOperandCompareSigned`): a declared integer type wins for its own operand, otherwise the syntactic sign class decides, falling back to `cv.sig` for an unrecognized untyped shape. This keeps a declared-unsigned operand from masking a negative counterpart — `const u: u8 = 200; if (u > -1) 1;` (and `-1 < u`, `u > (0 - 1)`) is accepted and true, while `const umax: u64 = …; if (umax < 0)` stays unsigned/false and rejected. Fix round 1's `have_decl` gate that suppressed the negative sign class is removed] [updated: 2026-09-23 — Task 9D fix round 1: the comparison fold's signedness is now the operands' DECLARED integer types (new private `comptimeEvalOperandDeclaredSigned`, which consults function-local consts first) instead of `l.sig or r.sig`; with no declared type on either side a definite syntactic negative still makes it signed (`comptimeEvalSignClass`). This fixes a `u64` const above i64 max comparing signed (`umax > 0` was rejected; `umax < 0` folded true and was accepted with an uninitialised result). `comptimeEvalLogical` now also handles a decisive RHS when the lhs does not fold (`<runtime> or true` -> true, `<runtime> and false` -> false), so those comptime-known-true conditions are accepted; `comptimeEvalSignClass` consults the local const scope too (only set by the sema probe, so the global fold is unaffected)] [updated: 2026-09-23 — Task 9D: the fold now handles comparisons (`cmp_eq`/`cmp_ne`/`cmp_lt`/`cmp_le`/`cmp_gt`/`cmp_ge`) via the new private `comptimeEvalCompare` (signedness mirrors `comptimeEvalBinOp`'s div/mod sign handling: signed if either operand is signed, values compared as sign-extended i64 / zero-extended u64; a `WIDTH_FLOAT` operand stays unfolded — a bounded residual) and logical `bool_and`/`bool_or`/`bool_not` via the new private `comptimeEvalLogical` (`and`/`or` **short-circuit**: a decisive lhs returns without evaluating the rhs, so `true or <runtime>` folds true and `false and <runtime>` folds false). `ComptimeEval` gains `local_consts: ?*type_resolver.LocalConstScope` (null by default); the `ident_expr` arm consults it before the module symbol registry so a function-local `const` participates in the fold (Gap B), and `semanticAnalyzerConditionIsComptimeTrue` sets it from `self.local_consts`. This makes a comptime-known-true comparison condition permit a no-`else` value `if`, matching Zig] [updated: 2026-09-21 — Task B3 items 2/3/4: `comptimeValFitsType` no longer blanket-accepts a `wb >= 64` target; it classifies the operand syntactically (`comptimeEvalSignClass`, a tri-state) so a definitely-negative source cannot fit an unsigned 64-bit target and a definitely-non-negative source above i64 max cannot fit a signed one (the bit pattern alone cannot distinguish `-1` from `18446744073709551615`); the shared `@intCast`/`@as` reject message now names the builtin actually used; the reject still uses `source_file_id = 0` (documented: the global comptime node sweep has no module context and the AST store has no node→file map, so a real location needs a structural change)] [updated: 2026-09-21 — Task 11U: `@as` is interned (`as_id`, 10-name foldable set) and shares the `@intCast` fold/range-check arm in `comptimeEvalBuiltin`, with a mandatory integer-target guard so a non-integer `@as` never folds to an integer `ComptimeVal` (which would miscompile float arithmetic, e.g. `@as(f64,3)/2`); the `@as` case is mirrored in `comptimeEvalOperandSigned`] [updated: 2026-09-21 — Task 11S (c): `ComptimeEval` gains a `diag` field and the `@intCast` arm range-checks an integer target via the new `comptimeValFitsType` helper, emitting `error[3000]` and refusing to fold an out-of-range comptime cast (previously it masked to the target width)] [updated: 2026-09-20 — Task 11D: 9-name foldable-builtin set (adds `@floatCast`/`@intToFloat`), the private float sub-evaluator, and the `WIDTH_FLOAT` float-fold sentinel; earlier: refreshed against the 7-name set (`@sizeOf`/`@alignOf`/`@offsetOf`/`@bitOffsetOf`/`@bitSizeOf`/`@intCast`/`@isWindows`), arbitrary-width/enum-backing folds, and the CLI-driven `host_is_windows`]

> Covers: `comptime_eval.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ComptimeVal` fields | 3 | Task 2: `v` (`ComptimeInt`), `kind` (`KIND_INT`/`KIND_BOOL`/`KIND_FLOAT`), `float_bits` (f64 pattern, valid iff `kind == KIND_FLOAT`). The old `bits`/`width_bits`/`sig` triple and the `WIDTH_FLOAT` sentinel are gone. |
| `ComptimeInt` | 3 fields + cap | Task 2: `mag: [8]u32` (little-endian magnitude limbs), `len: u8` (0 = zero; one past the top non-zero limb), `neg: bool` (`false` when zero). 8 limbs = 256 magnitude bits; every op is exact or declines. |
| Core limb ops (`ci*`) | 29 | Task 2, all `pub`: zero/from-u64/pow2/set/normalize/isZero/magCmp/toU64/toF64/valToOldBits/intVal/boolVal; magnitude and/or/xor/not/addInto/subInto/addOne/subOne; add/sub/neg/mul/divMod/bitAnd/bitOr/bitXor/bitNot/shl/shr. |
| `ComptimeEval` fields | 17 | registry, store, interner, symbol_reg, size_of_id, align_of_id, offset_of_id, bit_size_of_id, bit_offset_of_id, int_cast_id, as_id (Task 11U), float_cast_id, int_to_float_id, is_windows_id, host_is_windows, local_consts (Task 9D; `?*type_resolver.LocalConstScope`, null by default), diag (Task 11S) |
| Builtin intrinsics (comptime-foldable) | 10 | @sizeOf, @alignOf, @offsetOf, @bitOffsetOf, @bitSizeOf, @intCast, @as (Task 11U; integer targets only), @floatCast, @intToFloat, @isWindows — the ONLY names interned by `comptimeEvalInit` |
| Builtin names interned by sema | 35 | `@ptrCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@volatileCast`, `@bitCast`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@enumToInt`, `@as`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf` + runtime/console/async builtins (+ `_` stub) — type assignment only |
| Builtin names interned by lowerer | 37 | `@intCast`, `@intToFloat`, `print`, `@ptrCast`, `@volatileCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@enumToInt`, `@intToEnum`, `@as`, `@bitCast`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@cVaStart`, `@cVaArg`, `@cVaEnd` + runtime/console/async builtins — LIR dispatch only |
| Non-foldable builtins | 25 | every other interned builtin name (pointer/cast/introspection/runtime/console/async) — comptime eval returns `null`, handled by sema type rules + runtime LIR |
| Binary ops evaluated | 10 | add, sub, mul, div, mod, bit_and, bit_or, bit_xor, shl, shr |
| Unary ops evaluated | 3 | negate, bit_not, bool_not (Task 9D) |
| Comparison ops evaluated | 6 | cmp_eq, cmp_ne, cmp_lt, cmp_le, cmp_gt, cmp_ge (Task 9D; integer operands only) |
| Logical ops evaluated | 2 | bool_and, bool_or (Task 9D; short-circuit) |
| Extra operands | 1 | ident_expr const-chain (depth-16 guarded; local_consts first, Task 9D) |
| Literal kinds | 3 | int_literal, char_literal, bool_literal |
| Dispatch arms | 12 | int/char/bool/negate/bit_not/bool_not/binop/cmp/logical/builtin/paren/ident_expr |
| Const-chain depth cap | 16 | ident_expr chain returns null at depth ≥ 16; the array-size const evaluator in `type_resolver.zig` emits located `error[3050]` on a cycle/unfoldable size |

---

## Function Walkthrough

| Function | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions | Markers |
|----------|-----------|---------|-----------|-------|-------------|---------------|---------|
| `comptimeEvalInit` | pub | Initialize `ComptimeEval` by interning `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@intCast`, `@as`, `@floatCast`, `@intToFloat`, `@isWindows` string names (10 names; Task 11U added `@as`). Returns populated struct with `host_is_windows=false`, `local_consts=null` (Task 9D; a caller with a function-local scope sets it), and `diag=null` (Task 11S; `main.zig` sets `ce.diag = ctx.diag`). | `main.zig` phase_ComptimeEvaluation; unit tests (test_semantic_bin.zig) | `interner_mod.stringInternerIntern` | `interner` hash map, `ComptimeEval` fields | Ten builtin IDs frozen at init; no dynamic registration. | None [inference] |
| `comptimeEvalResolveTypeArg` | private | Resolve a type argument AST node to a `TypeId` using `resolveTypeExprFull`. Returns `null` on `node_idx==0` or `TYPE_UNDEFINED`. | `comptimeEvalBuiltin` | `type_resolver.resolveTypeExprFull` | `store`, `registry`, `symbol_reg`, `interner` | Creates an ephemeral `TypeResolveEnv` (`MODULE_ID_NONE`, no diag, no local consts) each call. No caching. | None [inference] |
| `comptimeEvalBuiltin` | private | Dispatch comptime-evaluable builtin calls across the 10 interned IDs. | `comptimeEvalEvaluateDepth` | `comptimeEvalResolveTypeArg`, `comptimeEvalEvaluateDepth`, `comptimeEvalFloatBuiltin`, `ast_mod.astStoreNodeExtraChildAt/Count` | `self.store`, `self.registry`, `self.interner` | Guards on `ty.state==2` (fully resolved); returns null for any other name. | None [inference] |
| `comptimeEvalBuiltin` — `@sizeOf` | — | Extract first extra child as type arg, resolve, return `ty.size` as `ComptimeVal`. | (same as above) | same | `registry.types_items[t].size` | Always width_bits=0, sig=false (compile-time size is unsigned). | None [inference] |
| `comptimeEvalBuiltin` — `@alignOf` | — | Same pattern as `@sizeOf` but returns `ty.alignment`. | (same as above) | same | `registry.types_items[t].alignment` | Width=0, sig=false. | None [inference] |
| `comptimeEvalBuiltin` — `@offsetOf` / `@bitOffsetOf` | — | Require ≥2 extra children: resolve type arg (extra child 0), take extra child 1 as a literal field name. For a struct, look up the field; packed struct uses `packed_fields[fi].bit_offset` (`@bitOffsetOf` = bit offset, `@offsetOf` = bit offset/8), unpacked struct uses `fields[fi].offset` (`@bitOffsetOf` = offset*8). For a packed union, returns 0. | (same as above) | `typeRegistryGetStructFields`, `typeRegistryGetPackedBitFields`, `typeRegistryGetUnionFields` | `registry` field arrays, `store.string_values` | Field name must be an `AstKind.string_literal`; struct must be resolved (`state==2`). | None [inference] |
| `comptimeEvalBuiltin` — `@bitSizeOf` | — | Resolve type; base `ty.size*8`. Packed struct → `typeRegistryGetPackedTotalBits`; packed union → `typeRegistryGetPackedUnionTotalBits`; integer → `typeRegistryIntWidthBits`; enum → backing type's width bits; bool → 1. | (same as above) | `typeRegistryGetPackedTotalBits`, `typeRegistryGetPackedUnionTotalBits`, `typeRegistryIsInteger`, `typeRegistryIntWidthBits`, `typeRegistryEnumBackingType` | `registry.types_items` | Arbitrary-width and `enum(uN)`-backing aware. | None [inference] |
| `comptimeEvalBuiltin` — `@intCast` / `@as` | — | Resolve target type, evaluate inner expression. `@as` shares this arm (identical extra-child layout `[target_type, value]`). **Task 11U:** the arm is gated on `int_cast_id OR as_id`; an `@as` with a NON-integer target returns null BEFORE folding (`if (node.child_0 == self.as_id and !is_int_t) return null;`) because the arm yields an integer `ComptimeVal` that would enter the integer binop evaluator (guards `@as(f64,3)/2`). **Task 2:** an integer target is range-checked EXACTLY via `comptimeIntFitsType(v, t)` (the value's exact sign/magnitude against `w`/signedness — no 64-bit pattern heuristic, no masking); an out-of-range value emits `error[3000]` (once per node) and returns null (no fold; the post-phase diag check exits rc=2 before emission), message named after the builtin actually used (**Task B3 item 3**). A fitting value folds EXACTLY (the cast is a range check, not a truncation); non-integer `@intCast` targets keep the pre-Task-2 fold-the-operand behavior. | (same as above) | `comptimeEvalEvaluateDepth`, `comptimeEvalResolveTypeArg`, `comptimeIntFitsType`, `typeRegistryIsInteger` | `registry.types_items[t]`, `self.diag` | A `KIND_FLOAT` inner returns null (no float→int fold). Enum targets are not integers (`typeRegistryIsInteger` is false for `enum_type`) and take the non-integer path. | None [inference] |
| `comptimeEvalBuiltin` — `@floatCast` / `@intToFloat` | — | Delegates to `comptimeEvalFloatBuiltin`; on a value, returns `ComptimeVal{ v = ciZeroInt(), kind = KIND_FLOAT, float_bits = <f64 bit pattern> }` (Task 2 replaced the `WIDTH_FLOAT` `width_bits` sentinel). The f64 bits are transported through a pointer reinterpretation because Z98 `@bitCast` is integer-only. | (same as above) | `comptimeEvalFloatBuiltin` | local `f64`, `ComptimeVal` | A non-float target or non-foldable operand returns null (no fold). | None [inference] |
| `comptimeEvalFloat` | private | Float-valued sub-evaluator, deliberately SEPARATE from `comptimeEvalEvaluateDepth` so no float bit pattern can reach the integer binop/negate/bit_not/int_cast paths. Handles `float_literal` (`store.float_values`), `negate` (`-v`, sign-preserving for `-0.0`), `paren_expr`, nested `@floatCast`/`@intToFloat`, and const `ident_expr` chains (depth-16 guarded). Fix round 1: the `ident_expr` arm resolves the const's **declared** type and rounds an `f32` const through `f32` before returning, so `const S: f32 = 0.1` evaluates as `f32(0.1)`, not the raw `f64` literal. | `comptimeEvalFloatBuiltin`; recursively itself | `comptimeEvalFloat`, `comptimeEvalFloatBuiltin`, `comptimeEvalResolveTypeArg`, `symbolRegistryQualifiedLookup` | `store.float_values`, `store.nodes`, `store.identifiers`, `symbol_reg` | `node_idx==0` or `depth>=16` → null. A non-float node kind → null. | None [inference] |
| `comptimeEvalOperandSigned` | — | **DELETED in Task 2.** `@intToFloat` now converts the exact `ComptimeInt` value (`ciToF64`: limb accumulation with the stored sign), so no syntactic signedness classification is needed. (`comptimeEvalSignClass` survives only for the pre-Task-3 comparison fold; Task 3 deletes it.) | — | — | — | — | — |
| `comptimeEvalFloatBuiltin` | private | Evaluate one `@floatCast`/`@intToFloat` call to an `f64`. Resolves the target type arg (extra child 0; must be `TYPE_F32`/`TYPE_F64`); **Task 2:** `@intToFloat` evaluates extra child 1 with the integer evaluator and converts the exact `ComptimeInt` (`ciToF64`, a bool is 0/1), `@floatCast` uses `comptimeEvalFloat`; an `f32` target rounds through `f32`. | `comptimeEvalBuiltin`, `comptimeEvalFloat` | `comptimeEvalResolveTypeArg`, `comptimeEvalEvaluateDepth`, `ciToF64`, `comptimeEvalFloat`, `@intToFloat`/`@floatCast` | `registry`, `store`, local `f64`/`f32` | A non-float target, a `KIND_FLOAT` integer operand, or a non-foldable operand → null. Values above 2^53 may differ from a correctly-rounded conversion by 1 ulp (documented residual). | None [inference] |
| `comptimeEvalBuiltin` — `@isWindows` | — | Returns `self.host_is_windows ? 1 : 0`, width=1, sig=false. | (same as above) | none | `self.host_is_windows` | Value set by `main.zig` from `cli.target_is_windows`. | None [inference] |
| `comptimeEvalBinOp` | private | **Task 2:** evaluate binary arithmetic EXACTLY over the `ComptimeInt` limb core. Handles add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr; both operands must be `KIND_INT`. Returns null when the op declines: cap overflow (> 256 magnitude bits), division by zero, negative/oversized shift counts. | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs/rhs), `ciAdd`/`ciSub`/`ciMul`/`ciDivMod`/`ciBitAnd`/`ciBitOr`/`ciBitXor`/`ciShl`/`ciShr` | `store.nodes`, lhs/rhs `ComptimeVal` (`ComptimeInt`) | No wrap, no truncation: exact or unfoldable. Division/remainder truncate toward zero with the dividend's remainder sign (Zig `/`); `>>` is floor; bitwise ops use infinite two's-complement semantics. | None [inference] |
| `comptimeEvalBinOp` — div/mod | — | `ciDivMod`: binary long division over the 256 dividend bits with a 9-limb remainder; signs applied from `neg` (truncating toward zero). | (same as above) | `ciDivMod` | local 9-limb remainder, quotient/remainder `ComptimeInt` | Divisor zero → null. | None [inference] |
| `comptimeIntFitsType` | pub | **Task 2** (replaces `comptimeValFitsType`): exact range check of a `ComptimeInt` against an integer type — negative requires a signed target with `mag <= 2^(w-1)`; non-negative requires `mag < 2^(w-1)` (signed) or `mag < 2^w` (unsigned). `w == 0`/non-integer → false. | `comptimeEvalBuiltin` (`@intCast`/`@as` arm); tests | `ciPow2`, `ciMagCmp`, `typeRegistryIsInteger`, `typeRegistryIntWidthBits`, `typeRegistryIntIsSigned` | `registry` | The exact value distinguishes `-1` from `u64` max, so no syntactic sign-class heuristic is needed. | None [inference] |
| `comptimeValStoreU64` | pub | **Task 2** fold-table materialisation: bool → 0/1, float → `float_bits`, int → its two's-complement 64-bit pattern when the exact value fits `[i64 min, u64 max]`; otherwise null (the fold is not stored, lowering keeps the runtime path — Task 4 later turns this into `error[3000]`). | `main.zig` `phase_ComptimeEvaluation` | `ciPow2`, `ciMagCmp`, `ciToU64`, `ciIsZero` | `ComptimeVal` | Keeps the `U32ToU64Map` fold-table ABI unchanged until Task 5. | None [inference] |
| `comptimeEvalCompare` | private | **Task 9D.** Fold a comparison (`cmp_eq`/`cmp_ne`/`cmp_lt`/`cmp_le`/`cmp_gt`/`cmp_ge`) of two integer `ComptimeVal`s to a bool `ComptimeVal` (`kind = KIND_BOOL`). Evaluates both operands; a `KIND_FLOAT` operand returns null (float comparisons stay unfolded — a bounded residual). **Fix round 2:** signedness is PER OPERAND; the comparison is signed if either operand is signed. **Fix round 3:** if either operand's signedness is not DETERMINABLE (`comptimeEvalOperandCompareSigned` returns false), the whole comparison returns null (unfoldable) — no `cv.sig` guess. **Task 2:** because the representation is now a big int, the two folded operands are first converted back to the old 64-bit view by `ciValToOldBits` (bool → 0/1; int → two's-complement bits when `mag < 2^64`); an operand at/above `2^64` makes the comparison unfoldable, preserving the frozen pre-Task-2 verdicts. Task 3 replaces this whole path with the exact magnitude+sign comparison and deletes the sign class. | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs/rhs), `comptimeEvalOperandCompareSigned`, `ciValToOldBits` | `store.nodes`, lhs/rhs `ComptimeVal`, `local_consts` | Either operand unfoldable, or either signedness undeterminable → null. A `u64` const above i64 max compares UNSIGNED; a negative untyped operand forces signed even against a declared-unsigned peer. | None [inference] |
| `comptimeEvalLogical` | private | **Task 9D.** Fold `bool_and`/`bool_or`/`bool_not` on comptime bools. **Task 2:** an operand must be `kind == KIND_BOOL` (the old `width_bits == 1` test) and zero is `ciIsZero(v)`. `bool_and`/`bool_or` **short-circuit** in both directions: a decisive folded lhs (`0` for `and`, `1` for `or`) returns immediately WITHOUT evaluating the rhs; when the lhs does NOT fold, a decisive RHS still decides (`<runtime> or true` -> true, `<runtime> and false` -> false) — fix round 1; any other non-folding operand yields null. | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs, and for the rhs when not short-circuited), `ciBoolVal`, `ciIsZero` | `store.nodes`, lhs/rhs `ComptimeVal` | A non-bool folded operand, or an unfoldable operand that is not the decisive side, returns null. | None [inference] |
| `comptimeEvalOperandDeclaredSigned` | private | **Task 9D fix round 1.** The DECLARED integer signedness of a comparison operand, or null when it has no declared integer type (an untyped comptime_int literal/expression). Unwraps `paren_expr` (depth-32 guarded) then resolves: an `ident_expr` via the function-local const scope first (Task 9D Gap B) then the module symbol tables, whose var_decl annotation must be an integer type; `char_literal` → unsigned; `@intCast`/`@as` → the integer target's signedness. Unlike `comptimeEvalOperandSigned` it does NOT fall back to `cv.sig`. | `comptimeEvalCompare` | `comptimeEvalResolveTypeArg`, `type_resolver.localConstScopeLookup`, `symbolRegistryQualifiedLookup` | `local_consts`, `symbol_reg`, `store.nodes` | A `u64`/`u8` const returns false; a `iN` const returns true; an unannotated const / int literal / negate returns null. | None [inference] |
| `comptimeEvalOperandCompareSigned` | private | **Task 9D fix round 3 (ruling m1293 (b)).** One comparison operand's signedness, with a DETERMINABILITY result: the declared integer type wins for its OWN operand (`comptimeEvalOperandDeclaredSigned`), else the syntactic sign class (`negative` → signed, `non_negative` → unsigned), else the signedness is UNDETERMINABLE and the function returns false (the caller makes the comparison unfoldable). Never falls back to `cv.sig`. Writes the signedness through `out_signed: *bool`. | `comptimeEvalCompare` | `comptimeEvalOperandDeclaredSigned`, `comptimeEvalSignClass` | `local_consts`, `symbol_reg`, `store.nodes` | true + `out_signed` for a declared `iN`/`uN` or a definite-sign literal/`negate`/cast/`0 - X`; false for any other shape (e.g. an arithmetic expression over a const). | None [inference] |
| `comptimeEvalEvaluate` | pub | Main comptime evaluation entry point. Thin wrapper delegating to `comptimeEvalEvaluateDepth(node_idx, 0)`. | `main.zig` phase_ComptimeEvaluation; recursion; unit tests (test_semantic_bin.zig) | `comptimeEvalEvaluateDepth` | `store.nodes`, `store.int_values` | Entry point; all recursion flows through the depth-guarded variant. | None [inference] |
| `comptimeEvalEvaluateDepth` | private | Depth-guarded evaluation core. Twelve dispatch arms, including the `ident_expr` const-chain arm. | `comptimeEvalEvaluate`, recursively by itself/binop/cmp/logical/builtin | `comptimeEvalBinOp`, `comptimeEvalCompare`, `comptimeEvalLogical`, `comptimeEvalBuiltin`, `comptimeEvalEvaluateDepth` (recursive), `symbolRegistryQualifiedLookup`, `type_resolver.localConstScopeLookup` | `store.nodes`, `store.int_values`, `store.identifiers`, `symbol_reg`, `local_consts` | `node_idx==0` returns null. `depth >= 16` returns null (const-chain guard). Recursive for paren_expr, negate, bit_not, bool_not, binop, cmp, logical, builtin, and ident_expr chains. | None [inference] |
| `comptimeEvalEvaluate` — int_literal | — | **Task 2:** returns `ciFromU64(store.int_values[node.payload])` as `KIND_INT` (exact value; the old `width=0, sig=true` flags are gone). | (same as above) | `ciFromU64`, `ciIntVal` | `store.int_values` | A source literal above `2^64-1` is already lossy at lex/parse time (`astStoreIntValue` stores a u64); the cap governs arithmetic results. | None [inference] |
| `comptimeEvalEvaluate` — char_literal | — | **Task 2:** same as int_literal (`KIND_INT`, exact 0..255 value). | (same as above) | `ciFromU64`, `ciIntVal` | `store.int_values` | Character treated as its integer code point. | None [inference] |
| `comptimeEvalEvaluate` — bool_literal | — | **Task 2:** returns `ciBoolVal(flags & 1)` (`KIND_BOOL`). | (same as above) | `ciBoolVal` | `node.flags` | Flags bit 0 = value. | None [inference] |
| `comptimeEvalEvaluate` — negate/bit_not | — | **Task 2:** recursively evaluate inner; require `kind == KIND_INT`; `ciNeg` (sign flip, `-0` normalizes to `0`) or `ciBitNot` (`~x = -x - 1`, null on cap). | (same as above) | `comptimeEvalEvaluateDepth`, `ciNeg`, `ciBitNot` | inner `ComptimeVal` | A `KIND_FLOAT`/`KIND_BOOL` inner returns null. **Task 9D:** the `bool_not` arm (`comptimeEvalLogical`) requires `KIND_BOOL`. | None [inference] |
| `comptimeEvalEvaluate` — binop | — | Dispatches to `comptimeEvalBinOp` for add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr kinds. **Task 9D:** comparison kinds dispatch to `comptimeEvalCompare`; `bool_and`/`bool_or` dispatch to `comptimeEvalLogical`. | (same as above) | `comptimeEvalBinOp`, `comptimeEvalCompare`, `comptimeEvalLogical` | `node.kind` | Forwards `node_idx`, `node.kind`, and current depth to the handler. | None [inference] |
| `comptimeEvalEvaluate` — builtin_call | — | Dispatches to `comptimeEvalBuiltin` for the builtin_call kind. | (same as above) | `comptimeEvalBuiltin` | `node.kind` | 10 names foldable; every other name returns null. | None [inference] |
| `comptimeEvalEvaluate` — paren_expr | — | Unwraps parentheses: recurses on `node.child_0`. | (same as above) | `comptimeEvalEvaluateDepth` | `node.child_0` | Trivial pass-through. | None [inference] |
| `comptimeEvalEvaluate` — ident_expr | — | Const-chain resolution: **Task 9D** consults the enclosing function's `local_consts` scope (`type_resolver.localConstScopeLookup`) FIRST — a local `const` is a statement, not a module symbol, and shadows a module const of the same name — then looks up `name_id` via `symbolRegistryQualifiedLookup` across all module tables; if the symbol is a `const` (symbol `flags & 0x01 == 0`) with a non-empty init (`decl.child_1 != 0`), recurse into that init at `depth+1`. Returns null on `depth >= 16` (const-chain guard) or no matching const. | (same as above) | `comptimeEvalEvaluateDepth` (recursive), `symbolRegistryQualifiedLookup`, `type_resolver.localConstScopeLookup` | `store.identifiers`, `symbol_reg`, `store.nodes`, `local_consts` | Enables `const B: i32 = A + 5` to fold from `const A: i32 = 30`, and `const a: i32 = 1; if (a == 1)` to fold from the local `a` (Task 9D). | None [inference] |

---

## Data Flow

```
comptimeEvalEvaluate(node_idx)
  └─ comptimeEvalEvaluateDepth(node_idx, depth=0)     ← every recursion carries depth
       ├─ int_literal ──→ store.int_values[node.payload] ──→ ciFromU64 → ComptimeVal{kind=KIND_INT}
       ├─ char_literal ──→ store.int_values[node.payload] ──→ ciFromU64 → ComptimeVal{kind=KIND_INT}
       ├─ bool_literal ──→ node.flags & 1 ──→ ciBoolVal → ComptimeVal{kind=KIND_BOOL, v=0|1}
       ├─ negate ──→ EvaluateDepth(child_0) (KIND_INT) ──→ ciNeg (sign flip; -0 → 0)
       ├─ bit_not ──→ EvaluateDepth(child_0) (KIND_INT) ──→ ciBitNot (~x = -x - 1)
       ├─ bool_not ──→ EvaluateDepth(child_0) (KIND_BOOL) ──→ ciBoolVal(!ciIsZero(v))
       ├─ add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr ──→ comptimeEvalBinOp(node_idx, kind, depth)
       │     └─ EvaluateDepth(child_0) + EvaluateDepth(child_1); both must be KIND_INT
       │           └─ exact limb ops (ciAdd/ciSub/ciMul/ciDivMod/ciBitAnd/ciBitOr/ciBitXor/ciShl/ciShr)
       │           └─ div/mod: truncating toward zero; zero divisor → null
       │           └─ shl/shr: exact; negative or > 2^32 count → null; shr is floor
       │           └─ > 256 magnitude bits (cap) → null (exact-or-unfoldable, never wrap)
       ├─ cmp_eq/cmp_ne/cmp_lt/cmp_le/cmp_gt/cmp_ge ──→ comptimeEvalCompare(node_idx, kind, depth)
       │     └─ EvaluateDepth(child_0) + EvaluateDepth(child_1) → ciBoolVal(res) {kind=KIND_BOOL}
       │           └─ per-operand (comptimeEvalOperandCompareSigned): declared type wins, else
       │              sign class (negative → signed / non_negative → unsigned), else UNFOLDABLE
       │           └─ signed if EITHER operand is; a declared-unsigned peer does NOT mask `-1`; KIND_FLOAT → null
       │           └─ Task 2: operands converted back to the old 64-bit view by ciValToOldBits
       │              (≥ 2^64 → UNFOLDABLE; Task 3 replaces this path with magnitude+sign)
       ├─ bool_and/bool_or ──→ comptimeEvalLogical(node_idx, kind, depth)
       │     └─ short-circuit: decisive lhs returns without evaluating the rhs; a decisive RHS
       │        decides when the lhs does not fold (`<runtime> or true` / `<runtime> and false`)
       ├─ builtin_call ──→ comptimeEvalBuiltin(node, depth)
       │     ├─ @sizeOf: resolveTypeArg → ciFromU64(ty.size)
       │     ├─ @alignOf: resolveTypeArg → ciFromU64(ty.alignment)
       │     ├─ @offsetOf/@bitOffsetOf: resolveTypeArg + field name → ciFromU64(offset / bit offset)
       │     ├─ @bitSizeOf: resolveTypeArg → ciFromU64(size*8 / packed bits / int width / enum backing / 1)
       │     ├─ @intCast/@as: resolveTypeArg + EvaluateDepth(inner) → exact range check
       │     │     └─ comptimeIntFitsType(v, t); out of range → error[3000] + null
       │     │     └─ fitting → exact value, kind=KIND_INT (no masking/truncation)
       │     ├─ @floatCast/@intToFloat: comptimeEvalFloatBuiltin → f64 (f32 target rounds)
       │     │     └─ @intToFloat: EvaluateDepth(inner) → ciToF64(limbs) → f64
       │     │     └─ @floatCast: comptimeEvalFloat(inner) → f64
       │     │     └─ comptimeEvalFloat ident const → round through DECLARED type (f32)
       │     │     └─ success → ComptimeVal{kind=KIND_FLOAT, float_bits=<f64 pattern>}
       │     └─ @isWindows: ciBoolVal(host_is_windows)
       ├─ paren_expr ──→ EvaluateDepth(node.child_0)
       └─ ident_expr ──→ local_consts lookup FIRST (Task 9D; local const shadows module const)
             └─ else symbolRegistryQualifiedLookup(name_id) across module tables
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
  └─ interner.stringInternerIntern("@as")           → as_id (Task 11U)
  └─ interner.stringInternerIntern("@floatCast")    → float_cast_id
  └─ interner.stringInternerIntern("@intToFloat")   → int_to_float_id
  └─ interner.stringInternerIntern("@isWindows")    → is_windows_id
  └─ host_is_windows = false               (main.zig overrides from cli.target_is_windows)
  └─ local_consts = null                    (Task 9D; a function-scope caller sets it)
```

---

## Debugging

- **Null return** — any evaluation that returns `null` means the node is NOT stored in
  `ctx.comptime_values`, so LIR lowering falls back to a runtime form instead of an `int_const`.
  Null causes include: type argument unresolved (`ty.state != 2`), division/mod by zero, shift
  amount ≥ 64, unhandled node kind, `node_idx == 0`, a const chain deeper than 16, and any builtin
  not in the fold set. The semantic analyzer still assigns a result *type* to the node
  regardless.
- **Wrong width** — `@intCast` width comes from `typeRegistryIntWidthBits` for integer targets
  (arbitrary-width included) and `ty.size * 8` otherwise. An unresolved type or wrong size makes
  the mask/sign-extend wrong. Enum targets are not integers (`typeRegistryIsInteger` is false for
  `enum_type`), so they take the `ty.size * 8` path.
- **Signedness** — `@intCast` determines signedness from `typeRegistryIntIsSigned`, so
  arbitrary-width signed ints are handled; non-integer targets, enum targets included, are treated
  as unsigned.
- **Division by zero** — both `div` and `mod_op` return `null` when the divisor is zero. This is distinct from a runtime SIGFPE.
- **Shift guard** — **Task 2:** `shl`/`shr` are exact for counts `0..=2^32-1` (the practical domain); a negative or `> 2^32` count returns `null`, as does a `shl` whose exact result needs more than 256 magnitude bits. `shr` is a floor shift (arithmetic), so a negative value shifted far right yields `-1`.
- **Cap decline** — any op whose exact result needs more than 256 magnitude bits returns `null`; the old 64-bit wrapping/truncating results are gone (`2^64`, `2^100`, `1 << 200` magnitudes all exact).
- **Enum literal evaluation** — not handled in this module; enum literals are resolved by the semantic analyzer, not comptime evaluated here.

---

## Builtin Internment: 10 in comptime_eval

`comptimeEvalInit` interns **exactly ten** names — `@sizeOf`, `@alignOf`, `@offsetOf`,
`@bitSizeOf`, `@bitOffsetOf`, `@intCast`, `@as`, `@floatCast`, `@intToFloat`, `@isWindows` — into
`size_of_id`/`align_of_id`/`offset_of_id`/`bit_size_of_id`/`bit_offset_of_id`/`int_cast_id`/`as_id`/`float_cast_id`/`int_to_float_id`/`is_windows_id`.
(Task 11D added the two float-cast names; Task 11U added `@as`.) The **semantic analyzer** interns a 35-name set at
`semanticAnalyzerInit` (including a `_` stub → `_stub_0`), and the LIR lowerer independently
interns a 37-name set at `lowererInit`.

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
| `@floatCast` | ✓ (fold float operand) | ✓ (type-value cast) | ✓ (float_const fold / runtime float_cast) |
| `@intToFloat` | ✓ (fold integer operand) | ✓ (type-value cast) | ✓ (float_const fold / runtime int_to_float) |
| `@intToEnum` | — | ✓ (type-value cast) | ✓ |
| `@enumToInt` | — | ✓ | ✓ (lower arg directly) |
| `@as` | ✓ (fold; integer targets only, Task 11U) | ✓ (type-value cast) | ✓ (lower inner) |
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
  │      └─ success → comptimeValStoreU64(v) → ctx.comptime_values[node_idx] = <64-bit pattern>
  │      └─ success but int outside [i64 min, u64 max] → NOT stored (Task 2; Task 4 will reject)
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
  │     │        @floatCast/@intToFloat → emit float_const at the resolved f32/f64
  │     │        target (the map stores the f64 bit pattern; Z98 @bitCast is
  │     │        integer-only, so the lowerer reinterprets via a pointer)
  │     └─ MISS, then:
  ├─ @sizeOf/@alignOf/@offsetOf/@bitSizeOf/@bitOffsetOf → iceUnresolvedComptime (must have folded; ICE if not)
  ├─ @enumToInt               → "E", lower inner directly
  ├─ @bitCast                 → int_cast LIR to the resolved destination type
  └─ other builtins           → their runtime LIR forms
```

So the semantic analyzer never evaluates comptime constants — it only assigns result **types**.
The actual constant *value* computed by `comptimeEvalEvaluate` is consumed one phase later, in
LIR lowering, where the `comptime_values` map lookup turns a folded builtin into an `int_const`
LIR instruction (marker `CEV`), or — for `@floatCast`/`@intToFloat` — a `float_const` at the
resolved `f32`/`f64` target. A builtin the comptime evaluator cannot fold (`null`) is either a
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
  `@ptrCast`/`@enumToInt` etc. are invoked and return `null` after checking the interned IDs.
- Fold results are stored keyed by AST node index in `ctx.comptime_values` and consumed by the
  lowerer's `comptime_values` lookups; a `@sizeOf`/`@alignOf`/`@offsetOf`/`@bitSizeOf`/`@bitOffsetOf`
  that failed to fold (type unresolved at fold time) ICEs via `iceUnresolvedComptime` rather than
  degrade to a runtime call.
- A const chain longer than the depth-16 guard silently falls back to runtime arithmetic
  (guarded, not fixed) — no current repro or gate triggers it.

### ComptimeInt core + arithmetic (Task 2) — [updated: 2026-09-23]

`ComptimeVal` is a discriminated value: `{ v: ComptimeInt, kind: u8, float_bits: u64 }` with
`kind ∈ { KIND_INT = 0, KIND_BOOL = 1, KIND_FLOAT = 2 }`. `ComptimeInt` is `{ mag: [8]u32,
len: u8, neg: bool }` — 8 little-endian magnitude limbs (256 bits), `len` = one past the top
non-zero limb (0 = zero), `neg` = sign (never true when zero: `-0` normalizes to `0`).
Construction/materialisation helpers: `ciZeroInt`, `ciFromU64`, `ciPow2`, `ciSet`,
`ciNormalize`, `ciIsZero`, `ciMagCmp`, `ciToU64` (two's-complement pattern), `ciToF64`
(limb accumulation, sign applied), `ciValToOldBits` (the pre-Task-3 comparison adapter),
`ciIntVal`/`ciBoolVal`.

**Overflow policy (exact-or-unfoldable).** Every op is exact or declines (`null`/`false`) — no
wrap, no truncation, no saturation: add/sub/mul/bit ops/shl when the exact result needs more
than 256 magnitude bits; div/mod by zero; a negative or `> 2^32` shift count (the design's
out-of-domain rule; in practice counts ≥ 256 are the cap cases). Division and `%` truncate
toward zero (`7/2=3`, `-7/2=-3`, `7/-2=-3`, `7%-2=1`; `%` keeps the dividend's sign);
`>>` is a floor shift (`-7>>1=-4`, `-1>>1=-1`); `&`/`|`/`^` use infinite-precision
two's-complement semantics via `~m = -m - 1`; `~x = -x - 1` (Z98 keeps `~`; Zig 0.15.2 rejects
it — pre-existing divergence).

**Materialisation.** `comptimeIntFitsType(v, t)` is the exact range check (negative: signed
target and `mag ≤ 2^(w-1)`; non-negative: `mag < 2^(w-1)` signed / `mag < 2^w` unsigned).
`comptimeValStoreU64(v)` maps a fold to the fold table's 64-bit pattern (bool 0/1, float
`float_bits`, int two's-complement when in `[i64 min, u64 max]`); an out-of-window integer is
NOT stored (lowering keeps the runtime path; Task 4 will emit `error[3000]` at untyped
materialisation). The `U32ToU64Map` fold-table ABI itself is unchanged until Task 5.

**Fixtures.** `repro/mi_matrix/stdlib_comptime_bigint_arith_xmod` (29 values, every one
Zig-0.15.2-oracle-checked: 2^64/2^100/2^200 magnitudes, div/mod/bitwise/shift signs, u64 max,
in-range controls) and the standalone `repro/comptime_bigint_arith.z98`. Unit coverage:
`test_semantic_bin.zig` `testComptimeBigIntCore` (cap declines, div-by-zero, negative shift
counts, truncating-division/floor-shift/bit-op signs).

### Float folds (Task 11D)

`@floatCast`/`@intToFloat` on comptime-known operands fold to a `float_const`. Because a float
value must never reach the integer fold operators, the two float branches return a `ComptimeVal`
whose `kind` is `KIND_FLOAT` (Task 2; before that, the `WIDTH_FLOAT` `0xFFFFFFFF` sentinel in
`width_bits`). `comptimeEvalBinOp`, the `negate`/`bit_not` arms, and the `@intCast` arm all return
`null` when the operand's kind is not the one they expect, so a float bit pattern can
never be folded as integer arithmetic (`@intToFloat(f64,3) + @intToFloat(f64,4)` stays runtime).
Float evaluation lives entirely in the private `comptimeEvalFloat` / `comptimeEvalFloatBuiltin`
pair; `comptimeEvalEvaluateDepth` still has NO `float_literal` arm (adding one would leak IEEE bits
into the integer binop path).

- The lowerer emits `float_const` (not `int_const`) for these two callees, resolving the target
  type from the resolved-type table or the type argument. The f64 value is transported as its bit
  pattern in `ctx.comptime_values` (a `U32ToU64Map`) and reinterpreted at the consumer via a
  pointer cast (`@bitCast` is integer-only in Z98).
- Fold coverage: float literals, `negate` (negative float literals are `negate(float_literal)`;
  computed as `-v` so `-0.0` keeps its sign bit), parentheses, nested `@intToFloat`/`@floatCast`,
  and const `ident_expr` chains. Float arithmetic (`X + 1.0`) and float comparisons are still NOT
  folded.
- **Fix round 1 (2026-09-20):** the `ident_expr` arm rounds a typed const through its DECLARED
  type (`const S: f32 = 0.1` is `f32(0.1)`), so widening it to `f64` folds to `f64(f32(0.1))` and
  matches the runtime path; and `@intToFloat` derives the operand's signedness from its declared
  type / literal shape (`comptimeEvalOperandSigned`), so a `u64` const above `i64` max folds
  unsigned (`18446744073709551615` → `1.8446744073709552e19`, not `-1.0`).
- **Fix round 2 (2026-09-20):** `comptimeEvalOperandSigned` recursively unwraps `paren_expr`, so
  `@intToFloat(f64, (U))` / `((U))` fold unsigned too (the unparenthesized shape was fixed in
  round 1; the parenthesized one was not). `(I)` for `i64` stays signed; `(SRC)` for `f32` still
  rounds through `f32` (the float sub-evaluator already unwrapped parens).
- `@floatCast` operand-type validation remains absent (Task 11A §6.4); a non-float operand simply
  returns `null` (no fold, runtime lowering unchanged).

### `@as` folds (Task 11U) — [updated: 2026-09-21]

`@as` is now interned by `comptimeEvalInit` (`as_id`) and shares the `@intCast` fold/range-check
arm in `comptimeEvalBuiltin` — `@as` and `@intCast` have the exact same extra-child layout
(`[target_type, value]`). Because that shared arm yields an integer `ComptimeVal` which enters the
integer binop evaluator, the arm carries a mandatory **integer-target guard**
(`if (node.child_0 == self.as_id and !is_int_t) return null;`): an `@as` with a NON-integer target
must NOT fold, or float arithmetic silently miscompiles (`const A: f64 = @as(f64,3)/2` would fold
as integer `3/2` = `1`, not `1.5`). `@intCast`'s non-integer behavior is deliberately unchanged
(out of scope). The `@as` case is mirrored in `comptimeEvalOperandSigned` (defense-in-depth,
matching the existing `@intCast` precedent). An out-of-range `@as` integer target emits the same
`error[3000]` as `@intCast` (the shared diagnostic names the builtin actually used — `@as` vs
`@intCast`, since Task B3 item 3; the canonical classifier keys only on the error code). Fixtures: `stdlib_comptime_inttofloat_as_xmod` (positive
folds + runtime oracle), `stdlib_as_float_guard_xmod` (the guard control that traps on an
unguarded arm), and the standalone `repro/comptime_inttofloat_as.z98`.

### 64-bit target range check + diagnostic wording/location (Task B3 items 2–4) — [updated: 2026-09-21]

- **Item 2 (range-check 64-bit targets).** `comptimeValFitsType` used to `return true` for every
  `wb >= 64` target, so `@intCast(u64, -1)` / `@as(u64, -1)` folded to `18446744073709551615` and
  `@intCast(i64, @as(u64, 18446744073709551615))` to `-1` — all invalid Zig. The 64-bit bit pattern
  cannot distinguish a negative source from a large non-negative literal (both have the top bit set),
  so the new `comptimeEvalSignClass(self, operand_idx, depth)` classifies the **operand node**
  syntactically: `int_literal`/`char_literal`/`bool_literal` → non-negative; `negate` → negative;
  an `ident_expr`/`@as`/`@intCast` by its declared/target integer type, recursing into a const
  initializer when no declared type is present; any unrecognized shape → `unknown` (never rejected,
  so valid programs are not over-rejected). **Task 9D fix round 1:** the classifier consults the
  function-local const scope first (mirroring the fold's Gap B); since `local_consts` is only set
  by the sema probe, the global `phase_ComptimeEvaluation` fold is unaffected. A definitely-negative source with the top bit set is
  rejected for an unsigned target; a definitely-non-negative source with the top bit set is rejected
  for a signed target. The type_resolver's i64 twin `intValueFitsType` gets the mirror classifier
  `evalConstSignClass` (used by the enum-initializer `@as`/`@intCast` fold). Fixtures:
  `comptime_cast64_range_reject_xmod` (GREEN, `error[3000]`),
  `enum_init_cast64_range_reject_xmod` (`error[3055]`), the positive
  `stdlib_comptime_cast64_range_xmod`, and the standalone `repro/comptime_cast64_range.z98`.
- **Item 3 (diagnostic wording).** The `@intCast`/`@as` reject arm is shared, so the message now
  selects `@intCast value does not fit the target type` or `@as value does not fit the target type`
  from `node.child_0` instead of always naming `@intCast`.
- **Item 4 (location).** The reject still passes `source_file_id = 0` (message printed without a
  `file:line`). This is deliberate and documented: `phase_ComptimeEvaluation` is a single global
  node sweep with no per-module context, and the AST store carries no node→source_file map, so a
  real location requires a structural change (per-module node ranges or a node→module table). The
  node span is still recorded on the diagnostic.

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

6. **Float arithmetic/comparisons do not fold** (`comptime_eval.zig`): only `@floatCast`/`@intToFloat`
   with comptime-known operands fold. `X + 1.0` and float comparisons fall back to runtime (the
   `kind == KIND_FLOAT` gate keeps the bit patterns out of the integer binop path; `comptimeEvalCompare`
   returns null on a non-int operand). Deliberate scope limit of Task 11D; the float-comparison
   residual is restated by Task 9D as a bounded divergence. **Task 9D** folds integer comparisons and
   the bool logical ops (see above).

7. **`@floatCast` operand-type validation absent**: sema accepts a non-float source (Task 11A §6.4).
   The fold branch returns `null` for a non-float operand rather than diagnosing; no new diagnostic
   was added in Task 11D.

8. **Negative zero is preserved in the sub-evaluator but not yet in emitted C** (`comptime_eval.zig`
   + `util/format.zig`): `comptimeEvalFloat`'s `negate` computes `-v`, so `-0.0` keeps its sign bit
   in the folded value; however `formatF64` (`sf/src/util/format.zig:99`) renders any zero as `0`,
   so `@floatCast(f64, -0.0)` still emits `(double)(0)`. Fixing the emitter's negative-zero rendering
   is out of Task 11D fix-round-1 scope (the finding targeted the sub-evaluator); no fixture uses
   `-0.0`.

9. **Comparison fold declines arithmetic operands (Task 9D fix round 3, ruling m1293 (b) — bounded
   divergence).** `comptimeEvalCompare` makes a comparison unfoldable when an operand's signedness
   cannot be derived from a declared type, a literal's sign / `negate`, or an explicit
   `@intCast`/`@as` target. Consequently valid Zig such as `(umax - 1) > 0`, `0 < (umax - 1)`,
   `(umax - 1) > zero`, `umax > (0 + 0)` and `(a + 1) == 2` is rejected `error[3059]` in a no-`else`
   value `if` (Zig computes them at arbitrary precision). Cases whose Zig outcome is also a rejection
   (`(umax - 1) < 0`, `(u - 300) < 0`) match. Fixture:
   `repro/mi_matrix/comptime_compare_diverge_reject_xmod` (+ NOTES.md); pinned in `EXPECTED_FAIL.md`
   v199. This is deliberate and deterministic — `cv.sig` is never used to guess.

