# 04 — Compile-Time Evaluation [updated: 2026-09-23 — Task 4 fix round (review Importants 1–4): (1) `var` declarations with arithmetic/unary inits are now range-checked (`checkDeclInitFits` folds the init on demand; `var y: u32 = 0 - 1;` was silent, ran 4294967295) while bare positive literals keep the warning[3000]+truncate decl path; (2) bare-literal parameters/returns are checked (`checkArgReturnIntFits` at the four call-arg loops + `return_stmt`; `f(300)`/`return 300;` ran 44); (3) unannotated module consts take the value-based slot type (`semanticAnalyzerResolveModuleVarDecl` override; `const X = 2000000000+1000000000;` is a u32 global, was an `int` truncation); (4) optional-payload targets are unwrapped before the fit check (`scalarTargetOf`; `takeOpt8(@as(i32,300))` / `var o: ?u8 = @as(i32,300);` were accepted and emitted gcc-invalid C). Coverage fixture `stdlib_comptime_intcast_nonint_mask_xmod` pins the restored non-integer `@intCast` masking; reject fixture now 12 sites; stdlib pin 221 → 222; fixed point `b4f999b5…` → `a8ea33f75f239f2255adeb8cc2426a7c`] [updated: 2026-09-23 — Task 4 (coercion into typed slots): the fold table is now the exact `ComptimeFoldTable` (node→slot `U32ToU32Map` + a dense `ComptimeVal` array; `comptimeFoldTableInit`/`comptimeFoldTablePut`/`comptimeFoldTableGet`), replacing the `U32ToU64Map` + `comptimeValStoreU64` production ABI (`comptimeValStoreU64` stays as a test helper); `comptimeIntFitsType` is now registry-based and gains `comptimeIntFits64`/`comptimeIntMaterialize`/`comptimeIntUntypedType`; the ident fold declines a name whose declared integer type cannot hold the initializer (Task 1 §5.3, `comptimeEvalDeclFits`); non-integer `@intCast` targets restore the pre-Task-2 `size*8` masking (carry item). Lowering range-checks every materialisation (`lowerFoldedIntConst`, `checkFoldedIntFits`, `reportComptimeIntFits`) and `type_resolver.evalConstU32Full` folds array sizes exactly (`0..0xFFFFFFFE`). Fixtures `stdlib_comptime_coerce_typed_slots_xmod` (stdlib pin 220 → 221) + `comptime_coerce_reject_xmod` + `array_size_negative_reject_xmod` + standalone repros; fixed point `f533e834…` → `b4f999b57e4516c2a2c305e8660d5c44`] [updated: 2026-09-23 — Task 3 fix round 2 (Important): the `bit_not` peer fit added in fix round 1 is REVERTED — `~` is exempt (Z98's exact `-x - 1` vs sema's wrapped complement), so valid Zig-equal `if ((~u) != 0) ...` shapes accept again (oracle `400 401`); `testComptimeCompareCore` is wired into `main()`; documented `~`-on-unsigned divergence in Known Issues 9] [updated: 2026-09-23 — Task 3 fix round 1 (Critical + 2 Important): the `if_expr` comptime-fold sub-path is now terminator-aware (`lower.zig`; a stored condition on `if (true) return 5;` no longer materialises the return as a value — see doc 07), the unary `-`/`~` folds apply the same peer fit as the binops (`-umax` on u64 declines), and `comptimeEvalOperandType` recurses into an UNANNOTATED const's initializer (`const c = @as(u8, 200)` types `c` as u8); `ciCmp` became `pub` and `test_semantic_bin.zig` gains `testComptimeCompareCore`; reject fixture now 9 sites, stdlib pin 219 → 220, fixed point `88c6b4c9…` → `04272a883bb00c7afc3364660b2adc4d`] [updated: 2026-09-23 — Task 3 (signedness-free comparisons + logical folds): `comptimeEvalCompare` now compares the exact magnitude+sign of the two `ComptimeInt`s (new `ciCmp`; `-0` is normalized, bools compare as 0/1) with no sign class, no declared-type lookup, and no `ciValToOldBits` 64-bit bridge; `comptimeEvalSignClass`/`SignClass`/`comptimeEvalOperandCompareSigned`/`comptimeEvalOperandDeclaredSigned` and the `0 - X` special case are DELETED. The arithmetic fold gains the Task 1 §5.4 operand peer-fit rule: the peer type P is a declared operand's integer type (both declared → wider wins, ties keep lhs); each UNTYPED operand's exact value and the exact result must fit P, else the fold declines — this keeps Zig-rejected `(u - 300) < 0` (u: u8) and `(0 - umax) < 0` rejected. `main.zig` `phase_ComptimeEvaluation` additionally folds and stores the condition of every capture-free no-`else` value `if` (Task 1 §7), so lowering's `if_expr` `ie_fold` path elides the untaken branch and module-scope conditions (step-0 S3/S5/E12) are runtime-equal to Zig. Fixtures `stdlib_comptime_compare_xmod` (22 values, Zig-0.15.2-oracle-checked) + `comptime_compare_reject_xmod` + standalone `repro/comptime_compare.z98`; fixed point `e0efd631…` → `27d3c382…` → `88c6b4c9b8b0ce154385f6c382b251ea`] [updated: 2026-09-23 — Task 2 (ComptimeInt core + arithmetic): `ComptimeVal` is now `{ v: ComptimeInt, kind: u8, float_bits: u64 }` with `ComptimeInt { mag: [8]u32, len: u8, neg: bool }` (256-bit fixed-cap little-endian magnitude, exact-or-unfoldable) and kinds `KIND_INT`/`KIND_BOOL`/`KIND_FLOAT` replacing `width_bits`/`sig`/`WIDTH_FLOAT`. add/sub/mul/div/mod/negate/bitand/bitor/bitxor/bitnot/shl/shr are exact limb ops (`ci*`, all `pub`), Zig-truncating division with floor `>>` and infinite two's-complement bitwise semantics; results needing > 256 magnitude bits, division by zero, and negative/oversized shift counts return null (unfoldable). `comptimeValFitsType` became the exact `comptimeIntFitsType`; `@intCast`/`@as` fold the exact value after an exact range check (messages/location preserved); `@intToFloat` converts from limbs (no `comptimeEvalOperandSigned`); comparison/logical folds keep their pre-Task-3 semantics via `kind` and a 64-bit `ciValToOldBits` adapter; the fold table stays `U32ToU64Map` until Task 5 (`comptimeValStoreU64` materialises bool/float/int, skipping ints outside `[i64 min, u64 max]`). Fixture `repro/mi_matrix/stdlib_comptime_bigint_arith_xmod` (Zig-0.15.2-oracle-checked) + standalone `repro/comptime_bigint_arith.z98`; fixed point `cd38f316…` → `e4246b19…` → `e0efd631…` (the last after the review fix that makes `ciShl` decline multi-word cap overflows whose shifted limbs would be dropped)] [updated: 2026-09-23 — Task 9D fix round 3 (operator ruling m1293 (b)): the comparison fold is now CONSERVATIVE. An operand's signedness is taken only from a declared integer type, a literal's own sign / `negate`, or an explicit `@intCast`/`@as` target; any other shape — e.g. an arithmetic expression over a const — makes the whole comparison UNFOLDABLE (null). `comptimeEvalOperandCompareSigned` now reports determinability through an out-param and never falls back to `cv.sig`; `comptimeEvalSignClass` classifies `0 - X` as the negation of X (the one arithmetic shape with a definite sign). Bounded divergence, documented in `repro/mi_matrix/comptime_compare_diverge_reject_xmod` and `EXPECTED_FAIL.md` v199: Zig evaluates `(umax - 1) > 0`, `umax > (0 + 0)`, `(a + 1) == 2`, etc. at arbitrary precision and accepts; Z98 declines and rejects `error[3059]`] [updated: 2026-09-23 — Task 9D fix round 2: the comparison signedness is computed PER OPERAND (new `comptimeEvalOperandCompareSigned`): a declared integer type wins for its own operand, otherwise the syntactic sign class decides, falling back to `cv.sig` for an unrecognized untyped shape. This keeps a declared-unsigned operand from masking a negative counterpart — `const u: u8 = 200; if (u > -1) 1;` (and `-1 < u`, `u > (0 - 1)`) is accepted and true, while `const umax: u64 = …; if (umax < 0)` stays unsigned/false and rejected. Fix round 1's `have_decl` gate that suppressed the negative sign class is removed] [updated: 2026-09-23 — Task 9D fix round 1: the comparison fold's signedness is now the operands' DECLARED integer types (new private `comptimeEvalOperandDeclaredSigned`, which consults function-local consts first) instead of `l.sig or r.sig`; with no declared type on either side a definite syntactic negative still makes it signed (`comptimeEvalSignClass`). This fixes a `u64` const above i64 max comparing signed (`umax > 0` was rejected; `umax < 0` folded true and was accepted with an uninitialised result). `comptimeEvalLogical` now also handles a decisive RHS when the lhs does not fold (`<runtime> or true` -> true, `<runtime> and false` -> false), so those comptime-known-true conditions are accepted; `comptimeEvalSignClass` consults the local const scope too (only set by the sema probe, so the global fold is unaffected)] [updated: 2026-09-23 — Task 9D: the fold now handles comparisons (`cmp_eq`/`cmp_ne`/`cmp_lt`/`cmp_le`/`cmp_gt`/`cmp_ge`) via the new private `comptimeEvalCompare` (signedness mirrors `comptimeEvalBinOp`'s div/mod sign handling: signed if either operand is signed, values compared as sign-extended i64 / zero-extended u64; a `WIDTH_FLOAT` operand stays unfolded — a bounded residual) and logical `bool_and`/`bool_or`/`bool_not` via the new private `comptimeEvalLogical` (`and`/`or` **short-circuit**: a decisive lhs returns without evaluating the rhs, so `true or <runtime>` folds true and `false and <runtime>` folds false). `ComptimeEval` gains `local_consts: ?*type_resolver.LocalConstScope` (null by default); the `ident_expr` arm consults it before the module symbol registry so a function-local `const` participates in the fold (Gap B), and `semanticAnalyzerConditionIsComptimeTrue` sets it from `self.local_consts`. This makes a comptime-known-true comparison condition permit a no-`else` value `if`, matching Zig] [updated: 2026-09-21 — Task B3 items 2/3/4: `comptimeValFitsType` no longer blanket-accepts a `wb >= 64` target; it classifies the operand syntactically (`comptimeEvalSignClass`, a tri-state) so a definitely-negative source cannot fit an unsigned 64-bit target and a definitely-non-negative source above i64 max cannot fit a signed one (the bit pattern alone cannot distinguish `-1` from `18446744073709551615`); the shared `@intCast`/`@as` reject message now names the builtin actually used; the reject still uses `source_file_id = 0` (documented: the global comptime node sweep has no module context and the AST store has no node→file map, so a real location needs a structural change)] [updated: 2026-09-21 — Task 11U: `@as` is interned (`as_id`, 10-name foldable set) and shares the `@intCast` fold/range-check arm in `comptimeEvalBuiltin`, with a mandatory integer-target guard so a non-integer `@as` never folds to an integer `ComptimeVal` (which would miscompile float arithmetic, e.g. `@as(f64,3)/2`); the `@as` case is mirrored in `comptimeEvalOperandSigned`] [updated: 2026-09-21 — Task 11S (c): `ComptimeEval` gains a `diag` field and the `@intCast` arm range-checks an integer target via the new `comptimeValFitsType` helper, emitting `error[3000]` and refusing to fold an out-of-range comptime cast (previously it masked to the target width)] [updated: 2026-09-20 — Task 11D: 9-name foldable-builtin set (adds `@floatCast`/`@intToFloat`), the private float sub-evaluator, and the `WIDTH_FLOAT` float-fold sentinel; earlier: refreshed against the 7-name set (`@sizeOf`/`@alignOf`/`@offsetOf`/`@bitOffsetOf`/`@bitSizeOf`/`@intCast`/`@isWindows`), arbitrary-width/enum-backing folds, and the CLI-driven `host_is_windows`]

> Covers: `comptime_eval.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ComptimeVal` fields | 3 | Task 2: `v` (`ComptimeInt`), `kind` (`KIND_INT`/`KIND_BOOL`/`KIND_FLOAT`), `float_bits` (f64 pattern, valid iff `kind == KIND_FLOAT`). The old `bits`/`width_bits`/`sig` triple and the `WIDTH_FLOAT` sentinel are gone. |
| `ComptimeInt` | 3 fields + cap | Task 2: `mag: [8]u32` (little-endian magnitude limbs), `len: u8` (0 = zero; one past the top non-zero limb), `neg: bool` (`false` when zero). 8 limbs = 256 magnitude bits; every op is exact or declines. |
| Core limb ops (`ci*`) | 31 | Task 2 + Task 3, all `pub`: zero/from-u64/pow2/set/normalize/isZero/magCmp/cmp/toU64/toF64/intVal/boolVal; magnitude and/or/xor/not/addInto/subInto/addOne/subOne; add/sub/neg/mul/divMod/bitAnd/bitOr/bitXor/bitNot/shl/shr. Task 3 deleted `ciValToOldBits` and added `ciCmp`. |
| `ComptimeEval` fields | 17 | registry, store, interner, symbol_reg, size_of_id, align_of_id, offset_of_id, bit_size_of_id, bit_offset_of_id, int_cast_id, as_id (Task 11U), float_cast_id, int_to_float_id, is_windows_id, host_is_windows, local_consts (Task 9D; `?*type_resolver.LocalConstScope`, null by default), diag (Task 11S) |
| Builtin intrinsics (comptime-foldable) | 10 | @sizeOf, @alignOf, @offsetOf, @bitOffsetOf, @bitSizeOf, @intCast, @as (Task 11U; integer targets only), @floatCast, @intToFloat, @isWindows — the ONLY names interned by `comptimeEvalInit` |
| Builtin names interned by sema | 35 | `@ptrCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@volatileCast`, `@bitCast`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@enumToInt`, `@as`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf` + runtime/console/async builtins (+ `_` stub) — type assignment only |
| Builtin names interned by lowerer | 37 | `@intCast`, `@intToFloat`, `print`, `@ptrCast`, `@volatileCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@enumToInt`, `@intToEnum`, `@as`, `@bitCast`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@cVaStart`, `@cVaArg`, `@cVaEnd` + runtime/console/async builtins — LIR dispatch only |
| Non-foldable builtins | 25 | every other interned builtin name (pointer/cast/introspection/runtime/console/async) — comptime eval returns `null`, handled by sema type rules + runtime LIR |
| Binary ops evaluated | 10 | add, sub, mul, div, mod, bit_and, bit_or, bit_xor, shl, shr |
| Unary ops evaluated | 3 | negate, bit_not, bool_not (Task 9D) |
| Comparison ops evaluated | 6 | cmp_eq, cmp_ne, cmp_lt, cmp_le, cmp_gt, cmp_ge (Task 9D; **Task 3:** exact signedness-free magnitude+sign over the big-int operands; bools compare as 0/1; a `KIND_FLOAT` operand declines) |
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
| `comptimeEvalBuiltin` — `@intCast` / `@as` | — | Resolve target type, evaluate inner expression. `@as` shares this arm (identical extra-child layout `[target_type, value]`). **Task 11U:** the arm is gated on `int_cast_id OR as_id`; an `@as` with a NON-integer target returns null BEFORE folding (`if (node.child_0 == self.as_id and !is_int_t) return null;`) because the arm yields an integer `ComptimeVal` that would enter the integer binop evaluator (guards `@as(f64,3)/2`). **Task 2:** an integer target is range-checked EXACTLY via `comptimeIntFitsType(v, t)` (the value's exact sign/magnitude against `w`/signedness — no 64-bit pattern heuristic, no masking); an out-of-range value emits `error[3000]` (once per node) and returns null (no fold; the post-phase diag check exits rc=2 before emission), message named after the builtin actually used (**Task B3 item 3**). A fitting value folds EXACTLY (the cast is a range check, not a truncation); a non-integer `@intCast` target restores the pre-Task-2 masking (Task 4 carry item): the folded bits are reduced to the target's `size * 8` low bits (e.g. `@intCast(f32, 4294967596)` folds 300), and `@as` with a non-integer target still declines. | (same as above) | `comptimeEvalEvaluateDepth`, `comptimeEvalResolveTypeArg`, `comptimeIntFitsType`, `typeRegistryIsInteger`, `ciToU64`/`ciFromU64` | `registry.types_items[t]`, `self.diag` | A `KIND_FLOAT` inner returns null (no float→int fold). Enum targets are not integers (`typeRegistryIsInteger` is false for `enum_type`) and take the non-integer path. | None [inference] |
| `comptimeEvalBuiltin` — `@floatCast` / `@intToFloat` | — | Delegates to `comptimeEvalFloatBuiltin`; on a value, returns `ComptimeVal{ v = ciZeroInt(), kind = KIND_FLOAT, float_bits = <f64 bit pattern> }` (Task 2 replaced the `WIDTH_FLOAT` `width_bits` sentinel). The f64 bits are transported through a pointer reinterpretation because Z98 `@bitCast` is integer-only. | (same as above) | `comptimeEvalFloatBuiltin` | local `f64`, `ComptimeVal` | A non-float target or non-foldable operand returns null (no fold). | None [inference] |
| `comptimeEvalFloat` | private | Float-valued sub-evaluator, deliberately SEPARATE from `comptimeEvalEvaluateDepth` so no float bit pattern can reach the integer binop/negate/bit_not/int_cast paths. Handles `float_literal` (`store.float_values`), `negate` (`-v`, sign-preserving for `-0.0`), `paren_expr`, nested `@floatCast`/`@intToFloat`, and const `ident_expr` chains (depth-16 guarded). Fix round 1: the `ident_expr` arm resolves the const's **declared** type and rounds an `f32` const through `f32` before returning, so `const S: f32 = 0.1` evaluates as `f32(0.1)`, not the raw `f64` literal. | `comptimeEvalFloatBuiltin`; recursively itself | `comptimeEvalFloat`, `comptimeEvalFloatBuiltin`, `comptimeEvalResolveTypeArg`, `symbolRegistryQualifiedLookup` | `store.float_values`, `store.nodes`, `store.identifiers`, `symbol_reg` | `node_idx==0` or `depth>=16` → null. A non-float node kind → null. | None [inference] |
| `comptimeEvalOperandSigned` | — | **DELETED in Task 2.** `@intToFloat` now converts the exact `ComptimeInt` value (`ciToF64`: limb accumulation with the stored sign), so no syntactic signedness classification is needed. (`comptimeEvalSignClass` and the rest of the sign-class machinery were deleted in Task 3.) | — | — | — | — | — |
| `comptimeEvalFloatBuiltin` | private | Evaluate one `@floatCast`/`@intToFloat` call to an `f64`. Resolves the target type arg (extra child 0; must be `TYPE_F32`/`TYPE_F64`); **Task 2:** `@intToFloat` evaluates extra child 1 with the integer evaluator and converts the exact `ComptimeInt` (`ciToF64`, a bool is 0/1), `@floatCast` uses `comptimeEvalFloat`; an `f32` target rounds through `f32`. | `comptimeEvalBuiltin`, `comptimeEvalFloat` | `comptimeEvalResolveTypeArg`, `comptimeEvalEvaluateDepth`, `ciToF64`, `comptimeEvalFloat`, `@intToFloat`/`@floatCast` | `registry`, `store`, local `f64`/`f32` | A non-float target, a `KIND_FLOAT` integer operand, or a non-foldable operand → null. Values above 2^53 may differ from a correctly-rounded conversion by 1 ulp (documented residual). | None [inference] |
| `comptimeEvalBuiltin` — `@isWindows` | — | Returns `self.host_is_windows ? 1 : 0`, width=1, sig=false. | (same as above) | none | `self.host_is_windows` | Value set by `main.zig` from `cli.target_is_windows`. | None [inference] |
| `comptimeEvalBinOp` | private | **Task 2:** evaluate binary arithmetic EXACTLY over the `ComptimeInt` limb core. Handles add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr; both operands must be `KIND_INT`. Returns null when the op declines: cap overflow (> 256 magnitude bits), division by zero, negative/oversized shift counts. **Task 3 (Task 1 §5.4):** the operand peer-fit rule — compute the operand peer type P via `comptimeEvalOperandType`/`comptimeEvalWiderIntType` (a declared operand's integer type; both declared → wider wins, ties keep lhs); each UNTYPED operand's exact value and the exact result must fit P via `comptimeIntFitsType`, else the fold declines. Comparisons are exempt. | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs/rhs), `comptimeEvalOperandType`, `comptimeEvalWiderIntType`, `comptimeIntFitsType`, `ciAdd`/`ciSub`/`ciMul`/`ciDivMod`/`ciBitAnd`/`ciBitOr`/`ciBitXor`/`ciShl`/`ciShr` | `store.nodes`, lhs/rhs `ComptimeVal` (`ComptimeInt`) | No wrap, no truncation: exact or unfoldable. Division/remainder truncate toward zero with the dividend's remainder sign (Zig `/`); `>>` is floor; bitwise ops use infinite two's-complement semantics. | None [inference] |
| `comptimeEvalBinOp` — div/mod | — | `ciDivMod`: binary long division over the 256 dividend bits with a 9-limb remainder; signs applied from `neg` (truncating toward zero). | (same as above) | `ciDivMod` | local 9-limb remainder, quotient/remainder `ComptimeInt` | Divisor zero → null. | None [inference] |
| `comptimeIntFitsType` | pub | **Task 2** (replaces `comptimeValFitsType`): exact range check of a `ComptimeInt` against an integer type — negative requires a signed target with `mag <= 2^(w-1)`; non-negative requires `mag < 2^(w-1)` (signed) or `mag < 2^w` (unsigned). `w == 0`/non-integer/out-of-range tid → false. **Task 4:** takes `registry: *TypeRegistry` (Task 1 §5.1) so the lowerer can call it without constructing an evaluator. | `comptimeEvalBuiltin` (`@intCast`/`@as` arm), `comptimeEvalBinOp`, `comptimeEvalDeclFits`; `lower.zig` `lowerFoldedIntConst`/`checkFoldedIntFits` | `ciPow2`, `ciMagCmp`, `typeRegistryIsInteger`, `typeRegistryIntWidthBits`, `typeRegistryIntIsSigned` | `registry` | The exact value distinguishes `-1` from `u64` max, so no syntactic sign-class heuristic is needed. | None [inference] |
| `comptimeIntMaterialize` / `comptimeIntFits64` / `comptimeIntUntypedType` | pub | **Task 4** (Task 1 §5.1/§5.2): `comptimeIntMaterialize(v)` = `ciToU64(v)` (two's-complement pattern after a fit check); `comptimeIntFits64(v)` = exact value in `[i64 min, u64 max]`; `comptimeIntUntypedType(v)` = value-based materialisation type for an untyped slot (`I32`/`U32`/`I64`/`U64`, negative → signed; null beyond the 64-bit window). | `comptimeValStoreU64`; `lower.zig` `lowerFoldedIntConst`; `semantic_analyzer.zig` var_decl untyped slot selection; tests | `ciPow2`, `ciMagCmp`, `ciToU64` | `ComptimeInt` | No registry needed (fixed primitive ids). | None [inference] |
| `ComptimeFoldTable` (+ `comptimeFoldTableInit`/`Put`/`Get`) | pub | **Task 4** (Task 1 §6.2): the exact fold table — `slots: U32ToU32Map` (node → dense slot) + a growable `[*]ComptimeVal` array in the module arena. `Put` overwrites an existing node's slot or appends; `Get` validates the slot before reading. Replaces the `U32ToU64Map` + `comptimeValStoreU64` production ABI, so a fold outside `[i64 min, u64 max]` is materialisable at the lowering site (rejected there) instead of vanishing. | `main.zig` `phase_ComptimeEvaluation` (Put), `lower.zig` (Get) | `hash_mod.u32ToU32Map*`, `alloc_mod.sandAlloc` | module arena (`ctx.comptime_folds`) | A private `comptimeFoldTableGrow` doubles the value array (16 → 2n, 8-byte alignment). | None [inference] |
| `comptimeValStoreU64` | pub | **Task 2** fold-table materialisation kept as a TEST HELPER only (Task 4 moved production to `ComptimeFoldTable`): bool → 0/1, float → `float_bits`, int → its two's-complement 64-bit pattern when `comptimeIntFits64`; otherwise null. | tests (`test_semantic_bin.zig`) | `comptimeIntFits64`, `ciToU64`, `ciIsZero` | `ComptimeVal` | No production caller after Task 4. | None [inference] |
| `comptimeEvalDeclFits` | private | **Task 4** (Task 1 §5.3 typed-slot fold rule): `false` when a name's declaration has a declared integer type that cannot hold the exact initializer value, so the ident fold declines (`const u: u8 = 300;` materialises 44 at runtime, so folding 300 would invent a value). Non-int values / absent / non-integer declared types accept. | `comptimeEvalEvaluateDepth` — ident_expr arm (local-const and module-symbol branches) | `comptimeEvalResolveTypeArg`, `comptimeIntFitsType`, `typeRegistryIsInteger` | `store.nodes` | Only the VALUE kind `KIND_INT` is checked. | None [inference] |
| `comptimeEvalCompare` | private | **Task 9D; Task 3 rewrite.** Fold a comparison (`cmp_eq`/`cmp_ne`/`cmp_lt`/`cmp_le`/`cmp_gt`/`cmp_ge`) of two integer/bool `ComptimeVal`s to a bool `ComptimeVal` (`kind = KIND_BOOL`) using the exact signedness-free magnitude+sign order (`ciCmp`: equal signs → `ciMagCmp` negated when negative; differing signs → the negative one is smaller; `-0` is normalized to `0`, bools are 0/1). There is no signedness/sign-class/declared-type inference and no `ciValToOldBits` adapter: the Task 9D bounded divergence is retired (`(umax - 1) > 0` etc. fold exactly like Zig). Comparisons are deliberately EXEMPT from the arithmetic peer-fit rule (the oracle accepts `const u: u8 = 200; u > -1` → true and `u > 300` → false). A `KIND_FLOAT` operands returns null (float comparisons stay unfolded — a bounded residual). | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs/rhs), `ciCmp`, `ciBoolVal` | `store.nodes`, lhs/rhs `ComptimeVal` | Either operand unfoldable, or a float operand → null. No declared type, no sign class, no 64-bit window. | None [inference] |
| `comptimeEvalLogical` | private | **Task 9D.** Fold `bool_and`/`bool_or`/`bool_not` on comptime bools. **Task 2:** an operand must be `kind == KIND_BOOL` (the old `width_bits == 1` test) and zero is `ciIsZero(v)`. `bool_and`/`bool_or` **short-circuit** in both directions: a decisive folded lhs (`0` for `and`, `1` for `or`) returns immediately WITHOUT evaluating the rhs; when the lhs does NOT fold, a decisive RHS still decides (`<runtime> or true` -> true, `<runtime> and false` -> false) — fix round 1; any other non-folding operand yields null. | `comptimeEvalEvaluateDepth` | `comptimeEvalEvaluateDepth` (recursive for lhs, and for the rhs when not short-circuited), `ciBoolVal`, `ciIsZero` | `store.nodes`, lhs/rhs `ComptimeVal` | A non-bool folded operand, or an unfoldable operand that is not the decisive side, returns null. | None [inference] |
| `comptimeEvalOperandType` | private | **Task 3 (Task 1 §5.4 / §8 risk 3)** — replaces Task 9D's `comptimeEvalOperandDeclaredSigned` (deleted): the integer type a binop operand receives in sema, or null when it is untyped. Unwraps `paren_expr` (depth-32 guarded); an `ident_expr` is resolved via the function-local const scope first (Task 9D Gap B) then the module symbol tables (an integer annotation returns its type; **fix round 1:** an UNANNOTATED const recurses into its initializer, `const c = @as(u8,200)` → u8); `@intCast`/`@as` report the integer target; `negate`/`bit_not` propagate their operand; the ten integer binops apply the INT_LIT/numeric arm plus `comptimeEvalWiderIntType` recursively, mirroring `semanticAnalyzerResolveArithmetic`/`ResolveBitwise` so the fold agrees with the runtime type. The binop peer-fit rule and (fix round 1) the unary `negate`/`bit_not` folds consume it. | `comptimeEvalBinOp`, `comptimeEvalEvaluateDepth` (unary arms) | `comptimeEvalOperandTypeDepth` (recursive), `comptimeEvalResolveTypeArg`, `type_resolver.localConstScopeLookup`, `symbolRegistryQualifiedLookup`, `comptimeEvalWiderIntType`, `typeRegistryIsInteger` | `local_consts`, `symbol_reg`, `store.nodes` | Returns a `TypeId` for a typed operand leaf/expression; null for literals/bool literals and underivable shapes. No signedness conversion any more. | None [inference] |
| `comptimeEvalWiderIntType` | private | **Task 3 (Task 1 §5.4).** The peer type of TWO declared integer operand types — mirror of `semanticAnalyzerResolveArithmetic`'s integer width rule (wider type wins; a tie keeps the lhs). | `comptimeEvalBinOp` | `typeRegistryIntWidthBits` | `registry` | Both ids are integer types; `lt == rt` returns immediately. | None [inference] |
| `comptimeEvalEvaluate` | pub | Main comptime evaluation entry point. Thin wrapper delegating to `comptimeEvalEvaluateDepth(node_idx, 0)`. | `main.zig` phase_ComptimeEvaluation; recursion; unit tests (test_semantic_bin.zig) | `comptimeEvalEvaluateDepth` | `store.nodes`, `store.int_values` | Entry point; all recursion flows through the depth-guarded variant. | None [inference] |
| `comptimeEvalEvaluateDepth` | private | Depth-guarded evaluation core. Twelve dispatch arms, including the `ident_expr` const-chain arm. | `comptimeEvalEvaluate`, recursively by itself/binop/cmp/logical/builtin | `comptimeEvalBinOp`, `comptimeEvalCompare`, `comptimeEvalLogical`, `comptimeEvalBuiltin`, `comptimeEvalEvaluateDepth` (recursive), `symbolRegistryQualifiedLookup`, `type_resolver.localConstScopeLookup` | `store.nodes`, `store.int_values`, `store.identifiers`, `symbol_reg`, `local_consts` | `node_idx==0` returns null. `depth >= 16` returns null (const-chain guard). Recursive for paren_expr, negate, bit_not, bool_not, binop, cmp, logical, builtin, and ident_expr chains. | None [inference] |
| `comptimeEvalEvaluate` — int_literal | — | **Task 2:** returns `ciFromU64(store.int_values[node.payload])` as `KIND_INT` (exact value; the old `width=0, sig=true` flags are gone). | (same as above) | `ciFromU64`, `ciIntVal` | `store.int_values` | A source literal above `2^64-1` is already lossy at lex/parse time (`astStoreIntValue` stores a u64); the cap governs arithmetic results. | None [inference] |
| `comptimeEvalEvaluate` — char_literal | — | **Task 2:** same as int_literal (`KIND_INT`, exact 0..255 value). | (same as above) | `ciFromU64`, `ciIntVal` | `store.int_values` | Character treated as its integer code point. | None [inference] |
| `comptimeEvalEvaluate` — bool_literal | — | **Task 2:** returns `ciBoolVal(flags & 1)` (`KIND_BOOL`). | (same as above) | `ciBoolVal` | `node.flags` | Flags bit 0 = value. | None [inference] |
| `comptimeEvalEvaluate` — negate/bit_not | — | **Task 2:** recursively evaluate inner; require `kind == KIND_INT`; `ciNeg` (sign flip, `-0` normalizes to `0`) or `ciBitNot` (`~x = -x - 1`, null on cap). **Task 3 fix round 1 (Important):** the `negate` fold requires the exact result to fit the operand's type via `comptimeEvalOperandType`+`comptimeIntFitsType` (`-umax` on u64 declines) — without it the unary fold escaped the peer-fit rule and accepted Zig-rejected programs. **Fix round 2:** `bit_not` stays EXEMPT (an unsigned operand's exact `-x-1` is always negative; a fit would false-reject every `~u` shape — declared divergence, Known Issues 9). | (same as above) | `comptimeEvalEvaluateDepth`, `ciNeg`, `ciBitNot`, `comptimeEvalOperandType`, `comptimeIntFitsType` | inner `ComptimeVal` | A `KIND_FLOAT`/`KIND_BOOL` inner returns null. **Task 9D:** the `bool_not` arm (`comptimeEvalLogical`) requires `KIND_BOOL`. | None [inference] |
| `comptimeEvalEvaluate` — binop | — | Dispatches to `comptimeEvalBinOp` for add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr kinds. **Task 9D:** comparison kinds dispatch to `comptimeEvalCompare`; `bool_and`/`bool_or` dispatch to `comptimeEvalLogical`. | (same as above) | `comptimeEvalBinOp`, `comptimeEvalCompare`, `comptimeEvalLogical` | `node.kind` | Forwards `node_idx`, `node.kind`, and current depth to the handler. | None [inference] |
| `comptimeEvalEvaluate` — builtin_call | — | Dispatches to `comptimeEvalBuiltin` for the builtin_call kind. | (same as above) | `comptimeEvalBuiltin` | `node.kind` | 10 names foldable; every other name returns null. | None [inference] |
| `comptimeEvalEvaluate` — paren_expr | — | Unwraps parentheses: recurses on `node.child_0`. | (same as above) | `comptimeEvalEvaluateDepth` | `node.child_0` | Trivial pass-through. | None [inference] |
| `comptimeEvalEvaluate` — ident_expr | — | Const-chain resolution: **Task 9D** consults the enclosing function's `local_consts` scope (`type_resolver.localConstScopeLookup`) FIRST — a local `const` is a statement, not a module symbol, and shadows a module const of the same name — then looks up `name_id` via `symbolRegistryQualifiedLookup` across all module tables; if the symbol is a `const` (symbol `flags & 0x01 == 0`) with a non-empty init (`decl.child_1 != 0`), recurse into that init at `depth+1`. **Task 4:** the resolved initializer value is checked against the declaration's integer type via `comptimeEvalDeclFits` (Task 1 §5.3) — a value the slot cannot hold makes the name UNFOLDABLE. Returns null on `depth >= 16` (const-chain guard) or no matching const. | (same as above) | `comptimeEvalEvaluateDepth` (recursive), `comptimeEvalDeclFits`, `symbolRegistryQualifiedLookup`, `type_resolver.localConstScopeLookup` | `store.identifiers`, `symbol_reg`, `store.nodes`, `local_consts` | Enables `const B: i32 = A + 5` to fold from `const A: i32 = 30`, and `const a: i32 = 1; if (a == 1)` to fold from the local `a` (Task 9D). | None [inference] |

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
       │           └─ Task 3 peer-fit: untyped operand value + exact result must fit the peer type
       │              (comptimeEvalOperandType + comptimeEvalWiderIntType + comptimeIntFitsType)
       ├─ cmp_eq/cmp_ne/cmp_lt/cmp_le/cmp_gt/cmp_ge ──→ comptimeEvalCompare(node_idx, kind, depth)
       │     └─ EvaluateDepth(child_0) + EvaluateDepth(child_1) → ciBoolVal(res) {kind=KIND_BOOL}
       │           └─ Task 3: exact magnitude+sign (ciCmp); no sign class, no declared type,
       │              no 64-bit bridge; bools compare as 0/1; KIND_FLOAT → null
       │           └─ comparisons are EXEMPT from the arithmetic peer-fit rule (mathematical)
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
  │      └─ success → comptimeFoldTablePut(&ctx.comptime_folds, node_idx, v)   ← exact value (Task 4)
  │      └─ success with an int outside [i64 min, u64 max] → STILL stored (Task 4); the
  │         lowering materialisation site rejects it with error[3000] (Task 1 §8 risk 1)
  │      └─ null   → not stored (skipped silently)
  │    const var_decl with binary/unary init → fold init node, store under the init node
  │    capture-free no-`else` if_expr → store the folded BOOL condition (Task 3)

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
       (Task 4: an unannotated local binding whose folded integer init does not fit i32
        takes the value-based type U32/I64/U64 so the slot and every reference agree)

phase_LIRLowering (lower.zig, builtin_call arm)
  ├─ comptime_folds (ComptimeFoldTable) lookup
  │     ├─ HIT → emit int_const LIR + marker "CEV" ← the fold is CONSUMED here
  │     │        (@intCast uses the resolved target type; @isWindows uses TYPE_BOOL;
  │     │         Task 4 range-checks a concrete integer target and materialises the
  │     │         exact pattern; an untyped slot picks I32/U32/I64/U64 by value)
  │     │        @floatCast/@intToFloat → emit float_const at the resolved f32/f64
  │     │        target (the table stores the f64 bit pattern; Z98 @bitCast is
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
`ciNormalize`, `ciIsZero`, `ciMagCmp`, `ciCmp` (Task 3: exact magnitude+sign order),
`ciToU64` (two's-complement pattern), `ciToF64`
(limb accumulation, sign applied), `ciIntVal`/`ciBoolVal`.

**Overflow policy (exact-or-unfoldable).** Every op is exact or declines (`null`/`false`) — no
wrap, no truncation, no saturation: add/sub/mul/bit ops/shl when the exact result needs more
than 256 magnitude bits; div/mod by zero; a negative or `> 2^32` shift count (the design's
out-of-domain rule; in practice counts ≥ 256 are the cap cases). Division and `%` truncate
toward zero (`7/2=3`, `-7/2=-3`, `7/-2=-3`, `7%-2=1`; `%` keeps the dividend's sign);
`>>` is a floor shift (`-7>>1=-4`, `-1>>1=-1`); `&`/`|`/`^` use infinite-precision
two's-complement semantics via `~m = -m - 1`; `~x = -x - 1` (Z98 keeps `~`; Zig 0.15.2 rejects
it — pre-existing divergence).

**Materialisation.** `comptimeIntFitsType(registry, v, t)` is the exact range check (negative: signed
target and `mag ≤ 2^(w-1)`; non-negative: `mag < 2^(w-1)` signed / `mag < 2^w` unsigned).
**Task 4:** the production fold table stores the exact `ComptimeVal` (`ComptimeFoldTable`), so
`comptimeValStoreU64` is now only a test helper; `comptimeIntMaterialize` returns the
two's-complement pattern, `comptimeIntFits64` the `[i64 min, u64 max]` window, and
`comptimeIntUntypedType` the value-based type for an untyped slot. Materialisation sites
(the `@intCast`/`@as` fold, typed decl slots, parameter/argument/return coercions through
`materializeInto`/`applyCoercion`, untyped HIT slots, array sizes) all reject an out-of-range
exact value with the preserved diag codes (see doc 07 §Task 4, doc 03 §Array size, doc 05 §var_decl).

**Fixtures.** `repro/mi_matrix/stdlib_comptime_bigint_arith_xmod` (31 values, every one
Zig-0.15.2-oracle-checked: 2^64/2^100/2^200 magnitudes, div/mod/bitwise/shift signs, u64 max,
multi-word shift controls (`y1`/`y2`), in-range controls) and the standalone
`repro/comptime_bigint_arith.z98`. Unit coverage: `test_semantic_bin.zig`
`testComptimeBigIntCore` (cap declines incl. the review's `word > 0` shapes, div-by-zero,
negative shift counts, truncating-division/floor-shift/bit-op signs).

**Review fix (Critical, 2026-09-23).** `ciShl`'s accumulation only consumed shifted source limbs
whose target limb starts below 8, so a nonzero limb landing at/beyond limb 8 was dropped and the
function returned `true` with a truncated value (`2^32 << 224`, `2^64 << 192`, `2^255 << 64`).
It now declines (`false`) when any `tmp[i] != 0` with `i + word >= 8`; the fixture and the unit
test gained multi-word cap and reduced-result coverage. Fixed point moved to `e0efd631…`.

### Signedness-free comparisons + logical folds (Task 3) — [updated: 2026-09-23]

**Comparison.** `comptimeEvalCompare` compares the exact magnitude+sign of the two folded
`ComptimeInt`s via the new private `ciCmp` (differing signs → the negative one is smaller; equal
signs → `ciMagCmp`, negated for negatives; `-0` is normalized to `0`; bools compare as 0/1). The
Task 9D sign-class machinery is DELETED: `comptimeEvalSignClass`, `SignClass`,
`comptimeEvalOperandCompareSigned`, `comptimeEvalOperandDeclaredSigned`, the `0 - X` special case,
and the Task 2 64-bit `ciValToOldBits` adapter. The bounded divergence is retired: arithmetic-derived
conditions (`(umax - 1) > 0`, `0 < (umax - 1)`, `(umax - 1) > zero`, `umax > (0 + 0)`,
`(a + 1) == 2`, `(imin + 1) < 0`) fold exactly like Zig, while Zig-rejected shapes stay rejected
(D6 `(umax - 1) < 0` folds false, S6 `umax < 0` folds false, D7 `(u - 300) < 0` / E5
`(0 - umax) < 0` decline via the peer-fit rule below). A `KIND_FLOAT` operand returns null (float
comparison folding is out of scope — a bounded residual). Comparisons are deliberately EXEMPT from
the arithmetic peer-fit rule (oracle: `const u: u8 = 200; u > -1` is true, `u > 300` is false).

**Arithmetic peer-fit rule (Task 1 §5.4).** `comptimeEvalBinOp` computes the operand peer type P:
one typed operand + an untyped other → P = that type; both typed → the sema width rule (wider
wins; ties keep lhs) via `comptimeEvalWiderIntType`; otherwise no P. Each UNTYPED operand's exact
value and the exact result must fit P (`comptimeIntFitsType`) or the fold declines:
`(u - 300)` with `u: u8` declines (Zig: "type 'u8' cannot represent integer value '300'"), and
`(0 - umax)` with `umax: u64` declines (Zig: overflow). The operand-type lookup
(`comptimeEvalOperandType`, replacing Task 9D's `comptimeEvalOperandDeclaredSigned`) unwraps parens,
consults the function-local const scope first then the module symbols, reports an
`@intCast`/`@as` integer target, and MIRRORS sema's integer typing recursively for compound
expressions (Task 1 §8 risk 3): `negate`/`bit_not` propagate their operand, and the integer binops
apply the INT_LIT/numeric arm plus the wider-wins/ties-lhs rule. The recursion is load-bearing —
without it `((u - 1) - 300) < 0` would fold to `true` and accept a program whose runtime u8
arithmetic wraps (silent miscompile); with it the outer sub sees the sema type `u8` and declines.
**Fix round 1 (Important, 2026-09-23):** the unary `negate` FOLD applies the peer fit to the exact
result against the operand's type (`-umax` on u64 declines; sema types `-x` as x's type), and
`comptimeEvalOperandType` also recurses into the initializer of an **unannotated** const
(`const c = @as(u8, 200)` types `c` as u8, so `(c + 300) == 500` declines instead of folding 500).
**Fix round 2 (Important, 2026-09-23):** `bit_not` is deliberately EXEMPT from the fit check — Z98's
`~` is the exact `-x - 1` (Task 1 §4), so a typed-unsigned operand's exact result is always negative
and a fit would reject every `~u` fold, including the valid Zig-equal `if ((~u) != 0) …` class; the
divergence is documented in Known Issues 9.

**Condition store (Task 1 §7; `main.zig`).** `phase_ComptimeEvaluation` additionally evaluates and
stores the condition of every capture-free (`payload == 0`) no-`else` `if_expr` whose result is a
bool — exactly the domain where `semanticAnalyzerConditionIsComptimeTrue` grants acceptance.
Lowering's existing `if_expr` `ie_fold` path then elides the untaken branch, so module-scope
conditions (step-0 S3 `uu > -1`, S5 `uu > (0 - 1)`, E12 `-9223372036854775808 < 0`) are
runtime-equal to Zig instead of materialising a false runtime branch plus an uninitialised result
temp. `if_stmt` conditions and `if_expr` with an `else` are deliberately NOT stored (their emitted
C is unchanged); a function-local condition operand is invisible to the module-scope sweep, so its
(C-correct) runtime branch is kept. **[Fix round 1 (Critical), 2026-09-23]:** a stored condition on
an if_expr with a TERMINATING arm (`if (true) return 5;`) exposed a lowering gap — the fold
sub-path lowered the arm as a value and left the var uninitialised; the `lower.zig` fold sub-path
is now terminator-aware (`lowerIfArmValue` + `block_terminated` guard + a `TYPE_NORETURN` shortcut
bypass; see doc 07 §If Expression). Fixture `repro/mi_matrix/stdlib_comptime_noreturn_if_xmod`.

**Fixtures.** `repro/mi_matrix/stdlib_comptime_compare_xmod` (`main.zig` + `expected.txt`/
`expected.rc`; 22 values: function-local D1–D5 + local `imax` and `@as`-spelled local `imin`, the
same shapes with module-scope consts plus S3/S4/S5/E12, and `and`/`or`/`!` over 2^100 magnitudes;
every value `@panic`-guarded and Zig-0.15.2-oracle-matched) + `repro/mi_matrix/
comptime_compare_reject_xmod` (9 `error[3059]` over-acceptance sites: `umax < 0`, `(umax - 1) < 0`,
`(u - 300) < 0`, `(0 - umax) < 0`, `(u + 1000) < 0`, nested `((u - 1) - 300) < 0`, `-umax < 0`,
`(c + 300) == 500` with `const c = @as(u8, 200)`, module `MUMAX < 0`) + standalone
`repro/comptime_compare.z98`. `comptime_compare_diverge_reject_xmod` is REPLACED by the pair.
Known residual at Task 3 time (now FIXED by Task 4): the bare local
`const imin: i64 = -9223372036854775808` spelling materialised as 0 (32-bit HIT type recovery);
the Task 3 fixture spelled it `@as(i64, …)`.

### Coercion into typed slots (Task 4) — [updated: 2026-09-23]

**Exact fold table.** `ComptimeFoldTable` (`slots: U32ToU32Map` + a dense `[*]ComptimeVal` array
in the module arena) replaces the `U32ToU64Map` + `comptimeValStoreU64` production path
(Task 1 §6.2). Every fold is stored exactly — including an integer outside `[i64 min, u64 max]`,
which lowering then rejects instead of silently keeping the runtime path (Task 1 §8 risk 1;
`const BIG = 1 << 100;` is now `error[3000]` where Zig accepts — a bounded, documented
divergence). `main.zig`'s three store arms (`builtin_call`, const-decl init, `if_expr` condition)
all use `comptimeFoldTablePut`; `lower.zig`'s readers use `comptimeFoldTableGet` /
`comptimeFoldBool`.

**Coercion primitive + untyped selection.** `comptimeIntFitsType(registry, v, t)` is the exact
fit check; `comptimeIntMaterialize` returns the two's-complement pattern; `comptimeIntUntypedType`
picks `I32`/`U32`/`I64`/`U64` for an untyped slot (negative → signed; null beyond the 64-bit
window). This fixes the Task 3 carry-item local bare-negate i64 min (`const imin: i64 =
-9223372036854775808;` now prints the exact value: the negate HIT no longer forces an i32 temp)
and the Task 1 §8 risk 7 untyped-local truncation class (`const c = 2000000000 + 1000000000;`
takes a U32 slot; `(1 << 63) + 7` a U64 slot; `0 - 3000000000` an I64 slot) — the
`semantic_analyzer.zig` var_decl path picks the same value-based binding type so the slot and
every reference agree (see doc 05).

**Typed-slot fold rule (Task 1 §5.3).** When the ident fold resolves a name whose declaration has
an integer type that cannot hold the exact initializer, the name is unfoldable
(`comptimeEvalDeclFits`): `const u: u8 = 300;` materialises 44 with `warning[3000]`, so folding
300 would invent a value the runtime slot never holds.

**Lowering materialisation sites (see doc 07 for the full list).** `lowerFoldedIntConst`
materialises every arithmetic/unary HIT (typed target → exact range check; untyped → value-based
type); the builtin HIT range-checks a concrete integer target. The fit checks share one core
(`checkIntFitsMode`) over `foldNodeIntExact`, which unwraps `?T`/`E!T` payloads
(`scalarTargetOf`) and has three lookup modes: `checkFoldedIntFits` (fold table only; used by
`materializeInto`/`applyCoercion`), `checkArgReturnIntFits` (table + bare int/char literals and
their `negate`; used at function-argument and return sites), and `checkDeclInitFits` (table +
on-demand folding of arithmetic/unary initializers; used at module/local decl slots). Failures
emit the preserved `error[3000]` (new message `"comptime integer value does not fit the target
type"`; the `@intCast`/`@as` fold keeps its own messages) at most once per node, and the
post-lowering diagnostic gate exits rc=2 with 0 `.c`. `~` folds stay exempt from the
materialisation fit (the Task 3 documented divergence).

**Fix round (review Importants 1–4), 2026-09-23.** Four escape holes closed:
1. **`var` arithmetic/unary declarations.** The phase sweep stores only const inits, so
   `var y: u32 = 0 - 1;` had no fold entry and ran 4294967295 with no diagnostic; `checkDeclInitFits`
   now folds such an init on demand (`foldNodeIntExact` probes an evaluator) and rejects it
   (`type 'u32' cannot represent integer value '-1'`; Zig-matching). Bare positive literals keep
   the pre-existing warning[3000] + truncate declaration path (`const x: i8 = 200;` stays
   accepted, Task 1 §5.3); `negate` literals follow the const-decl fold (`const x: i8 = -200;`
   already rejected).
2. **Bare-literal parameters/returns.** `f(300)` and `return 300;` in a `u8` function ran 44 with
   no diagnostic; the ARG mode makes a bare literal an exact comptime value at the four call-arg
   loops and `return_stmt` (Zig: `type 'u8' cannot represent integer value '300'`).
3. **Unannotated module consts.** `const X = 2000000000 + 1000000000;` emitted `int zG_X;` and ran
   truncated; `semanticAnalyzerResolveModuleVarDecl` now applies the same value-based selection as
   the function-local rule (front_resolution stores the returned type on the decl node and the
   symbol), so the global slot and every reference agree (now a `u32` global; see doc 05).
4. **Optional-payload shapes.** `takeOpt8(@as(i32, 300))` was accepted with NO diagnostic and
   emitted gcc-invalid C, and `var o: ?u8 = @as(i32, 300);` warned then emitted the same invalid C;
   `scalarTargetOf` unwraps `?T`/`E!T` before the fit check at every site, so both are now clean
   `error[3000]` rejects (Zig: `expected type '?u8', found 'i32'`).

**Array sizes.** `evalConstU32Full` now folds the size expression exactly (`0..0xFFFFFFFE`;
`0xFFFFFFFF` is the unfoldable sentinel) and rejects negatives/wrapping/over-u32 results, so
`[0 - 1]u8` is `error[3050]` (Task 1 §9.3; see doc 03).

**Fixtures.** `repro/mi_matrix/stdlib_comptime_coerce_typed_slots_xmod` (positive runtime,
Zig-0.15.2-oracle-matched: in-range typed decls/params/returns/`@intCast`/`@as`/array size/enum
backing + the carry-item i64 min + the fix-round controls `MX` unannotated module const,
`vy` var arithmetic, `takeLit` literal arg), `repro/mi_matrix/comptime_coerce_reject_xmod`
(12 lowering-phase `error[3000]` sites incl. the four fix-round shapes),
`repro/mi_matrix/array_size_negative_reject_xmod` (`error[3050]`),
`repro/mi_matrix/stdlib_comptime_intcast_nonint_mask_xmod` (the restored non-integer `@intCast`
masking — a Z98-only shape with no oracle twin; stdout `masked=300`), and the standalone
`repro/comptime_coerce_typed_slots.z98` + `repro/comptime_coerce_reject.z98`. Stdlib pin
**220 → 221 → 222** across the Task 4 fix round.

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
  by the sema probe, the global `phase_ComptimeEvaluation` fold is unaffected. **[Task 2/3 note:**
  the `comptime_eval.zig` side of this classifier was deleted — Task 2 replaced the 64-bit
  fits-check with the exact `comptimeIntFitsType`, and Task 3 deleted `comptimeEvalSignClass`
  entirely; the `type_resolver.zig` twin `evalConstSignClass` survives until Task 5.**]** A definitely-negative source with the top bit set is
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
   returns null on a non-int operand). Deliberate scope limit of Task 11D; Task 3 keeps the float
   comparison residual. **Task 9D** folds integer comparisons and the bool logical ops; **Task 3**
   made the integer comparison signedness-free and exact (see above).

7. **`@floatCast` operand-type validation absent**: sema accepts a non-float source (Task 11A §6.4).
   The fold branch returns `null` for a non-float operand rather than diagnosing; no new diagnostic
   was added in Task 11D.

8. **Negative zero is preserved in the sub-evaluator but not yet in emitted C** (`comptime_eval.zig`
   + `util/format.zig`): `comptimeEvalFloat`'s `negate` computes `-v`, so `-0.0` keeps its sign bit
   in the folded value; however `formatF64` (`sf/src/util/format.zig:99`) renders any zero as `0`,
   so `@floatCast(f64, -0.0)` still emits `(double)(0)`. Fixing the emitter's negative-zero rendering
   is out of Task 11D fix-round-1 scope (the finding targeted the sub-evaluator); no fixture uses
   `-0.0`.

9. **Comparison peer-fit / Zig-matching rejection cases (Task 3; the Task 9D bounded divergence is
   RETIRED).** `comptimeEvalCompare` is signedness-free and exact over arbitrary magnitudes, so
   `(umax - 1) > 0`, `0 < (umax - 1)`, `(umax - 1) > zero`, `umax > (0 + 0)`, `(a + 1) == 2` and
   `(imin + 1) < 0` are ACCEPTED in a no-`else` value `if` and runtime-equal to Zig. The remaining
   rejections match Zig: `umax < 0` / `(umax - 1) < 0` fold false; `(u - 300) < 0`, `(0 - umax) < 0`,
   `(u + 1000) < 0`, nested `((u - 1) - 300) < 0`, `-umax < 0` (fix round 1: `negate` peer fit) and
   `(c + 300) == 500` with `const c = @as(u8, 200)` (fix round 1: unannotated-const init recursion)
   decline via the peer-fit rule (Task 1 §5.4). **`~` is exempt from the fit** (fix round 2): Z98
   folds the exact `-x - 1` (Task 1 §4; Zig 0.15.2 rejects `~` on `comptime_int`), while sema types
   `~x` as x's type and the runtime complement wraps. Consequence: the accepted class
   `(~u) != 0` (u typed unsigned) is Zig-equal (`400 401` in the fixture), but a shape that depends
   on the WRAPPED complement — `(~u) == 4294967295` with `u: u32` — folds with the exact `-1` and
   false-rejects where Zig accepts. Pre-existing Z98 `~` divergence (Task 1 §4, out of scope),
   now documented and regression-pinned on the accepted side. Fixtures:
   `repro/mi_matrix/stdlib_comptime_compare_xmod`,
   `repro/mi_matrix/comptime_compare_reject_xmod` (9 sites) and
   `repro/mi_matrix/stdlib_comptime_noreturn_if_xmod` (+ NOTES.md); pinned in `EXPECTED_FAIL.md`
   v208. Float comparison folding remains out of scope.

10. **Unannotated MODULE int consts — RESOLVED by the Task 4 fix round.** The original residual
    (a module-scope unannotated const's C slot came from the symbol registry, so
    `const X = 2000000000 + 1000000000;` stored a U32 fold into an `int` global and ran
    truncated) is fixed: `semanticAnalyzerResolveModuleVarDecl` applies the same value-based
    selection as the function-local rule, and `front_resolution` stores the returned type on the
    decl node and the symbol, so the global slot and every reference agree (`unsigned int
    zG_…_X;`). The out-of-64-bit module case stays rejected (the untyped HIT). Positive control:
    `MX` in `stdlib_comptime_coerce_typed_slots_xmod` (oracle-matched `3000000000`).

11. **Optional-payload coercion — the folded/literal shapes are now clean rejects; the
    runtime-typed residual remains (Task 4 fix round + scope boundary).**
    `takeOpt8(@as(i32, 300))`, `takeOpt8(300)` and `var o: ?u8 = @as(i32, 300);` are clean
    `error[3000]` rejects now (`scalarTargetOf` unwraps `?T`/`E!T` before the fit check at the
    call-arg and decl sites; Zig rejects `expected type '?u8', found 'i32'`); previously they
    were accepted and two of them emitted gcc-invalid C. Remaining residual: an optional payload
    whose source is a RUNTIME value with no recorded wrap (`takeOpt8(runtime_i32)`) keeps the
    pre-existing assignability laxness (Task 14 territory), and a bare positive literal into an
    optional decl (`var o: ?i32 = 3000000000;`) keeps the pre-existing
    warning[3000]+truncate declaration path (Task 1 §5.3; valid C, Zig rejects).

