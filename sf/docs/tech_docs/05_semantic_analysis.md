# 05 — Semantic Analysis [updated: 2026-09-28 — FX11 (Volume II defect fix): the FX6 const-array-decay guarantee now covers an aggregate's array FIELD. `semanticAnalyzerResolveFieldAccess` builds the array-field element pointer with `semanticAnalyzerIsLValueConst(self, node_idx)` (struct/union/packed-union fields, tuple elements, tagged-union payload), so a const aggregate's field resolves `*const T` and the existing type-level machinery rejects every mutable materialisation (`var q: *i32 = cs.a`, `cs.a[0] = 9` → `error[3002]`, `var s: []i32 = cs.a[0..]` → `error[3000]`); a MUTABLE aggregate's field, a const-bound MUTABLE slice field, and a genuine pointer-typed field are unchanged. New `semanticAnalyzerFieldAccessArrayType` recovers the declared array type of a decayed field access; it feeds the `semanticAnalyzerConstArrayDecay` pointer-source arm (element site `[1][]i32{ cs.a }`), the `address_of` arm (`&cs.a` → `*[N]T`/`*const [N]T`, `&cs.a[i]` → `*const ElementType`), and the `slice_expr` constness path (`cs.a[0..]` → `[]const T`). Fixtures: `repro/mi_matrix/stdlib_const_field_decay_ok_xmod` (positive; stdlib pin 263 -> 264), `repro/mi_matrix/const_field_decay_reject_xmod` (29 x `error[3000]`), standalone `repro/const_field_decay.z98` + `repro/const_field_decay_reject.z98` (23 x `error[3000]`); migration `stdlib_method_syntax_ok_xmod` `const holder` -> `var holder` (its `holder.pts[0..2]` -> `[]Point` row was the closed field-bound hole). 4-MD5 emitted-C UNCHANGED 8/8; corpus `-s0` 1069 = 909 OK / 53 GREEN / 107 FAIL / 0 ICE / 0 CRASH (join-diff vs HEAD over the 1067 common dirs EMPTY; the only dir-set additions are the two FX11 fixtures; the one pre-migration mover `stdlib_method_syntax_ok_xmod` OK -> GREEN was migrated back to OK, see the FX11 EXPECTED_FAIL record).] [updated: 2026-09-28 — FX10 (Volume II defect fix, D6 extras follow-up): `semanticAnalyzerResolveSwitchExpr` now retypes a switch VALUE expression at an f32 expectation site value-aware like the FX9 `if` path. A new `sw_f32_site` guard (from `topExpectedType`) skips the value-blind prong unification, then every prong is classified with `semanticAnalyzerFloatNarrowArmStatus`: all acceptable => the switch records `TYPE_F32` and each non-f32 prong records its `tryRecordCoercion` narrowing (fixes a typed-int first prong truncating `switch (c) { 1 => C, else => 2.5 }` -> `2` where Zig yields `2.5`, and `else => x` runtime f32 -> `3`/`4` where Zig yields `3.5`/`4.5`; seed v88 was correct, FX3 fix round 1 introduced it); otherwise the switch takes the offending prong's type so the enclosing site's FX3 status rejects with the offending prong's `source:` note. Fixtures: positive `stdlib_f32_narrow_ok_xmod` gains the `swx=`/`swsites=` rows (11 lines / 196 B -> 13 lines / 250 B, Zig-twin byte-identical), reject `f32_narrow_reject_xmod` 33 -> 39 x `error[3000]`, standalone `repro/f32_narrow_switch.z98` (accept) + `repro/f32_narrow_switch_reject.z98` (6 x 3000). Fixed point `5744b468…` -> `0b3ea32bebe2eab92d0801fe0f48d094` (hop1 == hop2, explicit gate; seed v88 NOT rotated).] [updated: 2026-09-27 — FX9 fix round 1 (Volume II defect fix, D6 extras follow-up): `semanticAnalyzerFloatNarrowArmStatus` now treats a `TYPE_UNDEFINED` arm as neutral (like `noreturn`; `undefined` coerces to every type), so `if (c) undefined else 2.5` no longer rejects at an f32 site — return/declaration/assignment/field/argument, both arm positions (the field/argument forms used to emit gcc-invalid C or ICE `error[3043]`; the literal-taken branches now produce the correct value). Fixture `stdlib_f32_narrow_ok_xmod` gains the `und=` row (11 lines / 196 B, Zig-twin-equal) + standalone `repro/f32_undefined_arm_ok.z98`; fixed point `ee5f3070…` -> `5744b468…`. Documented accepted-wrong residual (FX10 owns the code fix; NOT fixed in FX9): a switch VALUE expression whose FIRST prong is a typed int and a later prong a float truncates (`switch (c) { 1 => C, else => 2.5 }` -> `2`, Zig `2.5`); seed v88 was correct, FX3 fix round 1 introduced it.] [updated: 2026-09-27 — FX9 (Volume II defect fix, D6 extras follow-up): the value-aware f32 narrowing now rejects a runtime non-float arm of an `if`/`switch` VALUE expression at an f32 site, and types valid mixed float arms f32. `semanticAnalyzerResolveIfExpr` gains an FX9 branch (after the peer rules, before the void fall-through): for an f32 expected type it classifies the REACHABLE arms via `semanticAnalyzerFloatNarrowArmStatus` — all-acceptable types the `if` f32 and records the arm narrowing (`if (c > 0) x else 2.5` with runtime `x: f32`); otherwise the `if` takes the offending arm's type, so the site's existing FX3 status rejects it with a `source: i32`/`u32`/`bool` note (`if (c > 0) n else 2.5`). A comptime-known condition (new tri-state `semanticAnalyzerConditionComptimeBool`, also backing `semanticAnalyzerConditionIsComptimeTrue`) makes the untaken arm unreachable (`if (false) n else 2.5` accepts; `if (true) n else 2.5` rejects). `semanticAnalyzerFloatNarrowStatusDepth` now intercepts `if`/`switch` BEFORE the numeric guard and skips unreachable arms, so `void`/bool/pointer-typed mismatched-arm expressions reject instead of silently producing no value. Pre-FX9 the if-arm forms were accepted-and-miscompiled (`r=0`) or ICEd/gcc-invalid; the switch form rejected but mid-typing. Fixtures: `f32_narrow_reject_xmod` 18 -> 33 × `error[3000]`; positive `stdlib_f32_narrow_ok_xmod` gains the `mix=` row (10 lines / 168 B, Zig-twin-equal, stdlib pin unchanged 259); standalone `repro/f32_runtime_arm_reject.z98` (11 × `error[3000]`); fixed point `fd4b79b6…` -> `ee5f30700668059c14c05a317fbae827` (hop1 == hop2, explicit gate; seed v88 NOT rotated).] [updated: 2026-09-27 — FB2 (Volume II defect fix): `semanticAnalyzerResolveTupleLiteral` types every inferred tuple element by value. Untyped integer-literal elements take the value-chosen carrier (`comptimeIntUntypedType`: i32 when the value fits, else u32/i64/u64; in-i32 keeps `TYPE_INT_LIT`, so existing tuples are byte-identical; a >64-bit exact value stays `TYPE_INT_LIT` and lowering reports `error[3000]`); the old `TYPE_VOID -> TYPE_I32` fallback is removed — a genuine void element keeps `TYPE_VOID` and both print paths reject `error[3063]`, while a VOID-typed bare/parenthesized ident or MODULE-member reference (an unresolved forward global; `semanticAnalyzerTupleElemVoidIsUnresolvedRef`, fix round 1 narrowing) keeps the pass-1 i32 fallback to preserve tuple identity/emitted C, while a field read on a VALUE base (`s.v`; void struct fields are legal Z98) keeps `void` and rejects; a type value referenced by name (`semanticAnalyzerTupleElemIsTypeValue`) becomes `TYPE_TYPE` and rejects `error[3063]` on both print paths. New Table B rows `semanticAnalyzerTupleElemIsTypeValue` / `semanticAnalyzerTupleElemVoidIsUnresolvedRef`; fixtures `stdlib_print_tuple_var_ok_xmod` (23 rows) + `tuple_elem_type_reject_xmod` (8 x 3063 + 2 x 3000) + standalone repros; fixed point `115c716c…` -> `416f0932e2e164fb4c04013d3fda549d` (hop1 == hop2, explicit gate; seed v88 NOT rotated); 4-MD5 emitted-C UNCHANGED 8/8; corpus join-diff EMPTY over the 1059 common dirs (+1 reject fixture). **Fix round 1 (void struct-field narrowing, 2026-09-27):** the transient fallback (`semanticAnalyzerTupleElemVoidIsUnresolvedRef`) now applies only to bare (parenthesized) idents and MODULE/`@import` member references (`semanticAnalyzerTupleElemFieldBaseIsModule`); a field read on a VALUE base (`s.v` with `struct { v: void, a: i32 }`) keeps `TYPE_VOID` and both print paths reject `error[3063]` (was typed i32 + gcc `'zT_N' undeclared` through the FD2 variable path). Fixture census 12 x 3063 + 2 x 3000; control `repro/void_field_ok.z98` (`ok=7 7` / `gok=9 1`, Zig-twin-equal); fixed point `416f0932…` -> `fd4b79b6b992be1b8dd097c24e7bfa7f` (hop1 == hop2, explicit gate; seed v88 NOT rotated); 4-MD5 emitted-C UNCHANGED 8/8; FB2->fix1 emitted C byte-identical on all 120 tuple-using dirs; corpus join-diff EMPTY.] [updated: 2026-09-27 — FX4 (Volume II defect fix, D11 extras): the FE qualified-prong helper now validates the prong. `semanticAnalyzerResolveSwitchCaseMember` resolves the QUALIFIER first: a known enum/tagged-union type other than `current_switch_cond_tu` rejects level-0 `error[3071]` (mismatch wording, qualifier span; mismatch wins over a missing member), a MODULE-namespace qualifier (`helper.LOMEM`, FX1's const item) is left to lowering, and an unverifiable qualifier is conservatively not rejected as foreign. A same-type qualifier with an unknown member and a shorthand `.bogus` case item (gated to case-item context by the new `switch_case_item` flag so prong BODIES keep the expected-type fall-through) reject 3071 with the member span; all sites dedupe per case-item node and carry a `union/enum declared here` related span. New reporter Table B row `semanticAnalyzerReportSwitchCaseQualifier`. The captured variants keep the unbound-capture `error[20]` cascade visible (no suppression, no `error[3060]` co-fires). Fixtures: reject `repro/mi_matrix/switch_case_qualifier_reject_xmod` (12 x 3071 + 2 x 20) + standalone `repro/switch_case_qualifier_reject.z98` (4 x 3071) + positive `repro/switch_case_qualified.z98`; the FE positive fixture gains alias/module-qualified-enum rows (golden 222 B / 21 lines, Zig-twin stderr byte-identical). 4-MD5 emitted-C UNCHANGED 8/8; valid-program emission byte-identical; fixed point `2012736050feb56f2d699ffb5fae38e1` -> `ce9906b62cb2b9ab7522d8cfafcf3cc9` (hop1 == hop2, explicit gate; seed v88 NOT rotated).] [updated: 2026-09-27 — FX3 fix round 1: `if`/`switch` VALUE expressions at f32 sites are now classified by their arms (new `semanticAnalyzerFloatNarrowStatusDepth` + `semanticAnalyzerFloatNarrowArmStatus`), so `return if (c > 0) 1.5 else 2.5;` and the `switch` form stay accepted (were over-rejected `error[3000]`); an inexact/runtime arm still rejects. Fixed point `8233580f…` -> `2012736050feb56f2d699ffb5fae38e1`; 4-MD5 UNCHANGED; corpus join-diff EMPTY; reject census unchanged (18 x `error[3000]`); positive golden 9 lines / 130 B; seed v88 NOT rotated.] [updated: 2026-09-27 — FX3 (Volume II defect fix, D6 extras): value-aware narrowing to f32. New `semanticAnalyzerFloatNarrowIsNumeric`/`semanticAnalyzerFloatNarrowStatus`/`semanticAnalyzerFloatNarrowRecord`/`semanticAnalyzerFloatNarrowReport` (see the new subsection above `tryRecordCoercion`) decide an f32 expectation site from the VALUE: an untyped `comptime_float` (float literal / literal-only `+ - * /`) is accepted and rounded; a typed comptime-known f64 or integer is accepted only when exactly representable; a runtime f64/i32 or inexact value rejects the site's level-0 `error[3000]`. Wired at function parameters (both call paths), returns, struct/union/tagged-union field initializers (incl. payloads), local/module declarations and assignments; `tryRecordCoercion` records the accepted narrowing when the source is not assignable, and the decl/assign/module sites record it directly. `CoercionKind.float_narrow` (coercion.zig) is deliberately NEVER returned by `classifyCoercion` (a value-blind f64 -> f32 would accept runtime values Zig rejects); `comptimeEvalFloatNarrow`/`floatNarrowProbe`/`floatNarrowDecl`/`comptimeIntF32Exact` (comptime_eval.zig, doc 04) supply the value+provenance and Zig's int-exactness check. Fixtures `repro/mi_matrix/stdlib_f32_narrow_ok_xmod` (positive; stdlib pin 257 -> 258) + `f32_narrow_reject_xmod` (18 x `error[3000]`) + standalone `repro/f32_narrow.z98`/`f32_narrow_reject.z98`; D06 gains `green_param.zig`. 4-MD5 emitted-C UNCHANGED; fixed point `325f741f…` -> `8233580ff281e73c006d04c5c91281e4` (hop1 == hop2; seed v88 NOT ROTATED). Bounded: the naive `parseF64` keeps an extreme typed literal `3.4028234663852886e38` rejected where Zig accepts (pre-existing float-literal precision residual, spec §7.2).] [updated: 2026-09-27 — FI (Volume II defect fix, operator ruling A): `for` iterates a pointer-to-array. `semanticAnalyzerResolveForHeader` now extracts the element type from a `ptr_type` iterable whose pointee is a fixed-size array (`*[N]T`, including the FH `*[0]T`/`*[1]T` slice results) with bounds-guarded payload reads, and `semanticAnalyzerCheckForIndexRangeComptime` applies its "non-matching for loop lengths" check to the pointee array's length for the explicit-range form. `for (p[0..1]) |v|` — the former FH over-rejection (`error[20]` on the capture) — runs again with the pre-FH `sum=42` shape; `for (p[0..0])`/`for (p[1..1])` iterate zero times; direct `for (pa) |v|`/`for (cpa) |v|` and `for (pa, start..end)`/`for (pa, start..)` match Zig 0.15.2 (including the comptime length reject `for (pa, 1..3)`). Every other pointer pointee (`*i32`, `*Point`, multi-level) keeps the pre-FI `error[20]` behavior, and array/slice/range iterables are byte-identical. Fixtures `repro/mi_matrix/stdlib_ptrarray_for_ok_xmod` (positive; stdlib pin 254 -> 255) + standalone `repro/ptrarray_for.z98`; D10 `control_slice_legal.zig` converted to include the former probe. 4-MD5 emitted-C UNCHANGED 4/4; corpus `-s0` 1053 = 900 OK / 49 GREEN / 104 FAIL (join-diff vs FH over the 1052 common dirs EMPTY; the only added dir is the new fixture, FAIL -> OK); fixed point `99ef01ad…` -> `b44a85111b1f89921ab1d46a752c61a5` (hop1 == hop2, explicit `FIXED_POINT_MD5` gate; seed v88 NOT ROTATED).] [updated: 2026-09-27 — FH (Volume II defect fix, D10): single-item-pointer indexing is a clean reject — `semanticAnalyzerResolveIndexAccess` rejects a `ptr_type` base whose pointee is not an array and a `type` base (`(*p)[i]`) with the new level-0 `error[3066]` (`type '*T' does not support indexing` / `unable to resolve comptime value`, Zig 0.15.2 wording, deduped per node, rc 2 / 0 `.c`); `semanticAnalyzerResolveSliceExpr`'s new `semanticAnalyzerCheckSinglePtrSlice` accepts only the comptime bounds `[0..0]`/`[0..1]`/`[1..1]` and returns Zig's `*[0]T`/`*[1]T` result (const/volatile carried via `typeRegistryGetOrCreatePtrQ`), rejecting every other form with the new level-0 `error[3067]` (the open `p[0..]` no longer ICEs `error[3043]`); struct/union array-field decays (`s.arr[i]`, `v.mag[0]`) keep their existing path via `semanticAnalyzerStaticArrayLen`. Table B gains `semanticAnalyzerCheckSinglePtrSlice`, `semanticAnalyzerReportIllegalPtrIndex`, `semanticAnalyzerReportPtrSliceBounded`/`Illegal`/`Runtime`, `semanticAnalyzerSpellTypeBack`/`SpellBytesBack`. Fixtures `repro/mi_matrix/stdlib_ptrslice_ok_xmod` (positive; stdlib pin 253 -> 254) + `ptr_slice_reject_xmod` (7 x `error[3066]` + 5 x `error[3067]`) + standalone `repro/single_ptr_slice_ok.z98` / `repro/single_ptr_index.z98`; D10 repro converted to the multi-code `fixedreject` census. 4-MD5 emitted-C UNCHANGED 4/4; corpus `-s0` 1052 = 899 OK / 49 GREEN / 104 FAIL (join-diff vs FB over the 1050 common dirs EMPTY); fixed point `d1ae4389…` -> `99ef01ad63ba37f98f327317608f577f` (hop1 == hop2, explicit `FIXED_POINT_MD5` gate; seed v88 NOT ROTATED).] [updated: 2026-09-26 — FC (Volume II defect fix, D5+D12): new `semanticAnalyzerConstDiscard` + `semanticAnalyzerMaybeDiagConstDiscard` (next to the volatile pair, see the subsection below) make every const-discarding coercion a level-0 `error[3000]` (`cannot implicitly discard 'const' qualifier`, deduped per node) across the frozen family slice->slice, slice->many, ptr->ptr and many->many; the check runs at local decl, assignment and module var and inside `tryRecordCoercion` (return, call args, field init). The legal const-ADDING directions are unchanged. Together with the D5 lowering fix (doc 07) this closes the `[]const T` -> `[*]T` silent-mutation hole. Fixtures `repro/mi_matrix/const_discard_reject_xmod` (17 x `error[3000]`, rc 2 / 0 `.c`) + `stdlib_slice_to_many_ptr_xmod`; standalone `repro/const_discard.z98` (8) / `repro/slice_to_many_ptr.z98`. Fixed point `cadf3c24…` -> `effa5a6aae9f11266597196561186f1b` (hop1 == hop2; seed v88 NOT rotated).] [updated: 2026-09-26 — FF (Volume II defect fix, D6+D9): the five type-introspection builtins now validate in sema before lowering via the new `semanticAnalyzerCheckIntrospectionBuiltin` + `semanticAnalyzerRejectIntrospection` + `semanticAnalyzerIntrospectionTypeLabel` (see the subsection below) — `@offsetOf`/`@bitOffsetOf` are struct-only (`error[3072]` `expected struct type, found 'X'`), unknown/non-literal field names reject `error[3073]`, unresolved/incomplete types and wrong arity reject `error[3074]`; every former `error[3043]` ICE on the path is gone (rc 2 / 0 `.c`). Fixed point `536ed494…` -> `cadf3c241abd1baf4d31da52b0ccd649` (hop1 == hop2; seed v88 NOT rotated).] [updated: 2026-09-26 — FE (Volume II defect fix, D8+D11): the `semanticAnalyzerResolveSwitchExpr` case-item loop gains an `AstKind.field_access` arm calling the new `semanticAnalyzerResolveSwitchCaseMember` (new subsection below `semanticAnalyzerResolveEnumLiteral`), so a container-qualified prong (`Shape.circle`, `Color.red`, `mod.Type.member`) fills `enum_value_table` + the resolved type exactly like the shorthand and the capture binding registers normally; the capture-binding block additionally registers an `enum_type`-condition capture with the enum type (Zig-style operand-value capture). No bogus-member/foreign-qualifier validation (FX4). Fixture `repro/mi_matrix/stdlib_errset_capture_qualified_xmod` + standalone `repro/errset_capture_qualified_prong.z98`; D11 repros RED->GREEN incl. the bundled unused-capture SIGSEGV guard (lower.zig, doc 07).] [updated: 2026-09-26 — FA-a fix round 1 (Volume II defect fix, D3): the mandatory-`else` gate is now the shared `semanticAnalyzerReportSwitchWithoutElse` and also fires from the two zero-prong early returns (`payload == 0`, `prongs_n == 0`), closing the `switch (x) {}` escape (it used to compile rc 0 and read the poisoned result temp in value position).] [updated: 2026-09-26 — FA-a (Volume II defect fix, D3): the strict mandatory-`else` gate now lives at the end of `semanticAnalyzerResolveSwitchExpr` (the old empty `if (has_else == 0) {}` tombstone is filled): a `switch` without an `else` prong emits level-0 `error[3068]` `ERR_3068_SWITCH_WITHOUT_ELSE` (`switch must have an 'else' prong`) at the switch node's span, deduped per node via `diagnosticCollectorMarkNodeOnce`, for value AND statement position (both resolve through this function) — rc=2 / 0 `.c`. The D3 uninitialized-result-temp path in lowering is hence unreachable for accepted programs. The dead `constraint_checker.checkSwitchExhaust` (old `ERR_3004`, no production caller, scalar-exempt) is DELETED, together with its two `test_semantic_bin.zig` callers. Migrated no-`else` switches: the compiler's 3 (`async_state_machine.remapInst` identity `else => return inst`, `dump_ast.astKindToString` `unknown` fallback, `dump_tokens.tokenKindToString` names `c_include_builtin`/`kw_anytype`/`kw_volatile` + `unknown` else) and 12 `examples/z98` sites.] [updated: 2026-09-25 — Task 9 fix round 3 (z98-print-formatting Amendment 1, B5; operator ruling Q7): `semanticAnalyzerResolveTupleLiteral` no longer rejects a changed element list — it rebuilds the tuple from the freshly resolved element types (returning the recorded type only when the list is unchanged, preserving the Task-4 one-C-type idempotence), and `frontResolveModuleInits` (`front_resolution.zig`) now UPDATEs an unannotated module binding's decl record and symbol type when the re-resolved init type differs, so a forward-referenced global's true type settles over the fixpoint (annotated bindings keep their annotation). The fix-round-1/2 `semanticAnalyzerTupleElem*` reject helpers are deleted; `error[3064]` is emitted only by the dependency-cycle detectors in lowering. Fixtures: positive `stdlib_print_tuple_fwd_ok_xmod` 21 rows, reject `tuple_fwd_global_reject_xmod` 1 x `error[3064]`, standalone `repro/print_tuple_fwd.z98` positive.] [updated: 2026-09-25 — Task 9 fix round 2 (z98-print-formatting Amendment 1, B5; review Critical 1 + Important 1): the recorded-element checks now recognise parenthesized references (`semanticAnalyzerUnwrapParens`), aliased module members and `@import(...).C` members (`semanticAnalyzerTupleElemGlobalSym`; the direct import form clears an `allow_inline` flag because the lowerer never inlines it), and apply the order/inline test to EVERY element regardless of type deltas (`semanticAnalyzerTupleElemSubtreeOrderOk`, child-fields-only), so the same-type silent-wrong shapes (`const s: i32 = 5 + 7`, `-5`, `@as(i32, 5)`) reject while parenthesized/aliased literal refs and earlier-declared globals stay accepted. `integer_literal` slots fit via the 32-bit-signed materialisation. Fixtures: positive `stdlib_print_tuple_fwd_ok_xmod` 9 rows, reject `tuple_fwd_global_reject_xmod` 11 x `error[3064]`; standalone `repro/print_tuple_fwd.z98`.] [updated: 2026-09-25 — Task 9 fix round 1 (z98-print-formatting Amendment 1, B5 narrowing; operator ruling): the recorded-tuple re-resolution now rejects only the BROKEN shapes. `semanticAnalyzerTupleElemRefreshOk` treats a changed element as benign when the recorded slot is the pass-1 `TYPE_I32` fallback, the element is a module `const` (not `var`), its init is a bare `int_literal`/`char_literal`, and the folded value also fits `i32` (the literal is inlined at the use site, so the frozen slot holds it exactly — `const s = 5` in `.{ s, 7 }`); composite/pointer/float/bool elements, out-of-i32 literals, and non-literal scalar inits still reject the new level-0 `error[3064]` (rc=2 / 0 `.c`). Positive fixture `stdlib_print_tuple_fwd_ok_xmod` (stdlib pin 241 -> 242), reject fixture `tuple_fwd_global_reject_xmod` (6 x `error[3064]`), standalone `repro/print_tuple_fwd.z98`.] [updated: 2026-09-25 — Task 9 (z98-print-formatting Amendment 1, B5): `semanticAnalyzerResolveTupleLiteral`'s recorded-type fast path now re-resolves the elements and compares them with the recorded tuple payload; a CHANGED element list meant pass 1 froze the `TYPE_VOID -> TYPE_I32` fallback for a forward-referenced global, so the shape clean-rejected with the new level-0 `error[3064]` `ERR_3064_FORWARD_REF_TUPLE_GLOBAL` (deduped per node, rc=2 / 0 `.c`) while the recorded type was still returned (no cascading errors). A stable re-resolution keeps the Task-4 idempotent fast path. Fixture `tuple_fwd_global_reject_xmod` + standalone `repro/print_tuple_fwd.z98`.] [updated: 2026-09-25 — Task 4 (z98-print-formatting): `semanticAnalyzerResolveTupleLiteral` resolves all elements before appending their types to `xt`, so a nested tuple literal can no longer shift the outer tuple's element range (its C model/printer saw `i32` instead of the nested tuple type); see `semanticAnalyzerResolveTupleLiteral`.] [updated: 2026-09-24 — Task 18 (F): related-span diagnostics + non-ASCII message audit. Every `error[3057]` shadow/redeclaration diagnostic now renders a related span at the earlier declaration (`note: previous declaration here` for a local/param/capture, `note: declared here` for a container-level symbol) via `diagnosticCollectorAddRelatedSpan` — the shadow check's local scan uses the new parallel `local_decl_spans_start`/`local_decl_spans_end` arrays (written at every registration site, grown by `semanticAnalyzerGrowLocalDecls`), and the container-level path uses the symbol's `decl_node` span. `semanticAnalyzerCheckLocalShadow` no longer emits the locationless `AddNote`; the collector reserves related-span slot 0 as the "none" sentinel so the first real span renders (index > 0). Also the five `error[3000]` message strings that embedded a UTF-8 em dash (return / function argument ×2 / assignment / variable declaration) are now ASCII ` -- `; audit: no diagnostic message string in `sf/src` contains non-ASCII bytes (the only remaining non-ASCII string literals are the emitted-C prelude comments in `emit_support.zig`, not diagnostics). Fixtures `repro/mi_matrix/shadow_related_span_xmod` + standalone `repro/shadow_related_span.z98`, Zig-0.15.2 note-location cross-check; fixed point `ea5d77ea…` -> moving point `13e9458114537ca669f21816762a4f30` (hop2 == hop3); 4-MD5 emitted-C UNCHANGED] [updated: 2026-09-24 — Task 18 (F) fix round (review Important 1): the base entry's "only Zig-note-with-location family" claim was corrected — four more families now emit related spans: `error[3061]` arity -> `note: function declared here` at the callee fn decl (`semanticAnalyzerReportCallArity` gains `decl_node`/`decl_file`), `error[3007]` visibility -> `note: declared here` at the non-`pub` declaration in its own file (both `semanticAnalyzerCheckMemberVisibility` and `typeResolverCheckMemberVisibility`; `Symbol` gains `file_id`, set from the declaring module in `symbol_registrator.registerDecl`), `error[3060]` member-not-found -> `note: struct/union/enum declared here` at the aggregate declaration (new `semanticAnalyzerFindTypeDecl` reverse lookup over the owning module's `type_alias` symbols; anonymous types and error sets get no note, matching Zig), and `error[3000]` call-arg -> `note: parameter type declared here` (new `semanticAnalyzerParamDeclNode`; new `semanticAnalyzerCalleeDeclSymbol` resolves ident + single-level `mod.fn`/`@import("x.zig").fn` callees — nested `std.io.print()` stays un-noted, bounded). Fixtures' expected notes pinned in their headers; Zig-0.15.2 note loci match. Fixed point `13e94581…` -> moving point `b7a7da2673d60852006e9ea87909be1d` (hop2 == hop3); 4-MD5 emitted-C UNCHANGED; corpus `-s0` 1016 = 878/46/92 zero movement] [updated: 2026-09-24 — Task 17 (F) fix round (review Important 1): the slice start check runs only against a comptime-known effective end — `alen` for the open form `a[s..]` (`child_2 == 0`), the folded end for a closed form with a comptime end; a closed form whose present end is RUNTIME (`a[7..ri]`) is skipped and keeps its pre-Task-17 runtime behavior (the base version fell back to `alen` and over-rejected `start index 7 is larger than end index 5` though Zig accepts the shape). Regression `repro/mi_matrix/slice_runtime_end_xmod` (compile rc 0; `-fsafe` rc 133 via the runtime cast guard, `-ffast` `len=-4`; emitted C byte-identical to the pristine compiler) + a runtime-end control in `stdlib_comptime_index_ok_xmod`; fixed point `44a3ce38…` -> moving point `ea5d77ea5c1f4fddd7cd0ab213476923` (hop2 == hop3); 4-MD5 emitted-C UNCHANGED] [updated: 2026-09-24 — Task 17 (F): comptime-known out-of-bounds index / constant slice-range reject. `semanticAnalyzerResolveIndexAccess` (fixed-size-array bases only) and `semanticAnalyzerResolveSliceExpr` now run `semanticAnalyzerCheckComptimeIndexOob` / `semanticAnalyzerCheckComptimeSliceBounds`, which fold the index/bounds (`semanticAnalyzerComptimeIntValue`: literals / `const` chains / constant arithmetic / `.len` recovered through `semanticAnalyzerStaticArrayLen`) and emit the new level-0 `error[3062]` `ERR_3062_INDEX_OUT_OF_BOUNDS` with official Zig 0.15.2's exact ASCII wording (`index N outside array of length L`, `end index N out of bounds for array of length L`, `start index S is larger than end index E`, `type 'usize' cannot represent integer value '-N'`) — rc=2, 0 `.c`. The fixed length comes from an array value, a `*[N]T`, or a struct/union array field (`semanticAnalyzerArrayFieldLength`, factored out of the Task-11N `.len` helper); a slice / `[*]T` / string literal (sentinel) is skipped, and a runtime index keeps its unchanged `-fsafe` `check_trap{kind=5}` guard. Before the fix `scores[5]` and `scores[scores.len]` on `[5]i32` compiled rc=0 and silently misread under `-ffast`] [updated: 2026-09-24 — Task 14 fix round (review Critical 1): the call-arg gates compute `!assignable and (isBShapeMismatch(self, carg, tgt, false) or !semanticAnalyzerCallArgTolerated(self, carg, tgt))` — the pointer-family tolerance no longer swallows the pre-existing `isBShapeMismatch` call-site rejects for `*T` -> `[]T` (rc=0 + gcc `incompatible types` before the fix) and mismatched `[N]T` -> `[M]T` (rc=0 + silent array decay); both restored to rc=2 / 0 `.c` / `error[3000]`, with oracle-checked regression sites in `call_arg_type_reject_xmod` and valid `&arr` -> `[]T` / same-length `[N]T` controls in `stdlib_call_arity_types_ok_xmod`] [updated: 2026-09-24 — Task 14 (S2): `semanticAnalyzerResolveFnCall` now enforces the callee's arity at the call site (new level-0 `error[3061]` `ERR_3061_WRONG_ARGUMENT_COUNT`, Zig's "expected N argument(s), found M" wording; variadic too-few is "expected at least N") and per-argument assignability for CROSS-FAMILY mismatches (`error[3000]` "type mismatch in function argument" + source/target notes), on both the direct-call and fn-value paths, rc=2 / 0 `.c`; arity was formerly a silent early return and `add(1, true)` silently coerced bool->i32. `semanticAnalyzerCallArgTolerated` keeps Z98's established implicit conversions (integer<->integer of any width/signedness, the pointer/slice/array family, error-set->int for `@enumToInt(<error set>)`, and void/unresolved sources)] [updated: 2026-09-24 — Task 13 fix round (C1/I1): the `error[3060]` reject is now emitted by the shared `semanticAnalyzerReportUnknownMember` helper (ASCII message tail names the base kind: struct/union/slice/array/enum/error-set/`type`), called from every "member not found" path — Phase 5, the enum/error-set arms and the non-aggregate `else` arm. **C1:** the Task-11N array-field `.len` recovery (`semanticAnalyzerArrayFieldLenCheck`) runs BEFORE every reject, so `.len` on an array field works for every element kind (`[N]Point` decays to `*Point` and used to false-reject); **I1:** a member access/call on a non-aggregate base (`const x: i32 = 5; x.foo();`) now rejects instead of compiling rc=0 and emitting an undeclared callee temp. Valid members/module access/`.len`/`.ptr`/`.tag`/`.payload`/real fields are unchanged] [updated: 2026-09-24 — Task 13 (S1): a member not found on a struct/union/packed_union/tagged_union value now clean-rejects with the new level-0 `error[3060]` (`ERR_3060_METHOD_SYNTAX_NOT_SUPPORTED`, message "no field or member function named '<name>' in struct/union type") — see §semanticAnalyzerResolveFieldAccess Phase 5; this closes the spec-forbidden method syntax `value.func()` (which previously compiled rc=0 and emitted an undeclared callee temp, `zT_N = zT_undeclared();`) and unknown aggregate members, while valid free-function calls and real field accesses are unchanged] [updated: 2026-09-24 — Task 11 (Part II): the explicit index-range `for (iterable, start..end)` pattern (`AstKind.for_index_range`) types as its iterable and validates/resolves its bounds in `semanticAnalyzerResolveForIndexRange` (usize-compatible unsigned bounds; comptime length/overflow/negative rejects; missing-index-capture reject), see §semanticAnalyzerResolveIfHeader / ForHeader / WhileHeader] [updated: 2026-09-23 — Task 4 fix round (review Important 3): `semanticAnalyzerResolveModuleVarDecl` now applies the same value-based selection to an UNANNOTATED MODULE binding — when the resolved init type is `INT_LIT`/`I32` and the folded integer does not fit i32, the value-based type is returned so `front_resolution` stores it on the decl node AND the symbol (`const X = 2000000000 + 1000000000;` is a u32 global; it previously stored a u32 fold into an `int` global and ran truncated)] [updated: 2026-09-23 — Task 4 (coercion into typed slots): the `var_decl` arm re-types an UNANNOTATED binding whose initializer folds (via a fresh `comptime_eval` probe with `local_consts` wired) to an integer outside i32 with the value-based type (`comptimeIntUntypedType`: U32/I64/U64), so the slot, the init HIT temp, and every later reference agree (`const c = 2000000000 + 1000000000;` is u32; after the Task 4 fix `const x = 3000000000;` prints the exact value instead of `-1294967296`). Values that fit i32 (and non-integer inits) keep the existing INT_LIT typing — emitted C for the common case is unchanged] [updated: 2026-09-23 — Task 9D fix round 3 (ruling m1293 (b), bounded divergence): the condition probe's comparison fold is conservative — an operand whose signedness cannot be derived from a declared type / literal sign / `@intCast`-`@as` target makes the comparison unfoldable, so a no-`else` value `if` on `(umax - 1) > 0`, `umax > (0 + 0)`, `(a + 1) == 2` etc. rejects `error[3059]` even though Zig 0.15.2 accepts (documented divergence, fixture `comptime_compare_diverge_reject_xmod`); the still-supported `umax > 0`, `uu > -1`, `uu > (0 - 1)` cases are unchanged] [updated: 2026-09-23 — Task 9D fix round 2: the condition probe's comparison fold is signed per operand, so a declared-unsigned const does not mask a negative literal — `const u: u8 = 200; var x: i32 = if (u > -1) 1;` (and `-1 < u`, `u > (0 - 1)`) is accepted and true; `umax < 0` and `run and false`/`run and true` stay rejected (all Zig 0.15.2-matched)] [updated: 2026-09-23 — Task 9D fix round 1: the condition probe's fold now compares by each operand's DECLARED integer type (a `u64` const above i64 max compares unsigned: `const umax: u64 = 18446744073709551615; if (umax > 0)` is accepted, `if (umax < 0)` is rejected) and a decisive RHS of `and`/`or` folds even when the lhs is runtime (`if (run or true)` is accepted, `if (run and false)`/`if (run and true)` stay rejected) — all matching official Zig 0.15.2] [updated: 2026-09-23 — Task 9D: `semanticAnalyzerConditionIsComptimeTrue` now sets `ce.local_consts = &self.local_consts` on the fresh `comptime_eval` probe, so the no-`else` value-`if` comptime-true decision sees function-local `const`s; combined with the Task 9D fold extension (integer comparisons + bool logical ops, short-circuit), a comptime-known-true comparison condition now permits a no-`else` value `if` (`const a: i32 = 1; var x: i32 = if (a == 1) 1;`), matching official Zig 0.15.2. A runtime `var` condition still does not fold and stays rejected `error[3059]`] [updated: 2026-09-22 — Task 9B (invalid condition/`if` forms): `semanticAnalyzerCheckConditionType` (called by the shared if/while headers after the capture block) requires a `bool` condition when there is no capture and an optional/error-union condition when there is one, else level-0 `error[3058]`; `semanticAnalyzerResolveIfExpr`'s `child_2 == 0` branch emits level-0 `error[3059]` when the then-type is not void/noreturn/undefined and the condition is not comptime-known-true (helper `semanticAnalyzerConditionIsComptimeTrue` folds via `comptime_eval` and requires a bool-width result). Both match official Zig 0.15.2 and reject with rc=2 / 0 `.c`; fix round 1 widens the `error[3059]` gate to also accept an optional/error-union condition (capture), so `if (o) |v| v` is rejected too] [updated: 2026-09-22 — Task 7D: Zig-matching local shadow rejection. A new `semanticAnalyzerCheckLocalShadow(name_id, span_start, span_end)` is called immediately before every local-registration site (local `const`/`var`, function params, `if`/`while`/`for` captures, switch-prong captures, `catch` payloads, function-local named types); it scans the scope-truncated `local_decl_names` newest-first (a hit = strictly-enclosing or same-scope declaration = Zig shadow/redeclaration) and also rejects shadowing a container-level symbol (`global`/`function`/`type_alias`/`module`) in the current module, emitting the dedicated level-0 `error[3057]` (`ERR_3057_LOCAL_SHADOW`) at the shadowing declaration. `_` (the discard) is exempt. To make the scan see exactly the currently-in-scope bindings, the block-scoped local-decl machinery is re-applied AND extended to expression-position scopes: the stmt walker pushes a scope-pop marker (`0x80000000 | saved_depth`) for blocks and `if`/`while`/`for` statements, the switch drain pops per prong, `catch` resolves its handler synchronously then pops, and `if_expr`/`orelse_expr`/expression-position `block` (draining any deferred statement work before restoring) pop in `semanticAnalyzerResolveExpr`. Non-forms: `else |e|` payloads and nested `fn` are not enforced] [updated: 2026-09-22 — Task 7B: `semanticAnalyzerResolveAssign` now enforces `const` — after resolving the l-value it calls the new `semanticAnalyzerIsLValueConst` helper and clean-rejects a write to an immutable l-value with level-0 `error[3002]` "cannot assign to immutable variable" at the l-value span (rc=2, 0 `.c`), covering a const local/param/capture, a module `const` (var_decl-backed), a `*const T` deref, and a `[]const T` element; `_ = expr;` stays exempt. The helper only READS the already-populated resolved-type/symbol/local tables (no re-resolve, so an undeclared base keeps its single `error[3001]`). A new parallel `local_decl_consts: [*]u8` bit tracks local/param/capture constness (set at every `local_decl_names` registration site); `.tag`/optional-member writes on a mutable binding remain legal] [updated: 2026-09-22 — Task 6F: `semanticAnalyzerResolveIdent`'s undeclared-identifier fallback now emits `error[3001]` (numeric code 20) "identifier '<name>' is not declared or imported in this module" with a precise `file:line:col` span instead of silently returning `TYPE_VOID`; the `_` discard sentinel (`_stub_0`) still returns `TYPE_UNDEFINED` silently by design. The redundant `error[3001]` emission in `semanticAnalyzerResolveFieldAccess`'s `else if (base_rt == TYPE_VOID)` branch is dropped (the branch keeps its early return), so an undeclared field base emits exactly ONE diagnostic — the `resolveIdent` one] [updated: 2026-09-22 — Task 6D: `semanticAnalyzerResolveFnCall`'s non-`fn_type` Phase-2 branch still returns `TYPE_VOID` with no diagnostic; the callability rejection (`error[3056]: expression is not callable`) is emitted in LIR lowering on the lowered callee temp (variant C), because a resolved-type check misses the flat non-pub module member whose sema type is `TYPE_VOID` — see `07_lir_lowering.md` Function Calls] [updated: 2026-09-21 — Task B2 final fix wave: the `var_decl` arm's local-type-value guard now fires for a `var` binding of a container type (invalid Zig — a `type` value must be `const`) and for a compound type-expression initializer (`*E`/`E!i32`/`[N]E`/`?E`/`fn(...)`/`[]E`/`[*]E`, via `type_resolver.isCompoundTypeExprKind`), both clean-rejecting `error[3000]` with 0 `.c` instead of leaking `TYPE_TYPE` into lowering; the pre-existing bare local-alias (`const F = E;`) reject is unchanged] [updated: 2026-09-21 — Task B3 item 6: corrected the `defer_stmt`/`errdefer_stmt` arm's call-site comment (the `semanticAnalyzerCheckDeferBody` walk deliberately does NOT descend into a nested defer/errdefer; the nested body is validated by its own invocation when the statement walk reaches it, with the inner-target state reset here so the nested scope starts from a clean `cur_defer_node` chain) — comment only, no behavior change] [updated: 2026-09-21 — Task B2 fix round 1: `semanticAnalyzerCheckLocalEnum` is now a thin wrapper over the shared `type_resolver.validateLocalEnum` (the strict local/inline enum walk + ERR_3055 emission), so inline enums validated by `registerContainerType` and the sema binding/expression forms cannot diverge] [updated: 2026-09-21 — Task B2: the `var_decl` arm binds a function-local named type (`const T = struct/enum/union/error{...}`) as a TYPE — `registerContainerType` + `layoutEnsure`, recorded in `local_decl_names`/`local_decl_types`, pushed into a new `local_types` scope, WITHOUT a `nameCachePut` — and skips the value path; a local type alias (`const F = E;` naming a local type) clean-rejects with `error[3000]`] [updated: 2026-09-21 — Task 11J fix round 1 (AMENDMENT 13): `semanticAnalyzerCheckLocalEnum` runs the shared enum-member walk in check-only strict mode for a function-local `enum_decl` expression, rejecting a duplicate tag / unfoldable initializer with `ERR_3055`] [updated: 2026-09-21 — Task 11J: the enum gate is a pure backing-width fit-check (it does NOT re-run the evaluator); the post-layout `enumReevaluateAll` pass is the single evaluation point that writes `em_items[].value`] [updated: 2026-09-21 — refreshed against current source: socket builtins removed (std_net extern surface), async/introspection/pointer/bitcast builtins, volatile + packed/enum checks, spill-backed resolved-type table; line refs and dated evidence removed; Task 10D adds the Zig-matched `defer`/`errdefer` outward-control-flow rejections ERR_3051–ERR_3054; Task 11N adds `semanticAnalyzerArrayFieldLen` so `.len` on a struct/union array field resolves to `TYPE_USIZE` despite the array-field decay, gated on the accessed name being `len` (fix round 1); Task 11P resolves the `for`-range start/end operands in the `range_exclusive`/`range_inclusive` arm before returning `TYPE_U32`] [updated: 2026-09-24 — Task 15 (S3): cross-module `pub` visibility enforcement. `semanticAnalyzerResolveFieldAccess` now runs `semanticAnalyzerCheckMemberVisibility` on every module-member lookup (flat `SymbolKind.module` arm, direct-`import_expr` arm, and the nested `module_type` arm) BEFORE using the field symbol: a symbol owned by a different module without the `pub` flag (bit 1) clean-rejects with level-0 `error[3007]` `ERR_3007_VISIBILITY_VIOLATION`, ASCII message `'<name>' is not marked 'pub'` (official Zig 0.15.2 wording), at the field-access span and returns `TYPE_VOID` (rc=2, 0 `.c`). Before this gate a non-`pub` function was callable across modules (`helper.secret(21)` compiled rc=0 and ran), a non-`pub` const read folded silently, and the nested/direct-import shapes had no check at all; same-module access never routes through these arms and is unchanged. `sf/src/type_resolver.zig:typeResolverCheckMemberVisibility` applies the same rule to type positions (`var x: mod.HiddenAlias`, `mod.Hidden{...}`) — see `03_type_resolution.md`] [updated: 2026-09-24 — Task 15 (S3) fix round 1: the type-resolver const-fold positions are gated too (`evalConstIntFull`'s `field_access` arm — array sizes and enum member values), so `[mod.hidden_const]u8` / `enum(u8){A = mod.hidden_const}` now reject `error[3007]` instead of folding; fixture `pub_visibility_fold_reject_xmod`, positive fold controls in `stdlib_pub_visibility_ok_xmod`; fixed point `b6bcb1bb…` → moving point `c9e5d744…` (hop2 == hop3)] [updated: 2026-09-26 — FB (Volume II defect fix, D4): `semanticAnalyzerResolveFieldAccess` gains a `tuple_type` base arm — the field name is decoded textually (`typeRegistryTupleOrdinalFromNameId`, `^[0-9]+$`/`^_[0-9]+$`), an out-of-range ordinal emits level-0 `error[3070]` (`index N outside tuple of length L`), an array element decays to `*elem` exactly like a struct array field, and a non-decimal name falls through to the existing `error[3060]` (so `.73` on a struct is `named '73'`, never a name-id alias). `semanticAnalyzerResolveIndexAccess`'s tuple arm folds the index with `semanticAnalyzerComptimeIntValue` (local consts included), rejects a non-comptime index with level-0 `error[3069]` (`tuple field index must be comptime-known`), rejects negatives with the array path's 3062 wording, rejects an out-of-range ordinal with `error[3070]`, converts an array element to `*elem` and records the node->ordinal in the new `tuple_index_table` (plumbed sema->lower like `enum_value_table`). A spelled tuple type with an array element is rejected at registration (`tupleElemArrayUnsupported`, `error[3000]`); inferred tuple literals may hold arrays (print already rejects them 3063) but a distinct tuple-to-tuple assignment with an array element is a level-0 mismatch (`typeRegistryIsAssignable`'s tuple arm requires no array on either side); `isBShapeMismatch` maps tuple/tuple to level 0. New Table B rows: `semanticAnalyzerReportTupleIndexNotComptime`, `semanticAnalyzerReportTupleIndexOob`, `tupleElemArrayUnsupported`.]

> Covers: `semantic_analyzer.zig`, `coercion.zig`, `resolved_type_table.zig`, `constraint_checker.zig`, `assign_helper.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `SemanticAnalyzer` fields | 89 | 54 non-`_name_id` (adds `local_decl_spans_start`/`local_decl_spans_end`, Task 18; adds `switch_case_item`, FX4) + 35 `_name_id` (the 35th is `discard_name_id`; 34 builtin name IDs, 11 socket IDs removed) |
| Expression kind dispatch arms | 47+ | Every `AstKind` handled in `semanticAnalyzerResolveExpr` |
| `CoercionKind` variants | 18 | `none` through `float_narrow` (row 17 `tuple_to_tuple`, row 18 `float_narrow`; the latter is sema-recorded only) |
| Coercion checks in `classifyCoercion` | ~20 | noreturn/undefined, null, optional, error union, ptr/slice/many-ptr (qualifier-monotone), array, widening, literal |
| Marker codes | 90+ | `IDE`, `D7`, `L`, `S`, `STY`, `FAE`, `PFA`, `FAPR`, `COE`, `CCK`, `COR`, `SIF`, `MIX`, `SWU`, etc. |
| Expected-type stack | stack-based | Push/pop in calls, returns, assigns, struct init, var decls, switch prongs |
| Resolved type table | `node_idx→TypeId` | Dense 5 B/node spill table + sparse resident source map |
| Constraint checks | 2 | Return type, break/continue validation (the dead `constraint_checker.checkSwitchExhaust` is deleted by FA-a; the mandatory-`else` rule `error[3068]` lives in `semanticAnalyzerResolveSwitchExpr`) |
| assign_helper | 1 | `resolveAssignedLocalTemp` (lowering-side lookup) |

---

## semantic_analyzer.zig (`sf/src/semantic_analyzer.zig`, 3438 lines)

Central phase-5 engine. Walks function bodies bottom-up via a worklist and resolves every expression to a `TypeId`. Records coercions for lowering and emits diagnostics for type errors.

### SemanticAnalyzer struct (`sf/src/semantic_analyzer.zig`)

```zig
pub const SemanticAnalyzer = struct {
    type_table: *ResolvedTypeTable,
    diag: *DiagnosticCollector,
    registry: *TypeRegistry,
    symbols: *SymbolRegistry,
    store: *AstStore,
    module_id: u32,
    source_file_id: u32,
    expected_type_stack_items: [*]TypeId,
    expected_type_stack_len: usize,
    expected_type_stack_cap: usize,
    expected_type_stack_alloc: *Sand,
    stmt_work_items: [*]u32,
    stmt_work_len: usize,
    stmt_work_cap: usize,
    current_fn_return: TypeId,
    current_fn_name: u32,
    coercion_table: *coercion_mod.CoercionTable,
    enum_value_table: *hash_mod.U32ToU32Map,
    error_code_registry: *hash_mod.U32ToU32Map,
    call_arg_types: *hash_mod.U32ToU32Map,
    call_param_map: *hash_mod.U32ToU32Map,
    current_switch_cond_tu: u32,
    switch_depth: u32,
    defer_depth: u32,
    defer_inner_loops: u32,
    defer_label_stack: [16]u32,
    defer_label_isloop: [16]u8,
    defer_label_len: usize,
    local_decl_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_consts: [*]u8,
    local_decl_count: usize,
    local_decl_cap: usize,
    discard_name_id: u32,
    local_consts: type_resolver.LocalConstScope,
    packed_gate_items: [*]u32,
    packed_gate_len: usize,
    packed_gate_cap: usize,
    packed_struct_tids: [*]u32,
    packed_struct_decl_nodes: [*]u32,
    packed_struct_cache_len: usize,
    packed_struct_cache_cap: usize,
    checked_struct_tids: [*]u32,
    checked_struct_tids_len: usize,
    checked_struct_tids_cap: usize,
    _stub_0: u32,
    _stub_1: u32,
    interner: *interner_mod.StringInterner,
    // 34 builtin name IDs (socket IDs removed netbind S3, 2026-09-04):
    ptrcast_name_id, volatilecast_name_id, ptrtoint_name_id, inttoptr_name_id,
    int_from_ptr_name_id, ptr_from_int_name_id, field_parent_ptr_name_id,
    bitcast_name_id, intcast_name_id, floatcast_name_id, inttofloat_name_id,
    inttoenum_name_id, enumtoint_name_id, as_name_id,
    size_of_name_id, align_of_name_id, offset_of_name_id,
    bit_size_of_name_id, bit_offset_of_name_id,
    putchar_name_id, stdout_write_name_id, stderr_write_name_id,
    getchar_name_id, exit_name_id, panic_name_id, sleep_ms_name_id,
    is_windows_name_id, console_clear_name_id, console_gotoxy_name_id,
    console_set_color_name_id,
    async_frame_size_name_id, async_init_name_id, async_resume_name_id,
    async_suspend_name_id,
    async_analysis_ready: bool,
    module_reg: *mr_mod.ModuleRegistry,
    suspending_fns: *hash_mod.U64ToU32Map,
};
```

Key state: expected-type stack for contextual type inference (enum literals, error literals, null), statement worklist for iterative traversal, switch context for enum literal resolution, local declaration shadow stack + function-local `const` scope, packed-struct gate/checked caches, and async suspending-function registry.

### semanticAnalyzerInit (`sf/src/semantic_analyzer.zig`)

`[inference: sandAlloc-builtin name interning, zero-init stacks/lists, return SemanticAnalyzer]`

Allocates no heap memory in the struct itself. Interns the 34 builtin names and the discard identifier `_`: (`@ptrCast`, `@volatileCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@bitCast`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@enumToInt`, `@as`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@putChar`, `@stdoutWrite`, `@stderrWrite`, `@getChar`, `@exit`, `@panic`, `@sleepMs`, `@isWindows`, `@consoleClear`, `@consoleGotoxy`, `@consoleSetColor`, `@asyncFrameSize`, `@asyncInit`, `@asyncResume`, `@asyncSuspend`). Stacks and work arrays are zero-capacity — grown on first use. The 11 socket names are no longer interned.

### semanticAnalyzerIsTypeValueCast (`sf/src/semantic_analyzer.zig`)

`[inference: match name_id vs 8 cast builtins → return bool]`

Checks if name_id matches `@ptrCast`, `@volatileCast`, `@intToPtr`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, or `@as`. Used by builtin_call dispatch in ResolveExpr to short-circuit as type-value cast.

### semanticAnalyzerIsBuiltinSupported / semanticAnalyzerBuiltinNameEq (`sf/src/semantic_analyzer.zig`)

`[inference: name-id allow-list + string-equality fallbacks → bool]`

`semanticAnalyzerIsBuiltinSupported` is the allow-list gating the builtin_call arm; `semanticAnalyzerBuiltinNameEq` compares an interned name against a literal for builtins without a dedicated name-id field (`@enumToInt`, `@cVaStart`, `@cVaArg`, `@cVaEnd`, `@panic`).

### semanticAnalyzerCheckIntrospectionBuiltin / semanticAnalyzerRejectIntrospection / semanticAnalyzerIntrospectionTypeLabel (`sf/src/semantic_analyzer.zig`)  [added: 2026-09-26 — FF, Volume II D9]

`[inference: arity gate → resolve type arg → kind/field validation → diagnostic]`

Volume II D9's Zig-0.15.2-parity validation of the five introspection builtins, called from the `builtin_call` arm of `semanticAnalyzerResolveExpr` before lowering:

- **Arity** (`semanticAnalyzerCheckIntrospectionBuiltin`): `@offsetOf`/`@bitOffsetOf` exactly 2 args, `@sizeOf`/`@alignOf`/`@bitSizeOf` exactly 1; otherwise `error[3074]` `ERR_3074_COMPTIME_BUILTIN_UNRESOLVED` with the house `expected N argument(s), found M` wording.
- **Target resolution**: `resolveTypeExprFull`; `TYPE_UNDEFINED`/out-of-range → `error[3074]` (`unable to resolve type argument`); a resolved type with `state != 2` → `error[3074]` (`type argument is not complete`).
- **Offset target kind**: `@offsetOf`/`@bitOffsetOf` require `struct_type` (packed structs included); every union kind and every scalar/pointer/enum/array/slice/optional/error-union/fn target emits `error[3072]` `ERR_3072_OFFSET_TARGET_NOT_STRUCT` (`expected struct type, found 'X'`; the label is the interned type name or a kind word for an unnamed composite).
- **Field name**: must be an `AstKind.string_literal` naming an existing struct field; a non-literal name (including a resolvable string `const`, a documented Z98 divergence — Zig folds it) emits `error[3073]` `field name must be a string literal`, an unknown name emits `error[3073]` with Zig's `no field named 'x' in struct 'S'` wording.
- `semanticAnalyzerRejectIntrospection` is the shared level-0 emitter (span on the builtin call, deduped per node via `diagnosticCollectorMarkNodeOnce`); `semanticAnalyzerIntrospectionTypeLabel` renders the `found 'X'` label. `@sizeOf`/`@alignOf`/`@bitSizeOf` accept every complete type with unchanged values (`@alignOf(void)` stays the documented `0` residual). The packed-union offset folds are deleted from `comptime_eval.zig` and `type_resolver.zig`, and the lowering net is a clean `error[3074]` fallback — no `error[3043]` remains on the path. Fixtures `repro/mi_matrix/stdlib_union_layout_payload_xmod` (positive) + `union_offset_reject_xmod` (6 x 3072 + 3 x 3073 + 4 x 3074) + standalone `repro/union_layout_payload.z98` / `repro/union_offset_reject.z98`.

### semanticAnalyzerGrowLocalDecls (`sf/src/semantic_analyzer.zig`)

`[inference: grow-by-doubling from min 8, memcpy name+type arrays]`

Grows the parallel name/type local-decl arrays. Called by registerLocalDecl on overflow.

### Async diagnostics (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerDiagAsyncOutsideSuspending` emits `ERR_3018` when `@asyncSuspend` is used outside a function known to be suspending (via `async_analysis.asyncIsSuspending`). `semanticAnalyzerDiagAsyncBuiltinInDefer` emits `ERR_3019` for any `@async*` builtin reached while `defer_depth > 0`.

### Defer control-flow rejections — `ERR_3051`–`ERR_3054` (`sf/src/semantic_analyzer.zig`)

Task 10D implements official Zig's (`src/AstGen.zig`) rule for control flow inside a `defer`/`errdefer` body, applied before lowering. `semanticAnalyzerDiagDeferCtl` emits the diagnostic at the offending node; `semanticAnalyzerCheckDeferBody` is a recursive walk entered from the `defer_stmt`/`errdefer_stmt` arm of `semanticAnalyzerResolveStmtIter` (state saved/restored around it):

- `return_stmt` → `ERR_3051` "cannot return from defer expression" (Zig's `any_defer_node`).
- `try_expr` → `ERR_3054` "'try' not allowed inside defer expression" (Zig's `any_defer_node`).
- `break_stmt`/`continue_stmt` → `ERR_3052`/`ERR_3053` "cannot break/continue out of defer expression" **only** when the target is not declared inside the body (Zig's `cur_defer_node` walk). A `while`/`for` increments `defer_inner_loops`; a `labeled_stmt` pushes onto `defer_label_stack` (with `defer_label_isloop` recording whether the label wraps a loop, so a labeled-block target is legal for `break` but not `continue`). `semanticAnalyzerDeferBreakAllowed`/`semanticAnalyzerDeferContinueAllowed` test membership.
- A nested `fn_decl` stops the walk (resets both markers); a nested `defer`/`errdefer` is skipped here and validated by its own arm. Children are walked generically via `nodeHasNodeExtraChildren`/`nodeChildIsNode` in `semanticAnalyzerCheckDeferChildren`.

### Packed / enum gates (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerGatePackedFields` and `semanticAnalyzerGatePackedUnionMembers` validate each `field_decl` of a `packed` struct/union: the field type must be `bool`, an integer, or (for structs) a packed struct; `enum` fields require an explicit unsigned backing. Fields wider than 31 bits and non-integer fields are rejected with `error[3000]`. `semanticAnalyzerGateEnumTypeDecl` / `semanticAnalyzerGateEnumModuleDecl` validate `enum(uN)` backings (unsigned only; `bool`/signed/invalid rejected) and that every tag value fits the backing width (`2^N - 1`, no silent truncation). **Task 11J:** the gate reads the stored `em_items[].value` and is a pure fit-check — it does NOT re-run `evalConstI64Full`; the post-layout re-evaluation pass (`enumReevaluateAll`, end of `phase_TypeResolution`) is the single evaluation point that writes those values, so the gate can never re-suppress a stale value. **Task 11J fix round 1:** the `enum_decl` expression arm calls `semanticAnalyzerCheckLocalEnum`, which runs the shared `enumMembersResolve` walk in check-only strict mode for a function-local enum (whose type is not registered) so a duplicate tag or unfoldable initializer is a clean `ERR_3055`. `semanticAnalyzerPackedFieldTypeAllowed` and `semanticAnalyzerPackedStructDeclForType` back these checks; the `packed_gate_items`/`packed_struct_*`/`checked_struct_tids` caches memoize results.

### Volatile helpers (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerVolatileDrop` decides whether a coercion would implicitly discard a `volatile` qualifier (ptr/many-ptr/slice to a non-volatile counterpart, including optional unwrapping and array-decay pointee shapes). `semanticAnalyzerMaybeDiagVolatileDrop` emits `error[3000]` "cannot implicitly discard 'volatile' qualifier; use @volatileCast to remove it". `semanticAnalyzerPtrCastDropsVolatile` rejects `@ptrCast` dropping volatile; `semanticAnalyzerVolatileCastValid` requires `@volatileCast` to have a volatile source and the same base type.

`semanticAnalyzerConstDiscard` (FC, D12; extended by FX6) is the const twin: source `const` flag bit set, target clear, and same effective element/base across slice->slice, slice->many, ptr->ptr and many->many (the frozen operator-ruled family; `pointerQualifiersMonotone` masks only volatile, which is why const-discard slipped through the classifier). FX6 extends it with ptr->slice and ptr->many for a pointer whose pointee is a KNOWN-LENGTH array — the string-literal family (`"abc"` is `*const [3]u8`, assignable to `[]u8`/`[*]u8` through `array_to_slice`, with `qok` masking only volatile) — mirroring the assignability tables exactly (pointee must be `array_type`, element must match). `semanticAnalyzerMaybeDiagConstDiscard` emits level-0 `error[3000]` "cannot implicitly discard 'const' qualifier" (deduped per node via `diagnosticCollectorMarkNodeOnce`; the module-var front-resolution fixpoint revisits initializers). It is called from the local-decl and assignment sites, from `semanticAnalyzerResolveModuleVarDecl`, and from `tryRecordCoercion` (covering return, call arguments and field initializers). The legal const-adding directions never match. The `[]const T` -> `[*]T` direction is required for the D5 lowering fix (doc 07): without it, the corrected `.ptr` extraction would create a silently mutating alias.

**FX6 (Volume II) const-array-decay half.** An array VALUE carries no `const` flag on its type — the qualifier lives on the BINDING — so the type-level predicate cannot see `const arr` -> `[]T`/`[*]T`, `arr[0..]`, or `&arr`. Three additions close that gap:

- `semanticAnalyzerConstArrayDecay` / `semanticAnalyzerMaybeDiagConstArrayDecay` (the expression-level twin, same message/dedup): source type `array_type` + target mutable `slice_type`/`many_ptr_type` + same element/base + `semanticAnalyzerIsLValueConst(src_node)` true. Called at the same sites as the type-level twin, plus the array-literal ELEMENT site in `semanticAnalyzerResolveArrayInit` (the one materialisation path FC's site set did not cover; each element is checked against the literal's declared element type). Mutable arrays never match.
- `semanticAnalyzerResolveSliceExpr`: an array base whose binding is const yields a `const` slice (`se_is_const`), so `arr[0..]` carries the qualifier in its result TYPE and the ordinary sites reject a mutable target. Deliberately array-only: a const-bound MUTABLE slice (`const s: []T`) keeps element mutability (`s[0..]` is `[]T`), matching Zig.
- `semanticAnalyzerResolveExpr`'s `address_of` arm: `&arr` on a const-bound array rebuilds the pointer as `*const [N]T` (`semanticAnalyzerIsLValueConst` on the operand), so `*[N]T`/`[]T`/`[*]T` targets reject through the type-level predicate while `*const [N]T`/`[]const T`/`[*]const T` stay accepted. Deliberately array-only (a non-array operand keeps the pre-existing pointer spelling).

**FX11 (Volume II) aggregate-field-bound half.** The FX6 predicates fire only when the source resolves as `array_type`, but `semanticAnalyzerResolveFieldAccess` materialises an aggregate's array FIELD as a pointer to the element (the C decay), so `cs.a`'s type never says `array` and the binding's constness was lost. FX11 closes the family:

- `semanticAnalyzerResolveFieldAccess` (struct/union/packed-union fields, tuple elements, tagged-union payload): the decayed element pointer is built with `semanticAnalyzerIsLValueConst(self, node_idx)` instead of `false`, so a const aggregate's field resolves `*const T` and a mutable aggregate's field stays `*T`. Reads through a `*const S` l-value (`cp.a`) const-qualify identically; a genuine pointer-typed field is returned unchanged (copying a pointer VALUE out of const storage is legal).
- `semanticAnalyzerFieldAccessArrayType` (new): recovers the DECLARED array type of a field access that resolved through that decay (paren-transparent `field_access`, resolved type a pointer, base struct/union/packed-union/tagged-union/tuple whose named member's declared type is `array_type`; tagged-union `payload` and tuple ordinals mirror the resolver). Returns 0 for non-fields and for genuine pointer fields.
- `semanticAnalyzerConstArrayDecay`: a pointer source is accepted when `semanticAnalyzerFieldAccessArrayType` finds the array field, the pointer's base is that array's element, and `semanticAnalyzerIsLValueConst(src_node)` is true — the target families (`[]T`/`[*]T`) are unchanged. This covers the element site (`[1][]i32{ cs.a }`, the only one where the source is the decayed field pointer and the target differs) and every six-site materialisation that reaches the predicate.
- `semanticAnalyzerResolveExpr`'s `address_of` arm: a field base that is an array-field decay is rebuilt as `*[N]T` / `*const [N]T` from `semanticAnalyzerFieldAccessArrayType` + the l-value constness; `&cs.a[i]` is `*const ElementType`. Non-array operands keep the pre-existing spelling.
- `semanticAnalyzerResolveSliceExpr`: a pointer base that is an array-field decay takes the field path's constness (belt-and-braces on top of the const-typed field pointer), so `cs.a[0..]` yields `[]const T`.
- Consequences at the ordinary sites need no new code: `var q: *i32 = cs.a` rejects through the type-level `semanticAnalyzerConstDiscard` (`*const i32` -> `*i32`), `cs.a[0] = 9` / `cs.a.* = 9` reject through `semanticAnalyzerIsLValueConst`'s index/deref arms (3002), and the slice/address forms reject through the same one-liner. Fixtures: `repro/mi_matrix/stdlib_const_field_decay_ok_xmod`, `repro/mi_matrix/const_field_decay_reject_xmod`, standalone `repro/const_field_decay.z98` / `repro/const_field_decay_reject.z98`.

### Calling-convention / shape checks (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerFnPtrConvMismatch` compares two fn-ptr types' `FN_FLAG_STDCALL` bits; a mismatch promotes the assignment/return/var-decl diagnostic to a hard error. `isBShapeMismatch` hard-errors the real-Zig-invalid shapes (bare `*T`→slice, array element/length mismatch, error-set superset→subset, enum→integer without `@enumToInt`; `full` also selects bare `*T`→`[*]T` in var-decl/assignment positions).

### Termination analysis (`sf/src/semantic_analyzer.zig`)

`fnReturnRequiresValue` decides whether a result type carries data (false for `void`/`noreturn` and the void-payload forms of error unions and optionals). `astTerminates`/`astSwitchTerminates`/`astSwitchExhaustive`/`astWhileTerminates`/`astSubtreeHasBreak` are a definitely-returns predicate over the AST (block/if/switch/`while(true)`, declarations and assignments whose initializer terminates); `semanticAnalyzerResolveFnBody` uses it to emit `ERR_3003` "missing return" only when a value is required and a path can fall through.

### registerLocalDecl (`semantic_analyzer.zig`)

`[inference: grow if full → write name_id/type_id/span → inc count; SCT:n/SCT:t markers]`

Core local declaration registration. Called by resolveIdent local lookup, resolveFnBody param registration, and if/while/for header captures.

**Task 7D:** callers invoke `semanticAnalyzerCheckLocalShadow(name_id, span_start, span_end)` immediately BEFORE registering. It rejects (level-0 `error[3057]`, span on the shadowing declaration) when `name_id` already exists in `local_decl_names[0..local_decl_count)` (strictly-enclosing or same-scope = Zig shadow/redeclaration) or is a container-level `global`/`function`/`type_alias`/`module` symbol in the current module. `discard_name_id` (`_`) is exempt. The local table is kept scope-exact by the block-scoped scope-pop markers (see the statement walker and `semanticAnalyzerResolveExpr` expression-scope notes).

**Task 18:** `registerLocalDecl` takes the declaration's name span (`span_start`, `span_end`) and every direct `local_decl_names[local_decl_count] = ...` registration site (switch capture, `catch` payload, parameter, `for` item/index, function-local named type, `var_decl`) writes the parallel `local_decl_spans_start`/`local_decl_spans_end` arrays (grown/copied alongside the name/type/const arrays by `semanticAnalyzerGrowLocalDecls`). The shadow diagnostic uses them to render the related span — see below.

### semanticAnalyzerCheckLocalShadow (`semantic_analyzer.zig`)  [added: 2026-09-22 — Task 7D; related spans: Task 18]

```
semanticAnalyzerCheckLocalShadow(name_id, span_start, span_end):
  if name_id == discard_name_id: return
  scan local_decl_names[local_decl_count-1 .. 0] for name_id
    hit -> error[3057] "local declaration shadows an earlier declaration in an enclosing scope"
           at [span_start, span_end)
           + related span at local_decl_spans_start/end[hit] "previous declaration here"; return
  if symbolRegistryQualifiedLookup(symbols, module_id, name_id) is global|function|type_alias|module:
    error[3057] "local declaration shadows an outer-scope declaration" at [span_start, span_end)
    + (when the symbol's decl_node != 0) related span at that decl node "declared here"
```

**Task 18:** both reject paths emit their earlier-declaration pointer as a *related span*
(`diagnosticCollectorAddRelatedSpan`) rather than a locationless `diagnosticCollectorAddNote`, so the
renderer prints `<file>:<line>: note: previous declaration here` (or `declared here` for a
container-level declaration) — the same note locations official Zig 0.15.2 prints. The collector
reserves related-span slot 0 as the "no related span" sentinel (the renderer only prints indices
> 0), so the first real span lands at index 1.

Mirrors official Zig 0.15.2 ("Variable identifiers are never allowed to shadow identifiers from an
outer scope"). Enforced at every registration site. Non-forms (not enforced): `else |e|` payloads
(unparseable -> `error[2000]`) and nested `fn` (unsupported -> `error[3020]`).

**Task 7D fix round 1.** The `[span_start, span_end)` passed for a shadowing declaration points at
its NAME token. `if`/`while`/`catch`/param use the capture/param node span directly; `var_decl` and
`for` item/index and switch-prong captures carry the name only as a payload, so their name token is
located by source scanning (`semanticAnalyzerNthIdentSpan` + `diagnostics.zig`'s
`diagnosticCollectorScanIdentSpan` / `diagnosticCollectorFindFirstByte` / `FindLastByte`), falling
back to the declaration span when not locatable. The scope-pop-marker restore shared by the
stmt-walker worklist, switch-prong drain, and expression-block drain is factored into
`semanticAnalyzerPopScopeMarker`.

### pushExpectedType / popExpectedType (`semantic_analyzer.zig`)

`[inference: grow-by-doubling from 64, write/inc or dec stack pointer]`

```
pushExpectedType(self, ty):
  if stack full: grow to max(64, cap*2) entries
  items[len] = ty; len += 1

popExpectedType(self):
  if len > 0: len -= 1

topExpectedType(self) -> u32:
  if len == 0: return 0
  return items[len-1]
```

Used for contextual type inference: fn call args, return stmts, assigns, struct init fields, var decl init, if/else unification, switch prongs, enum/error literals. `if_expr` itself never pushes; its then/else branches inherit the expected type pushed by the enclosing return-statement or var-decl.


### semanticAnalyzerStmtWorkPush (`semantic_analyzer.zig`)

`[inference: grow-by-doubling from 64, write/inc work pointer]`

Worklist growth and push. Grows the statement work array (min 64, doubling). Pushes stmt node index onto the worklist.

### semanticAnalyzerResolveIdent (`semantic_analyzer.zig`)

`[inference: local-decl stack → symbol registry qualified lookup → name cache → TYPE_UNDEFINED → TYPE_VOID]`

Resolution order:
1. **Marker `IDE\n`** — entry; `SEM:vi` if name_id == 1 (underscore).
2. **Local declarations** (reverse scan): if `local_decl_names[li] == name_id`, emit `D7:Yn D7:n<name> D7:t D7:<type> L\n L:t<type>` and return type.
3. **Symbol registry**: `symbolRegistryQualifiedLookup(symbols, module_id, name_id)`:
   - `type_alias` → gate the alias decl (`semanticAnalyzerMaybeGateAliasDecl`); if `s.type_id != 0` return it, else fall back to the module-qualified then bare name cache, else `SVO\n` + `TYPE_VOID` (marker `TAL\n`).
   - `s.type_id != 0` → return `s.type_id` (marker `STY:N STY:T`, plus `STY:C` when a bare-name cache entry exists).
   - else → return `TYPE_VOID` (marker `SVO\n`).
4. **Name cache**: `nameCacheGet(registry, name_id)` (module-0 key) → return cached type (marker `C2:T`).
5. **Debug detail `D8:*`**: if node_idx in [450, 660], dump name, node kind, resolved type.
6. If name_id == `_stub_0` (discard sentinel) → return `TYPE_UNDEFINED`.
7. Fallback — an **undeclared identifier** → emit `error[3001]` (numeric code 20) "identifier '<name>' is not declared or imported in this module" with a precise `file:line:col` span (`astStoreNodeAt(node_idx).span_start` .. `+span_len`, `self.source_file_id`), then return `TYPE_VOID` (marker `IDT:<name>:VOID\n`). [updated: 2026-09-22 — Task 6F: this fallback has a single caller (the `ident_expr` arm of `semanticAnalyzerResolveExpr`), so every expression-position use of an undeclared identifier (`nope()`, `take(nope)`, `return nope;`, `arr[nope]`, `_ = nope;`, conditions, binary operands, `nope.foo`, `nope()()`, cross-module) is diagnosed; the post-sema `hasErrors` gate turns it into rc=2 / 0 `.c` before lowering. Residuals (distinct root causes) remain: `undefined()` (literal callee), `s.nope()` (field resolution), unknown param/return/pointee type names (`type_resolver`).]

The name-cache key for the bare lookup is `(u64)name_id` (module 0); a separate module-qualified lookup uses `(module_id<<32)|name_id`. The `_stub_0` discard sentinel is saved and restored around every clobbering helper (`ResolveIndexAccess`/`ResolveSliceExpr`/`ResolveTupleLiteral`/`ResolveArrayInit`), and `resolveAssign` additionally special-cases `_ = expr`, so a discard ident reliably yields `TYPE_UNDEFINED`.

### semanticAnalyzerResolveFieldAccess (`semantic_analyzer.zig`)

`[inference: resolve base expr → type-kind dispatch on TypeKind for field lookup → resolvedTypeTableSet]`

Entry: `FAE\n PFA:BK<kind> PFA:FN<name_id>`.

**Phase 1 — ident_expr base (module-qualified, type alias fields):**
- If base is `ident_expr` and resolves to a symbol:
  - `type_alias` on tagged_union/enum/error_set → scan field/member/error names, return `alias_type_id`.
  - `module` → lookup field in target module (`Q1:FL/KL/TL/FN`). **[updated: 2026-09-24 — Task 15 (S3)]** `semanticAnalyzerCheckMemberVisibility` runs first: a field symbol whose owning module is not this module and whose flags lack bit 1 (`pub`) emits level-0 `error[3007]` and the access resolves to `TYPE_VOID` (rc=2, 0 `.c`). Flags check (bit 1 = `0x2`). If function, resolve fn type via return_type_node (`resolvedTypeTableGet`, else `resolveTypeExprFull`; markers `Q1FX`, `BR:x/rt/fnr/treN/treT/dv/ft`).
  - If the base ident is undeclared (`TYPE_VOID`) → early-return `TYPE_VOID` (marker `FB\n`). [updated: 2026-09-22 — Task 6F: the diagnostic is emitted by the base `semanticAnalyzerResolveExpr` call at the top of this block (`semanticAnalyzerResolveIdent` now emits `ERR_3001`), so this branch no longer emits its own copy — an undeclared field base produces exactly ONE `error[3001]`. A declared-but-void base still rejects via its declaration's `error[3000]`. Dropping the old emission also removed a false `error[3001]: identifier 'x' is not declared` for `const x = v(); x.foo;` where `x` was in fact declared.]
- An `import_expr` base resolves through the module registry and looks the field up in the target module. **[updated: 2026-09-24 — Task 15 (S3)]** The same `semanticAnalyzerCheckMemberVisibility` gate runs before the field symbol is used (direct `@import("x.zig").secret(21)` was previously accepted; it even emitted invalid C with an undeclared callee temp).

**Phase 2 — general field access (non-ident base):**
- Resolve base expr. If `TYPE_VOID`, bail `FB\n`.
- **Pointer dereference**: if ptr_type/many_ptr_type, follow to pointee. Markers: `FAPR:OK FAPR:DK`. **Task 11S (b):** when the original base kind was `many_ptr_type` and the accessed field is `len`, emit `error[3000]: many-item pointer has no field 'len'` and return `TYPE_VOID` (`[*]T` has no `.len`; previously the auto-deref resolved it silently to `TYPE_VOID`, giving a gcc-class failure or a silent 0 in a range position). `*T` keeps its existing pointee walk.
- **Optional guard**: `error[3000]` "cannot access field on optional type; use .? to unwrap first".
- **Error union guard**: `error[3000]` "cannot access field on error-union type; handle the error first".

**Phase 3 — type-kind-specific field lookup:**
- `struct_type` → scan `FieldEntry[]` at `st_items[payload_idx].fields_start`.
- `union_type` / `packed_union_type` → scan `FieldEntry[]` at `un_items[payload_idx].fields_start`.
- `tagged_union_type` → `.tag` returns the tag type (`FT:TAG`); `.payload` returns the first non-void field type (array fields decay to `*elem`, marker `FP:PAYLOAD`); otherwise scan `FieldEntry[]`.
- `module_type` → `MFA\n`/`MF1\n`/`MFF\n`/`MFP` markers. **[updated: 2026-09-24 — Task 15 (S3)]** `semanticAnalyzerCheckMemberVisibility` runs first on the target-module symbol (the nested `mod.sub.member` shape had no visibility check before Task 15), then: look up field in target module's symbols. If function, look up resolved fn type.
- `slice_type` → `.len` returns `TYPE_USIZE` (`FSL:USIZE\n`). `.ptr` returns `[*]elem` (`FSP:PTR\n`).
- `array_type` → `.len` returns `TYPE_USIZE` (`FAA:USIZE\n`).
- **array-field `.len` fallback** `[updated: 2026-09-24 — Task 13 fix round (C1)]`: `semanticAnalyzerArrayFieldLenCheck` (a thin wrapper over the Task-11N `semanticAnalyzerArrayFieldLen`) inspects the `.len` base in EVERY "member not found" path — the non-aggregate `else` arm, the enum/error-set arms and Phase 5. If the base is a `field_access` whose container (struct / union / packed_union, optionally through a pointer) declares the named field as an `array_type`, `.len` resolves to `TYPE_USIZE` regardless of the element kind (`[N]u8` derefs to a scalar, but `[N]Point`/`[N]E`/`[N]Err` deref to `struct_type`/`enum_type`/`error_set_type` and reach a different arm). This recovers `s.a.len` after the Phase-4 array-field decay (`s.a` → `*elem`). The fallback is gated on the accessed name being `len` (`field_name_id == len_id`); a genuine unknown field on an array field (`s.a.foo`) rejects via `error[3060]` (Task 13/I1), not a silent `TYPE_VOID`. A `[*]T` field (many-item pointer) is not an array and is still rejected cleanly with `error[3000]` by the Task 11S (b) many-ptr `.len` gate.
- `error_set_type` → `typeRegistryErrorSetMemberIndex` check. If found, return `base_type_id`; a miss now runs the `.len` recovery and then `error[3060]` (`semanticAnalyzerReportUnknownMember`, base kind `error set type`).
- `enum_type` → scan enum members; if found, return `base_type_id`; a miss now runs the `.len` recovery and then `error[3060]` (base kind `enum type`).

**Phase 4 — struct/union/tagged_union field scan:**
```
fi from 0..fields_count:
  if fe_items[fields_start+fi].name_id == field_name_id:
    result = fe.type_id
    if result is array_type: result = *elem (array-to-ptr decay)
    return result (marker FF:R<type>)
```

**Phase 5 — not found:** marker `NF\n FF2:N FF2:F FF2:B`. [updated: 2026-09-24 — Task 13 (S1) + fix round (C1/I1)]: the `.len` array-field recovery (`semanticAnalyzerArrayFieldLenCheck`) runs first; then `semanticAnalyzerReportUnknownMember` emits the dedicated level-0 `error[3060]` (`ERR_3060_METHOD_SYNTAX_NOT_SUPPORTED`) with the ASCII message `no field or member function named '<name>' in <kind> type` and the function returns `TYPE_VOID` (rc=2, 0 `.c`). The kind tail is `struct type` for `struct_type`, `union type` for `union_type`/`packed_union_type`/`tagged_union_type`, `slice type`/`array type`/`enum type`/`error set type` for those kinds, and the generic `type` for a non-aggregate base (the non-aggregate `else`/enum/error-set arms call the same helper). Z98 aggregate types cannot contain function declarations, so the spec-forbidden method syntax `value.func()` is always an unknown member (matching official Zig 0.15.2); before this check the access resolved silently to `TYPE_VOID` and a call lowered to an undeclared callee temp (`zT_N = zT_undeclared();`, gcc/link failure with no diagnostic). Deduped per node via `diagnosticCollectorMarkNodeOnce` (the expression walk can revisit a field access). Valid enum/error-set members, module access, slice/array `.len`/`.ptr`, tagged-union `.tag`/`.payload` and real aggregate fields never reach the reject. **Task 18 fix round:** the helper takes the base type id and renders Zig's aggregate declaration note — `note: struct declared here` / `note: union declared here` / `note: enum declared here` — via the new `semanticAnalyzerFindTypeDecl` reverse lookup (the owning module's `type_alias` symbol whose `type_id` matches, using its `decl_node` + `file_id`); an anonymous type or an error set gets no note, matching Zig.


### Expression Resolution Dispatch — semanticAnalyzerResolveExpr

`semantic_analyzer.zig` — master `if/else` chain on `node.kind`:

| Arm | AstKind | `[inference]` | Returns |
|-----|---------|---------------|---------|
| 1 | `int_literal` | `[inference: return TYPE_INT_LIT]` | `TYPE_INT_LIT` (19) |
| 2 | `float_literal` | `[inference: return TYPE_F64]` | `TYPE_F64` (16) |
| 3 | `char_literal` | `[inference: return TYPE_U8]` | `TYPE_U8` (8) |
| 4 | `bool_literal` | `[inference: return TYPE_BOOL]` | `TYPE_BOOL` (2) |
| 5 | `null_literal` | `[inference: return TYPE_NULL]` | `TYPE_NULL` (17) |
| 6 | `undefined_literal` | `[inference: return TYPE_UNDEFINED]` | `TYPE_UNDEFINED` (18) |
| 7 | `unreachable_expr` | `[inference: return TYPE_NORETURN]` | `TYPE_NORETURN` (3) |
| 8 | `string_literal` | `[inference: `*const [N]u8`, N = real byte length]` | `typeRegistryGetOrCreatePtr(array[u8;N], true)` |
| 9 | `enum_literal` | → `semanticAnalyzerResolveEnumLiteral` | switch context / expected type |
| 10 | `error_literal` | `[inference: expected-type → error set member lookup (unwraps optional)]` | error set TypeId, error union, or TYPE_VOID (`ERR_3011` when not found) |
| 11 | `ident_expr` | → `semanticAnalyzerResolveIdent` | local/symbol/cache/UNDEFINED/VOID |
| 12 | `field_access` | → `semanticAnalyzerResolveFieldAccess` | field type |
| 13 | `index_access` | → `semanticAnalyzerResolveIndexAccess` | elem type / tuple field type. **[updated: 2026-09-24 — Task 17 (F)]** additionally rejects a comptime-known out-of-bounds index on a fixed-size array with `error[3062]` before returning the elem type |
| 14 | `slice_expr` | → `semanticAnalyzerResolveSliceExpr` | slice type. **[updated: 2026-09-24 — Task 17 (F)]** additionally rejects comptime-known out-of-bounds constant bounds (`end > len`, `start > end`, negative) on a fixed-size array with `error[3062]` |
| 15 | `deref` | `[inference: ptr/many_ptr → base type]` | `pp.base` or base type |
| 16 | `address_of` | `[inference: return *T for expr of type T; packed field address rejected]` | `typeRegistryGetOrCreatePtr(base, false)` |
| 17 | `fn_call` | → `semanticAnalyzerResolveFnCall` | return type |
| 18 | `builtin_call` (unsupported) | `[inference: diag error[3000] unsupported builtin]` | `TYPE_VOID` |
| 19 | `builtin_call` (supported) | → dispatch by `child_0` | per builtin (see below) |
| 20 | `bool_not` | `[inference: resolve child, return TYPE_BOOL]` | `TYPE_BOOL` |
| 21 | `negate` / `wrap_negate` | → `semanticAnalyzerResolveNegate` | numeric type or VOID |
| 22 | `bit_not` | → `semanticAnalyzerResolveBitNot` | integer type or VOID |
| 23 | `try_expr` | → `semanticAnalyzerResolveTryExpr` | error union payload |
| 24 | `catch_expr` | `[inference: unwrap error union + capture]` | payload type |
| 25 | `orelse_expr` | → `semanticAnalyzerResolveOrelseExpr` | optional payload |
| 26 | `break_stmt` / `continue_stmt` | `[inference: return TYPE_VOID]` | `TYPE_VOID` |
| 27 | `var_decl` / `defer_stmt` / `errdefer_stmt` / `labeled_stmt` | → `semanticAnalyzerResolveStmtIter` | `TYPE_VOID` |
| 28 | `if_expr` | → `semanticAnalyzerResolveIfExpr` | unified then/else type |
| 29 | `if_stmt` | `[inference: resolve header, push children to worklist]` | `TYPE_VOID` |
| 30 | `for_stmt` | → `semanticAnalyzerResolveForHeader` | `TYPE_VOID` |
| 31 | `while_stmt` | → `semanticAnalyzerResolveWhileHeader` | `TYPE_VOID` |
| 32 | `swt_ex` | → `semanticAnalyzerResolveSwitchExpr` | unified prong type |
| 33 | `tuple_literal` | → `semanticAnalyzerResolveTupleLiteral` | tuple TypeId |
| 34 | `struct_init` | → `semanticAnalyzerResolveStructInit` | struct/TU/union TypeId |
| 35 | `array_init` | → `semanticAnalyzerResolveArrayInit` | array TypeId |
| 36 | `ptr_type` / `many_ptr_type` / `array_type` / `slice_type` / `optional_type` / `error_union_type` / `fn_type` / `struct_decl` / `enum_decl` / `union_decl` / `error_set_decl` | `[inference: return TYPE_TYPE; struct_decl also runs packed gate]` | `TYPE_TYPE` (20) |
| 37 | `paren_expr` | `[inference: delegate to child]` | child type |
| 38 | `return_stmt` | → `resolveReturnStmt` | `TYPE_NORETURN` |
| 39 | `expr_stmt` | `[inference: delegate to child]` | child type |
| 40 | `import_expr` | `[inference: return TYPE_VOID]` | `TYPE_VOID` |
| 41 | `block` | `[inference: stmt iter children, resolve last child]` | last child type / VOID |
| 42 | `add` / `sub` / `mul` / `div` / `mod_op` / `wrap_add` / `wrap_sub` / `wrap_mul` / `sat_add` / `sat_sub` / `sat_mul` | → `semanticAnalyzerResolveArithmetic` | numeric/ptr type or VOID |
| 43 | `bit_and` / `bit_or` / `bit_xor` / `shl` / `shr` / `sat_shl` | → `semanticAnalyzerResolveBitwise` | integer type or VOID |
| 44 | `bool_and` / `bool_or` | → `semanticAnalyzerResolveLogical` | `TYPE_BOOL` or VOID |
| 45 | `cmp_eq` / `cmp_ne` / `cmp_lt` / `cmp_le` / `cmp_gt` / `cmp_ge` | → `semanticAnalyzerResolveComparison` | `TYPE_BOOL` or VOID |
| 46 | `plain_assign` … `or_assign` plus `wrap_add_assign`/`wrap_sub_assign`/`wrap_mul_assign`/`sat_add_assign`/`sat_sub_assign`/`sat_mul_assign`/`sat_shl_assign` | → `semanticAnalyzerResolveAssign` | lhs type or VOID |
| 47 | `range_exclusive` / `range_inclusive` | `[inference: resolve child_0, and child_1 when present, then return TYPE_U32]` (early return) `[updated: 2026-09-21 — Task 11P]` | `TYPE_U32` |
| — | (any other AstKind) | `[inference: diag ERR_3020, return TYPE_VOID]` | `TYPE_VOID` |

After all arms: emit `STX:n<idx> STX:k<kind> STX:r<result> A4:N<idx> A4:K<kind> A4:R<result>`, `resolvedTypeTableSet(node_idx, result)`, `STB:N<idx> STB:R<result>`, return `result`.



#### Builtin dispatch

`semanticAnalyzerIsBuiltinSupported` (name-id equality, with string-equality fallbacks for `@enumToInt`, `@cVaStart`, `@cVaArg`, `@cVaEnd`, `@panic`) gates the whole arm: any other `@name` reaching `resolveExpr` emits `error[3000]: unsupported builtin function` and resolves to `TYPE_VOID`. `semanticAnalyzerIsTypeValueCast` returns true for the eight type-value casts (`@ptrCast`, `@volatileCast`, `@intToPtr`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@as`); those resolve their value arg first, then `resolveTypeExprFull` the type arg (child_0) and return that type.

**Core I/O builtins** — each resolves its value args via `semanticAnalyzerResolveExpr` and returns the signature type:

| Builtin | Args resolved | Returns |
|---------|---------------|---------|
| `@putChar(c: u8)` | `ec[0]` | `TYPE_VOID` |
| `@stdoutWrite(buf, len)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@stderrWrite(buf, len)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@getChar()` | none | `TYPE_U8` |
| `@exit(code)` | `ec[0]` | `TYPE_NORETURN` |
| `@panic(msg)` | `ec[0]` | `TYPE_NORETURN` |
| `@sleepMs(ms: u32)` | `ec[0]` | `TYPE_VOID` |

**Console builtins:**

| Builtin | Args resolved | Returns |
|---------|---------------|---------|
| `@isWindows()` | none | `TYPE_BOOL` (comptime-folded — never reaches runtime) |
| `@consoleClear()` | none | `TYPE_VOID` |
| `@consoleGotoxy(x: i32, y: i32)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@consoleSetColor(fg: i32, bg: i32)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |

`@isWindows()` is the sema-half of a comptime intrinsic: `comptime_eval.zig` folds it to a `ComptimeVal` 0/1 (module const `host_is_windows`, currently `false`), so `phase_ComptimeEvaluation` stores it in `ctx.comptime_folds` (`comptimeFoldTablePut`) and the lowerer emits an `int_const` (`TYPE_BOOL`). `if (@isWindows())` then folds to only the active branch (see 07 §Builtin console + comptime branch folding).

**Introspection / pointer / bitcast builtins:**

| Builtin | Behavior | Returns |
|---------|----------|---------|
| `@sizeOf` / `@alignOf` / `@offsetOf` / `@bitSizeOf` / `@bitOffsetOf` | type arg resolved via `resolveTypeExprFull` | `TYPE_INT_LIT` |
| `@ptrToInt` / `@intFromPtr` | value arg resolved | `TYPE_USIZE` |
| `@ptrFromInt` | value arg resolved; target taken from `topExpectedType` (must be a ptr/many-ptr, else `error[3000]`) | the inferred ptr type |
| `@fieldParentPtr` | outer type + field name resolved; returns `*outer` | `*outer` |
| `@bitCast` | destination type + source resolved; requires same-size integer source and destination (`state==2`), else `error[3000]` | destination type |
| `@enumToInt` | arg resolved; enum arg yields its backing type | enum backing / arg type |
| `@cVaArg` | arg + type resolved | the resolved type |
| `@cVaStart` / `@cVaEnd` | accepted (supported); argument resolved by the generic arm | arg type |
| `@ptrCast` | type-value cast; exactly two args (`ERR_3049` otherwise); rejects dropping `volatile` | target type |
| `@volatileCast` | type-value cast; requires a volatile source and same base type | target type |

**Async builtins:**

| Builtin | Behavior | Returns |
|---------|----------|---------|
| `@asyncFrameSize(fn)` | resolves the fn reference; requires a known suspending function (`ERR_3046` otherwise) | `TYPE_INT_LIT` |
| `@asyncInit(...)` | resolves up to 4 args; rejected inside defer/errdefer (`ERR_3019`) | `*void` |
| `@asyncResume(...)` | resolves up to 2 args; rejected inside defer/errdefer (`ERR_3019`) | `?*void` |
| `@asyncSuspend(...)` | resolves arg; rejected inside defer/errdefer (`ERR_3019`) and outside a suspending function (`ERR_3018`) | `*void` |

#### Socket builtins — REMOVED

The 11 socket builtins (`@socketCreate`/`BindListen`/`Accept`/`Connect`/`Send`/`Recv`/`Select`/`FdZero`/`FdSet`/`FdIsset`/`Close`) were removed (netbind S3, 2026-09-04). A direct `@socket*` caller now fails `error[3000]: unsupported builtin function` (rc=2, 0 `.c`); networking is now the `std_net` extern surface (target-selected wsock32/libc `extern "c"` bindings, WSAStartup init, `createTcpClient`).


### semanticAnalyzerResolveArithmetic (`semantic_analyzer.zig`)

`[inference: ptr+int → ptr, ptr-ptr → isize, num+int_lit → num, else wider-width/size winner]`

```
lhs = resolveExpr(child_0), rhs = resolveExpr(child_1)
if lhs==0 or rhs==0: return TYPE_VOID

if op is add/sub:
  if lhs is ptr/slice and rhs is unsigned/int_lit → return lhs
  if add and lhs is unsigned/int_lit and rhs is ptr/slice → return rhs
  if sub and lhs is ptr/slice and rhs is ptr/slice → return isize

if lhs is int_lit and rhs is numeric → return rhs
if rhs is int_lit and lhs is numeric → return lhs

if not both numeric → return TYPE_VOID
if lhs == rhs → return lhs
if both integer → return the wider bit width
return the one with larger byte size
```

### semanticAnalyzerResolveBitwise (`semantic_analyzer.zig`)

`[inference: int_lit + integer → wider, both same integer type → that type]`

```
if lhs is int_lit and rhs is integer → return rhs
if rhs is int_lit and lhs is integer → return lhs
if lhs != rhs or lhs is not integer → return TYPE_VOID
return lhs
```

### semanticAnalyzerResolveComparison (`semantic_analyzer.zig`)

`[inference: error/enum literal with expected type, then numeric/optional/pointer/error-set/enum comparison, return TYPE_BOOL]`

Special expected-type push for error/enum literals when the other operand has a matching error_set/tagged_union type (markers `CPE`/`CP0`/`CPB`/`CPV`). Then:
- int_lit + numeric → `TYPE_BOOL`
- same numeric → `TYPE_BOOL`
- `==`/`!=`: optional+null, null+optional, error_set+error_set → `TYPE_BOOL`
- same bool → `TYPE_BOOL`
- same pointer → `TYPE_BOOL`
- same enum_type → `TYPE_BOOL`

### semanticAnalyzerResolveLogical (`semantic_analyzer.zig`)

`[inference: both operands TYPE_BOOL → TYPE_BOOL; else TYPE_VOID]`

Dispatched from ResolveExpr for bool_and/bool_or. Emits `LOE`/`LOB`/`LOV`. Returns TYPE_BOOL only if both lhs and rhs are TYPE_BOOL.

### semanticAnalyzerResolveNegate (`semantic_analyzer.zig`)

`[inference: INT_LIT → INT_LIT; numeric → same type; else VOID]`

Dispatched from ResolveExpr for negate and wrap_negate. Returns the inner type if numeric.

### semanticAnalyzerResolveBitNot (`semantic_analyzer.zig`)

`[inference: INT_LIT → INT_LIT; integer → same type; else VOID]`

Dispatched from ResolveExpr for bit_not. Returns the inner type if integer.

### semanticAnalyzerResolveFnCall (`semantic_analyzer.zig`)

`[inference: direct callee → resolve return type → push/pop expected types for params → record coercions]`

**Phase 1 — direct call optimization (callee is ident_expr):**
- Symbol lookup (marker `XF`/`xS`). If `SymbolKind.function` with decl_node:
  - Look up return_type_node in the resolved type table (marker `BR:rnt`).
  - If not resolved, route through `resolveTypeExprFull` with `.module_id = s.module_id` (markers `DRETFB:n`, `BR:fc`); no manual name-cache scan.
  - If `direct_ret != 0`, iterate args against fn params: `call_param_map` (`(decl_cap<<16)|ai`) or `xt_items[params_start+ai]` → `pushExpectedType` → resolve → record into `call_arg_types` → `tryRecordCoercion` (with `errLitSrcType` and a shape-mismatch diagnostic). **[updated: 2026-09-24 — Task 14 (S2)]** Before the loop, the resolved fn type's params_count/variadic flag drive `semanticAnalyzerReportCallArity` (too few / too many / variadic too-few → level-0 `error[3061]`); inside the loop each typed arg is rejected with `error[3000]` when it is neither assignable nor tolerated — the `(b)` shape arm (`isBShapeMismatch(..., false)`) is consulted first, then `semanticAnalyzerCallArgTolerated` (the cross-family rule — see the new subsections). **[fix round 2026-09-24]** the shape arm was restored after a review Critical: without it the pointer-family tolerance swallowed `*T` -> `[]T` and mismatched `[N]T` -> `[M]T` call args (rc=0 again).

**Phase 2 — general callee:**
- Resolve callee expr. If ptr_type pointing to fn_type, dereference.
- If not fn_type: emit `FN3:N/T/K` markers, resolve every argument with `pushExpectedType(0)`, return `TYPE_VOID`. **[updated: 2026-09-22 — Task 6D]** This branch emits no diagnostic: the callability rejection (`error[3056]`) is performed in LIR lowering on the lowered callee temp, which also covers the flat non-pub module member this resolved-type check misses (its sema type is `TYPE_VOID`).
- **Variadic arity:** read `fnp.flags_packed & 0x01` → `is_var`. **[updated: 2026-09-24 — Task 14 (S2)]** When variadic, a short call (`args.len < params_count`) reports `semanticAnalyzerReportCallArity` ("expected at least N argument(s), found M"); a non-variadic call with `args.len != params_count` reports it with the plain "expected N argument(s), found M" wording. Both emit level-0 `error[3061]` (`ERR_3061_WRONG_ARGUMENT_COUNT`) and analysis CONTINUES with the present arguments clamped (`check_n = min(params_count, args.len)`) so every argument is still resolved; the sema `hasErrors` gate rejects before lowering. Before Task 14 a mismatch returned the declared return type leniently (rc=0, gcc-only failure). The first `params_count` args are typed against the named params; the extra variadic args are resolved with `pushExpectedType(0)` and recorded into `call_arg_types` (loosely typed).
- **[updated: 2026-09-24 — Task 14 (S2)] Per-arg loop (both paths):** `pushExpectedType(param_type)` → resolve → `popExpectedType` → `errLitSrcType` → the assignability gate: when the effective source is neither assignable nor `semanticAnalyzerCallArgTolerated`, emit `error[3000]` "type mismatch in function argument — argument type may not be compatible with the parameter type" + `source:`/`target:` TypeKind notes at the argument span. Only pairs that are `TYPE_UNDEFINED`/`TYPE_VOID` (no annotation) or a not-yet-resolved 0 source skip the gate; `tryRecordCoercion` still runs for every typed arg.

The Phase-1 return-type fallback always routes through `resolveTypeExprFull` with `.module_id = s.module_id`.

### semanticAnalyzerReportCallArity (`semantic_analyzer.zig`)  [added: 2026-09-24 — Task 14 (S2)]

`[inference: integers → itoa → interned message → level-0 error[3061]]`

Builds `"expected N argument(s), found M"` (variadic short-call: `"expected at least N argument(s), found M"`) with `itoa_mod.itoa` and `diagnosticBuilderMakeMsg`; deduped per call node with `diagnosticCollectorMarkNodeOnce`; the span is the call expression. Level 0 → rc=2 / 0 `.c`. Called from both the direct-call path (against the resolved fn type's `params_count` + `FN_FLAG_VARIADIC`) and the fn-value path. **Task 18 fix round:** takes the callee declaration node + its source file and renders Zig's `note: function declared here` related span; `semanticAnalyzerResolveFnCall` supplies them through `note_decl`/`note_file` (ident callee from the symbol; module-member callee via `semanticAnalyzerCalleeDeclSymbol`; nested `std.io.print()` has no note — bounded).

### semanticAnalyzerCallArgTolerated / semanticAnalyzerIsPointerFamilyKind / semanticAnalyzerCallArgIntegerKind (`semantic_analyzer.zig`)  [added: 2026-09-24 — Task 14 (S2)]

`[inference: type-kind families → bool]`

The call-site gate rejects only CROSS-FAMILY argument mismatches. Returns true (keep, no diagnostic) for: a `TYPE_VOID` source; both sides in the integer family (`typeRegistryIsInteger` plus Z98's distinct `TYPE_C_CHAR`); an `error_set_type` source with an integer target (Z98's `@enumToInt(<error set>)` keeps the error-set type in the front end); or both sides in the pointer family (`ptr_type`/`many_ptr_type`/`slice_type`/`array_type`). The tolerance is consulted only AFTER the `isBShapeMismatch(..., false)` `(b)`-shape arm at both call sites, so the pre-existing `*T` -> `[]T` and mismatched `[N]T` -> `[M]T` call-argument rejects keep firing (Task 14 fix round). `bool` is in NO family, so `add(1, true)` rejects with `error[3000]`; so do int<->float, float<->pointer and aggregate cross-family pairs. `semanticAnalyzerIsPointerFamilyKind` is the 4-kind predicate; `semanticAnalyzerCallArgIntegerKind` is `TYPE_C_CHAR || typeRegistryIsInteger`.

### semanticAnalyzerCheckMemberVisibility (`semantic_analyzer.zig`)  [added: 2026-09-24 — Task 15 (S3)]

`[inference: (owning module, pub flag) → bool | emit error[3007]]`

The cross-module `pub` gate used by all three module-member arms of `semanticAnalyzerResolveFieldAccess` (flat `SymbolKind.module`, direct `import_expr`, nested `module_type`) and by function-call callee resolution (a cross-module field-access callee goes through the same arms). Returns true when the symbol is owned by the current module (`sym.module_id == self.module_id`) or carries the `pub` flag (`symbol_table.symbolIsPublic`, bit 1); otherwise emits level-0 `error[3007]` `ERR_3007_VISIBILITY_VIOLATION` with the ASCII message `'<name>' is not marked 'pub'` (official Zig 0.15.2 wording; `diagnosticBuilderMakeMsg` over the interned field name), deduped per node via `diagnosticCollectorMarkNodeOnce`, and returns false so the caller maps the expression to `TYPE_VOID` (rc=2 / 0 `.c`). Type positions and the const-fold positions (array sizes / enum initializers) use the sibling `type_resolver.typeResolverCheckMemberVisibility` (same rule; audits only passes with a live `env.diag`; fix round 1 added the fold arm). Same-module access is untouched — it never routes through the module-member arms. **Task 18 fix round:** both helpers render Zig's `note: declared here` related span at the non-`pub` declaration's own location; `Symbol` carries the owning `file_id` (set in `symbol_registrator.registerDecl` from the declaring module) so a cross-module note prints the right filename (`helper.zig:10`).

### semanticAnalyzerResolveSwitchExpr (`semantic_analyzer.zig`)

`[inference: resolve condition → set switch context → resolve prongs → unify types → return unified]`

1. Increment `switch_depth`. Markers `SE`, `SWI:n/p/d`.
2. Resolve condition. A `tagged_union_type` or `enum_type` condition sets `current_switch_cond_tu` (marker `Z`); an `error_set_type` condition sets `cond_es` (marker `SWES:e`); an `error_union_type` condition sets `cond_es` from its error set (marker `SWEU:e`).
3. Iterate prongs. For each:
   - If else-prong with capture (flag 0x10) → error 3001 "switch else-prong capture ... is not supported".
   - If the condition is enum/tagged-union and the prong has cases: resolve each `enum_literal` case via `semanticAnalyzerResolveEnumLiteral` with the new `switch_case_item` flag set (an unknown shorthand member rejects `error[3071]` in case-item context; an enum literal inside the prong BODY keeps the expected-type fall-through); `undefined_literal` cases resolve as before. A `field_access` case (a container-qualified prong: `Shape.circle`, `Color.red`, `mod.Type.member`) resolves through `semanticAnalyzerResolveSwitchCaseMember` — FX4 validates the qualifier (foreign → 3071) and the member name (unknown → 3071), module-namespace qualifiers are left to lowering's const-item resolution, and a valid same-type member fills `enum_value_table` + the resolved type exactly like the shorthand, so qualified prongs bind captures identically. If capture (flag 0x10), register a local decl with the TU field type (or, for an `enum_type` condition, with the enum type — Zig's operand-value capture; or the switch type when the case is empty); a rejected prong's capture stays unbound and its use keeps the `error[20]` cascade.
   - If `cond_es != 0` and the prong has cases: resolve `error_literal` cases with `cond_es` pushed as expected type.
   - Resolve the prong body expr, then drain any statements it queued on the stmt worklist back to `sw_base`.
   - **Type unification**: track `unified`/`unified_node`. String-literal prongs resolve toward a `[]const u8` peer; otherwise coercion-aware: if bt can coerce to unified, record coercion; if unified can coerce to bt, swap; if unified is int_lit and bt is numeric → use concrete.
   - **MIX else-branch (non-coercible prong types):** records `resolvedTypeTableSet(..., TYPE_VOID)` for the switch node and **`continue`s to the next prong** — the conflicting prong is skipped from the `unified`-type contribution but ALL remaining prongs still resolve.
   - **Mandatory `else` (FA-a):** after the prong loop, `has_else == 0` emits level-0 `error[3068]` `ERR_3068_SWITCH_WITHOUT_ELSE` (`switch must have an 'else' prong`) at the switch node's span, deduped per node via `diagnosticCollectorMarkNodeOnce` — value AND statement position (both resolve through this function); rc=2 / 0 `.c`. The D3 uninitialized-result-temp default path in lowering is unreachable for accepted programs.
4. If no prong contributed a unified type, `unified = TYPE_NORETURN`. Return unified. Marker `SWU:n/t`.

### semanticAnalyzerResolveEnumLiteral (`semantic_analyzer.zig`)

`[inference: switch context → expected type stack → tagged union/enum scan → error or return type]`

1. If `current_switch_cond_tu != 0`: for a tagged-union condition, scan TU fields for a matching name_id and register `enum_value_table[node_idx]=fi`, returning the switch type; for an enum_type condition, scan enum members, register the member value, and return the switch type. **FX4:** when both scans miss and `node.kind == enum_literal` and the `switch_case_item` flag is set, emit level-0 `error[3071]` (`no field or member function named '<name>' in union/enum type`, member span + `declared here` related span) and return `TYPE_VOID` BEFORE the expected-type fall-through; the flag is set only around a case-item resolution in `semanticAnalyzerResolveSwitchExpr`'s loop, so an enum literal in a prong body still resolves against the expected type.
2. If `expected_type_stack` top is a tagged_union: scan fields. If field type is VOID → register enum value, return top type. If field type is non-VOID → error `ERR_3008` "enum literal member requires payload".
3. If field not found in the expected TU → error `ERR_3009` "unknown enum literal member". If the expected type is an enum_type, scan its members and return the type.
4. Fallback → marker `ELV:N`, return `TYPE_VOID` (unresolvable).

### semanticAnalyzerResolveSwitchCaseMember (`semantic_analyzer.zig`) — [added: 2026-09-26 — FE (D11)]

`[inference: prong member name → current_switch_cond_tu scan → enum_value_table + resolved type]`

The qualified-prong twin of `semanticAnalyzerResolveEnumLiteral`'s switch-context arm. A prong spelled
`Container.member` parses as a `field_access` (child_0 = qualifier, payload = member name), so the
`enum_literal` resolver never sees it. **FX4** extends the helper with qualifier and member validation:

1. `current_switch_cond_tu == 0` → `TYPE_VOID` (no switch context).
2. **Qualifier identity (FX4, Zig's order).** Resolve `child_0` via `semanticAnalyzerResolveExpr`. A
   qualifier that resolves to a known type with kind `module_type` is an FX1 const-item namespace
   (`helper.LOMEM`) and returns `TYPE_VOID` immediately — lowering's const-item resolver owns it, FX4
   must not validate it. A known enum/tagged-union type other than `current_switch_cond_tu` is a
   foreign qualifier: emit `error[3071]` (mismatch message, qualifier span) and stop (the mismatch
   wins over a missing member, matching Zig). An identity of 0/`TYPE_VOID`/`TYPE_UNDEFINED` (its own
   diagnostic already fired) or any other kind is conservatively not rejected as foreign.
3. `tagged_union_type` condition: scan the TU fields for the name; on a match register
   `enum_value_table[case_i] = field_index` and the resolved type, return the switch type. No match →
   `error[3071]` (`no field or member function named '<name>' in union type`, member span) and
   `TYPE_VOID`.
4. `enum_type` condition: scan the enum members; on a match register `enum_value_table[case_i] =
   member.value` and the resolved type, return the switch type. No match → `error[3071]` (`... in enum
   type`, member span) and `TYPE_VOID`.

The capture-binding block then finds the table entry and registers the capture local — for a
tagged-union condition with the field's payload type, for an enum condition with the enum type
(Zig-style operand-value binding). A rejected prong leaves no table entry, so its capture stays
unbound and every use keeps the pre-existing `error[20]` cascade visible. Multi-qualified
(`helper.Box.num`) and nested-qualified siblings resolve the qualifier expression and compare its
type id, so aliases (`const C = A; C.x`) and module-qualified types (`shapes.Shape.circle`,
`helper.Kind.plus`) pass the identity check.

### semanticAnalyzerReportSwitchCaseQualifier (`semantic_analyzer.zig`) — [added: 2026-09-27 — FX4 (D11 extras)]

`[inference: case-item node → dedup → level-0 error[3071] + typed message + declared-here related span]`

The one FX4 reject reporter, used by both the qualified helper and the shorthand path (via
`semanticAnalyzerResolveEnumLiteral`). Deduped per case-item node via
`diagnosticCollectorMarkNodeOnce`; `foreign != 0` selects the mismatch message
(`type mismatch in switch case item -- case item type may not be compatible with the switch condition
type`) and the qualifier span, otherwise the `error[3060]`-style unknown-member message
(`no field or member function named '<name>' in union type` / `in enum type`) and the member span.
It emits code `ERR_3071_SWITCH_CASE_QUALIFIER` level 0 at the chosen span (rc 2 / 0 `.c`) and adds a
`union declared here` / `enum declared here` related span via `semanticAnalyzerFindTypeDecl` on the
condition type (qualifier type for the foreign case). The pre-existing unbound-capture `error[20]`
cascade is deliberately not suppressed; no `error[3060]` co-fires (the member check is the direct
condition walk, not the generic field-access reporter).

### semanticAnalyzerResolveStructInit (`semantic_analyzer.zig`)

`[inference: explicit type → expected type → scan fields → push/pop expected types for each init]`

- If type is tagged_union: iterate field_inits, find matching field by name_id, push expected type, resolve init, record coercion.
- If type is struct: same process on struct fields.
- If type is `union_type` or `packed_union_type`: same process on union members, `resolvedTypeTableSet(node_idx, union_type)`. A bare-union struct literal (`Inner{ .Int = v }`), including nested inside an outer struct literal, resolves to the union type and records its member coercion.

### semanticAnalyzerResolveAssign (`semantic_analyzer.zig`)

`[inference: resolve lhs → push expected type for rhs → try coercion → error or return lhs type]`

Special case: if lhs is ident_expr with name `_`, resolve rhs but discard (explicit discard). [updated: 2026-09-22 — Task 7B: before the `pushExpectedType` step, `semanticAnalyzerIsLValueConst(node.child_0)` is consulted; a true result emits level-0 `error[3002]` "cannot assign to immutable variable" at the l-value span and returns `TYPE_VOID` (rc=2, 0 `.c`), so this single choke point covers plain + compound assignment.] Otherwise `pushExpectedType(lhs)` → resolve rhs → compute effective source via `errLitSrcType`; if the assignment would implicitly discard `volatile` (or, FC/D12, `const`; or, FX6, a const-bound array value via `semanticAnalyzerMaybeDiagConstArrayDecay`), emit that diagnostic and return VOID; if assignable, `tryRecordCoercion` and return lhs. On mismatch, emit a type-mismatch diagnostic (with source/target TypeKind notes), raising the level to a hard error for fn-ptr calling-convention mismatch or `(b)`-shape mismatch. Markers `ASE`, `AS0`, `AS1`, `AS2`.

### semanticAnalyzerIsLValueConst (`semantic_analyzer.zig`)  [added: 2026-09-22 — Task 7B]

`[inference: read resolved-type/symbol/local tables → bool]`

Mirrors zig0's `TypeChecker::isLValueConst` (`src/bootstrap/type_checker.cpp:6470`). Returns true for: an `ident_expr` whose local/param/capture binding has `local_decl_consts[i] != 0`, or whose module symbol is a `var_decl`-backed `global` with `(flags & 1) == 0` (immutable); a `deref` whose operand's resolved type is `ptr_type`/`many_ptr_type` with `Type.flags & 1`; an `index_access` whose base resolved type is `slice_type`/`ptr_type`/`many_ptr_type` with `flags & 1`, or an `array_type` (recurse into the binding); a `field_access` through a const pointer or a const module member, else recurse into the base; and a `paren_expr` (recurse). It never calls `semanticAnalyzerResolveExpr` (the l-value is already resolved), so an undeclared base is not double-reported. `.tag`/optional-member writes on a mutable binding are deliberately NOT special-cased (Z98 supports them on a `var`; a `const` union/optional binding is caught by the recursion).

### semanticAnalyzerResolveFnBody (`semantic_analyzer.zig`)

`[inference: clear locals → register params → set current_fn_return → call stmt iter]`

1. Clear `local_decl_count`, `local_consts.count`, and (Task B2) `local_types.count`.
2. Resolve fn_decl node, get `FnProto`. If the resolved fn type is variadic and `stdcall` (`FN_FLAG_STDCALL`), emit `ERR_3012` "variadic functions cannot use the stdcall calling convention".
3. For each param: if `child_0 != 0` (has type annotation), look up resolved type from RTT or set `TYPE_UNDEFINED`. Register as local decl (markers `RT:P/A/T/M`) with the const bit set (params are immutable — Task 7B).
4. Set `current_fn_return` from `resolvedTypeTableGet(proto.return_type_node)` and `current_fn_name` from `proto.name_id`.
5. Resolve body via `semanticAnalyzerResolveStmt(body_node)`. Then, if `fnReturnRequiresValue(current_fn_return)` and the body does not definitely terminate (`astTerminates`), emit `ERR_3003` "missing return: not all control paths return a value".
6. Emit `EVC:N`/`EVC:C` enum-value-table count/cap markers.


### semanticAnalyzerResolveStmtIter (`semantic_analyzer.zig`)

`[inference: worklist-based iteration over statement tree]`

Worklist (stack-based) traversal. Pushes stmt children in reverse order for pre-order processing. Handles:
- `block` → push children in reverse (last first for correct order after pop).
- `var_decl` → **Task B2 first:** a `const` with no annotation whose initializer is one of the four container decls is a function-local named type: run the packed-field / local-enum gates, `registerContainerType`, `layoutEnsure`, record the binding in `local_decl_names`/`local_decl_types`, push it into `local_types`, set the RTT entries, and skip the value path (NO `nameCachePut`). A `const` whose initializer is an ident naming a local type (`const F = E;`) is a local type alias → `error[3000]` + skip. **Task B2 final fix wave:** the guard is extended so ANY local `const`/`var` binding whose initializer names a `type` value clean-rejects (`error[3000]` + skip): a `var` binding of a container type (`a local type value must be declared with 'const'`), and a compound type-expression initializer (`*E`/`E!i32`/`[N]E`/`?E`/`fn(...)`/`[]E`/`[*]E`, detected by `type_resolver.isCompoundTypeExprKind`; same alias message). Otherwise resolve the type annotation (ident_expr via `resolveExpr` with a `resolveTypeExprFull` fallback, else RTT / `resolveTypeExprFull`). Resolve init with push/pop expected type. Infer an error-literal type by scanning the registry for a containing error set; emit `ERR_3010` for an un-inferable enum literal. Record coercions (with a `volatile`-drop guard). Push a function-local `const` into `local_consts`. Register local decl + name cache; diagnostics for mismatches. **Task 4:** after `decl_type = it` for an unannotated binding, if the inferred type is an integer type (`INT_LIT`/`I32`) a fresh `comptimeEvalEvaluate` probe (`local_consts` wired, no diagnostics) folds the initializer; when the exact integer does not fit i32 it takes `comptimeIntUntypedType` (U32/I64/U64), so the binding, its slot and all later references are consistent (`const bigu = 2000000000 + 1000000000;` → u32).
- `if_stmt` → resolve header, push else then then (for correct worklist order).
- `while_stmt` → resolve header, push body.
- `for_stmt` → resolve header, push body.
- `return_stmt` → `resolveReturnStmt`.
- Assignments → `semanticAnalyzerResolveExpr`.
- `defer_stmt`/`errdefer_stmt` → run `semanticAnalyzerCheckDeferBody` (Task 10D outward-control-flow rejections `ERR_3051`–`ERR_3054`), then bump `defer_depth`, recurse into the body, decrement.
- **`labeled_stmt` → transparent unwrap:** if `child_0 != 0`, push it onto the stmt work queue — the label is a pure wrapper, the inner statement resolves as if unlabeled. (A `labeled_stmt` reaching `resolveExpr` re-enters the stmt iter and returns `TYPE_VOID`, preventing the `error[3020]` unhandled-else.)
- `break_stmt`/`continue_stmt` → no-op here (validated by `constraint_checker.zig`).
- Other → `semanticAnalyzerResolveExpr`; if the result is an error union, emit `ERR_3015` "error union result is ignored".

Skips `fn_decl` children (inner functions handled by outer phase).

#### Worklist strategy: why iterative, not recursive

`semanticAnalyzerResolveStmtIter` is explicitly iterative: it pushes the root statement onto `stmt_work`, then pops/processes in a `while` loop until drained back to the entry `sp_base`. Three reasons this design was chosen over plain recursion:

1. **Bounded C-call depth for statement trees.** The companion pre-pass `resolveStmtTypes` (main.zig) is recursive and hard-caps its depth. The real semantic pass must not blow the bootstrap C89 stack on deeply nested blocks; the worklist keeps C-call depth flat regardless of statement nesting.
2. **Explicit source-order traversal.** Children are pushed in reverse so the pop order is pre-order source order — the same guarantee a recursive descent gives, without recursion. `constraintCheckerCheckBreakContinue` uses the same explicit-`(node_idx, depth)`-stack pattern.
3. **Per-module lifecycle.** The worklist lives on the `SemanticAnalyzer`, which is created per module on the scratch arena. `sp_base` is captured at entry, so every fn body drains exactly back to its base — the worklist is always empty (at base) between fn bodies and dies with the module's scratch reset.

The worklist is statement-scoped: *expression* subtrees are still resolved recursively via `semanticAnalyzerResolveExpr`, which re-enters the worklist only for statement-like nodes (var_decl/defer/errdefer). A deep expression nest still recurses; the worklist absorbs only statement nesting.

### semanticAnalyzerResolveStmt (`semantic_analyzer.zig`)

`[inference: delegate to semanticAnalyzerResolveStmtIter]`

Public entry point. Thin wrapper around semanticAnalyzerResolveStmtIter.

### semanticAnalyzerResolveTryExpr (`semantic_analyzer.zig`)

`[inference: resolve inner → error_union → payload type]`

If inner is error_union_type, return `eu.payload`. Else return `TYPE_VOID`.

### semanticAnalyzerResolveOrelseExpr (`semantic_analyzer.zig`)

`[inference: null + expected optional → wrap_optional_null coercion → payload type; optional → unwrap_optional coercion → payload type]`

Cases:
- Inner is `TYPE_NULL` and expected type is non-zero: if expected is optional, extract payload, add `wrap_optional_null` coercion, return payload.
- Inner is `optional_type`: extract payload, add `unwrap_optional` coercion; if an `orelse` RHS exists, push the payload as its expected type, resolve it, and record a coercion; return payload.
- Otherwise emit `ERR_3016` "orelse requires an optional operand; use 'catch' for error unions" and return `TYPE_UNDEFINED`.

### semanticAnalyzerResolveIfExpr (`semantic_analyzer.zig`)

`[inference: resolve header → resolve then/else → unify against expected type, else pairwise]`

Unification first honors an expected type from the enclosing context (`topExpectedType`). If both branches are assignable to it (with string literals typed `*const [N]u8` and treated as slice coercions), both are coerced to the expected type and it is returned. Otherwise the pairwise priority is:
- No else → if `then_type` is not `VOID`/`NORETURN`/`undefined` and the condition is not comptime-known-true, emit level-0 `error[3059]` (`ERR_3059_IF_WITHOUT_ELSE`) at the `if` expression, then return `then_type`. `[updated: 2026-09-22 — Task 9B (b, m1240 ruling 3): a no-`else` value `if` is typed `void` in Zig, so it may only be used as a value when the then-branch is void/noreturn or the condition folds to a comptime-true bool (`semanticAnalyzerConditionIsComptimeTrue` — a fresh `comptime_eval` evaluator with `diag = null`, accepting a `bool_literal true`, a const-bool chain, or a folding builtin whose result has bool width 1). The validity gate accepts a `bool` condition (no capture) **or** an optional/error-union condition (capture), so a capture-condition value `if` without `else` (`if (o) |v| v`) is rejected too (fix round 1); an invalid condition still gets only its header `error[3058]` (no double report). Otherwise rc=2 / 0 `.c`. `_ = if (c) foo();` (void then) stays legal.] `[updated: 2026-09-23 — Task 9D: the probe now sets `ce.local_consts = &self.local_consts`, and the fold (`comptime_eval.zig`) covers integer comparisons and the bool logical ops (short-circuit), so a function-local const comparison (`const a: i32 = 1; if (a == 1)`) folds true and is accepted — matching Zig; a runtime `var` condition still does not fold and stays rejected `error[3059]`. Task 9D fix round 1: the fold compares by DECLARED integer type (`const umax: u64 = 18446744073709551615; if (umax > 0)` accepted; `if (umax < 0)` rejected) and folds a decisive RHS of `and`/`or` when the lhs is runtime (`if (run or true)` accepted; `if (run and false)` rejected).]`
- then == else → return either
- then is noreturn → return else
- else is noreturn → return then
- then is int_lit, else is numeric → coerce then, return else
- else is int_lit, then is numeric → coerce else, return then
- then is VOID → return else
- else is VOID → return then
- Otherwise → return TYPE_VOID (type mismatch)

### semanticAnalyzerCaptureType (`semantic_analyzer.zig`)

`[inference: if optional → unwrap payload; else return cond_type as-is]`

Unwraps optional types in if/while/for capture expressions. If cond_type is optional, returns the payload type; otherwise returns cond_type unchanged.

### semanticAnalyzerResolveIfHeader / ForHeader / WhileHeader

`resolveIfHeader` (`semantic_analyzer.zig`):
`[inference: resolve condition → if_capture → registerLocalDecl with captured type → validate condition type]`
Capture unwraps optional via `semanticAnalyzerCaptureType`. After resolving the condition and registering any capture, `semanticAnalyzerCheckConditionType(node_idx, cond_idx, cond_t, has_capture)` validates it: with no capture the condition must be `bool`, and with a capture it must be optional or error-union; a violation emits level-0 `error[3058]` (`ERR_3058_CONDITION_NOT_BOOL`) at the condition (rc=2, 0 `.c`). A condition already typed `void`/`undefined`/`noreturn` is skipped so an earlier diagnostic (e.g. an undeclared identifier) is not cascaded. `[updated: 2026-09-22 — Task 9B (c, m1240 ruling 5): rejects a non-`bool` `if` condition (`if (a)` with i32/u32/pointer/enum/optional) and a non-optional capture condition (`if (q) |v|` with a non-optional `q`), matching official Zig 0.15.2 ("expected type 'bool'" / "expected optional type"). Deduped via `diagnosticCollectorMarkNodeOnce`.]`

`resolveForHeader` (`semantic_analyzer.zig`):
`[inference: resolve iterable → slice/array/pointer-to-array/range → element type → register capture + index]`
If payload (capture name), register local decl with element type. If child_2 (index name), register with `TYPE_USIZE`. When the iterable is a `range_exclusive`/`range_inclusive` node, its start/end operands are resolved by that node's own arm of `semanticAnalyzerResolveExpr` (Task 11P), so operands whose lowering needs the resolved-type table (e.g. `.len` on a struct/union array or slice field) get resolved-type entries. **Task 11:** a `for_index_range` pattern (explicit index form) types as its iterable via `semanticAnalyzerResolveForIndexRange`, which also resolves/validates the start/end bounds (literal or unsigned int width <= 32; comptime bounds must fit `usize`), rejects a comptime span != a fixed array's length ("non-matching for loop lengths"), a comptime `end < start` (overflow), and a range without an index capture — all level-0 `error[3000]`, deduped via `diagnosticCollectorMarkNodeOnce`. **[FI, 2026-09-27]** a `ptr_type` iterable whose pointee (payload-index-guarded) is a fixed-size array takes the pointee array's element as the item type (so `*[0]T` iterates zero times, `*[1]T` once, and the direct/quoted pointer-to-array forms register normally); every other pointee leaves the item unresolved (`error[20]` at the capture use, unchanged). `semanticAnalyzerCheckForIndexRangeComptime` applies the same comptime span-vs-length reject to such a pointer-to-array iterable (the pointee array's length). `[updated: 2026-09-24 — Task 11 (Part II): `semanticAnalyzerResolveForIndexRange`, `semanticAnalyzerForIndexBoundOk`, `semanticAnalyzerReportForIndexRange`, `semanticAnalyzerCheckForIndexRangeComptime`.]`

`resolveWhileHeader` (`semantic_analyzer.zig`):
`[inference: resolve condition → while_capture → registerLocalDecl → validate condition type]`
Same capture logic as if-header, and the same `semanticAnalyzerCheckConditionType` validation (no capture requires `bool`; a capture requires optional/error-union; level-0 `error[3058]`). Also resolves `child_2` (the `while` continue expression) so nested field stores there have resolved types. `[updated: 2026-09-22 — Task 9B (c): the shared condition-type check covers `while (a)` with a non-`bool` condition.]`

### semaTraceStep (`semantic_analyzer.zig`)

`[inference: follow ident_expr → var_decl → slice_expr → ident_expr chain, up to 3 steps]`

Source-tracing helper for index-access error messages. Follows a variable name through up to 3 levels of var_decl/slice_expr indirection to find the original source name. Called by semanticAnalyzerResolveIndexAccess.

### semanticAnalyzerResolveIndexAccess (`semantic_analyzer.zig`)

`[inference: resolve index → resolve base → trace source → indexed elem type]`

Resolve child_1 (index), then child_0 (base), saving/restoring `_stub_0`. If base is `ident_expr`, trace back up to 3 steps through var_decl → slice_expr → ident_expr chain to find source name (for error messages) and record it via `resolvedSourceTableSet`. Returns `typeRegistryIndexedElemType`, or the tuple's first element type, or the base type. If the base is a scalar/aggregate that is not indexable, emits a hard `error[3000]` "cannot index a value of non-array, non-pointer type" instead of silently returning the base type. **[updated: 2026-09-24 — Task 17 (F)]** When `typeRegistryIndexedElemType` succeeds it first runs `semanticAnalyzerCheckComptimeIndexOob` (fixed-array length + folded index → `error[3062]`); `_stub_0`/`_stub_1` are saved/restored around the call because the `.len` recovery can re-resolve the base. **[updated: 2026-09-27 — FH (D10)]** Before the shared elem helper, a `ptr_type` base whose pointee is not a fixed-size array (and is not the `semanticAnalyzerStaticArrayLen`-marked struct/union array-field decay) rejects `semanticAnalyzerReportIllegalPtrIndex` → level-0 `error[3066]` `ERR_3066_SINGLE_PTR_INDEX` (`type '*T' does not support indexing`, Zig's note `operand must be an array, slice, tuple, or vector`, span on the index expression, deduped per node); the `type_type` base (`(*p)[i]`) rejects the same code with `unable to resolve comptime value` + `types must be comptime-known` instead of the former silent traced-initializer wrong code. `*[N]T`, `[*]T` and `p.*` are unchanged.

### semanticAnalyzerResolveSliceExpr (`semantic_analyzer.zig`)

`[inference: resolve base → validate base kind → resolve bounds → create slice type from elem]`

Resolves child_0 (base/elem), child_1 (start), child_2 (end). Emits `error[2000]` "cannot slice base type: expected array, slice, or many-pointer" unless the base is an array/slice/many-ptr/ptr. Determines element type via `typeRegistryIndexedElemType`. Creates slice type with const flag from base type's flags **[updated: 2026-09-28 — FX6 (Volume II)]** plus the BINDING's constness for an ARRAY base (`semanticAnalyzerIsLValueConst(child_0)`): an array value carries no const flag on its type, so `const arr` must yield `[]const T`; deliberately array-only (a const-bound mutable slice `const s: []T` keeps `s[0..]` as `[]T`). **[updated: 2026-09-28 — FX11 (Volume II)]** The same binding constness applies to a pointer base that is an aggregate array-field decay (`semanticAnalyzerFieldAccessArrayType(child_0)`), so `cs.a[0..]` on a const aggregate yields `[]const T` (belt-and-braces: the field access itself already resolves `*const T`). **[updated: 2026-09-24 — Task 17 (F)]** After the base-kind check it runs `semanticAnalyzerCheckComptimeSliceBounds` (comptime-known constant bounds on a fixed-size array → `error[3062]`), preserving `_stub_0` around the call. **[updated: 2026-09-27 — FH (D10)]** First, for a `ptr_type` base whose pointee is not an array (and not the array-field decay), `semanticAnalyzerCheckSinglePtrSlice` accepts only the comptime-known `(0,0)`/`(0,1)`/`(1,1)` pairs and returns Zig's `*[0]T`/`*[1]T` (`typeRegistryGetOrCreateArray` + `typeRegistryGetOrCreatePtrQ` with the base's const/volatile flags); every other form rejects level-0 `error[3067]` `ERR_3067_SINGLE_PTR_SLICE_BOUNDS` (`slice of single-item pointer must be bounded` / `unable to resolve comptime value` + `slice of single-item pointer must have comptime-known bounds` / `slice of single-item pointer must have bounds [0..0], [0..1], or [1..1]`, span on the offending bound). This replaces the former unchecked acceptance (`p[0..2]`, `p[1..0]`) and the `error[3043]` ICE on `p[0..]`. **[updated: 2026-09-28 — FX5 (Volume II)]** After the single-item-pointer gate, a `many_ptr_type` base with an omitted end (`mp[s..]`/`mp[0..]`) is ACCEPTED and returns `[*]T` (`typeRegistryIndexedElemType` + `typeRegistryGetOrCreateManyPtrQ` with the base's const/volatile flags) — the Zig-0.15.2 result for the form (operator ruling, fix round 1; the interim `error[3067]` reject and the former lowering-path `error[3043]` ICE are withdrawn). A genuine `[*]T` base is the only shape reaching the arm: `h.arr` resolves as its declared array type, so a struct/union array FIELD keeps the ordinary `[]T` slice path (declared length as the effective end). The `*[N]T`/array/slice bases keep the ordinary path (element type + slice type unchanged); `*[N]T` ranges keep the Z98 `[]T` result (Zig's `*[M]T` is a documented divergence).

### semanticAnalyzerStaticArrayLen / semanticAnalyzerArrayFieldLength (`semantic_analyzer.zig`)  [added: 2026-09-24 — Task 17 (F)]

`[inference: declared type → fixed array length (or null)]`

`semanticAnalyzerStaticArrayLen(base_node)` recovers the compile-time length of an indexed/sliced base: an `array_type` resolved type; a `ptr_type` whose pointee is an array (`*[N]T`); or, for a `field_access` base whose field decayed to an element pointer, `semanticAnalyzerArrayFieldLength` (the declaration walk factored out of the Task-11N `semanticAnalyzerArrayFieldLen`, which is now a thin `usize`-or-0 wrapper). A `slice_type` / `many_ptr_type` / scalar has no compile-time length and a direct string literal is skipped (its Zig type carries an implicit NUL sentinel, so Zig's bound is `N + 1` while Z98 has no sentinel array kind). Returns `null` when unknown, so the runtime `-fsafe` guard is the only bound.

### semanticAnalyzerComptimeIntValue (`semantic_analyzer.zig`)  [added: 2026-09-24 — Task 17 (F)]

`[inference: comptime_eval fold → .len recovery → ?ComptimeInt]`

Folds an index / slice-bound expression to an exact `ComptimeInt` using the shared `comptime_eval` evaluator (literals, `const` chains, constant arithmetic; `local_consts` wired). It has no field-access arm, so when the fold returns null and the node (after unwrapping up to 4 parens) is a `field_access` named `len`, the value is recovered through `semanticAnalyzerStaticArrayLen` on the `.len` base — the `scores[scores.len]` shape. A runtime value returns false and keeps the runtime check.

### semanticAnalyzerCheckComptimeIndexOob / semanticAnalyzerCheckComptimeSliceBounds (`semantic_analyzer.zig`)  [added: 2026-09-24 — Task 17 (F)]

`[inference: static length + folded value → compare → error[3062]]`

The index check rejects `idx < 0` (Zig's `type 'usize' cannot represent integer value '-N'`) and `idx >= len` (`index N outside array of length L`). The slice check follows Zig's order: a negative bound is the coercion reject; then `end > len` (`end index N out of bounds for array of length L`); then `start > end_eff` where the effective end is the length for the **open form** (`a[s..]`, `child_2 == 0`) and the folded end for a **closed form with a comptime end** (`start index S is larger than end index E`). **[fix round 2026-09-24 -- review Important 1]** a CLOSED form whose present end is runtime (`a[7..ri]`) has no comptime end to compare against, so the start check is skipped and the shape keeps its pre-Task-17 runtime behavior (Zig accepts it too; the base version wrongly compared the start against the length and rejected `start index 7 is larger than end index 5`). `a[len..]`/`a[len..len]` stay legal empty slices. Both emit the new level-0 `error[3062]` `ERR_3062_INDEX_OUT_OF_BOUNDS` (deduped per node via `diagnosticCollectorMarkNodeOnce`, span on the offending index/bound) with the ASCII messages above, so the program rejects rc=2 / 0 `.c` before lowering; the runtime `-fsafe` `check_trap{kind=5}` path for a runtime index is untouched. Helpers `semanticAnalyzerComptimeIntText` / `semanticAnalyzerU32Text` render the values, and `semanticAnalyzerReportIndexOob` / `semanticAnalyzerReportSliceEndOob` / `semanticAnalyzerReportSliceStartAfterEnd` / `semanticAnalyzerReportUsizeNegative` build the messages.

### semanticAnalyzerCheckSinglePtrSlice + the 3066/3067 reporters (`semantic_analyzer.zig`)  [added: 2026-09-27 — FH (D10)]

`[inference: base ptr → non-array pointee → comptime bound fold → accept three pairs / report 3067]`

Returns 0 when the base is not a single-item pointer to a non-array pointee (the ordinary slice path runs, and the struct/union array-field decay is exempted via `semanticAnalyzerStaticArrayLen`), 1 when one of the three Zig-legal comptime pairs was accepted (`out_len` = end − start), and 2 when a 3067 diagnostic was emitted. An open end (`child_2 == 0`) reports `slice of single-item pointer must be bounded`; a non-folding start/end reports `unable to resolve comptime value` + `slice of single-item pointer must have comptime-known bounds`; a negative or out-of-set pair reports `slice of single-item pointer must have bounds [0..0], [0..1], or [1..1]`. `semanticAnalyzerReportIllegalPtrIndex` emits the 3066 index reject (pointer wording or the `type`-base wording), and `semanticAnalyzerSpellTypeBack` / `semanticAnalyzerSpellBytesBack` render the base type into the message backward (`*i32`, `*const i32`, `**i32`, `*[3]i32`, `*?i32`, `*Point`; depth-capped, kind-word fallback). All are level 0, deduped per node via `diagnosticCollectorMarkNodeOnce`; `notes` use the locationless `diagnosticCollectorAddNote` (mirrors Zig's `note:` lines). **Superseded by FI (operator ruling A, 2026-09-27):** the FH review-round residual that the adopted `*[0]T`/`*[1]T` results were not iterable is fixed — `for` now iterates a pointer-to-array (see `resolveForHeader` above), so `for (p[0..1]) |v|` runs again with the pre-FH shape. Remaining residual: `emitArrayType` clamps the `*[0]T` typedef to `[1]` (`c89_emit.zig` `decl_len = if (ap.length == 0) 1 else ap.length`) while the sema length stays 0 (`.len` 0, index 3062), so the C model — not the behavior — is clamped.

### semanticAnalyzerResolveTupleLiteral (`semantic_analyzer.zig`)

`[inference: resolve each element → append to xt → create tuple type]`

Each element is resolved and typed by what it is (FB2, 2026-09-27): a TYPE value referenced by name (`.{ i32, 5 }`, `.{ S, 5 }`, `.{ mod.T, 5 }` — the `semanticAnalyzerTupleElemIsTypeValue` mirror of lower's `printFmtArgIsTypeValue`) types as `TYPE_TYPE` so the print validator's type-kind arm rejects `error[3063]` on both the literal and FD2's tuple-variable path (inline type expressions already resolved to `TYPE_TYPE`); a genuine `void` element keeps `TYPE_VOID` (the old i32 fallback is removed) so both print paths reject `error[3063]` instead of fabricating an invalid i32 element — a VOID-typed bare (paren-transparent) ident or module-member reference is an unresolved forward global (`semanticAnalyzerTupleElemVoidIsUnresolvedRef` + `semanticAnalyzerTupleElemFieldBaseIsModule`; fix round 1 narrows the field-access case: only a module/import base is transient) and keeps the pre-FB2 pass-1 `TYPE_I32` fallback so the settled tuple identity and every later type id stay byte-identical — a field read on a VALUE base (`s.v`, `p.v`, `g.v`) is NOT transient because void-typed struct fields are legal Z98, so it keeps `TYPE_VOID` and both print paths reject `error[3063]`; an untyped integer-literal element folds through `comptimeEvalInit`/`comptimeEvalEvaluate` and takes the value-chosen carrier (`comptimeIntUntypedType`: i32 / u32 / i64 / u64; a value outside the 64-bit window keeps `TYPE_INT_LIT` and lowering reports `error[3000]`), exactly like the unannotated-binding rule, so `.{ 3000000000, -3000000000 }` is `{u32, i64}` and not `{i32, i32}`; in-i32 values keep `TYPE_INT_LIT`, so existing in-range tuples emit byte-identical C. **[updated: 2026-09-25 — Task 4]** All elements are resolved FIRST into a scratch `u32` array, then their types are appended to `registry.xt_items` contiguously, then `typeRegistryGetOrCreateTuple(start, count)` is created. The old resolve+append-interleaved loop captured `start` before resolving, so a nested tuple literal (which appends its own element types while resolving) left the outer tuple payload's `elems_start`/`count` spanning the nested tuple's element range — the outer tuple's C model and its generated printer then saw `i32` instead of the nested tuple type. **[fix round 1, 2026-09-25 — Critical 1]** resolution is now **idempotent per node**: if the resolved-type table already holds a non-`TYPE_UNDEFINED` type for the literal, it is returned before a new tuple is created. The module-var resolution loop in `front_resolution.zig` re-resolves every global initializer, and the old per-pass tuple creation left the global symbol on `Tup_N` while lowering used `Tup_M` (module-level `var g = .{ 11, 22 };` emitted a cross-type `__module_init` assignment, gcc `incompatible types`, with or without a print); the cached type keeps the global symbol, the lowered temp and the generated printer on one C type. Regression coverage: the nested-tuple and `gtupv`/`gtupc` global rows of `repro/mi_matrix/stdlib_print_aggregate_xmod`. **[Task 9 (B5), 2026-09-25; fix round 1 narrowed]** the recorded fast path also RE-RESOLVES the elements and compares their types positionally with the recorded tuple's `tup_items` payload. A changed element list is a stale pass-1 inference (the element referenced a global declared later, which pass 1 typed with the `TYPE_VOID -> TYPE_I32` fallback). Most such changes are broken: a composite element emitted gcc-invalid C (`zT_0._0 = zG_b` with `_0` an `int` and `b` a `Pair`), an out-of-i32 integer truncated silently (`3000000000` printed `-1294967296`), and a non-literal scalar init (`5 + 7`, `-5`, `true`, `1.5`) lowered to a global load that `__module_init` stores after the tuple owner (printed `0`/`0`/`0`/`1`). Since `__module_init` cannot be reordered here, those shapes reject level-0 `error[3064]` `ERR_3064_FORWARD_REF_TUPLE_GLOBAL` at the tuple span (deduped per node via `diagnosticCollectorMarkNodeOnce`) and the recorded type is still returned. **Fix round 1 (operator ruling):** `semanticAnalyzerTupleElemRefreshOk` keeps the ONE benign class accepted — a module `const` (not `var`) initialised by a bare `int_literal`/`char_literal` whose exact folded value fits `i32` (`const s = 5`, `2147483647`, `'A'`); the literal is inlined at the use site (the module-init emitter skips literal consts), so the frozen slot holds it exactly and the program is Zig-identical. Every other changed element still rejects. Stable tuples (`.{ 11, 22 }`, `gtupv`/`gtupc`, print-arg tuples) re-resolve to an identical list and keep the idempotent fast path. Zig 0.15.2 accepts and prints the forward-referenced shapes — documented bounded residual (Language_Spec §4); positive fixture `repro/mi_matrix/stdlib_print_tuple_fwd_ok_xmod` (stdlib pin 241 -> 242), reject fixture `repro/mi_matrix/tuple_fwd_global_reject_xmod` (6 x `error[3064]`, rc 2 / 0 `.c`) + standalone `repro/print_tuple_fwd.z98`. **[Task 9 fix round 2 (review Critical 1 + Important 1), 2026-09-25]** the reference classifier was completed: `semanticAnalyzerUnwrapParens` peels any `( ... )` chain and `semanticAnalyzerTupleElemGlobalSym` resolves a module global through a bare ident, an aliased module member (`colors.C`), an `@import("x.zig").C` member (with `allow_inline = 0`, because the lowerer does not inline that form — the base emitted gcc-invalid C), or a global aggregate field (`cfg.x` -> `cfg`). The recorded path now validates EVERY element through the same inline/order test regardless of type deltas (`semanticAnalyzerTupleElemSubtreeOrderOk`, descending only `child_0/child_1/child_2` — a generic `extra_children` walk is unsafe), so the same-type silent-wrong forward references (`var g = .{ s, 7 }; const s: i32 = 5 + 7;` / `-5` / `@as(i32, 5)` printed `0` where Zig prints `12`/`-5`/`5`) now reject `error[3064]`; a parenthesized/aliased literal ref and a global declared before the tuple stay accepted. The fit test handles `integer_literal` slots via the 32-bit-signed materialisation (`comptimeIntFitsType` cannot take the width-0 primitive). Fixtures: positive `stdlib_print_tuple_fwd_ok_xmod` 9 rows (byte-identical to the Zig-0.15.2 twin), reject `tuple_fwd_global_reject_xmod` **11 x `error[3064]`**, standalone `repro/print_tuple_fwd.z98` 3 x `error[3064]`. Residual sub-class: a forward global ref hidden inside a call argument is not walked (extras) and stays accepted — documented in Language_Spec §4 / EXPECTED_FAIL v245. **[Task 9 fix round 3 (Q7), 2026-09-25]** the reject approach was replaced by the true fix in the LOWERING/emitter layers (doc 07/08/09): this function now rebuilds a changed tuple from the settled element types instead of rejecting, and `frontResolveModuleInits` updates unannotated decl/symbol types until stable. Consequently every forward-reference class (non-literal scalar consts, composite/wide/float/bool elements, cross-module members, struct-literal field and call-argument refs) resolves and the `semanticAnalyzerTupleElem*` helpers are deleted; `error[3064]` moved to the dependency-cycle reject in `lowerModuleInit`/`computeModuleInitOrder`.

### semanticAnalyzerResolveArrayInit (`semantic_analyzer.zig`)

`[inference: resolve child_0 annotation (or infer `[_]T` elem) → push element expected type → create array type]`

If `child_0` has a resolved array type, return it directly. Otherwise resolve an explicit `array_type` annotation (including a `[_]T` inferred-length annotation, whose element type is resolved and used as the expected type for every element). Element types come from char_literal → u8, int_literal → u32, else resolve with the element expected type pushed. With an annotation, returns the annotation type; otherwise creates an array type from the first element and the element count.

### errLitSrcType (`semantic_analyzer.zig`)

`[inference: if child is error_literal and target is error_union → return error_set; else ret_val]`

Helper for tryRecordCoercion and resolveReturnStmt. Extracts the error set type from an error union target when the source node is an error literal.

### resolveReturnStmt (`semantic_analyzer.zig`)

`[inference: push expected fn return → resolve expr → record coercion]`

Bare return: if `fnReturnRequiresValue(current_fn_return)` → `ERR_3003` "return with no value in function returning non-void". Otherwise `pushExpectedType(current_fn_return)` → resolve → `popExpectedType`. If the return type is non-zero non-void: emit `T2F:*` markers, compute the effective source via `errLitSrcType`, emit a shape-mismatch diagnostic when not assignable, then `tryRecordCoercion`.

### Value-aware f32 narrowing — `semanticAnalyzerFloatNarrow*` (`semantic_analyzer.zig`) [added: 2026-09-27 — FX3 (Volume II D6 extras)]

The Zig 0.15.2 value-aware rule at an **f32 expectation site** (an f32
parameter, return, struct/union/tagged-union field initializer, local or
module declaration, or assignment). `semanticAnalyzerFloatNarrowStatus(src_node,
src_ty, F32)` returns `FLOAT_NARROW_NONE` / `_ACCEPT` / `_REJECT`:

- `semanticAnalyzerFloatNarrowIsNumeric` gates the pair to an f64 source or an
  integer kind (`typeRegistryIsInteger`, so `TYPE_INT_LIT`, fixed and
  arbitrary-width ints; `c_char`/enum/bool are out).
- f64 source: `comptimeEvalFloatNarrow` (comptime_eval.zig) folds the value and
  its typed/untyped provenance via `floatNarrowProbe`/`floatNarrowDecl`
  (literals, `negate`/paren, literal-only `+ - * /`, `@as`/`@floatCast`/
  `@intToFloat`, const chains, and integer literals/operands). An **untyped**
  (`comptime_float`) value is `ACCEPT` (it is ROUNDED, even inexact `0.1` or
  `1e40` -> `inf`); a **typed** value is `ACCEPT` iff
  `comptimeEvalF64IsF32Exact(value)`, else `REJECT`; a non-foldable expression
  (a runtime var/param) is `NONE` (the site's existing runtime reject applies).
- integer source: the exact `ComptimeInt` (`comptimeEvalEvaluate`) is `ACCEPT`
  iff `comptimeIntF32Exact` (significand <= 24 bits AND the f64->f32 round trip
  is exact, which also enforces the f32 finite range), else `REJECT`; a runtime
  integer is `NONE`.

**FX3 fix round 1** — `if`/`switch` VALUE expressions at the site are
classified by their ARMS, not the joined f64 value that the probe cannot fold:
`semanticAnalyzerFloatNarrowStatusDepth` intercepts `if_expr` (both arms) and
`swt_ex` (every prong's `child_0`) after paren-unwrapping, and
`semanticAnalyzerFloatNarrowArmStatus` looks the arm's sema type up in the
resolved-type table and requires it to accept — a `noreturn` arm (a diverging
branch), a genuine `f32` arm, and (FX9 fix round 1) a `TYPE_UNDEFINED` arm
are neutral, an `integer_literal` arm still
passes the int-exactness check (`if (c) 16777217 else 2.5` rejects), and a
  runtime/void/unresolvable arm rejects the whole expression. An accepted
  `if`/`switch` records `float_narrow` (the site narrows the joined temp; with
  FX10 the switch itself is retyped `f32` and records each prong, see below),
  so `return if (c > 0) 1.5 else 2.5;`,
  `return switch (c) { 1 => 1.5, else => 2.5 };` and an `if`-initialized
  declaration all build and run Zig-identically. Pre-fix these over-rejected
  `error[3000]` although the seed and Zig 0.15.2 accept them.

**FX9** — a runtime non-float arm of an `if`/`switch` VALUE expression at an
f32 site rejects. Because the mismatched arms did not unify under Z98's peer
rules, `semanticAnalyzerResolveIfExpr` used to fall through to `TYPE_VOID`;
the value probe then saw a non-numeric source and returned `NONE`, so
`fn f(c: i32, n: i32) f32 { return if (c > 0) n else 2.5; }` compiled rc 0
and returned 0 (the arms were lowered as no-value). Two changes: (1) the
resolver's new FX9 branch (after the void/int-literal rules, before the void
fall-through) classifies the REACHABLE arms with
`semanticAnalyzerFloatNarrowArmStatus` for an f32 expected type — all
acceptable types the `if` `TYPE_F32` and records each arm's narrowing, so a
runtime `f32` arm beside a float literal or an exact typed `i32`/`f64`
(`if (c > 0) x else 2.5`, `if (c > 0) x else C`, nested
`if (c > 0) (if (e > 0) x else 2.5) else 3.5`) is now correct where it used
to return 0; otherwise the `if` takes the offending arm's type, so (2) the
site's existing FX3 status reports the runtime-arm reject with the offending
`source:` note (`if (c > 0) n else 2.5` -> `source: i32`). A comptime-known
condition makes the untaken arm unreachable (`semanticAnalyzerConditionComptimeBool`,
the tri-state form of `semanticAnalyzerConditionIsComptimeTrue`), matching
Zig: `if (false) n else 2.5` accepts, `if (true) n else 2.5` rejects.
`semanticAnalyzerFloatNarrowStatusDepth` now runs the `if`/`switch` arm
interception BEFORE the `semanticAnalyzerFloatNarrowIsNumeric` guard (and
skips unreachable if arms), so a `void`/bool/pointer-typed mismatched-arm
expression rejects at the site instead of silently producing no value. The
switch form already rejected (`switch (c) { 1 => n, else => 2.5 }`); the
field/argument if forms used to emit gcc-invalid C (`zT_4294967295`
undeclared) or ICE `error[3043]`. Fixtures: `f32_narrow_reject_xmod`
18 -> 33 x `error[3000]`; `stdlib_f32_narrow_ok_xmod` gains the `mix=` row
(10 lines / 168 B, Zig-twin byte-identical); standalone
`repro/f32_runtime_arm_reject.z98` (11 x `error[3000]`).

**FX9 fix round 1** — an `undefined` arm is neutral.
`semanticAnalyzerFloatNarrowArmStatus` returns `ACCEPT` for
`TYPE_UNDEFINED` (like `noreturn`/`f32` arms): `undefined` coerces to every
type, so `if (c) undefined else 2.5` is accepted at return, declaration,
assignment, field and argument sites and in either arm position (the seed
v88 / PRE `89aaf0ec` / Zig 0.15.2 all accept; the field/argument forms
emitted gcc-invalid C or ICEd before FX9 and now compile and run, and the
taken-literal branch now produces the correct value where PRE dropped it).
The runtime-arm reject is unchanged (`if (c) n else undefined` with runtime
`n: i32` still rejects `source: i32`, matching Zig). Fixture
`stdlib_f32_narrow_ok_xmod` gains the `und=` row (11 lines / 196 B,
Zig-twin-equal) + standalone `repro/f32_undefined_arm_ok.z98`; reject
  censuses unchanged (33/11/8 x `error[3000]`). The accepted-wrong residual
  this section used to name (a switch VALUE expression whose first prong is a
  typed integer and a later prong a float truncating,
  `switch (c) { 1 => C, else => 2.5 }` -> `2` where Zig yields `2.5`) is
  **fixed by FX10** (next paragraph); the FX9 retyping branch is `if`-only.

**FX10** — the switch VALUE expression at an f32 site is retyped value-aware.
`semanticAnalyzerResolveSwitchExpr` gained a `sw_f32_site` flag (from
`topExpectedType`): when set, the prong loop SKIPS the value-blind unification
(so no widening is recorded on a prong and the first prong no longer wins),
and after the loop every prong is classified with
`semanticAnalyzerFloatNarrowArmStatus`. All acceptable => the switch records
`TYPE_F32` and each non-f32 prong gets `tryRecordCoercion` (lowering
materialises the per-prong narrowing like the `if` path); otherwise the switch
takes the offending prong's type so the enclosing f32 site's FX3 status
rejects with the offending `source:` note (`switch (c) { 1 => n, else => 2.5 }`
with runtime `n: i32` -> `source: i32`; an int-inexact literal prong ->
`source: comptime_int`; a runtime-f64 else prong after an exact first prong ->
`source: f64`). The switch OPERAND's comptime-ness is deliberately not used
(unlike the `if` condition reachability), preserving the documented
`switch (0)` over-reject. Fixtures: positive `stdlib_f32_narrow_ok_xmod`
gains the `swx=`/`swsites=` rows (13 lines / 250 B, Zig-twin byte-identical)
covering the typed-int first prong at return/declaration/assignment/field/
union/argument, the typed-exact-f64 first prong, a runtime f32 else prong and
the reverse order; reject `f32_narrow_reject_xmod` 33 -> 39 x `error[3000]`;
standalone `repro/f32_narrow_switch.z98` (accept,
`sw=6 2.5 6 3.5 2.5 2.5`, Zig-twin matched) +
`repro/f32_narrow_switch_reject.z98` (6 x `error[3000]`).

`semanticAnalyzerFloatNarrowRecord` adds `CoercionKind.float_narrow` on the
VALUE node (lowering's `lowerExpr` wrapper then emits the `float_cast`), and
`semanticAnalyzerFloatNarrowReport` emits the level-0 `error[3000]` with the
site's message plus `source:`/`target:` notes (`mark_once` for the field-init
sites whose expected-type pass can revisit the node). Wiring: both call-arg
loops skip the mismatch reject for `ACCEPT` and reject for `REJECT` even when
the source is an assignable `int_literal` (`take(16777217)`); `resolveReturnStmt`
rejects a runtime f64/i32 return that previously fell through silently;
`semanticAnalyzerResolveStructInit` (three field arms),
`semanticAnalyzerResolveAssign`, the local `var_decl` arm and
`semanticAnalyzerResolveModuleVarDecl` handle the remaining sites.
`tryRecordCoercion` calls the status for an f32 target when the source is not
assignable and records `ACCEPT`, so returns/arguments/field inits/if-switch
arms all materialise. Int-exact `takeF32(2)` stays on the existing
`int_literal_coerce` path (emitted C unchanged). Fixtures
`repro/mi_matrix/stdlib_f32_narrow_ok_xmod` (positive; stdlib pin 257 -> 258) +
`f32_narrow_reject_xmod` (18 x `error[3000]`) + standalone
`repro/f32_narrow.z98`/`f32_narrow_reject.z98`; D06 `green_param.zig`. Documented
boundary (pre-existing float-literal precision, spec §7.2): the naive
`parseF64` keeps an extreme typed literal (`3.4028234663852886e38`) rejected
where Zig accepts; the rule is applied to the lexed value.

### tryRecordCoercion (`semantic_analyzer.zig`)

`[inference: classifyCoercion → if non-none or null→ptr, add to coercion table]`

Emits `COE:N/S/D/SK/DK/NK` markers. If src == dst or src is UNDEFINED → skip. Calls `semanticAnalyzerMaybeDiagVolatileDrop`; if the coercion would implicitly discard a `volatile` qualifier, emit the diagnostic and record nothing (FC adds the same guard for a `const` discard). If not assignable: **[FX3]** for an f32 target an `ACCEPT` from `semanticAnalyzerFloatNarrowStatus` records `CoercionKind.float_narrow` on the value node; otherwise skip. Calls `classifyCoercion(registry, src, dst)` (marker `CCK:ca`). If coercion kind is not `none`, or src is null and dst is pointer → `coercionTableAdd(node, ck, dst_type)` (markers `COR:N/K`).

### Marker Reference

`File` is `sema` (`semantic_analyzer.zig`) unless noted.

| Marker | File | Meaning |
|--------|------|---------|
| `IDE\n` | sema | Resolve ident entry |
| `SEM:vi` | sema | Name is underscore (void ident) |
| `D7:Yn D7:n D7:t D7:<t>` | sema | Local decl found |
| `L\n L:t` | sema | Local resolved |
| `S\n` | sema | Symbol lookup |
| `TAL\n` | sema | Type alias resolved |
| `STY:N STY:T STY:C` | sema | Symbol type found (+ cached variant) |
| `SVO\n` | sema | Symbol is void |
| `C2:T` | sema | Name cache hit |
| `D8:*` | sema | Debug dump for node [450,660] |
| `IDT:<n>:VOID\n` | sema | Ident is void (unresolved) |
| `SCT:n SCT:t` | sema | Local decl registered |
| `FAE\n` | sema | Field access entry |
| `PFA:BK PFA:FN` | sema | Base kind + field name |
| `Q1:FL Q1:KL Q1:TL Q1:FN` | sema | Module-qualified lookup |
| `Q1FX\n` | sema | Cross-module fn decl |
| `BR:x BR:rt BR:fnr` | sema | Bridge fn return resolution |
| `BR:treN BR:treT BR:dv BR:ft` | sema | Bridge fallback through `resolveTypeExprFull` |
| `FAPR:OK FAPR:DK` | sema | Ptr deref in field access |
| `FT:TAG` / `FP:PAYLOAD` | sema | Tagged-union tag/payload field |
| `MFA\n` / `MF1\n` / `MFF\n` / `MFP` | sema | Module field access |
| `MF2` / `MF3\n` | sema | Module field fallback |
| `FSL:USIZE\n` | sema | Slice `.len` → usize |
| `FSP:PTR\n` | sema | Slice `.ptr` → many-ptr |
| `FAA:USIZE\n` | sema | Array `.len` → usize |
| `FF\n` | sema | Unknown base type |
| `FF:R` | sema | Field found result |
| `NF\n FF2:N FF2:F FF2:B` | sema | Field not found |
| `COE:N COE:S COE:D` | sema | Coercion attempt |
| `COE:SK COE:DK COE:NK` | sema | Src/dst TypeKind + node kind |
| `CS1\n` / `CS4\n` | sema | null-source coercion sites |
| `CCK:ca` | sema | classifyCoercion result (tryRecordCoercion) |
| `CCK:vr` | sema | classifyCoercion result (var-decl path) |
| `COR:N COR:K` | sema | Coercion recorded |
| `FNE\n` | sema | Fn call entry |
| `XF\n` / `xS\n` | sema | Direct-callee symbol hit/miss |
| `FN1\n FN1:R` | sema | Direct call resolved |
| `FN2\n` | sema | Callee void |
| `FN3:N FN3:T FN3:K` | sema | Not a fn type |
| `FN4a-FN4g` | sema | Fn call param resolution |
| `FN4:R` | sema | Fn call return |
| `PTM:A PTM:T PTM:N` | sema | Param type marker |
| `SF:H` | sema | Resolved fn-type param lookup |
| `BR:rnt DRETFB:n BR:fc BR:fnr` | sema | Direct return-type resolution |
| `T2F:C T2F:R T2F:F` | sema | Return coercion tracking |
| `LOE` / `LOB LOV` | sema | Logical op entry / bool or void |
| `CPE` / `CP0 CPB CPV` | sema | Comparison entry / outcomes |
| `SIF:0N-7N` / `SIF:FN` | sema | If-expr type unification |
| `SE` / `SWI:n SWI:p SWI:d` | sema | Switch expr entry / info |
| `P0: n` / `PL0:n` | sema | Switch with no payload / no prongs |
| `SWES:e` / `SWEU:e` | sema | Switch condition error-set / error-union |
| `Z` | sema | Switch enum/tagged-union condition |
| `PCT:C PCT:P` | sema | Prong context |
| `CC:K` | sema | Case kind |
| `SCE:p SCE:l SCE:R` | sema | Switch capture entry |
| `SCFE:n SCFE:t SCFE:k` / `SCAX:N SCAX:T` | sema | Switch capture field |
| `PBD:N PBD:K` / `PCT:n PCT:b PCT:f` | sema | Prong body details |
| `SWPB:i SWPB:t` | sema | Sw prong body type |
| `MIX:P MIX:U MIX:B MIX:tk MIX:uk MIX:cd MIX:b MIX:pf MIX:pn MIX:ni` | sema | Mixed prong types |
| `SWU:n SWU:t` | sema | Switch unified type |
| `eL\n EL:N EL:F EL:C EL:V EL:M` | sema | Enum literal entry |
| `ELV:N` | sema | Enum literal void |
| `ASE` / `AS0 AS1 AS2` | sema | Assign entry / outcomes |
| `RXS RXS:n` | sema | Switch in expr dispatch |
| `FAD:R` | sema | Field access result |
| `STX:n STX:k STX:r` | sema | Expression result |
| `A4:N A4:K A4:R` | sema | After-expr markers |
| `STB:N STB:R` | sema | Type table set |
| `AW:R` | sema | Array-init entry |
| `EBLK:N EBLK:C EBLK:S EBLK:D` | sema | Block-expr resolution |
| `ST:N ST:K` | sema | Unhandled node kind |
| `FB` | sema | Fn body entry |
| `RT:P RT:A RT:T RT:M` | sema | Fn param registration |
| `EVC:N EVC:C` | sema | Enum-value table count/cap |
| `SP:n SP:K` | sema | Stmt worklist pop |
| `BLK:N BLK:C` | sema | Block iteration |
| `BCK:B BCK:I BCK:N BCK:K` / `]\n` | sema | Block child push |
| `VD:N VD:C` | sema | Var decl |
| `D10:C0 D10:C1 D10:IK` | sema | Var-decl payload-55 debug |
| `VRT:<n>:<t>` | sema | Var resolved type |
| `I:K` | sema | Init node kind |
| `VDIAG:void_var` / `VFLOW:vdag` | sema | void-typed var diagnostic |
| `REG:cp REG:ct` | sema | Name cache register |
| `IFST:N IFST:C IFST:K IFST:2 IFST:K2` | sema | If-header details |
| `WST:N WST:K` | sema | While-header body kind |
| `FS:C FS:CK FS:T FS:P FS:E FS:M` | sema | For-header details |
| `D4F:N D4F:T` / `FIX2:LN` | sema | For capture / index registration |
| `ELS:n ELS:k ELS:c` | sema | Fallback stmt kind |
| `IXA:N` / `C0K:K` | sema | Index access entry / base kind |
| `STE:N` / `SRC:N SRC:S` | sema | Source trace entry / name |
| `IX:T IX:R` | sema | Index type result |
| `CC:nul` | coercion | classifyCoercion: null target |
| `CLS:p<base>e<elem>` | coercion | classifyCoercion: ptr-to-slice check |

---

## coercion.zig (`sf/src/coercion.zig`, 211 lines)

### CoercionKind enum (`sf/src/coercion.zig`)

| # | Variant | When |
|---|---------|------|
| 0 | `none` | No coercion needed / identity |
| 1 | `wrap_optional` | Source assignable to optional payload |
| 2 | `wrap_error_success` | Source assignable to error union payload |
| 3 | `wrap_error_err` | Source is error_set, target is error_union |
| 4 | `unwrap_optional` | optional → payload (orelse) |
| 5 | `array_to_slice` | [N]T → []T |
| 6 | `array_to_many_ptr` | [N]T → [*]T |
| 7 | `slice_to_many_ptr` | []T → [*]T |
| 8 | `string_to_slice` | [*c]u8 → []const u8 |
| 9 | `string_to_many_ptr` | [*c]u8 → [*c]u8 (identity) |
| 10 | `string_to_ptr` | [*c]u8 → *u8 |
| 11 | `ptr_to_optional_ptr` | *T → ?*T |
| 12 | `const_qualify` | T → const T (ptr/slice/many_ptr) |
| 13 | `int_widen` | Same-signedness, smaller → larger integer |
| 14 | `float_widen` | f32 → f64 |
| 15 | `int_literal_coerce` | Integer literal type → concrete numeric |
| 16 | `wrap_optional_null` | null → ?T (null → optional) |
| 17 | `tuple_to_tuple` | Named↔literal / shape-identical named tuple (FB) |
| 18 | `float_narrow` | Value-aware f64/integer → f32 (FX3; recorded by sema only — never returned by `classifyCoercion`) |

### classifyCoercion (`sf/src/coercion.zig`)

`[inference: type-kind dispatch on source/target for 20+ checks, return CoercionKind]`

Deterministic check order:

1. `source == target` → `none`
2. Source kind is `noreturn_type` or `undefined_type` → `none`
3. `integer_literal_type` + `isNumeric(target)` → `int_literal_coerce`
4. Both integer (source not `TYPE_INT_LIT`), same signedness, source width < target width → `int_widen`
5. `TYPE_F32` → `TYPE_F64` → `float_widen` (the reverse `f64`/integer → f32 narrowing is NEVER classified here — FX3 classifies it by VALUE in sema; a value-blind return would accept runtime values Zig rejects)
6. `null_type` (marker `CC:nul`): `isPointer(target)` → `none`; `optional_type` → `wrap_optional_null`; `fn_type` → `none`.
7. Target is `optional_type`: if source assignable to payload → `wrap_optional`; if source is null → `none`.
8. Target is `error_union_type`: if source assignable to payload → `wrap_error_success`.
9. Source is `error_set_type` and target is `error_union_type`: → `wrap_error_err`.
10. ptr→ptr (qualifier-monotone under `VOLATILE_FLAG`): if either base is VOID → `none`; if target is const, source is not, same base → `const_qualify`.
11. slice→slice: if target is const, source is not, same elem → `const_qualify`.
12. many_ptr→many_ptr: if target is const, source is not, same base → `const_qualify`.
13. array→slice: same elem → `array_to_slice` (const target variant too).
14. array→many_ptr: same elem → `array_to_many_ptr`.
15. array→array: same elem and same length → `none` (identity).
16. ptr→many_ptr: if the source pointee is an array and its elem matches the many-ptr base → `none` (array-to-pointer decay).
17. slice→many_ptr: same elem → `slice_to_many_ptr`.
18. ptr→optional: if the optional payload is a ptr and source is assignable → `ptr_to_optional_ptr`.
19. u8↔c_char: `none` (identity).
20. ptr→slice (marker `CLS:p<base>e<elem>`): only a pointer to a **known-length array** whose elem matches the slice elem decays → `array_to_slice`. A bare `*const u8`/`*const c_char` → slice is NOT a coercion (no length; must not become a length-1 slice).
21. Fallback → `none`.


### CoercionTable (`sf/src/coercion.zig`)

```zig
pub const CoercionTable = struct {
    entries_items: [*]CoercionEntry,
    entries_len: usize,
    entries_cap: usize,
    entries_alloc: *Sand,
    index: hash_mod.U32ToU32Map,  // node_idx → entry_idx
};
```

Flat array of `CoercionEntry{node_idx, kind, target_type}` + hash index by node_idx.

#### coercionTableInit

`[inference: zero-cap entries, empty index, allocator bound]`

Returns a fresh `CoercionTable` bound to the given `Sand` allocator.

#### coercionTableAdd

`[inference: upsert pattern — get-or-insert in index, update existing or append new entry]`

If node_idx already in index, update entry in-place. Otherwise ensure capacity, append, add to index.

#### coercionTableEnsureCapacity

`[inference: grow-by-doubling from 8, in-place realloc or memcpy, update cap]`

Internal grow helper for CoercionTable. Called by coercionTableAdd when entries_len >= entries_cap.

#### coercionTableGet

`[inference: index lookup → entry or null]`

Simple hash lookup. Returns `?CoercionEntry`.

---

## resolved_type_table.zig (`sf/src/resolved_type_table.zig`, 234 lines)

Maps AST nodes to their resolved types and source names. Used by semantic analysis and lowering. The type relation is now a **dense, block-addressed spill table** (Disk/Ram backend); the source relation is a small sparse resident hash map.

### ResolvedTypeTable (`sf/src/resolved_type_table.zig`)

```zig
pub const ResolvedTypeTable = struct {
    cap: usize,                  // logical node extent (file covers blocks up to aligned(cap))
    entries_alloc: *Sand,        // supplies the resident cache window + Ram buffer
    spill: spill_mod.SpillStore, // dense spill (Disk/Ram backend)
    spill_path: [512]u8,
    spill_path_len: usize,
    cache_buf: [*]u8,            // RTT_SLOTS * RTT_BLOCK_BYTES resident window
    cache_allocated: u8,
    slot_block: [8]u32,          // resident slot -> block index (EMPTY_BLOCK = empty)
    slot_dirty: [8]u8,           // write-back flag per resident slot
    ring_next: u32,              // next eviction candidate
    src_map: hash_mod.U32ToU32Map, // sparse resident node_idx -> source_name_id (only-on-Set)
};
```

The dense record is `{ type_id u32 @0, present u8 @4 }` = 5 B/node (the old inlined source half is gone). Block geometry constants: `RTT_BLOCK_NODES = 409`, `RTT_BLOCK_BYTES = 2045`, `RTT_REC_BYTES = 5`, `RTT_SLOTS = 8`. `file_byte_off = block * RTT_BLOCK_BYTES + (node_idx % RTT_BLOCK_NODES) * 5`.

### Lifecycle and accessors

- `resolvedTypeTableInit(alloc)` — zero-cap table; `spill_path` defaults to `.zig1_res.tmp`, all slots empty, `src_map` empty.
- `resolvedTypeTableSetSpillPath(self, path)` — override the spill filename.
- `resolvedTypeTableReserve(self, node_count)` — extend the dense extent (block-aligned zero-fill).
- `resolvedTypeTableSet(self, node_idx, type_id)` — fault the block into a resident slot, write the 5-byte record with `present=1`, mark the slot dirty.
- `resolvedTypeTableGet(self, node_idx) -> ?TypeId` — `null` if `node_idx >= cap` or `present==0`; otherwise the stored TypeId.
- `resolvedSourceTableSet(self, node_idx, source_name_id)` / `resolvedSourceTableGet(self, node_idx) -> ?u32` — the sparse `src_map`; used by `semanticAnalyzerResolveIndexAccess` to trace variable sources through var_decl → slice_expr chains.
- `resolvedTypeTableClose(self)` — write back dirty slots and close the spill.

Internally, `rttExtend` grows the block-aligned dense extent, `rttBlockEnsure` evicts/writes back the ring victim and faults a block into the resident window, and `rttWriteU32`/`rttReadU32` encode the little-endian record. A spill extent beyond `SEEK_MAX` panics via `panicHandler`.

---

## constraint_checker.zig (`sf/src/constraint_checker.zig`, 113 lines)

Three independent validation passes run after semantic analysis. `checkReturnType` is also re-run by the phase driver against each resolved return statement.

### checkReturnType (`sf/src/constraint_checker.zig`)

`[inference: if return_stmt with no child and fn returns non-void/noreturn → error; if return expr not assignable → error]`

Two checks:
- `child_0 == 0` (bare return): if `current_fn_return` is non-void and non-noreturn → `ERR_3003` "return with no value in function returning non-void".
- `child_0 != 0`: if `return_expr_type != 0` and not assignable to `current_fn_return` → error "return type mismatch" (generic code 0).

### ~~checkSwitchExhaust~~ (DELETED by FA-a, 2026-09-26)

The dead `constraint_checker.checkSwitchExhaust` (old `ERR_3004_SWITCH_NOT_EXHAUSTIVE`, tests-only caller, scalar conditions exempt) is deleted together with its two `test_semantic_bin.zig` callers. The switch exhaustiveness/`else` rule now lives in `semanticAnalyzerResolveSwitchExpr` as the mandatory-`else` gate: `has_else == 0` → level-0 `error[3068]` `ERR_3068_SWITCH_WITHOUT_ELSE` (`switch must have an 'else' prong`), deduped per node, value AND statement position.

### constraintCheckerCheckBreakContinue (`sf/src/constraint_checker.zig`)

`[inference: DFS stack with depth tracking — break/continue at depth 0 → error]`

Explicit-stack iterative traversal (avoiding recursion depth limits). Each stack entry pairs `(node_idx, depth)`. Deeper `while_stmt`/`for_stmt` increments depth. If `break_stmt`/`continue_stmt` at depth == 0 → error "break/continue outside loop" (generic code 0). Pushes `child_0`–`child_2` and the node's extra children with the current depth.

---

## assign_helper.zig (`sf/src/assign_helper.zig`, 5 lines)

A single small helper shared with lowering: `resolveAssignedLocalTemp(lt_ptr, ln_ptr, count, temp_id)` reverse-scans the parallel local-type/local-name arrays (`count` entries) and returns the local name id whose type id equals `temp_id`, or `0` if none matches. It lets the lowerer recover a source variable name for a temp that was assigned from a local.

---

## Data Flow

```
semanticAnalyzerResolveFnBody(decl)
  │
  ├─ Resolve params: local_decl_names/types[] += param types from RTT
  ├─ Set current_fn_return
  │
  └─ semanticAnalyzerResolveStmt(body)
       │
       └─ semanticAnalyzerResolveStmtIter(root_node)
            │
            ├─ Worklist: push children in reverse order
            │
            ├─ For each stmt/expr node:
            │   │
            │   ├─ semanticAnalyzerResolveExpr(node) → TypeId
            │   │   │
            │   │   ├─ pushExpectedType / popExpectedType (contextual hints)
            │   │   ├─ resolve child exprs recursively
            │   │   ├─ resolvedTypeTableSet(node_idx, result)  ──┐
            │   │   ├─ tryRecordCoercion(node, src, dst)         │
            │   │   │   └─ coercionTableAdd(node, kind, dst)  ───┤
            │   │   └─ return TypeId                             │
            │   │                                                │
            │   └─ ResolvedTypeTable ────────────────────────────┤
            │        node_idx → TypeId                           │
            │        node_idx → source_name_id (index access)    │
            │                                                    │
            └─ After all stmts exhausted:                        │
                                                                    │
                    CoercionTable ────────────────────────────────┤
                      node_idx → {kind, target_type}               │
                                                                    │
                    ↓ constraint checks                             │
                    checkReturnType                                 │
                    constraintCheckerCheckBreakContinue              │
                                                                    │
                    ↓ Ready for lowering (phase 7)                  │
                    Each expression node has either:                │
                    - resolvedTypeTableGet(node) → TypeId           │
                    - coercionTableGet(node) → CoercionEntry        │
                    - or no entry (identity type)                   │
```

---

## Debugging

### Key Markers for Tracing

**Expression resolution tracing:**
- `STX:n<i> STX:k<k> STX:r<r>` — every resolved expr with node index, AstKind, result TypeId
- `A4:N A4:K A4:R` — same, emitted just after resolve, before RTT set
- `STB:N STB:R` — confirmation of RTT set

**Field access tracing:**
- `FAE\n PFA:BK<bk> PFA:FN<fn>` — entry with base kind and field name
- `FF:R<r>` — field found, returning type id
- `NF\n FF2:N<idx> FF2:F<name> FF2:B<base>` — field not found

**Fn call tracing:**
- `FNE\n` — entry
- `FN1\n FN1:R<r>` — direct call with resolved return
- `FN4a-FN4g` — param-by-param resolution with `PTM:A<T>M:T<T>M:N`

**Switch tracing:**
- `SE\n SWI:n<idx> SWI:p<payload>` — entry
- `PCT:C<cond_tu> PCT:P<prong_payload>` — per-prong context
- `SWPB:i<idx> SWPB:t<type>` — per-prong body resolved type
- `SWU:n<idx> SWU:t<unified>` — final switch type

**Variable declaration tracing:**
- `VD:N<name> VD:C<count>` — var decl start
- `VRT:<node>:<type>` — resolved type annotation
- `IK:K<kind>` — init node kind
- `REG:cp<name> REG:ct<type>` — name cache put

### Expected-Type Stack Inspection

The expected-type stack is a dynamic array on the scratch arena. To inspect at runtime:
- `self.expected_type_stack_items[self.expected_type_stack_len - 1]` — current top
- `self.expected_type_stack_len` — current depth

Breakpoints for stack state:
- `pushExpectedType` in `semantic_analyzer.zig` — watch `ty` parameter
- `popExpectedType` in `semantic_analyzer.zig` — watch `self.expected_type_stack_len` decrement

Use cases for expected-type stack:
- Error literals: expected type provides error set context
- Enum literals: expected type provides tagged union context
- Fn call args: expected type = param type
- Return stmts: expected type = fn return type
- Assignments: expected type = lhs type
- Struct init: expected type = field type per field

### GDB Breakpoints

```gdb
# Entry to semantic analysis for a module
break semanticAnalyzerResolveFnBody

# Every expression resolution
break semanticAnalyzerResolveExpr

# Every coercion insertion
break tryRecordCoercion

# Expected-type stack operations
break pushExpectedType
break popExpectedType

# Identifier resolution
break semanticAnalyzerResolveIdent

# Field access
break semanticAnalyzerResolveFieldAccess

# Switch expression (complex unification)
break semanticAnalyzerResolveSwitchExpr

# Return statement with coercion
break resolveReturnStmt

# Variable declaration type checking
break semanticAnalyzerResolveStmtIter

# Constraint checks
break checkReturnType
break constraintCheckerCheckBreakContinue
```

### Print commands for debugging

```gdb
# Print current fn return type
print self.current_fn_return

# Print expected type stack top
print self.expected_type_stack_items[self.expected_type_stack_len - 1]

# Print local decls count
print self.local_decl_count

# Print switch context
print self.current_switch_cond_tu

# Print coercion table entry for a node
print coercionTableGet(self.coercion_table, node_idx)
```
