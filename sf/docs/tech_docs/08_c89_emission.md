# 08 — C89 Emission [updated: 2026-10-12 — P6 (emitter sanitization: lowerer carries decisions, Decision-vs-spelling; the emitter SPELLS only): the named emit-time semantic re-derivations are removed. (1) `resolveFieldAccess` no longer re-resolves `fe_items` by ordinal — the field identity is the lowering-recorded `field_name_id`/`field_type_id` on `load_field`/`store_field`/`assign_field`/`addr_of_field` (filled at the `lower.zig` construction funnel by `lowerFieldRecord`), consumed by the designator spelling (the `name_out`/`fld_tid_out` outputs are gone; `emitFieldAssign`/`dceFieldIsArray` read the recorded field type; the base-kind/mode-bit spelling policy is unchanged). (2) `findCalleeFnTypeId` is DELETED — the callee fn type id is recorded on `CallDirectData`/`TailCallData.fn_type_id` by `lower.zig` `lowerCalleeFnTypeId` (the same name/module/convention resolution, at the owning phase). (3) `getTemp*`/`hoisted*` re-derivation is gone: `getTempEffType` loses its `d4_wtype` written-type write-scan fallback and `getTempTypeInfo` (the cross-temp result→lhs→rhs chain + ICE) is deleted; the temp result types are the recorded `TempDecl.type_id` facts, read purely by `getTempTypeByIndex`/`hoistedTypeOf*`. (4) Saturation/wrap semantics are carried on the `binary` inst (`result_type`/`width`/`is_signed`, Amendment 5 ruling 2, A15 pattern — recorded at lowering via P5 predicates by `lowerRecordFacts`/`lowerBinSemType`); the `.binary` `op >= 16` arm and the nest mirrors (`nestEmitBinExpr`/`emitUnaryRvalue`) consume the carried/recorded types and `emitSatBinary` spells ONLY from them (its `typeRegistryIntWidthBits` derivation is deleted). `async_state_machine.zig` `remapInst` copies every new record field (Amendment 5 ruling 1a, copier-only, `int_const`-facts precedent).] [updated: 2026-10-12 — combined fix (P6-pre-f3+P12-f1) H2 (every `sorted` walker bounded on the sort SNAPSHOT; the P2/P12 deferred follow-up "bound on snapshot length" is TAKEN — this SUPERSEDES the P12 entry's "Walk bounds untouched" note): `C89SpellPlan` gains `typedef_order_len: usize` (set to `reg.types_len` at plan time in `spellPlanPlanTypeOrder` — exactly the count `tstTopologicalSort` covers at snapshot; init 0 in `spellPlanInit`). The 4 `sorted[tsi]` walkers — `emitTypePasses`'s 3 loops (Pass 1 forward typedefs / Sub-pass 2a pointer-only / Sub-pass 2b value-embedding) and `emitModuleHeaderFile`'s module header walk — now bound on `emitter.plan.typedef_order_len` instead of live `types_len`; the old live-`types_len` over-read into the sort's own `queue` buffer is structurally impossible. Not in scope (NOT `sorted` walkers, unchanged): `emitNeededTupleTypes`'s `needed_tuple_set` membership walk and the `ts_ref_set` walk. Expected behavior delta ZERO (battery proves: corpus class file byte-identical, pins 0/8, goldens 5/5 — the multi-module dumps exercise the header walk incl. post-snapshot synthetic types).] [updated: 2026-10-12 — P12 (emitter sanitization: typedef ordering planning): the typedef emission order is planned ONCE at the pre-emit `phase_EmissionClassification` boundary — `tstTopologicalSort` (with the P2 popped/append cycle-residue derivation) moves verbatim from this file to `c89_plan.zig`, filled into `C89SpellPlan.typedef_order` by `spellPlanPlanTypeOrder`; both former emit-time sort call sites (`emitModule`, the multi-file `phase_C89Emission` region) read the carried order — zero sort calls remain in the emitter or mid-emission. Walk bounds untouched (`tsi < types_len`); post-snapshot appended-type handling byte-identical (P2 deferred minor unchanged). Pins 0/8.] [updated: 2026-10-12 — P6-pre fix round 1 (fact-carrier route; the carrier is read from the plan where the temp type used to be read): Class B temps become `TYPE_INT_LIT`, so two const-spelling sites now read the planned carrier where they previously read the carrier-typed temp. `C89Emitter` gains `d4_fcar` (fact-carrier table, beside `d4_wtype`/`d4_wflag`/`d4_t2p`; init 0xFFFFFFFF), filled in the written-type walk's `.int_const` arm ONLY for fact-carryed materializations (`ic.width_bits != 0` + `TYPE_INT_LIT` hoisted — Class A (0,0) and typed consts leave the sentinel). `factCarrierOfTemp` (bounds-checked `d4_t2p`/`d4_fcar` read) is consumed by `nestScalarEffTid` (after the kind-whitelist attempt: a fact-carryed materialization is a scalar of its planned carrier — `nestEffCType`/`emitNestCompute` byte-identical `printI64((zT_i64)((zT_i64)-3000000000LL))` shapes; Class A keeps the historical 0xFFFFFFFF non-inlinable `zT_8 = 5000000000ULL;` statement shape) and by the `.print_val` scalar route (`route_tid` = the planned carrier for fact-carryed materializations; Class A keeps `printFnSourceName`'s 32/signed fallback; typed args unchanged). The three side-table reads (`planConstCarrierAt` written-type walk / `nestEmitDefRvalue` / `emitInst`) and `writeIntConstRvalue`/`intLitSuffix*` are unchanged. Table-completeness note (O3, keep for P12): `lirOptRun` running inside `emitFunctionSet` (post-boundary) is what makes the boundary see pre-opt LIR; the I.2 population proof (in-place rewrites, fold gate `intKindWidth != 0`, retarget `dt == st`) is what makes the side table complete without moving the opt. If a future opt rewrite ever inserts/inst-moves instructions or relaxes those gates, the table must be re-evaluated (P12's move of related machinery should keep this invariant in mind). Pins 0/8, hop1==hop2.] [updated: 2026-10-12 — P6-pre (emitter sanitization: C89 spelling planner, carrier derivation): the emit-time carrier deciding helper `intConstTypeForValue` is DELETED — the i32/u32/i64/u64 carrier derivation is owned by `sf/src/c89_plan.zig` (`deriveConstCarrier`, same rule) and recorded as `C89SpellPlan` side-table state (const-id → carrier) at the pre-emit `phase_EmissionClassification` boundary. `C89Emitter` gains `plan: *c89_plan.C89SpellPlan` + `plan_fn_key` (the current fn's LIR spill slot offset, set at fn entry in `emitFunctionSet`); the three former consumption sites (written-type inference, `nestEmitDefRvalue`, `emitInst` `.int_const`) read the plan via `planConstCarrierAt` (spell-time READ — Decision-vs-spelling: the emitter spells the carried carrier, never derives; `writeIntConstRvalue`/`intLitSuffix*` stay spelling). Pins 0/8, hop1==hop2.] [updated: 2026-10-12 — P4 fix round 2 (placement correction, Decision-vs-spelling): the emitter is now PURE spelling for classification — `C89Emitter` holds `classif: *type_resolver.EmissionClassification` (the four group maps owned by `CompilerContext`, filled at the pre-emit `phase_EmissionClassification` boundary) and READS only. The `emitTypePasses`-invoked `classifyTypeEmissionFinalize` call is DELETED (`emitTypePasses` retains ZERO classification calls); `collectNeededTuples` moved out of this file into `type_resolver.zig`; the four map fields and the `c89EmitterInit` map parameters are replaced by the single `classif` pointer (all reads rewired `emitter.classif.*`). Zero decision-logic change: dump pins 0/8, hop1==hop2.] [updated: 2026-10-12 — P4 (emitter sanitization: single classification pass, operator amendment option (a) — extend + re-time): the emitter's type classification is DELETED — `computeSharedSet` and `shouldSkipTypeEmission` (and the per-pass `skip_arb` local) are gone; the emitter CONSUMES the resolver's single classification (doc 03): `c89EmitterInit` now takes the three group maps (`pointer_only_map`/`needs_def_map`/`shared_set`) fully populated from `classifyTypeEmissionGroups`'s `ClassificationResult` (the former `ptr_only_ids`/`pointer_only_len` args and both id→map fill loops are deleted), `emitTypePasses` consults `needs_def_map` where it called `shouldSkipTypeEmission` (same filter positions; the E10 `skip_arb` arm was unreachable-equivalent), and `emitTypePasses` opens with the resolver's emission-time finalize `type_resolver.classifyTypeEmissionFinalize(reg, shared_set, pointer_only_map, needs_def_map, needed_tuple_set)` — step 2 of the SAME mechanism (doc 03), covering the E4 needed-tuple shared seed and types registered after the classification snapshot (the old functions evaluated their rules LIVE at emission; the po-map fallthrough — absent = value-embedding — is preserved). Spec §4 "Type classification" row AMENDED (operator, 2026-10-12; recorded doc 03 + P4 report; closeout will note it). Emission byte-identical: dump pins 0/8, hop1==hop2.] [updated: 2026-10-12 — P3 (emitter sanitization: canonical `typeCName`, D2 residue CLOSED): the C-type-name derivation moves OUT of the emitter — `type_registry.typeCName` (doc 03) is THE one derivation (verbatim relocation of the old `getCTypeName` body incl. the synthetic `Arr_`/`Tup_`/`Slice_`/`Opt_`/`EU_`/`FS_`/`FP_`/`FN_`/`ES_` compositions and F2's `sliceElementName` rule), synthetic names minted ONCE through the P1 `name_mangler.zig` authority, and the `c_name_map` memo is owned by the derivation (the `emitErrorUnionType` write-back is REMOVED; the emitter is a pure reader). `getCTypeName` is a thin consumer wrapper; every declaration site (`emitStructType`/`emitUnionType`/`emitTaggedUnionType`/`emitEnumType`/the FX14 carriers) and the former duplicated mints (`emitArrayType`'s local `Arr_` mint, `emitOptionalType`'s local `Opt_` mint) consume it, so decl and use cannot drift. All spellings byte-identical (dump pins 0/8; hop1==hop2). See §1.5.] [updated: 2026-10-12 — P2 (emitter sanitization: type-reference relation + ordering, D8 root cause CLOSED): the typedef-ordering edge set now derives from the SINGLE relation `type_registry.typeRefs`/`typeNeedsFullDef`/`typeRefsContains` (doc 03) — `tstTopologicalSort` takes its indegree from `typeRefs` and its decrements from `typeRefsContains`, and `computeSharedSet`'s closure probes `typeRefsContains`. DELETED: `c89NeedsEmitEdge`, `tstEdgesWalk`, `tstSeenInRange`, `tstEdgesCount`, `tstEdgesFill`, `tstIsDep` (the divergent hand-rolled edge machinery). The relation covers ALL kinds incl. `fn_type` return/param refs (D8: a fn-ptr typedef now follows its return typedef — the D8 reproducer's `zig_special_types.h` inverts the old fnptr-before-EU order), `packed_union`, and pointer chain-leaf name refs (a `*fn` struct field's C type IS the fn typedef name). See §1.1.] [updated: 2026-10-12 — P1 (emitter sanitization: identifier authority): `sf/src/name_mangler.zig` is REVIVED as the single C-identifier minting authority (keyword escape + collision resolution + stable per-kind names). The emitter-internal `NameMangler` struct and all ad-hoc mint helpers (`writeHex`, `isTempOrBuiltin`, `isC89Keyword`, `mangleC89Keyword`, `cUnionMemberName`, `nameManglerPopulateKeywords`, `nameManglerInit`, `nameManglerMangle`, `nameManglerMangleGlobal`, `syntheticTypeName`, `mangleLocalName`, `mangleTempName`, `typeIdName`, `aggPackedScratchName`, and `moduleQualifiedName`'s stem rule) MOVE to `name_mangler.zig`; `c89_emit.zig` keeps only 4 thin `pub` forwarders (`NameMangler`, `nameManglerInit`, `nameManglerMangle`, `nameManglerMangleGlobal`) as its external compatibility surface (main.zig emission phase + `tests/test_name_mangle_bin.zig`) and calls `nm_mod.*` at every mint site. New per-kind mints: `nameManglerMintLocal`/`MintField`/`MintMember` (raw-name rule: source name byte-identical, C keyword -> `z_<name>`, per-scope collision -> `_N`), `nameManglerMintTemp` (`zT_<id>`), `nameManglerMintSyntheticType` (3-part synthetic rule), `nameManglerMintIndexName` (prefix+decimal; printer/table/scratch), `nameManglerMintModuleStem` (`<stem>_<fnv1a-hex>`), `nameManglerFnScope` (per-function scope key for local collision maps). D1 root cause closed incl. **struct fields** (decl + all access arms + printer `v.<f>` access; display labels keep the raw source name so `.{ .int = 7 }` prints unchanged); union members keep the F1 `z_` escape and gain collision resolution. Self-emission names byte-identical (pins 0/8; `hop1==hop2` holds). See §1.3/§3.] [updated: 2026-10-12 — P5 (emitter sanitization: predicates + promotion centralized): the emitter's private int-kind/signedness/width/scalar/pointer truth tables (`intKindIsSignedBase`, `intKindIsUnsignedBase`, `intKindWidthBytes`, `classifyIntSignedness`, `intTypeNeedsWidthWrap`, `intTypeByteWidth`, `typeIsIntKind`, `retTypeIsScalarC`, `typeIsPtrKind`) are DELETED — canonical predicates now live in `type_registry.zig` (doc 03) with every emitter call site rewired (per-caller membership extras verbatim), and `emitBinRvalueText` delegates mixed-sign C usual-arithmetic promotion to `coercion.zig` `coercionUsualArithPromote` (doc 05), keeping only `getTempEffType`/`getCTypeName` glue. See §1.15 note.] [updated: 2026-10-10 — D5/F6 (`-fsafe` root-index bounds check RESTORED, task F6): the D5 address-taking path (`lowerAssignLValue` `sf/src/lower.zig:2507`, `lowerLValueAddr` `:2202`) bypassed the by-value element read that carried the `-fsafe` bounds check, so the chain ROOT index `i` of `s[i].field[j] = x` / `a[i].field[j] = x` was not trapped when out-of-range. `lowerLValueAddr` gained a `safe_check: u8` parameter; its `index_access` arm emits `emitSafeCheckIndex(lv_ix_base, lv_node.child_0, idx_temp)` (`:2235`) when set, and only the D5 call site passes `1` (`:2507`); every other address-of caller passes `0`, so their C is byte-identical and `-ffast` is unchanged (helper early-returns when `!safe_checks`). Repro `repro/mi_matrix/slice_index_field_store_oob_xmod/` traps rc 133 under `-fsafe` (pre-fix rc 0); in-bounds D5 repro still `9\n11\n22\nslice_index_field_store ok\n`; corpus `1121 = 947/58/116/0/0` (FAIL unchanged; +1 OK = new repro); stdlib 283/0; example matrix 25/25; runtime goldens gol/lisp/json/mud+client byte-identical; all 8 dump-MD5 pins unchanged. See §1.13.] [updated: 2026-10-09 — D5-F5 (lost store through a slice-index aggregate lvalue FIXED, task F5): `lowerAssignLValue`'s `index_access` arm (`sf/src/lower.zig:2484`) now takes an ARRAY-typed aggregate l-value chain by ADDRESS before the value path — when the base is a `field_access`/`index_access`/`deref`/`paren_expr` whose chain roots at an `index_access` (new helpers `d5BaseChainHasIndex`/`d5IndexAssignArrayType`, `sf/src/lower.zig:2564`/`:2612`), `lowerLValueAddr` forms `&elem->field` once and `assign_index` emits `(*zT)[j] = src;`, so `s[i].field[j] = x` / `a[i].field[j] = x` write into the element instead of a by-value copy. An array field's resolved type decays to a bare element pointer, so the declared array type is recovered from the container's field table (mirroring `fieldStaticLenForBase`). Slice/pointer bases and local-aggregate field bases keep the value path byte-identically. Repro `repro/mi_matrix/slice_index_field_store_xmod/` prints `9\n11\n22\nslice_index_field_store ok\n`; corpus `1120 = 946/58/116`; stdlib 283/0; 8 dump-MD5 pins unchanged; z9torr tiers PASS and the sent handshake carries the real `-Z9T01-…` peer_id. See §1.13.] [updated: 2026-10-09 — D2-F2 (slice-of-synthetic element typedef FIXED, task F2): new helper `sliceElementName` (`sf/src/c89_emit.zig:931`) computes a slice element's C name — recursion `getCTypeName(elem)` when the element is synthetic (`name_id == 0`: slice/array/pointer/optional/tuple/error-union), else the exact `nameManglerMangle(elem.name_id, 2, 0)` — so `[][]const u8`, `[][20]u8`, `[][*]u8`, `[]?T`, `[]tuple` each get a distinct `Slice_…` typedef. Both `getCTypeName`'s slice branch and `emitSliceType` use the helper (`emitSliceType` now takes its typedef name from `getCTypeName(tid)`, so decl and use cannot drift). Primitive/named element slices (`[]u8`→`Slice_zT_0B42B2F8_u`, `[]i32`, `[]Struct`) are byte-identical. Repros `repro/mi_matrix/slice_of_slice_xmod/` + `repro/mi_matrix/slice_of_array_xmod/` are warning-free (no `-Wincompatible-pointer-types`) and green (both print `11`). The 8 dump-MD5 pins move because the gate dumps include the std modules, which define synthetic-element slices (e.g. `[][]const u8` in `sf/src/std_str.zig` `split`/`splitLines`/`join` and `sf/src/std_sort.zig` `StrBox`/`sortStr`, pulled in by every `@import("std")`); runtime goldens gol/lisp/json/mud are byte-identical. Re-baseline of the dump pins requires operator authorization (spec §6.1). See §1.5.] [updated: 2026-10-09 — D1-F1 (union-member C-keyword tag FIXED, task F1): new shared helper `cUnionMemberName` (`sf/src/c89_emit.zig:594`) returns the interned C union-member name — the existing `z_` C-keyword escape (`mangleC89Keyword`) for C-keyword names, every non-keyword name byte-identical — applied at the tagged-union declaration (`emitTaggedUnionType`) and payload access (`emitVariantFieldPayload`) plus the bare-union declaration (`emitUnionType`), its union access arms in `resolveFieldAccess` (struct fields untouched), and the generated aggregate printer (`emitAggPrinterDef` tagged-union arm — mangled payload designator, raw tag kept as the print label). `union(enum){ int: i64 }` now emits `.payload.z_int._0` consistently; repro `repro/mi_matrix/union_keyword_tag_xmod/` (now also printing the keyword-tagged union) compile+link+run green; corpus FAIL 118→117; all 8 dump-MD5 pins unchanged (D1-neutral). See §1.7.] [updated: 2026-10-09 — D5-I5 (lost store through a slice-index aggregate lvalue, task I5): `lowerAssignLValue`'s `index_access` arm (`sf/src/lower.zig:2484-2531`) lowers its base by **value** (`:2487` `lowerExpr(indexBaseAfterArrayDeref(...))`); only the tuple sub-case (`:2493-2508`) takes an address, so `s[i].field[j] = x` materialises the element struct into a temp and the emitter stores into the copy (`emitBaseIdxAccess` `sf/src/c89_emit.zig:204-267`, `assign_index` `:7226-7271`; emitted `zT = s.ptr[i]; p = zT.field; p[j] = x;`). In Zig the chain is an lvalue and must write through `&s[i].field[j]`, so the write is silently lost at runtime. Compile-only classify is OK, so the gate is the runtime repro `repro/mi_matrix/slice_index_field_store_xmod/` (pre-fix prints the pre-store value; expected `9\n11\n22\nslice_index_field_store ok\n`, pre-fix `9\n0\n0\nslice_index_field_store FAIL\n`). Correct sibling `lowerFieldStore` (`:2878-2928`) takes nested bases by address. Fix (task F5, planned): route non-tuple index-assign bases through `lowerLValueAddr` exactly as `lowerFieldStore`. See §1.13.] [updated: 2026-10-09 — D2-I2 (slice-of-synthetic-element typedef collapse, task I2): `getCTypeName`'s slice branch (`sf/src/c89_emit.zig:1028-1036`) derives the slice typedef's element name from the element type's `name_id` (`:1031` `nameManglerMangle(mangler, elem_ty2.name_id, 2, 0)`); every *synthetic* element (slice/array/pointer/optional/tuple) has `name_id == 0`, so `[][]const u8` and `[][20]u8` both mangle to the empty-name string `zT_811C9DC5_` and collapse to one `typedef struct { …* ptr; unsigned int len; } zT_9DFA8D74_Slice_zT_811C9DC5_;` (whichever synthetic element is registered first wins). gcc compiles it with `-Wincompatible-pointer-types`; the value is correct only by luck of the hoisted temp. The array branch (`:959-967`; `emitArrayType` `:2116-2137`) already recurses `getCTypeName(reg, mangler, ap.elem)` and the tuple branch (`:972-979`) already uses the dense type id (`Tup_<tid>`); optional/error-set use their payload idx. Fix (task F2, planned): recurse for synthetic (`name_id == 0`) slice elements (or reuse `syntheticTypeName` `:882` with the dense type id), keeping primitive/named element slices byte-identical. Repros `repro/mi_matrix/slice_of_slice_xmod/` + `repro/mi_matrix/slice_of_array_xmod/`. See §1.5.] [updated: 2026-10-09 — D1-I1 (union-member C-keyword tag, task I1): `emitTaggedUnionType` (`:1921`) writes each `union(enum)` variant's `fe.name_id` verbatim as the C union member (`:2013` read → `:2020` write) and `emitVariantFieldPayload` (`:419`; via `resolveFieldAccess` `:499`) writes it verbatim into the payload designator `.payload.<name>._<sub>` (`:435` read → `:436` write). A legal Zig tag that is a C keyword (`int`, `long`, `switch`, …) therefore emits invalid C89 — `struct { long long _0; } int;` / `v.payload.int._0` → gcc `expected identifier before 'int'`; `@"int"` is rejected by Z98 (`error[4]`). Tag constants (`zTU_<base>_<member>`) and switch dispatch are already safe. Fix (task F1, planned): C-keyword-mangle the member name consistently at both write sites (or emit stable non-keyword member names). Repro `repro/mi_matrix/union_keyword_tag_xmod/`. See §1.7.] [updated: 2026-10-04 — A2-F (Volume IV Amendment A2): `emitStructType` emits `\tunsigned char _[1];\n` as the body of an empty non-packed struct (`fields_count == 0`), so the emitted C `sizeof`/offsets match the registry's min-1 size 1 / align 1 (previously `struct {}` either aliased a foreign payload or produced an empty C struct). See §1.7.] [updated: 2026-09-29 — FX16-F (Volume II ch7 amendment, adjacent pointer `.tag` store): the `store_field` pointer-base arm gains a `tagged_union_type` pointee case — `p.tag = v` on a `*union(enum)` base now renders `p->tag = v;` (mirroring the ptr→struct/union/tuple arms) instead of falling to the `error[3043] internal: store_field unresolved field` ICE. Only `TU_FIELD_TAG` is handled; `p.payload = …` stays the pre-existing ICE (payload-member stores reject in lowering, doc 07). No existing program has the shape (it ICEd), so the 4-MD5 pins are unchanged.] [updated: 2026-09-29 — FX14-F (Volume II layout-model pin, operator ruling A): the frozen 32-bit layout model (i64/u64/f64 size 8 align 8) is now pinned in the emitted C. `emitInt64Type`/`emitUint64Type` append ` Z98_ALIGN8` to their carrier typedefs, a new `emitF64Type` emits the f64 carrier `typedef double <cname> Z98_ALIGN8;` (previously `getCTypeName` returned bare `"double"`), and `getCTypeName`/the f64 pointee fast path, `ctypeGuardWrite` (`ZIG_F64_`), `computeSharedSet`, `emitPointeeDep` and `emitTypeDefinition` gained the f64 arm. `Z98_ALIGN8` lives in `zig_compat.h` (canonical `sf/src/include/zig_compat.h` + hand-written bytes in `emit_support.zig`): `__attribute__((aligned(8)))` on gcc/clang/mingw, empty on MSVC/Watcom (whose 32-bit defaults `/Zp8`/`-zp8` already align 64-bit scalars to 8); the shared `z64`/`zu64`/`f64` typedefs carry it too. Every declaration funnels through `getCTypeName`, so structs, unions, tagged unions, optionals, error unions, tuples, arrays and standalone vars all inherit the model alignment; a `-zp4`/`/Zp4` packing override breaks the pin and is documented as unsupported. The stale unused `c89_emit.emitZigCompatH` duplicate was deleted. Fixtures `repro/mi_matrix/stdlib_layout_align8_xmod` + `repro/layout_align8.z98`. See §1.5/§1.7.] [updated: 2026-09-25 — Task 9 fix round 3 (z98-print-formatting Amendment 1, B5; operator ruling Q7): `emitModuleInitCalls` now iterates `C89Emitter.module_init_order`/`module_init_order_len` — the stable dependency-ordered module list computed by `computeModuleInitOrder` (doc 09) — instead of the raw module-registry order, so a module whose global initializers read another module's globals has its `__module_init` called after that module's. The reachable-prune and `moduleHasRuntimeInit` filters are unchanged, and a program without cross-module global dependencies keeps its exact previous call sequence.] [updated: 2026-09-25 — Task 8 (z98-print-formatting Amendment 1, B2 + B3): one pointer-chain depth cap of 16 — `emitPointeeDep`'s dependency walk bail moves from `depth > 8` to `depth > 16`, matching `zigPrintNameAppend` and the validator (`lower.zig printFmtPointeeNameOk`/`printFmtAggFieldsOk`), so a validator-accepted chain (up to 14 wrappers in a field's pointee alias / 15 in a print argument) emits every wrapper typedef before use instead of gcc `unknown type name` at rc=0. `emitPtrValuePrint`'s name-append failure is now a `@panic` backstop (was a silent no-op that dropped the value); the validator mirrors the 512-byte name budget exactly, so an over-budget name is a clean `error[3063]`. See §1.20 and doc 07.] [updated: 2026-09-25 — final whole-branch review fix wave (Finding 1): an untyped integer `print` argument is materialised by lowering into its value-chosen carrier (i32/u32/i64/u64; `lowerPrintArgExact`), so `printFnSourceName`'s `integer_literal` arm is only the non-folded fallback (e.g. builtin results) and big untyped literals no longer print truncated/re-interpreted values. Finding 2 / operator ruling R11 recorded: a recursive or mutually recursive aggregate rejects `error[3063]`; `emitAggPrinterRec`'s `emitted`/`visiting` guard terminates cycles, but its printers are emitted post-order with no forward declarations, so a mutual `A -> B -> A` cycle would reference a not-yet-defined printer (gcc error) and relaxing the validator first needs forward declarations.] [updated: 2026-09-25 — Task 6 (z98-print-formatting): pointer/fn-pointer `{}` prints Zig 0.15.2's `T@<lowercase-hex>` (NO `0x`; operator ruling R3) or delegates to the pointee printer (`*struct`/`*union`/`*tagged`/`*packed`/`*tuple` → the Task-4 generated printer, `*enum` → the Task-5 name printer, everything else the address form). The address form is emitted inline — `std_print("<@typeName(child)>@")` + the EXISTING std.fmt `printHexU64` — and the child name is rendered by the new `zigPrintNameAppend` for the exact Z98-expressible space (ints/floats/bool/void/`c_char`/arb/pointers/many/slices/arrays/optionals/error-unions/error-sets/fn); named struct/enum/union components reject `error[3063]` (Zig container-qualifies them — bounded residual). Float `{x}` prints a hand-rolled C89 hex-float (`0x1.8p0`, `Writer.zig:1572-1720`) through compiler-generated static helpers `z98_printFloatHex32/64` (emitted on demand — adding a std_fmt function would move the 4-MD5 pins). The Task-4 closure is extended for pointer/fn-pointer fields (Zig's `{any}` field pointer route); type-dependency emission (`emitTypeDefOnce`/`emitTypeDeps`/`emitPointeeDep`/`emitDepMember`) fixes the pre-existing "typedef used before emitted" ordering for a pointer member's pointee typedef (fn-pointer/enum/error-set/optional/slice/array/packed), and `c89NeedsEmitEdge` now treats `fn_type` as a value-embedding dependency edge. See §1.20.] [updated: 2026-09-25 — Task 5 (z98-print-formatting): `.print_val` on an enum (bare `{}`) calls the compiler-generated `z98_printEnum_<tid>` and on an error set uses `z98_printErrorSet_<tid>`; each carries a static name table (`z98_etab_` name blob + `z98_eoff_`/`z98_elen_` byte offset/length arrays + `z98_eval_` member values / `z98_escode_` global codes) and writes the name through the EXISTING std.fmt `printStr` (std_fmt.zig stays untouched so the 4-MD5 dumps keep their pinned bytes). See §1.19.] [updated: 2026-09-25 — Task 4 (z98-print-formatting): `.print_val` on struct/union/tagged-union/packed-union/tuple calls a compiler-generated per-type static printer (`z98_printStruct_<tid>`, ...) that emits Zig 0.15.2's `. { .a = 1 }` / `.{ 1, 2, 3 }` form with `std.fmt.default_max_depth = 3`; tuple types gain a `Tup_<tid>` C model (`typedef struct { _0, _1, ... }`), emitted only for `needed_tuple_set` (runtime hoisted temps/globals) so registry-only print-args tuples keep the 4-MD5 dumps byte-identical. See §1.18.] [updated: 2026-09-25 — Task 2 (z98-print-formatting): `printFnSourceName` is a width/signedness dispatcher (`printKindIsIntegerLike` + `typeRegistryIntWidthBits`/`IsSigned`; ≤32 → U32/I32, 33..64 → U64/I64, `{x}` → the matching `printHex*`; Z98 `usize` is 32-bit unsigned; `integer_literal` is the 32-bit signed fallback) and `std.fmt`'s `printHexI32/I64` print `-` + hex magnitude for negative values; `pal_f64_to_str` omits the `.`+fraction for an integral float. Fixture `stdlib_print_dispatch_xmod`.][updated: 2026-09-24 — Task 1 (z98-print-formatting): `.print_val` emits a mangled cross-module call into the Z98 std module `sf/src/std_fmt.zig` (`std.fmt`); `printFnSourceName` picks the std.fmt source name and `getPrintFnName` mangles it against the auto-imported std_fmt module id (new `C89Emitter.std_fmt_module_id`, set in `phase_C89Emission`; a `.print_val` also seeds a `ref_edges` entry so std_fmt stays reachable and its header is included). The C `std_print_<type>` bodies are retired; `std_print`/`std_print_len` remain the raw-bytes helpers for `.print_str`/console. `.print_str` is unchanged.] [updated: 2026-09-22 — `getPrintFnName` gained an `f32_type` arm routing `f32` to the existing `std_print_f64` (Task 7F f32 print dispatch; the prototype widens `float`→`double`, no runtime change)] [updated: 2026-09-20 — refreshed against current source: added `emit_support.zig` (self-contained output dir + companion build scripts), packed/int-width/`volatile`/calling-convention and `-fsafe`/`-ffast` guard emission, emission-core compaction, and module pruning; documented the removed `@socket*` builtin emission; dropped line references and the 4-example evidence appendix] [updated: 2026-09-26 — FB (Volume II defect fix, D4): `load_field`, `store_field` and `addr_of_field` gain tuple arms — a tuple VALUE base renders `._<field_id>` and a pointer-to-tuple base `->_<field_id>` (the positional C model `emitTupleType` already writes for `assign_field`/printers), so `.0`/`._0`/`t[0]` reads, writes and `&t.0` all reach the emitted fields. `emitNeededTupleAt` emits a needed tuple typedef at its topological position in the sorted type loops (value and pointer-only buckets; a struct that embeds a tuple by value previously emitted before the tuple typedef -> gcc `unknown type name`), sharing the `seen` dedupe map with the trailing `emitNeededTupleTypes` fallback (signature now takes `seen`).]

> Covers: `c89_emit.zig`, `name_mangler.zig`, `cinclude.zig`, `emit_support.zig`
> Cross-ref: [INDEX.md](INDEX.md) §E (NameMangler, BufferedWriter data structures)

## Summary

| Key | Value |
|-----|-------|
| Input | spill-backed function-slot list (`LirFunction`s per module), `TypeRegistry`, `ModuleRegistry` |
| Output | C89 `.c` via stdout (`--dump-c89`), or a self-contained multi-module tree + companion build scripts (`-o DIR` / `--output-dir`) |
| Phase marker | `C` (entry), `FINAL_FLUSH` (complete) |
| Key structs | `C89Emitter`, `BufferedWriter`, `NameMangler` |
| Key functions | `emitModule`, `emitSpecialTypes`, `emitFunctionBody`, `emitInst`, `nameManglerMangle`, `cincludeUnionAll`, `emitSupportFiles`, `emitBuildScripts` |

---

## 1. `c89_emit.zig` — C89 Emitter (9231 lines)


### 1.1 2-Phase Output Architecture

Emission follows a strict 2-phase ordering per module, enforced in `emitModule`:

```
Phase 1: Type Headers (emitSpecialTypes)
  ├─ Sub-pass 1: Forward declarations for struct/union/tagged_union types
  │   (typedef struct Foo Foo; — packed structs/unions skipped)
  ├─ Sub-pass 2a: Pointer-only types (fields all through ptr/slice/wrapper)
  │   (emitTypeDefinition — only if in pointer_only_map)
  └─ Sub-pass 2b: Value-embedding types (structs with inline fields)
      (emitTypeDefinition — only if NOT in pointer_only_map)

Phase 2: Function Bodies (emitModuleHeader → emitFunctionSignature → emitFunctionBody)
  ├─ Module header: includes, forward declarations
  ├─ Per function: signature + hoisted decls + basic blocks
  └─ main() wrapper for non-void return types
```

Phase 1 runs once via `emitSpecialTypes` BEFORE any function body. Phase 2 iterates the
spill-backed function-slot list.

#### Type Topological Sort

**[updated: 2026-10-12 — P12 (typedef ordering planning)]** the order is computed ONCE at the
backend-neutral `phase_EmissionClassification` boundary (`c89_plan.spellPlanPlanTypeOrder` →
`c89_plan.tstTopologicalSort`, the verbatim move of the former emitter-resident sort incl. the
P2 popped/append derivation) and carried as `C89SpellPlan.typedef_order`. Both former emit-time
call sites (`emitModule` and the multi-file `phase_C89Emission` region) now READ the carried
order; zero sort calls remain in the emitter or mid-emission (Decision-vs-spelling: ordering is
on the "emitter never decides" list). The emission passes' walk bounds are untouched (still
`tsi < types_len`), so post-snapshot appended types (the `emitHoistedDecls` ptr-type appends)
keep their exact pre-P12 handling — the walk's over-read of the carried array lands in the
sort's own `queue` buffer (consecutive `sandAlloc`s) and re-visits are dedup no-ops (P2
deferred minor "bound on snapshot length" unchanged and NOT taken here). Pins 0/8.
**[updated: 2026-10-12 — P2 fix round 1]** `tstTopologicalSort` now APPENDS any Kahn cycle
residue (nodes whose indegree never reaches 0) in stable ascending-tid order, so `sorted`
ALWAYS covers all `types_len` entries and the emission passes' `tsi < types_len` walk can never
read uninitialized arena memory (the append is a no-op for acyclic programs). A post-resolve
cyclic type still emits — possibly invalid C — instead of clean-rejecting (the pre-P2 behavior
class; the diagnose/reject variant is ruled out — no new error codes).
**[updated: 2026-10-12 — P2, D8]** Types are emitted in dependency order using Kahn's
algorithm (`tstTopologicalSort`), with the edge set derived from the SINGLE type-reference
relation in `type_registry.zig` (`typeRefs` / `typeRefsContains` / `typeNeedsFullDef` — doc 03).
The former hand-rolled edge machinery (`c89NeedsEmitEdge`, `tstEdgesWalk`, `tstSeenInRange`,
`tstEdgesCount`, `tstEdgesFill`, `tstIsDep`) is deleted; no divergent kind membership remains.

```
Input: TypeRegistry (all types 0..types_len-1)
1. indegree[ti] = typeRefs(reg, ti, buf) — the distinct typedef-ordering edge targets
2. Enqueue all types with indegree 0
3. Dequeue → add to result → for every tj with typeRefsContains(tj, cur): decrement → enqueue 0s
4. Result order: every referenced typedef before its referrer
5. Append cycle residue (unpopped nodes) in ascending-tid order → sorted covers types_len (P2 fix round 1)
```

The relation (`type_registry.zig`, kind-by-kind table in the P2 SDD report): by-value positions
(aggregate fields incl. `packed_union`, tagged-union tag, array elem, tuple elems, optional /
error-union payload) contribute every `typeNeedsFullDef(R)` ref (membership = the historical
`c89NeedsEmitEdge` set PLUS `packed_union`); name-spelling positions (fn return, fn params,
slice elem) require additionally NOT `typeHasForwardDecl(R)` (Pass-1 forward typedefs declare
named non-packed struct/tagged_union/union names); pointer references contribute a
name-visibility edge to their chain-leaf (a `*fn` field's C type IS the fn typedef name — the
D8 shape). Dedup is by edge target, so indegree equals the number of Kahn decrements exactly
(the old `tstSeenInRange` source-range dedupe is subsumed; `tstEdgesFill` had no callers and is
gone with the walk).

#### Pointer-only vs Value-embedding Split

The classification's `pointer_only` group (`classif.pointer_only_map`; computed in
`phase_TypeResolution` by `classifyTypeEmissionGroups`, completed at the pre-emit
`phase_EmissionClassification` boundary — `emitModule` receives no id arrays
(**P4 fix round 2**; the `ptr_only_ids` parameter is long deleted)). Types in this set have all
their field dependencies reachable through pointers — only
a forward declaration is needed for C89 correctness. The split prevents redundant full type
definitions:

- **Sub-pass 2a:** Iterates types in topo order, skips if NOT in `pointer_only_map`, (shared path) NOT in `shared_set`, or NOT in `needs_def_map` (**P4** — the deleted `shouldSkipTypeEmission`). Emits full definition.
- **Sub-pass 2b:** Iterates types in topo order, skips if IS in `pointer_only_map` or NOT in `needs_def_map` (**P4**). Emits full definition.

Both sub-passes dedup via `emitter.emitted_type_set` (hash of C type name string) — same type only
emitted once.

### 1.2 BufferedWriter — 4KB Buffered Output

Fixed-size 4096-byte buffer with auto-flush. `BufferedWriter` carries a **file-descriptor sink**
(`fd: usize`) so the multi-module path can flush each `.h`/`.c`/`zig_special_types.h` to its own
open file. Stdout remains the default (`fd=1`), so the bare `--dump-c89` byte-identical gate is
preserved.

| Field | Type | Purpose |
|-------|------|---------|
| `buf` | `[4096]u8` | Output buffer — written sequentially, flushed to sink when full |
| `pos` | `usize` | Current write cursor (0 = empty, 4096 = full, triggers flush) |
| `fd` | `usize` | Output sink fd. `1` (stdout) by default; set per-file via `bufferedWriterInitFd`. `usize` — an all-ones `INVALID_FD` sentinel (`pal.zig`) replaces the `-1` open-fail test |

| Function | Purpose |
|----------|---------|
| `bufferedWriterInit` | Returns new BufferedWriter with `pos=0`, `buf=undefined`, `fd=1` (stdout) |
| `bufferedWriterInitFd` | Returns new BufferedWriter writing to the given fd (multi-module per-file sink) |
| `bufferedWriterFlush` | Writes `buf[0..pos]` to `self.fd` via `pal.fileWrite`, resets pos to 0 |
| `bufferedWriterWrite` | Writes byte slice to buffer. Loops: copies min(remaining, 4096-pos) bytes into buf, increments pos, flushes if full |
| `bufferedWriterWriteByte` | Single byte write, flush-if-full, store at pos, increment |
| `bufferedWriterWriteIndent` | Writes `level * 4` spaces (flush-safe, byte-by-byte) |

Markers `FL:p` (flush start, prints current pos) and `FE:p` (flush end, prints 0) bracket each flush.

### 1.3 NameMangler — Deterministic Name Mangling [updated: 2026-10-12 — P1]

Lives in `name_mangler.zig` (the single C-identifier minting authority; P1). The emitter imports
it as `nm_mod` and keeps only thin `pub` forwarders for external callers. Every emitted C
identifier in the 10 kinds (fn/global/type/local/temp/union-member/struct-field/synthetic-type/
module/printer) is minted by `name_mangler.zig`; extern C symbols (PAL/runtime/`extern fn`) keep
their exact C names via the emitter's `is_extern` override (hard boundary).

| Field | Type | Purpose |
|-------|------|---------|
| `hash_seed` | `u32` | Currently always 0 |
| `cache` | `U64ToU32Map` | Multi-key: `(module_id << 35) \| (kind << 32) \| name_id` → mangled_id |
| `keyword_set` | `U32ToU32Map` | All 32 C89 keywords (auto..while), interned name_id → 1 |
| `collision_mod` | `U32ToU32Map` | Mangled name_id → module_id (detects collisions) |
| `collision_name` | `U32ToU32Map` | Mangled name_id → original name_id (maps collision back) |
| `interner` | `*StringInterner` | For interning mangled name strings |
| `exported` | `?*U64ToU32Map` | Optional set of `(module_id, kind, name_id)` keys whose symbol is `export`ed and must keep its **source name** (bypasses mangling) |
| `raw_cache_local`/`raw_cache_field`/`raw_cache_member` | `U64ToU32Map` | P1: `(scope << 32) \| name_id` → minted name_id (per-kind raw-name memo) |
| `raw_taken_local`/`raw_taken_field`/`raw_taken_member` | `U64ToU32Map` | P1: `(scope << 32) \| cand_id` → 1 (per-kind, per-scope occupancy for collision resolution) |

#### Mangling Scheme

`nameManglerMangle(name_id, kind, module_id)`:

```
Format: z<K>_<8-hex-digits>_<original-name>
        ↑  ↑         ↑
        |  kind      hash
        prefix       (FNV-1a of original name)
```

1. **Temp/builtin bypass** (`isTempOrBuiltin`): Names starting with `__tmp`, `__ret`, `__bootstrap` return unmangled.

2. **C89 keyword escape** (`isC89Keyword` → `mangleC89Keyword`): If the name matches a C89 keyword, prefix with `z_` and return. e.g., `int` → `z_int`.

3. **Export bypass:** if `exported` contains the key, return the original `name_id` (source name).

4. **Cache lookup:** Key = `(module_id << 35) | (kind << 32) | name_id`. If previously mangled, return cached.

5. **Mangle construction:**
   - `buf[0]` = `'z'` (prefix — avoids leading digit/underscore collision)
   - `buf[1]` = kind char: `F`=function(0), `G`=global(1), `T`=type(2), `L`=local(default)
   - `buf[2]` = `'_'`
   - `buf[3..11]` = 8 hex chars of FNV-1a hash
   - `buf[11]` = `'_'`
   - Followed by original name chars, truncated to fit 31 total

6. **31-char limit:** Total mangled name capped at 31 bytes (C89 standard minimum). Original name truncated if needed.

7. **Collision resolution:** If mangled name already used by a different `(module_id, name_id)`, append `_N` suffix with counter. Original name portion truncated further to stay within 31 chars. Digits counted dynamically before truncation.

8. **Cache population:** Store in `collision_mod`, `collision_name`, and `cache`.

`nameManglerMangleGlobal(registry, name_id, module_id, type_id)` is the module-global variant:
when the name is a type-storage global (the type's `name_id` equals the global's), identity is
the **stored type** (name + owning module), so every module aliasing the type agrees on one C
symbol; otherwise it falls back to per-module `nameManglerMangle`.

#### Per-kind mint API (P1) [updated: 2026-10-12]

| mint fn | rule | replaces |
|---------|------|----------|
| `nameManglerMangle(name_id, kind, module_id)` | hash-mangled `z<K>_<hex8>_<name>` (kinds F/G/T, collision `_N`) — fn/global/type + derived composites | (moved verbatim) |
| `nameManglerMangleGlobal` | type-storage-global identity variant | (moved verbatim) |
| `nameManglerMintLocal(name_id, scope)` | raw name; keyword -> `z_<name>`; per-scope collision -> `<cand>_N` | `mangleLocalName` |
| `nameManglerMintField(name_id, scope)` | same raw rule, per-struct scope (the D1 struct-field fix) | raw `stringInternerGet` at decl/access/printer |
| `nameManglerMintMember(name_id, scope)` | same raw rule, per-union scope | `cUnionMemberName` (+ collision check) |
| `nameManglerMintTemp(temp_id)` | `zT_<temp_id>` | `mangleTempName` |
| `nameManglerMintSyntheticType(prefix, elem, len, cap)` | `prefix+transformed(elem)+[_len]` -> kind-2 mangle | `syntheticTypeName` |
| `nameManglerMintIndexName(prefix, n)` | `prefix<decimal n>` (printer/table/scratch names) | `typeIdName`, `aggPackedScratchName` |
| `nameManglerMintModuleStem(path)` | `<file-stem>_<fnv1a(path) hex8>` | `moduleQualifiedName` core |
| `nameManglerFnScope(fn_name_id, fn_module_id)` | interned `"<module>_<name>"` scope key (map-partition token only) | (new) |

Determinism: hash-mangled collision state is order-stable (unchanged call order); raw-name
occupancy is per-scope with mint order a pure function of the program (params then `decl_local`s
per fn; fields in declaration order — types emit before bodies), so the same input mints the same
names in every compilation (`hop1==hop2` depends on this).

#### Temp Name Mangling

`nameManglerMintTemp`: Format `zT_<temp_id>`. Used for hoisted temporaries in function bodies. No
collision check needed — temp_ids are unique per function.

#### Local / Field / Member Name Mangling [updated: 2026-10-12 — P1]

`nameManglerMintLocal`/`MintField`/`MintMember` (shared raw rule): a non-keyword source name is
returned **byte-identical**; a C89 keyword becomes `z_<name>`; a candidate already claimed in the
same scope by a different name gets a `_N` suffix (the F1 `int`/`z_int` collision case). Scope =
the C function (`nameManglerFnScope`) for locals/params, the owning aggregate type id for struct
fields and union members. Used for function parameters, locals, struct fields (declaration,
every `resolveFieldAccess`/`emitFieldAssign` access arm, and the aggregate printer's `v.<f>`
access), union members (declaration + every access arm). Printer **display labels** keep the raw
source name (`.{ .int = 7 }` prints unchanged).

#### D2 gap — typedef `_N` suffix not mirrored on fn-signature type refs — FIXED (F1)

The `_N` collision suffix (step 7 above) is applied **per mangled name**, keyed by
`(module_id, kind, name_id)`. When the same-named type is defined in two module instances, the
second instance's typedef legitimately mangles to `zT_<hash>_<Name>_1`, and the struct definition
is emitted from that type's own `module_id`.

The fn-signature/return-type references come from `lir_fn.return_type` / `param.type_id` via
`getCTypeName`. Before F1, a bare return type `Arena` resolved to **module 0**'s TypeId, so the fn
reference mangled to the unsuffixed `zT_<hash>_<Name>` while the typedef in the same header was
`zT_<hash>_<Name>_1` — gcc rejected the emitted C (`return type is an incomplete type`).
**FIXED (F1):** the root cause was fixed upstream in `type_resolver.zig` (bare `ident_expr` type
resolution is now module-scoped), so the fn reference mangles to the same `_N`-suffixed name as
the typedef and `arena_multi_inst_xmod` compiles + runs clean. No emitter change was needed; the
`_N` collision mechanism is correct.

### 1.4 C89Emitter — Central Emitter State

`C89Emitter` (initialized by `c89EmitterInit`) holds all emission context:

| Field | Type | Purpose |
|-------|------|---------|
| `writer` | `BufferedWriter` | 4KB output buffer |
| `indent` | `u32` | Current indentation level (incremented in fn bodies) |
| `alloc` | `*Sand` | Per-function scratch arena |
| `persist_alloc` | `*Sand` | Persistent arena (maps, growable tables) |
| `registry` | `*TypeRegistry` | Type system reference |
| `interner` | `*StringInterner` | String lookups |
| `mangler` | `*NameMangler` | Name mangling |
| `diag` | `*DiagnosticCollector` | Error reporting |
| `switch_cases` | `*SwitchCaseArrayList` | Current function's switch cases |
| `call_args` | `*U32ArrayList` | Temporary call argument buffer |
| `current_fn` | `*LirFunction` | Function currently being emitted |
| `spill` / `fn_slots` / `fn_slots_start` / `fn_slots_len` / `spill_arena` | `*LirStream` / `[*]LirSlot` / `usize` | Spill-backed function-slot window for the current module (`faultIn`) |
| `d4_wtype` | `[*]u32` | Type propagation tracking (hoisted temps) |
| `d4_wflag` | `[*]u8` | Written flag: 0=unwritten, 1=resolved, 2=call-result, 3=suppressed |
| `d4_t2p` | `[*]u32` | Temp ID → hoisted_temps index mapping |
| `d4_dead` / `d4_local` / `d4_nodecl` / `d4_lread` | `[*]u8` | DCE / local-mapped / no-decl / load-read suppression flags |
| `d4_max_temp` | `u32` | Max temp id + 1 for the current function |
| `bb_used` / `bb_used_count` | `[*]u8` / `u32` | Referenced-block labels (unused labels pruned) |
| `dl_hoisted` | `u8` | Whether decl_local hoisting has run (guard against double-emit) |
| `nest_ok` / `nest_max` / `nest_inl` | `u8` / `u32` / `[*]u8` | Expression-nesting state: temps inlined into their consumer (def/decl suppressed) |
| `emitted_type_set` | `U32ToU32Map` | Dedup: type name hash → emitted marker |
| `fwd_decl_set` | `U32ToU32Map` | Dedup: forward decl name hash → emitted marker |
| `classif` | `*type_resolver.EmissionClassification` | **P4 fix round 2:** the completed classification state (doc 03) — owned by `CompilerContext`, filled at the pre-emit `phase_EmissionClassification` boundary; the emitter READS only. `pointer_only_map` = CLS:p snapshot (absent = value-embedding); `needs_def_map` = needs-definition group (typedef emitted; the deleted `shouldSkipTypeEmission`); `shared_set` = shared-header group (synthetics ∪ CLS:v ∪ i64/u64/f64 ∪ named fn_type, plus the CLS:p closure — a type joins when referenced **by value OR in a way that requires the C type name in scope**); `needed_tuple_set` = the E4 tuple seed |
| `plan` | `*c89_plan.C89SpellPlan` | **P6-pre:** the C89 spelling planner state (per-const carrier side tables) — filled at the same boundary; the emitter READS carriers at spell time (`planConstCarrierAt`) and never derives them (the deleted `intConstTypeForValue`). **P12:** the same state carries `typedef_order` (the typedef emission order, planned ONCE at the boundary by `spellPlanPlanTypeOrder`); the emitter walks the carried order and never sorts |
| `plan_fn_key` | `u32` | **P6-pre:** the current fn's plan key (its LIR spill slot offset — unique per fn, stable across the `lir_slots` regrouping), set at fn entry in `emitFunctionSet` |
| `module_reg` | `*ModuleRegistry` | Module registry (qualified names, pruning) |
| `reachable` | `U32ToU32Map` | Value-reference reachability set (module pruning) |
| `prune_active` | `u8` | Whether module pruning is active (multi-module path) |
| `error_code_registry` | `*U32ToU32Map` | Error-tag name_id → dense error code |
| `dedup_names` / `dedup_cap` / `dedup_count` | `[*]u32` / `u32` | Local variable dedup during hoisting (grown on demand) |
| `fl_name_ids` / `fl_temps` / `fl_count` | `[*]u32` / `u32` | Flat lookup: local name_id ↔ temp_id |
| `temp_global_map` | `U32ToU32Map` | Temp → global alias mapping |
| `ts_ref_set` | `U32ToU32Map` | Type-storage global reference set |
| `global_decls` / `global_decls_len` | `[*]ModuleGlobalDecl` / `u32` | Module global declarations |
| `needed_tuple_set` (via `classif`) | `U32ToU32Map` | Task 4: tuple type ids that hold a runtime value (hoisted temp / global); only these get a C typedef (registry-only print-args tuples are skipped so the 4-MD5 dumps stay byte-identical). **P4 fix round 2:** filled at the `phase_EmissionClassification` boundary (`type_resolver.collectNeededTuples`) |
| `safe_checks` | `bool` | `-fsafe` (true, default) / `-ffast` (false) |

### 1.5 Type Name Generation

**P3 (2026-10-12): `type_registry.typeCName` is the ONE canonical derivation** (doc 03);
`getCTypeName` is a pure consumer wrapper. It maps `TypeId` → C89 type name string:

| TypeKind | C89 Name | Notes |
|----------|----------|-------|
| `void_type` | `"void"` | Direct |
| `bool_type` | `"unsigned char"` | 1 byte; C89 has no bool |
| `i8_type` | `"signed char"` | |
| `i16_type` | `"short"` | |
| `i32_type` | `"int"` | |
| `i64_type` | mangled type | `typedef long long zT_<hash>_<name> Z98_ALIGN8;` (FX14 carrier) |
| `u8_type` | `"unsigned char"` | |
| `u16_type` | `"unsigned short"` | |
| `u32_type` | `"unsigned int"` | |
| `u64_type` | mangled type | `typedef unsigned long long ... Z98_ALIGN8;` (FX14 carrier) |
| `arb_uint_type` | `"unsigned char"`/`"unsigned short"`/`"unsigned int"`/u64 | Carrier chosen by `size` (1/2/4/8) |
| `arb_int_type` | `"signed char"`/`"short"`/`"int"`/i64 | Carrier chosen by `size` (1/2/4/8) |
| `f32_type` | `"float"` | |
| `f64_type` | mangled type | `typedef double zT_<hash>_<name> Z98_ALIGN8;` (FX14 carrier; was bare `"double"`) |
| `usize_type` | `"unsigned int"` | |
| `isize_type` | `"int"` | |
| `c_char_type` | `"char"` | |
| `va_list_type` | `"va_list"` | |
| `enum_type` | mangled type | `typedef <backing> <mangled>;` |
| `array_type` | `Arr_<elem-cname>_<len>` | Typedef'd — `typedef <elem> Arr_<elem>_<len>[<len>];` |
| `tuple_type` | `Tup_<tid>` (mangled, module 0) | Task 4 — synthetic (name_id 0), so the name is derived from the global dense type id; typedef'd `typedef struct { <e0> _0; ... } <cname>;` |
| `ptr_type` / `many_ptr_type` | `<base>*` | Direct pointer syntax; fn ptr → use fn name. A `volatile` flag emits the pointee-qualified `volatile T *` (or `T * volatile` for pointer-to-pointer) |
| `slice_type` | `Slice_<elem>` | Typedef'd struct: `typedef struct { <elem>* ptr; unsigned int len; } ...;` |
| `optional_type` | `Opt_<payload>` | Typedef'd struct with `{ <type> value; int has_value; }` (void payload: `{ int has_value; }`). Null construction emits `set_optional_null` directly on an `Opt_`-typed temp (`zT_M.has_value = 0;`), so no scalar null payload temp is produced. |
| `error_union_type` | `EU_<payload>` | Typedef'd struct with `{ union { <type> payload; int err; } data; int is_error; }` |
| `fn_type` | `F_<N\|P\|S>_<ret>_<p1>_<p2>...` | `F_N_` default, `F_P_` fn-ptr flag, `F_S_` stdcall |
| `error_set_type` | mangled type | `typedef int <mangled>;` + `#define` for each error tag |
| `undefined_type` | `"int"` | Fallback |
| `null_type` | `"int"` | Fallback (uncoerced null / non-optional pointer/fn targets — pointer-compatible). A null literal coerced to an optional emits `set_optional_null` directly, so no `null_const` temp is produced. |
| `integer_literal_type` | `"int"` | Fallback |

**`bool` representation (Task 11L, 2026-09-21).** `bool` is 1 byte / align 1 and maps to C89 `"unsigned char"` (C89 has no `_Bool`), matching Zig. The registry (`type_registry.zig`) and the emitter MUST agree — the folded `@sizeOf`/`@offsetOf` come from the registry, the actual layout from the emitted type. `typeRegistryIntByteWidth(bool) = 1` and `typeRegistryIntSignednessClass(bool) = 0` (unsigned) agree with the emitted type (P5, 2026-10-12: the emitter-local `intTypeByteWidth`/`classifyIntSignedness` names are gone — these predicates live in `type_registry.zig`). **Accepted residuals (Task 11V / AMENDMENT 16 — operator-ruled no action; NOT full Zig parity):** `?bool` is 8 bytes / align 4 (the optional arm keeps a `max(payload.alignment, 4)` floor) and `E!bool` keeps a 4-byte floor (`max(payload.size, 4)`); `typeWidthBitsForKind(bool)` stays 0 (`@bitSizeOf`/packed layout special-case bool to 1).

**Frozen 32-bit layout model pinned in the emitted C (FX14, 2026-09-29).** The registry registers exactly `i64`/`u64`/`f64` at size 8 / align 8 (`type_registry.zig` `typeRegistryRegisterPrimitives`), and `layoutCompute` folds composites from that model. Previously the emitted C used plain `long long`/`double`, which i386 System V (`gcc -m32`) aligns to 4 — so a `{a: u8, b: i64, c: u8}` measured `16/4/4/12` in the built binary while Z98 printed `24/8/8/16`. FX14 pins the model on every supported host compiler through the carrier typedefs (all three now carry ` Z98_ALIGN8`) plus the shared compat typedefs; because every declaration site (struct/union/tagged-union/tuple/array/optional/error-union/global/local/param) goes through `getCTypeName`, one typedef attribute covers them all. Packed aggregates are exempt (byte-array carriers; 64-bit packed fields reject `error[3000]`). Verified on `gcc -m32` and mingw; MSVC (`/Zp8`) and wcc386 (`-zp8`, 32-bit default) rely on their natural 8 and get an empty macro.

**P3 (2026-10-12): the derivation lives in `type_registry.typeCName`.** `getCTypeName` is now a
pure consumer wrapper (`return type_mod.typeCName(reg, mangler, tid);`) — the per-kind model
below is `typeCName`'s (doc 03), synthetic names are minted once through the P1 `name_mangler.zig`
authority, and the `c_name_map` memo is owned by the derivation (every post-memo-check kind stores
its mangled name id on first derivation). The former emitter write-back
(`emitErrorUnionType` → `typeRegistryCNameIdSet`) is removed; the emitter only READS the memo
(`emitStructType`'s `ES:n` telemetry). Declaration sites (`emitStructType`/`emitUnionType`/
`emitTaggedUnionType`/`emitEnumType`/`emitInt64Type`/`emitUint64Type`/`emitF64Type`) and the
former duplicated mints (`emitArrayType`'s local `Arr_` mint, `emitOptionalType`'s local `Opt_`
mint) all consume `getCTypeName(tid)` — decl and use cannot drift. All spellings byte-identical
to the pre-P3 emitter (dump pins 0/8); `sliceElementName` moved to `type_registry.typeSliceElementName`
(its F2 rule — synthetic element recurses, named element keeps the module-0 `name_id` mangle —
unchanged).

**D2 defect — slice-of-synthetic element typedef collapse (FIXED; task F2, 2026-10-09).**
In Zig `[][]const u8` and `[][20]u8` are distinct types, but the C slice typedef
for each was derived from its element's `name_id`
(`getCTypeName` slice branch), and every synthetic element
(slice/array/pointer/optional/tuple/error-union) has `name_id == 0`, so all
mangled to the same empty-name string `zT_811C9DC5_`:
`typedef struct { <elem>* ptr; unsigned int len; } zT_9DFA8D74_Slice_zT_811C9DC5_;`
whichever synthetic element was registered first won. A
`struct { announce_list: [][]const u8; piece_hashes: [][20]u8; }` therefore
declared **both** fields with the *same* typedef; gcc compiled it with a
`-Wincompatible-pointer-types` warning (the value was correct only by luck of the
hoisted temp).
**Fix (task F2, applied):** new helper `sliceElementName` (`c89_emit.zig:931`; **P3: now
`type_registry.typeSliceElementName`** — moved with the canonical derivation)
returns `getCTypeName(reg, mangler, elem)` when `elem.name_id == 0`, else the
exact `nameManglerMangle(elem.name_id, 2, 0)` used before. `getCTypeName`'s slice
branch feeds that name to `syntheticTypeName`, and `emitSliceType` derives its
typedef name from `getCTypeName(tid)` (single source of truth, decl/use cannot
drift). Distinct synthetic elements therefore get distinct `Slice_…` typedefs;
primitive/named element slices (`[]u8`→`Slice_zT_0B42B2F8_u`, `[]i32`,
`[]Struct`) stay byte-identical because they take the unchanged `name_id` path.
Repros: `repro/mi_matrix/slice_of_slice_xmod/` and
`repro/mi_matrix/slice_of_array_xmod/` — both now compile **warning-free** (no
`-Wincompatible-pointer-types`) and run green (print `11`).

### 1.6 Type Emission — emitSpecialTypes

`emitSpecialTypes(emitter, reg, sorted)` drives type header output for the stdout single-file
path. For the multi-module path (`--output-dir`), the shared-header writer `emitSharedHeader`
performs the equivalent partition into `zig_special_types.h` (see §1.17):

```
emitSpecialTypes(emitter, reg, sorted):
  1. fwd_decl pass: for each struct/tagged_union/union with name_id:
       skip packed struct and packed_union (carrier typedef is complete)
       emit "typedef <struct|union> <cname> <cname>;\n"
       keyword from aggregateKeyword(kind) — "union " for union/packed_union else "struct "
       (bare unions emit `typedef union` so the tag-namespace agrees with the def)
       dedup via fwd_decl_set (hash of cname string)
  2. pointer-only pass: for each type in sorted:
       if NOT in pointer_only_map → skip
       if NOT in needs_def_map → skip   (P4: the classification's needs-definition group —
       the deleted shouldSkipTypeEmission's void/bool/noreturn/null/undefined/int-lit/type/
       module + unnamed-non-composite skip rules; the old skip_arb arm was unreachable-equivalent)
       dedup via emitted_type_set (hash of cname string)
       emitTypeDefinition()
  3. value-embedding pass: for each type in sorted:
       if IS in pointer_only_map → skip
       if NOT in needs_def_map → skip   (P4)
       dedup via emitted_type_set
       emitTypeDefinition()
```

`emitModule` calls `emitErrorCodePrologue` before `emitSpecialTypes`; the
classification is completed at the pre-emit `phase_EmissionClassification`
boundary (doc 03) — `emitTypePasses` retains ZERO classification calls
(**P4 fix round 2**; see §1.17).

### 1.7 Type Definition Emission

`emitTypeDefinition` dispatches by `TypeKind`:

| TypeKind | Emitter Function | Output |
|----------|-----------------|--------|
| `slice_type` | `emitSliceType` | `typedef struct { <elem>* ptr; unsigned int len; } Slice_<elem>;` |
| `optional_type` | `emitOptionalType` | `typedef struct { <type> value; int has_value; } Opt_<payload>;` (void payload: omit value). Null-payload temps for this type are emitted as `Opt_` (`set_optional_null` writes `has_value = 0;`) |
| `error_union_type` | `emitErrorUnionType` | `typedef struct { union { <type> payload; int err; } data; int is_error; } EU_<payload>;` (void payload: `{ int err; int is_error; }`) |
| `error_set_type` | `emitErrorSetType` | `typedef int <cname>;` + `#define <cname>_<tag> <N>` per tag |
| `tagged_union_type` | `emitTaggedUnionType` | Complex struct + union + tag constants |
| `enum_type` | `emitEnumType` | `typedef <backing> <cname>;` + `#define <cname>_<member> <val>` per member (64-bit member values via `itoa64`) |
| `struct_type` | `emitStructType` | `struct <cname> { <type> <field>; ... };` — or, when `typeRegistryIsPacked`, a carrier `typedef struct { unsigned char _[N]; } <cname>;`; an empty non-packed `struct {}` (`fields_count == 0`) emits `struct <cname> { unsigned char _[1]; };` so the C layout matches the registry's min-1 size 1 / align 1 (**A2-F**) |
| `union_type` | `emitUnionType` | `union <cname> { <type> <field>; ... };` — real C union (all members at offset 0, size = max member) matching `@sizeOf`'s union-max. Keyword from `aggregateKeyword(ty.kind)` — the same helper as the two fwd-decl sites, so the C89 tag-namespace (struct/union tags share one namespace) always agrees. Guard tag is `ZIG_UNION_` (see §1.17). |
| `packed_union_type` | `emitUnionType` | carrier `typedef struct { unsigned char _[N]; } <cname>;` (untagged, members at bit 0 via bitfield access) |
| `array_type` | `emitArrayType` | `typedef <elem> Arr_<elem>_<len>[<len>];` |
| `tuple_type` | `emitTupleType` | `typedef struct { <e0> _0; <e1> _1; ... } <cname>;` (positional C model; only for tuples in `needed_tuple_set`, see §1.18) |
| `i64_type` | `emitInt64Type` | `typedef long long <cname> Z98_ALIGN8;` (FX14) |
| `u64_type` | `emitUint64Type` | `typedef unsigned long long <cname> Z98_ALIGN8;` (FX14) |
| `f64_type` | `emitF64Type` | `typedef double <cname> Z98_ALIGN8;` (FX14) |
| `fn_type` | `emitFnPtrType` | `typedef <ret> (<Z98_STDCALL >*<cname>)(<params>);` — emitted only when the fn-ptr-used flag is set |

#### Tagged Union Emission

`emitTaggedUnionType` handles two cases:

**Enum-tagged** (tag type is enum):
```
#define TU_<name>_<member> <N>
struct <name> {
    <tag-type> tag;
    union {
        char _dummy;
        struct { <field-type> _0; } <field-name>;
        ...
    } payload;
};
```

**Integer-tagged**:
```
#define <name>_<field> <N>
struct <name> {
    unsigned int tag;
    union {
        char _dummy;
        struct { <field-type> _0; } <field-name>;
        ...
    } payload;
};
```

Field constants are `#define`d for integer matching. Tagged union payload access uses `.payload.<field-name>._<sub-field-idx>`.

**D1 defect — C-keyword tag emitted invalid C89 (FIXED; task F1, 2026-10-09).**
`emitTaggedUnionType` (`:1921`) reads each variant's `fe.name_id` at **`:2013`** and
writes it verbatim as the C union member at **`:2020`**; `emitVariantFieldPayload`
(`:419`, called from `resolveFieldAccess` `:499`, shared by `.assign_field` /
`.load_field` / `.store_field`) reads `evp_vfe.name_id` at **`:435`** and writes it
verbatim into the payload designator `.payload.<name>._<sub>` at **`:436`**. In Zig
any identifier is a valid `union(enum)` tag (`int`, `long`, `switch`, … are not Zig
keywords), so `union(enum) { int: i64 }` is legal Z98; the emitted C is
`struct { zT_C69B2266_i64 _0; } int;` (declaration) and `v.payload.int._0` (access),
which gcc rejects (`expected identifier before 'int'`). `@"int"` is rejected by Z98
(`error[4]`), so the tag cannot be spelled around. The tag-constant `#define`s
(`:1973-1982`, prefix `zTU_<base>_`) and switch dispatch compare prefixed
names/numeric cases, so only the payload declaration and access sites leak the raw
name. Bare-union member emission (`emitUnionType` `:2104`/`:2109`) has the same
class of leak. **Fix (task F1):** the shared helper `cUnionMemberName`
(`c89_emit.zig:594`) returns the interned C member name, applying the existing `z_`
C-keyword escape (`mangleC89Keyword`) only for C-keyword names and returning every
non-keyword name **byte-identical**; it is used at the tagged-union declaration
(`emitTaggedUnionType`) and payload access (`emitVariantFieldPayload`) and, for the
same class of leak, at the bare-union declaration (`emitUnionType`) and the union
arms of `resolveFieldAccess` (value/ptr/addr-of; struct fields untouched), and at
the generated aggregate printer's tagged-union arm (`emitAggPrinterDef` — the
payload designator is mangled while the human-readable print label stays the raw
tag, e.g. `int = `). A `union(enum){ int: i64 }` now emits `z_int` consistently at
every site. Repro: `repro/mi_matrix/union_keyword_tag_xmod/` (pre-fix FAIL,
post-fix compile+link+run; the repro also prints a keyword-tagged union through the
generated aggregate printer).

### 1.8 Function Emission

#### emitFunctionSignature

```
/* <original-name> */
<call-conv> <return-type> <mangled-name>(<param-type> <param-name>, ...) {
```

- Mangled name via `nameManglerMangle(name_id, F, module_id)`
- `extern` functions: use original name, not mangled
- Comment with original name above signature for readability
- `stdcall` functions: `Z98_STDCALL ` before the name (`emitCallConv`)
- Empty params → `(void)`, variadic → `(...)` (with a `, ` separator when params exist)
- Param names go through `nm_mod.nameManglerMintLocal` (keyword-safe)
- Opens `{` and increments indent
- **Variadic externs get forward declarations:** the extern-prototype guards in
  `emitModuleHeader` / `emitModuleHeaderFile` are `is_extern==0 OR is_variadic!=0`, so a variadic
  `extern fn printf(fmt, ...)` emits its C prototype (`int printf(unsigned char*, ...);`,
  name-passthrough) while non-variadic externs rely on `@cInclude`'d headers.

#### emitHoistedDecls

Emitted immediately after the function signature, before the body. Two passes:

**Pass 1: Type propagation.** Scans all instructions, tracking written types for temporaries via
`d4_wtype`/`d4_wflag` arrays and resolving `TYPE_UNDEFINED` temps. Keys:
- `.assign`: propagates src type to dst
- `.call_direct`/`.call`/`.tail_call`: marks as type 2 (call result)
- `.int_const`, `float_const`, `bool_const`, `string_const`, `enum_const`, `.poison_init` → set types
- `.binary`/`.unary`: propagates operand types to result
- `.int_cast`, `.int_cast_checked`, `.width_wrap`, `.float_cast`, `.ptr_cast`, `.int_to_float`,
  `.int_to_ptr`, `.ptr_to_int`: use target type
- `.load`, `.addr_of`, `.addr_of_field`, `.load_index`, `.load_field`, `.load_bitfield`,
  `.make_slice`, `.load_local`: set type from hoisted_temp or operand
- `.add_with_overflow`/`.sub_with_overflow`/`.mul_with_overflow`/`.shl_with_overflow`/
  `.neg_with_overflow`/`.overflow_flag`: set result type

**Pass 2: Declaration emission.** For each hoisted temp (skipping params), emits a C declaration
`<type> zT_<temp_id>;` (scalar → `= 0;`, aggregate → `= {0};`, `-fsafe` uninitialized → a
`zig_poison_fill` after the decl block). `TYPE_VOID` temps are skipped. Debug markers `D4:`,
`D7:`, `D9:`, `HTT:`, `HT:` track type resolution. Declaration is suppressed for temps that are
dead (`d4_dead`), local-mapped (`d4_local`), no-decl (`d4_nodecl`), or inlined by expression
nesting (`nest_inl`) — see §6.3.

#### emitFunctionBody

```
emitFunctionBody:
  1. Emit local variable declarations (decl_local hoisting):
     - Scans all blocks for decl_local instructions
     - Dedups by name_id (emitter.dedup_names, grown on demand to dedup_cap)
     - Skips dead names (isDeadLocalName) and TYPE_VOID locals
     - Emits "type name;\n" for each unique local
     - Sets dl_hoisted guard
  2. Emit "(void)name;" for each unused parameter
  3. Emit basic blocks:
     - Block 0: label "z_bb_0:" (emitted by the .loop_header inst — see §1.9)
     - Blocks > 0: label "z_bb_<id>:" only when referenced (bb_used)
  4. Emit each instruction via emitInst() (dead/nested defs skipped)
  5. Close "}\n"
```

Blocks are labeled with `z_bb_<id>:` — C89-style goto labels. Since the TCO feature
(`loop_header(0)` is injected as the first entry-block inst; the `.loop_header` arm emits
`z_bb_0:`), **every function** whose entry block is referenced gets a `z_bb_0:` label, emitted
after the hoisted temp decls and local decls and before the first entry-block statement:

```
ret_zF_fn(params) {
    <hoisted temp decls zT_N;>      (emitHoistedDecls)
    <local decls name;>             (emitFunctionBody decl_local hoist)
    z_bb_0:                         ← .loop_header arm
    <bb0 entry-block insts>
z_bb_1:
    <bb1 insts>
    ...
}
```

This is the TCO self-recursion jump target: self-tail calls emit rebind assigns + `goto z_bb_0;`
(back-edge to the entry block) instead of a recursive C call — O(1) stack for self-recursion.
Unused block labels are pruned (`bb_used`), so a function with no tail call and no jump to its
entry block does not emit a `z_bb_0:` label at all.

### 1.9 LirInst → C89 Emission Table

Every `LirInst` variant handled in `emitInst`:

| LirInst | C89 Output |
|---------|-----------|
| `.nop` | (nothing) |
| `.trap` | `pal_trap();` (unconditional divergence — `unreachable`/`@panic`) |
| `.check_trap` | `if (!(cond)) { pal_trap(); }` (`-fsafe` guard) |
| `.add_with_overflow` / `.sub_with_overflow` / `.mul_with_overflow` / `.shl_with_overflow` | `result = zig_wrap_<op>_<s\|u>((T)lhs, (T)rhs, <w>u);` (`emitWrapOp`) |
| `.neg_with_overflow` | `result = zig_wrap_neg_<s\|u>(value, <w>u);` (`emitWrapNeg`) |
| `.overflow_flag` | `result = zig_overflow_flag_<op>_<s\|u>((T)lhs, (T)rhs, <w>u);` (`emitFlagOp`) |
| `.ret_void` | `return;` (non-void scalar → `return 0;`; aggregate → `{ <type> zT_ret_void = {0}; return zT_ret_void; }`) |
| `.loop_header` | `z_bb_0:` (entry-block label — TCO self-recursion jump target; emitted only when bb0 is referenced) |
| `.label` | (nothing — waits for block label) |
| `.decl_local` | Emitted by hoisting pass in emitFunctionBody |
| `.assign` | `dst = src;` (array: `{ unsigned int _i=0; while(_i<N) { dst[_i]=src[_i]; _i++; } }`; dead name → `(void)src;`) |
| `.assign_field` | `base.field = src;` (struct/union/packed_union/ptr/slice/tagged_union) |
| `.assign_index` | `base[idx] = src;` or `(*base)[idx] = src;` |
| `.jump` | `goto z_bb_<id>;` |
| `.branch` | `if (cond) goto z_bb_<then>; else goto z_bb_<else>;` |
| `.ret` | `return val;` |
| `.load_local` | `result = name;` (array: `{ ... for-loop copy ... }`) |
| `.store_local` | `name = val;` (`_` → `(void)val;`) |
| `.load_global` | `result = name;` |
| `.store_global` | `name = val;` |
| `.load_field` | `result = base.field;` (slice → `.ptr`/`.len`; tagged_union → `.tag`/`.payload`; ptr → `->field`; struct → `.field`) |
| `.store_field` | `base.field = val;` (same field resolution as load_field; ptr-base struct/union pointee → `ptr->field`) |
| `.load_index` | `result = base[idx];` or `result = (*base)[idx];` |
| `.load` | `result = *ptr;` |
| `.store` | `*ptr = val;` |
| `.addr_of` | `result = &operand;` |
| `.addr_of_field` | `result = &base.field;` / `&base->field;` (struct/union field address) |
| `.binary` | `result = lhs op rhs;` (op: `+` `-` `*` `/` `%` `&` `\|` `^` `<<` `>>` `==` `!=` `<` `<=` `>` `>=`; BIN_EQ/BIN_NE with `tagged_union_type` operands append `.tag` to each operand → `s.tag == t.tag`, active-tag comparison) |
| `.unary` | `result = op operand;` (op: `-` `!` `~`) |
| `.int_const` | `result = <value>;` (signed: cast + neg magnitude to avoid warnings; tagged_union: `.tag = <value>;`) |
| `.enum_const` | `result = <type>_<member>;` |
| `.float_const` | `result = <d.ddd>;` (via `formatF64`) |
| `.string_const` | `result = "<escaped>";` (escape: `\n`, `\t`, `\r`, `\\`, `\"`) |
| `.null_const` | `result = NULL;` (optional type → `result.has_value = 0;`) |
| `.set_optional_null` | `result.has_value = 0;` |
| `.bool_const` | `result = 1;` or `result = 0;` |
| `.undefined_const` | `result = 0;` (arrays: `{ ... for-loop zero ... }`; tagged union arrays: `[_i].tag = 0;`; nested struct arrays: recursive loop) |
| `.poison_init` | `zig_poison_fill((void*)&result, (unsigned int)sizeof result);` (`-fsafe` `undefined` poison) |
| `.call` | `result = callee(args...);` (indirect call through function pointer) |
| `.call_direct` | `result = fn_name(args...);` (extern return wrapping for optional/error_union) |
| `.tail_call` | `result = fn_name(args...); return result;` — call+ret **fallback**, NOT a jump; void return → `fn_name(args...); return;`; extern → original name; indirect callee via `resolveTempName` |
| `.switch_br` | `switch (cond) { case <val>: goto z_bb_<target>; ... default: goto z_bb_<else>; }` |
| `.wrap_optional` | `result.has_value = 1;\n result.value = src;` |
| `.int_cast` | `result = (type)src;` (unchecked plain cast; the checked `-fsafe` path is the separate `.int_cast_checked`) |
| `.int_cast_checked` | `result = (type)zig_cast_checked_s/u((unsigned long long)src, <sw>u, <ss>u, <dw>u);` (`-fsafe` width/sign-aware) |
| `.width_wrap` | `result = (type)(src & <mask>);` (signed: `((... ^ <signbit>) - <signbit>)`) |
| `.int_to_float` | `result = (type)src;` |
| `.float_cast` | `result = (type)src;` |
| `.make_slice` | `result.ptr = ptr;\n result.len = len;` |
| `.print_str` | `std_print("literal");` (unchanged: the raw-bytes helper for a format-string literal segment) |
| `.print_val` | mangled `std.fmt.<printer>(val);` cross-module call into the auto-imported `sf/src/std_fmt.zig` (slice → `printStr(val.ptr, val.len)`); the old `std_print_<type>` C-ABI calls are retired. Task 4: an aggregate/tuple type calls its generated per-type printer `<name>(val, 3)` instead (see §1.18). Task 5: a bare `{}` on an enum calls `z98_printEnum_<tid>(val)`, on an error set `z98_printErrorSet_<tid>(val)` (the `print_val.implicit` bit distinguishes a bare `{}` from an explicit enum `{d}`/`{x}`, which keeps the numeric route; see §1.19). Task 6: a pointer/fn-pointer type emits the inline `T@hex` / pointee-delegation form, and a `fmt == 'x'` float calls `z98_printFloatHex32/64(val)` (see §1.20) |
| `.ptr_cast` | `result = (type)src;` |
| `.check_error` | `result = src.is_error;` |
| `.unwrap_error_payload` | `result = src.data.payload;` |
| `.unwrap_error_code` | `result = src.data.err;` (void-payload → `src.err;`) |
| `.wrap_error_ok` | `result.data.payload = src;\n result.is_error = 0;` (void-payload → `result.err = 0;\n result.is_error = 0;`) |
| `.wrap_error_err` | `result.data.err = src;\n result.is_error = 1;` (void-payload → same pattern, `.err`) |
| `.check_optional` | `result = src.has_value;` |
| `.unwrap_optional` | `result = src.value;` (void-payload → nothing) |
| `.unwrap_optional_checked` | `if (!(src.has_value)) { pal_trap(); }\n result = src.value;` (`-fsafe`) |
| `.unwrap_optional_abi` | `result = src.has_value ? src.value : NULL;` |
| `.int_to_ptr` | `result = (type)(unsigned int)src;` |
| `.ptr_to_int` | `result = (usize)src;` |
| `.func_ref` | `result = fn_name;` (function pointer; stdcall casts to the `FS_...` typedef) |
| `.va_start` | `va_start(vl, last_param);` |
| `.va_arg` | `res = va_arg(vl, TYPE);` (TYPE = `getCTypeName(type_id)`) |
| `.va_end` | `va_end(vl);` |
| `.load_bitfield` | packed bitfield extract (`emitPackedLoadBitfield`, sign-aware) |
| `.store_bitfield` | packed bitfield insert (`emitPackedStoreBitfield`) |
| `.builtin_put_char` | `putchar(value);` |
| `.builtin_stdout_write` | `fwrite(ptr, 1, len, stdout);` |
| `.builtin_stderr_write` | `fwrite(ptr, 1, len, stderr);` |
| `.builtin_get_char` | `result = getchar();` (result typed `unsigned char`) |
| `.builtin_exit` | `exit(value);` |
| `.builtin_sleep_ms` | `#ifdef _WIN32` `Sleep(value);` `#else` `usleep(value * 1000);` `#endif` |
| `.builtin_console_clear` | `#ifdef _WIN32` `FillConsoleOutputCharacter/Attribute`+home `#elif __WATCOMC__`/`#else` ANSI `std_print_len("\x1b[2J\x1b[H", 7)` `#endif` |
| `.builtin_console_gotoxy` | `#ifdef _WIN32` `SetConsoleCursorPosition(COORD)` `#elif __WATCOMC__`/`#else` `sprintf(buf, "\x1b[%d;%dH", y+1, x+1)` + `std_print_len` `#endif` |
| `.builtin_console_set_color` | `#ifdef _WIN32` `SetConsoleTextAttribute` `#elif __WATCOMC__`/`#else` `sprintf(buf, "\x1b[%s;%sm", fg_ansi[fg&0x0F], bg_ansi[bg&0x0F])` + `std_print_len` `#endif` |

Any unhandled variant falls through the `else => {}` (no-op). Emission is preceded by the LIR
optimization pass (`lirOptRun`) and the dead-temp DCE / expression-nesting suppression (§6.3),
so a declared instruction may be omitted entirely from the emitted C.

**`@intCast` / arbitrary-width emission:** `.int_cast` is the unchecked plain cast — the arm
emits `result = (type)src;` only, with all bound/sign decisions made in lowering. The checked path
is the separate `.int_cast_checked` op, emitted only under `-fsafe` (narrowing or same-width sign
change), which maps to the width/sign-aware `zig_cast_checked_s/u` helpers in `zig_runtime.h`. The
older `__bootstrap_<DST>_from_<SRC>` helpers still exist as retained runtime support (emitted by
`emit_support.zig` as `static` in `zig_runtime.h` + `extern` in `zig_runtime.c`, message
`"integer cast overflow in @intCast"`), but the emitter no longer selects them.

**`stdarg.h` gating:** `emitStdargInclude` emits `#include <stdarg.h>` only when
`moduleHasVaInsts` finds a `va_start`/`va_arg`/`va_end` LirInst in the TU — gated on actual
`va_*` usage (not `is_variadic`). The include is emitted in `emitModuleHeader`,
`emitModuleHeaderFile`, and `emitModuleFile`.

**Builtin include gating:** `emitBuiltinIncludes` emits `#include <stdio.h>` when any of
`builtin_put_char`/`builtin_stdout_write`/`builtin_stderr_write`/`builtin_get_char` appear,
`#include <stdlib.h>` for `builtin_exit`, the `_WIN32`/`unistd.h` guard for `builtin_sleep_ms`,
and the Win98-forcing console preamble (`windows.h` / `<stdio.h>`) plus
`extern void std_print_len(const char* s, unsigned int len);` for `builtin_console_*` — each
gated on actual usage (`moduleHasStdioBuiltin` / `moduleHasExitBuiltin` / `moduleHasSleepBuiltin`
/ `moduleHasConsoleBuiltin`). The includes are emitted in both the single-stream
`emitModuleHeader` and the multi-module `emitModuleFile` paths.

**Builtin console emission:** the 3 console arms emit the
`#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else` guard chain; the `__WATCOMC__` and `#else`
arms share the ANSI-escape body. `@isWindows()` emits NO C (folded in sema/comptime to an
`int_const` 0/1). The Win32 console arms emit inline (no `return` — they run in the user
function, so a `return` would exit the caller).

**C89 cross-function TCO limitation:** `.tail_call` is emitted as a **call followed by a
`return`** (`zT = fn(args); return zT;`), preserving a C stack frame — semantically a tail call
but not a jump. Only **self-recursion** TCO achieves O(1) stack (rebind assigns + `goto z_bb_0;`
back-edge to the entry label). Real frame-reusing cross-function tail calls require a backend
that can emit a proper tail-jump; until then cross-function TCO is call+ret. The `.tail_call`
written-type scan marks the result temp as a call-result (written_flag=2) so the decl pass does
not flag it UNWRITTEN.

### 1.10 emitModule — Top-Level Orchestration

`emitModule(emitter, name, c_includes)` (P4 fix round 2: the `ptr_only_ids`/`ptr_only_len`
parameters are deleted — the classification maps arrive on `emitter.classif`) drives one module's output
for the **stdout single-file path** (bare `--dump-c89`). With `--dump-c89 --output-dir DIR` (or
`-o DIR`), `phase_C89Emission` instead writes `zig_special_types.h` once via `emitSharedHeader`,
then loops modules emitting per-module `.h`/`.c` via `emitModuleHeaderFile`/`emitModuleFile`
(§1.17), and finally the support files/scripts (§6). `phase_C89Emission` runs the single-file
path as: create a separate `BufferedWriter` (`cwriter`), emit the fixed `emitIncludes` preamble
(`#include "zig_compat.h"` + `#include "zig_runtime.h"`), flush it, then call `emitModule` with
the hardcoded module name `"output"` — hence `/* Module: output */` in every single-file dump.

```
emitModule(emitter, name, c_includes):   (P4: the classification maps arrive pre-loaded)
  1. sorted = emitter.plan.typedef_order   (P12: the carried typedef order — planned
     ONCE at the phase_EmissionClassification boundary; the emitter never sorts)
  2. emitErrorCodePrologue
  3. emitSpecialTypes(emitter, registry, sorted)  ← Phase 1: type headers
  4. emitModuleHeader(name, c_includes)           ← Phase 2a: includes + fwd decls
  5. emitGlobalDecls(module 0, all=1)             ← storage globals
  6. For each function slot (skip extern):
     a. emitter.switch_cases = &func.switch_cases
     b. lirOptRun(...)                            ← LIR optimization pass
     c. emitFunctionSignature(emitter, &func)
     d. emitHoistedDecls(emitter, &func)          ← temp declarations + DCE/nest/poison
     e. emitFunctionBody(emitter, &func)          ← local hoist + basic blocks
     f. If func.is_pub and name=="main": emitMainWrapper
  7. emitModuleFooter()                           ← "/* EOF */\n"
```

The fn list is `emitter.fn_slots` (spill-backed `LirSlot`s), not a direct parameter.

#### main() Wrapper

When a public function named `main` is found, an additional `int main(void)` wrapper is emitted.
If `main` takes parameters, the wrapper signature becomes `int main(int argc, char** argv)` and
the call forwards `(argc, <argv-cast>)`. The wrapper first emits `__module_init()` calls for every
reachable module with runtime-initialized globals (`emitModuleInitCalls`), then:

| Return Type | Wrapper |
|------------|---------|
| `void` | `int main(void) { ... zF_<hash>_main(); return 0; }` |
| `error_union` (void payload) | `int main(void) { ... zT_main_result = zF_<hash>_main(); return zT_main_result.is_error ? zT_main_result.err : 0; }` |
| `error_union` (non-void payload) | `int main(void) { ... return zT_main_result.is_error ? zT_main_result.data.err : (int)zT_main_result.data.payload; }` |
| normal | `int main(void) { ... return (int)zF_<hash>_main(); }` |

#### emitModuleHeader

```
/* Module: <name> */
#include "zig_compat.h"
#include "zig_special_types.h"
<stdarg include, iff va_* used>
<builtin includes, gated on use>
<c-includes...>

/* Forward declarations */
<func-forward-decls...>
```

C-includes: if starts with `<`, emit raw (`#include <foo.h>`). Otherwise wrap in quotes (`#include "foo.h"`).
`emitStdargInclude` adds `<stdarg.h>` only when the TU uses `va_start`/`va_arg`/`va_end`;
`emitBuiltinIncludes` adds `<stdio.h>`/`<stdlib.h>`/`<windows.h>`/`<unistd.h>` and the console
preamble gated on actual builtin use.

### 1.11 emitModuleFooter

```
/* EOF */
```

### 1.12 emitFunctionForwardDecl

Emits `return-type fn-name(param-types...);` — same mangling and calling convention as the
signature but without param names.

### 1.13 emitBaseIdxAccess

Handles indexed load/store with ptr-to-array detection:

- Ptr-to-array: `result = (*base)[idx];` or `(*base)[idx] = src;`
- Normal: `result = base[idx];` or `base[idx] = src;`
- Decay forms: `&(*base)[idx]`, `&base[idx]`, or a byte-copy for a by-value array element
  (`decay` 1/2/3).

`isBasePtrToArray` checks if a temp's type is ptr-to-array.

**D5 defect — lost store through a slice-index aggregate lvalue (FIXED; task F5, 2026-10-09).**
`s[i].field[j] = x` (and the fixed-array `a[i].field[j] = x`) compiles and links cleanly but
the store is **silently lost**. In Zig the whole index/field chain is an **lvalue**: the store
must write through `&s[i].field[j]`. Today `lowerAssignLValue`'s `index_access` arm
(`sf/src/lower.zig:2484-2531`) lowers its base by **value**
(`lowerExpr(indexBaseAfterArrayDeref(...))` `:2487`) and only the tuple sub-case takes an
address (`:2493-2508`), so the base (`s[i].field`) is materialised as a by-value struct temp
and `assign_index`/`emitBaseIdxAccess` (`c89_emit.zig:204-267`, `:7226-7271`) stores into the
array field **of that copy**. Emitted C (D5 repro; `backing` a `[N]Peer` global with an
`[4]u8` `peer_id` field):

```c
zT_12 = zG_..._backing[zT_11];   /* Peer copied BY VALUE into a local temp */
zT_13 = zT_12.peer_id;           /* pointer into the LOCAL copy */
zT_13[zT_14] = zT_9;             /* the store lands in the temp, not backing[i] */
```

The correct sibling path `lowerFieldStore` already addresses nested bases
(`sf/src/lower.zig:2878-2928`: an index base via `maybeExtractSlicePtr` + ptr+idx at
`:2878-2909`, a field/deref/paren base via `lowerLValueAddr` at `:2910-2928`), which is why a
direct `s[i].field = x` is correct while `s[i].field[j] = x` is not. **Fix (task F5,
applied):** the `index_access` arm of `lowerAssignLValue` now takes an **array-typed**
aggregate l-value chain by ADDRESS before the value path: when the base is a
`field_access`/`index_access`/`deref`/`paren_expr` whose chain roots at an `index_access`
(new helpers `d5BaseChainHasIndex`/`d5IndexAssignArrayType`, `sf/src/lower.zig:2564`/`:2612`),
`lowerLValueAddr` forms `&elem->field` once and `assign_index` emits `(*zT)[j] = src;`. An
array field's resolved type decays to a bare element pointer, so the declared array type is
recovered from the container's field table (mirroring `fieldStaticLenForBase`). Slice/pointer
bases and local-aggregate field bases (no index in the chain) keep the value path
**byte-identically**. This is a **runtime** defect — the compile-only corpus classify is OK
both before and after the fix — so the gate is the runtime assertion in
`repro/mi_matrix/slice_index_field_store_xmod/`: post-fix stdout is
`9\n11\n22\nslice_index_field_store ok\n`; the emitted C drops the by-value copy and writes
`zT_12 = backing + zT_11; zT_13 = &zT_12->peer_id; (*zT_13)[zT_14] = zT_9;`. All 8 dump-MD5
pins are unchanged (slice/pointer/local bases byte-identical).

**D5 `-fsafe` root-index check (RESTORED; task F6, 2026-10-10).** The address path above
bypassed the by-value element read that used to carry the `-fsafe` bounds check, so the chain
ROOT index `i` in `s[i].field[j] = x` / `a[i].field[j] = x` was no longer trapped when
out-of-range. `lowerLValueAddr` gained a `safe_check: u8` parameter (`sf/src/lower.zig:2202`);
its `index_access` arm emits `emitSafeCheckIndex(lv_ix_base, lv_node.child_0, idx_temp)`
(:2235) when set, and only the D5 call site opts in (`:2507`); every other address-of caller
passes `0`, so their emitted C is byte-identical. `-ffast` is unaffected (the helper returns
early when `!safe_checks`). Emitted `-fsafe` now has `zT = peers.len; if(!(i < zT)){ pal_trap(); }`
before the address add. Repro `repro/mi_matrix/slice_index_field_store_oob_xmod/` traps
(rc 133) under `-fsafe`; the in-bounds D5 repro still prints `9\n11\n22\nslice_index_field_store ok\n`;
all 8 dump-MD5 pins unchanged; corpus `1121 = 947/58/116/0/0` (the extra OK is the new repro);
stdlib 283/0; example matrix 25/25; runtime goldens byte-identical.

### 1.14 emitFieldAssign

Resolves field access for `.assign_field`:

| Base Type | Access Pattern |
|-----------|---------------|
| `slice_type` | `.ptr` (field 0), `.len` (field 1), `.f_<N>` (N>1) |
| `tagged_union_type` | `.tag` (field 0), `.payload.<variant-name>._<sub>` or `.payload` (field 1) |
| `ptr_type`/`many_ptr_type` → `struct_type` | `->field` |
| `struct_type` | `.field` (with array copy: `{ ... while(_j < len) { base.field[_j] = src[_j]; _j++; } }`) |
| `union_type` / `packed_union_type` | `.field` — the base-type dispatch gained a `union_type` branch mirroring the `struct_type` branch but scanning `un_items[payload_idx].fields_start` + `fe_items` for `field_id` (same array-copy handling). A union-typed base now emits `.member_name` like `store_field`'s ptr-base `->` emitter instead of falling through to the numeric fallback. Regression guard: `union_literal_nested_xmod`. |
| unknown | `.f_<field_id>` (numeric fallback) |

### 1.15 Helper Functions

**P5 predicates + promotion centralized (2026-10-12).** The emitter's private int-kind/signedness/width/scalar truth tables are DELETED (no dead copies left behind): `intKindIsSignedBase`, `intKindIsUnsignedBase`, `intKindWidthBytes` (the Task 2b3 D1-2 base trio), `classifyIntSignedness`, `intTypeNeedsWidthWrap`, `intTypeByteWidth`, `typeIsIntKind`, `retTypeIsScalarC`, `typeIsPtrKind`. Their canonical homes are `type_registry.zig` — `typeKindIsSignedIntBase` / `typeKindIsUnsignedIntBase` / `typeKindIntWidthBytes` / `typeRegistryIntSignednessClass` / `typeRegistryIntNeedsWidthWrap` / `typeRegistryIntByteWidth` / `typeRegistryIsIntKind` / `typeRegistryIsScalarC` (doc 03) — plus the pre-existing `typeRegistryIsPointer`, which replaces `typeIsPtrKind` (membership-identical for reachable tids; the tid 0/1/18 guards were redundant). Every emitter call site (`nestScalarEffTid`, `writeIntConstRvalue`, `getUnsignedCTypeName`, `getTempEffType`, `getTempTypeInfoResolve`, `printKindIsIntegerLike`, `nestShapeOk`, `emitHoistedDecls`, `emitFieldAssign`, `emitFlagOp`, …) now calls the canonical predicate; each caller's own membership extras are preserved verbatim. `emitBinRvalueText`'s mixed-sign C usual-arithmetic promotion block is relocated verbatim to `coercion.zig` `coercionUsualArithPromote` (doc 05): `emitBinRvalueText` now delegates the promotion decision to `coercion` and keeps only emitter glue — `getTempEffType` temp→type resolution plus `getCTypeName` cast-name minting (at most once per op, same branch as before; `D6:` markers unchanged).

| Function | Purpose |
|----------|---------|
| `getBinOpStr` | Maps binary op u8 → C operator string (+, -, *, /, %, &, \|, ^, <<, >>, ==, !=, <, <=, >, >=) |
| `getUnOpStr` | Maps unary op u8 → C operator string (-, !, ~) |
| `getCheckedCastFnName` | Maps TypeId → checked cast function name (std_checked_cast_i8/u8/i16/u16/i32/u32/i64/u64) |
| `getPrintFnName` | Maps TypeId → **mangled C name** of the fmt printer: infers `printFnSourceName` then mangles it (`nameManglerMangle` kind 0) against `emitter.std_fmt_module_id`; when that id is absent (`0xFFFFFFFF`) it falls back to the unmangled source name. |
| `printKindIsIntegerLike` | Task 2: true for fixed ints, arbitrary-width ints, `c_char`, `enum`, `integer_literal` — the kinds the width/signedness dispatch routes (everything else keeps an explicit arm or the defensive `printI32` fallback). |
| `printFnSourceName` | Maps TypeId × specifier → the `std.fmt` SOURCE name. Task 2 width/signedness dispatch: integer-like kinds (`printKindIsIntegerLike`) route via `typeRegistryIntWidthBits`/`typeRegistryIntIsSigned` → `printU32`/`printI32` at ≤32 bits, `printU64`/`printI64` at 33..64, and the matching `printHex*` for `{x}` (Z98 `usize` is 32-bit unsigned). Final-review fix wave: an untyped `integer_literal` argument is materialised by lowering into its value-chosen carrier (`lowerPrintArgExact`), so the `integer_literal` 32-bit signed arm below is only the non-folded fallback (mostly builtin results). Non-integer arms unchanged: `printF64` (`f32_type` too — the `float`→`double` widening is implicit via the `void printF64(double)` prototype), `printBool`, `printChar` (u8 `{c}`), `printStr` (slice), default `printI32` (defensive; Task 3 rejects those arguments). |
| `printAggKind` / `aggPrinterName` | Task 4: true for struct/union/tagged_union/tuple/packed_union; the generated static C printer name (`z98_printStruct_<tid>` etc.; see §1.18). |
| `emitGeneratedPrinters` / `collectPrintRoots` / `emitAggPrinterRec` / `emitAggPrinterDef` / `emitAggValue` | Task 4: per-module scan for `.print_val` aggregate roots, dependency-first deduped emission, and the printer body (fields/tag-switch/packed extraction/depth-1 recursion). |
| `emitTupleType` / `emitNeededTupleTypes` | Task 4: the tuple `typedef struct { _0, _1, ... }` C model and the needed-tuple emission pass (end of both type-emission paths). (`collectNeededTuples` — the hoisted-temp/global collector — moved to `type_resolver.zig`, P4 fix round 2.) |
| `aggAccessAppend` / `aggAccessAppendIndex` / `aggIndentStmt` | Task 4 helpers: `v.field` / `v._N` access-string builders, printer-statement indentation (packed-field scratch names now `nm_mod.nameManglerMintIndexName(mangler, "zT_pkf", idx)` — P1). |
| `zigPrintNameAppend` / `zigNamePut` / `zigNamePutU32` / `zigNamePutQuals` | Task 6: Zig 0.15.2 `@typeName` renderer for a pointer child (exact Z98-expressible space; named enum/struct/union components return false, i.e. the `error[3063]` named-composite residual). `kZigPrintNameCap = 512` (Task 8 B2: the validator mirrors this budget byte-for-byte incl. the trailing `@`). Kept in lockstep with `lower.zig` `printFmtPointeeNameOk`. |
| `emitPtrValuePrint` / `emitPtrValueExpr` | Task 6: one pointer value's print dispatch — pointee aggregate/tuple/packed → the generated aggregate printer with `*(value)` (depth unchanged at top level, `d - 1` as a field); pointee enum → the Task-5 name printer; else inline `std_print("<name>@")` + `printHexU64((unsigned long long)(unsigned int)(value))`. `emitAggValue` routes pointer/many-pointer FIELDS here, `.print_val` routes top-level ones (`is_top`). Task 8 (B2): a `zigPrintNameAppend`/`zigNamePut` failure is a `@panic` (was a silent no-op). |
| `emitFloatHexHelper` | Task 6: emits the on-demand `static void z98_printFloatHex32(float)` / `z98_printFloatHex64(double)` C89 hex-float (bit-for-bit Zig's `printFloatHex`, no precision option; the decimal exponent goes through the existing mangled `std.fmt.printI32`). Rooted by `collectPrintRoots` flags `need_fhex32`/`need_fhex64`. |
| `emitTypeDefOnce` / `emitTypeDeps` / `emitPointeeDep` / `emitDepMember` | Task 6: shared gated/bare type-definition writer (refactored out of the four special-types sub-passes) plus the pointer-pointee dependency emission that fixes "typedef used before emitted" for a pointer member's pointee C type (fn-pointer/enum/error-set/optional/slice/array/packed/ptr-chain); dedup via the pass's `seen` map. Task 8 (B3): `emitPointeeDep`'s depth cap is 16, one cap shared with `zigPrintNameAppend` and the validator. |
| `c89NeedsEmitEdge` → `typeNeedsFullDef`/`typeRefs` (P2) | Task 6 added `fn_type` as a value-embedding dependency edge; P2 replaced the whole predicate with the single relation in `type_registry.zig` (which also covers `fn_type` return/param refs — the D8 defect — `packed_union`, and pointer chain-leaf name refs). |
| `emitCStringLiteral` | Emits C string literal with escape sequences (\n, \t, \r, \\, \") |
| `resolveTempName` | Resolve temp_id → C name. Checks local flat lookup first (fl_temps), falls back to `nm_mod.nameManglerMintTemp` |
| `getTempTypeByIndex` | Read the recorded `TempDecl.type_id` for a temp_id (P6: pure record read — the `getTemp*`/`hoisted*` re-derivation fallbacks, incl. `getTempEffType`'s written-type write-scan and `getTempTypeInfo`'s cross-temp chain, are deleted) |
| (`name_mangler.zig`, P1) `nameManglerMintTemp` / `nameManglerMintLocal` / `nameManglerMintField` / `nameManglerMintMember` | `zT_<temp_id>` / raw-keyword-escape-per-scope mints (moved out of the emitter — see §1.3) |
| (`name_mangler.zig`, P1) `writeHex` / `isTempOrBuiltin` / `isC89Keyword` | Moved mangler internals (hex hash writer; `__tmp`/`__ret`/`__bootstrap` bypass; keyword test) |
| `dbgPrintU32` | Debug: write u32 to stderr |
| `aggregateKeyword` | Single source of the `struct `/`union ` keyword for named aggregates (struct/tagged_union → `struct `, union/packed_union → `union `) |
| `ctypeGuardWrite` | Writes the `ZIG_<TAG>_` include-guard prefix for a type kind |
| `emitCallConv` | Writes `Z98_STDCALL ` for a `stdcall` function |
| `emitCalleeExpr` | Writes a callee expression, casting a stdcall callee to its `FS_...` fn-pointer typedef |
| `findCalleeFnTypeId` (P6: DELETED) / `tempFnTypeId` | The callee fn-type id is now a lowering-recorded fact on `CallDirectData`/`TailCallData` (`fn_type_id`); `tempFnTypeId` still unwraps a fn-pointer temp for `func_ref` |
| `moduleQualifiedName` | Computes the `DIR/<basename>_<FNV1a8>` output stem for a module |
| `emitSupportFiles` / `emitBuildScripts` | Write the self-contained support files and companion build scripts (§6) |
| `openSupportOutputFile` | Opens `DIR/<name>` for writing; aborts on path overflow / open failure |
| `emitPackedStoreBitfield` / `emitPackedLoadBitfield` | Shift/mask read/write of a packed bitfield through a byte carrier |
| `emitSatBinary` | Saturating add/sub/mul/shift for arbitrary-width ints — P6: SPELLS ONLY from the lowering-carried `result_type`/`width`/`is_signed` (the emit-time width/signedness derivation is gone) |
| `emitWrapOp` / `emitWrapNeg` / `emitFlagOp` | `-fsafe` wrapping (`zig_wrap_*`) and overflow-flag (`zig_overflow_flag_*`) emission |
| `emitValueExpr` / `nestEmitDefRvalue` / `nestEmitBinExpr` / `nestEmitUnaryExpr` | Recursive expression-nesting renderer (emission-core compaction) |
| `dceResultPos` / `dceMarkAllReads` / `dceMarkAllWritten` / `dceReleaseOperands` | Dead-temp DCE marking |
| `isDeadLocalName` | True when a local name is never read (skip its declaration) |
| `emitBuildTargetSh` / `emitBuildTargetBat` / `emitBuildOwcBat` | Companion build-script bodies (`emitBuildScripts`) |

### 1.16 Marker Reference

| Marker | Location | Meaning |
|--------|----------|---------|
| `C` | emitModule | Start of C89 emission phase |
| `FINAL_FLUSH` | main.zig | Final buffer flush, emission complete |
| `FL:p` | bufferedWriterFlush | Flush start (pos value) |
| `FE:p` | bufferedWriterFlush | Flush end (0) |
| `E2A:t` | emitSpecialTypes sub-pass 2a | Processing type in pointer-only pass |
| `E2B:t` | emitSpecialTypes sub-pass 2b | Processing type in value-embedding pass |
| `D2:t` | emitSpecialTypes 2b | Debug: tagged union type in sub-pass 2b |
| `D6:t` | `type_registry.typeCName` (P3) | C-name lookup debug — fires for every `tid>=20` derivation query (very noisy; `g_markers_debug`-gated, absent from `--markers` captures) |
| `ET:t` | emitTypeDefinition | Emitting type definition (tid + kind) |
| `ES:n` | emitStructType | Struct type emitted (mangled name id, read from the `c_name_map` memo — pure reader since P3) |
| `FE:` | emitStructType | Field entry detail (name_id:type_id) |
| `FWD:n=` | emitFunctionSignature | Forward decl detail (name_id, module_id) |
| `HTT:` | emitHoistedDecls | Hoisted temp type tracking (temp_id, type_id) |
| `P0:` | emitHoistedDecls | Parameter/local count |
| `P1:` | emitHoistedDecls | Local decl discovery (temp, type_id, name_id) |
| `P2:` | emitHoistedDecls | Final local count |
| `P3:` | emitHoistedDecls | Assign propagation (dst, src, type) |
| `D4:` | emitHoistedDecls | Type propagation debug summary |
| `D7:` | emitHoistedDecls | Written type detail |
| `D9:` | emitHoistedDecls | Call-result type (type 2) detail |
| `RST:t` | resolveTempName | Temp resolution (temp_id → name_id) |
| `I` | emitInst | Instruction start |
| `BIN:` | emitInst (.binary) | Binary inst debug (dst, lhs, rhs) |
| `BNR:` | emitInst (.binary) | Binary name resolution lengths |
| `ASX:` | emitInst (.assign) | Assign debug (dst, src) |
| `AS:t` | emitInst (.assign) | Assign type lookup |
| `AIDX:` | emitInst (.assign_index) | Index assign debug (base, index, src) |
| `AFE:` | emitInst (.assign_field) | Field assign debug (base, field_id) |
| `LFD:` | emitInst (.load_field) | Load field debug (base, result) |
| `LFU:` | emitInst (.load_field) | Load field unresolved (field_id) |
| `LL:` | emitInst (.load_local) | Load local debug (name_id, result) |
| `LLd:` | emitHoistedDecls (.load_local) | Load local type debug |
| `STL:` | emitInst (.store_local) | Store local debug (name_id, value) |
| `STN:` | emitInst (.store_local) | Store local name=value |
| `DC2:` | emitInst (.call_direct) | Direct call debug (name_id, result) |
| `AD:` | emitInst (.call) | Call arg count |
| `INSTA:` | emitInst | Instantiation detail (optw, optt, optu, tulf, eup, euc) |
| `INSTC:` | emitInst (.binary) | Constant RHS |
| `VFLOW:` | emitInst | Variable flow tracking (cdv, ldv, spv, rnt, dlt, ehd, ehdv, ehdd, opV, oTV) |
| `WRAP:main` | emitModule | main() wrapper emitted |
| `GAPC:` | emitInst | Gap check markers (coe, cos) |
| `JXP` | emitInst (.jump) | Jump instruction |
| `MTP:ti` | emitHoistedDecls | Type 1 (void) temp skip |
| `T4U:` | emitFunctionBody | Type 4 (?) temp declaration in body |
| `INSTB:` | emitFunctionBody | Instance temp body |
| `DxA:` | emitFunctionBody | Duplicate local skipped |
| `DLD:s` | emitFunctionBody | Dead local name skipped |
| `BFN:p` / `BFX:p` | emitFunctionBody | Function-body buffer position (start / end) |
| `HT:` | emitHoistedDecls | Hoisted-temp declaration detail (temp, type, eff-type, written) |
| `ESTA:` / `ESTB:` | emitSpecialTypes | Synthetic type with `name_id==0` skipped (2a / 2b) |
| `NUL:TYnul` | `type_registry.typeCName` (P3) | `null_type` → `"int"` fallback |
| `UCT:r` | emitInst (.poison_init) | `-fsafe` poison-fill result temp |
| `DBGFNPTR:t` | emitHoistedDecls | Fn-pointer effective-type resolution detail |

### 1.17 Multi-Module Emission (`--output-dir`)

With `--dump-c89 --output-dir DIR` (or `-o DIR`), `phase_C89Emission` switches from the single
stdout stream to **per-module file emission**. Output set: `DIR/<qualified>.c` (one per module) +
`DIR/<qualified>.h` (one per module) + `DIR/zig_special_types.h` + the self-contained support
files/scripts (§6). The stdout single-file path (§1.10) is kept for bare `--dump-c89`; the two
paths are branched on the CLI, never mixed.

- **Qualified filename scheme (F-S7)** — output stems come from `moduleQualifiedName`:
  `DIR/<basename clamped 64>_<FNV1a8>.c/.h`, where `<basename>` is the module path's last `/`
  component with `.zig`/`.z98` stripped (clamped to 64 chars) and `<FNV1a8>` is the
  8-uppercase-hex FNV-1a hash of the full module path (`hash_mod.fnv1a` + `writeHex`). No
  module_id in the filename, so two same-basename deps get distinct `.h`/`#include` lines.
- **Length guard** — before constructing each path, the emitter checks
  `od.len + 1 + base.len + 3 > 511`; if exceeded, `error: output filename too long` +
  `pal.exit(1)`.
- **Shared header** — `emitSharedHeader` emits
  `zig_special_types.h` with file guard `ZIG_SPECIAL_TYPES_H`, preamble
  `#include "zig_compat.h"` + `#include "zig_runtime.h"`, the error-code prologue, a
  fwd-decl pass (`typedef <struct|union> X X;` for every named struct/tagged_union/union, keyword
  from `aggregateKeyword(kind)`, so bare unions forward-decl `typedef union X X;` matching their
  definition), sub-pass 2a restricted to `shared_set` (guarded), and all of sub-pass 2b.
  **P4:** the shared group is the resolver classification's `shared` map (doc 03) — seeds
  synthetics (`name_id==0` in slice/optional/error_union/error_set/
  tagged_union/union/array/fn_type) ∪ value-embedding named types (CLS:v, `pointer_only_map`
  miss) ∪ i64/u64/f64 ∪ named fn_type ∪ (emission-time) unnamed needed tuples, then closes over
  pointer-only named types referenced by shared members (fixpoint over `reg.types_len`, via
  `typeRefsContains`). The former emitter `computeSharedSet` is deleted; the completion
  (`type_resolver.classifyTypeEmissionFinalize` — needed-tuple seed + full-registry walk +
  closure) runs at the pre-emit `phase_EmissionClassification` boundary (**P4 fix round 2**;
  `emitTypePasses` retains ZERO classification calls). Packed structs and
  `packed_union` skip the fwd-decl pass (their carrier typedef is complete).
- **Closure-edge model (F-S8)** — a type joins `shared_set` when it is referenced **by value OR
  in a way that requires the C type name in scope** (typedef'd kinds — enum/error_set — need the
  name in scope even behind a pointer/slice, since a typedef cannot be implicitly
  forward-declared like a `struct` tag). `c89NeedsEmitEdge` admits enum/error_set targets;
  `tstIsDep`/`tstEdgesCount`/`tstEdgesFill` have optional_type/slice_type/union_type source
  branches. The optional/slice edges are **restricted** to enum/error_set element targets
  (prevents the recursive-slice 2-cycle hazard); `union_type` is unrestricted (by-value fields).
- **Guard scheme** — every type definition is wrapped
  `#ifndef ZIG_<TAG>_<cname> / #define ZIG_<TAG>_<cname> / <def> / #endif`. Tag from
  `ctypeGuardWrite`: `ZIG_STRUCT_`, `ZIG_UNION_` (union + packed_union), `ZIG_ENUM_`,
  `ZIG_ERROR_SET_`, `ZIG_SLICE_`, `ZIG_OPTIONAL_`, `ZIG_ERRORUNION_`, `ZIG_ARRAY_`, `ZIG_FNPTR_`,
  `ZIG_I64_`, `ZIG_U64_`, fallback `ZIG_TYPE_`.
- **Per-module `.h`** — `emitModuleHeaderFile`: module guard
  `ZIG_MODULE_<UPPER(qualified)>_H` (qualified stem uppercased, non-alnum → `_`; the path hash
  makes guards auto-unique); includes `zig_compat.h` + `zig_special_types.h`, the module's own
  `@cInclude` directives (per-module, NOT the global `cincludeUnionAll` union), stdarg/builtin
  includes gated on use, each dependency's `.h` by its **qualified** name (value-ref deps ∪
  import edges, skipping self), owned CLS:p type full-definitions, fn fwd-decls (non-extern),
  storage global `extern` decls, and type-storage global `extern` decls.
- **Per-module `.c`** — `emitModuleFile`: `#include "<qualified>.h"`, stdarg/builtin includes,
  global definitions, then the module's own fn bodies (externs skipped; `switch_cases`/
  `dl_hoisted` reset per fn, `lirOptRun` per fn). The `int main(void)` wrapper is emitted only
  for `module_id==0`'s public `main` (`emitMainWrapper`).
- **Companion build scripts are live** — `emitBuildScripts` (called from `phase_C89Emission`)
  writes `build_target.sh` always, plus `build_target.bat` (MSVC `cl`) and `build_owc.bat`
  (OpenWatcom `wcc386`/`wlink`) when the target is Windows; see §6.1. The old claim that the
  `emitBuildTarget*` templates are dead code no longer holds.
- **Module pruning — needed-only std.** Only modules in the value-reference reachability set are
  emitted and listed by the scripts; see §6.2. This is what makes a stdio-only `@import("std")`
  program emit no `std_net` and link without `-lwsock32`.
- **Module→file emission loop — no silent drop.** The multi-module branch loops
  `moduleRegistryGetModules` and, for each registered reachable module, emits one `.h` and one
  `.c`; every reachable module is emitted. (`mod_silent_drop_xmod` is kept as a regression guard
  for the false "silent module drop" theory.)
- **Orphan-module handling** — a `.zig` file with no incoming `@import` edge is never added to the
  module registry (`moduleRegistryResolveImports` enqueues only via import edges), so un-imported
  files are never emitted. Correct behavior, not a defect.
- **Known Issues (fixed):**
  - **Cross-module enum-literal comparison (I3) — FIXED.** A cross-module qualified enum literal
    (`json.JsonValueTag.Null`) resolved to `TYPE_VOID`, emitting an undeclared temp
    (`'zT_XX' undeclared`). Fixed by adding an `enum_type` member-literal case to the generic
    base-type field-access dispatch in both `semanticAnalyzerResolveFieldAccess` and `lower.zig`
    (Option A). Regression guards: `zT_missing_fwd_xmod`, `json_parser_workaround`.
  - **Cross-module tagged-union `==` / member-literal SEGV (I6) — FIXED.** A tagged-union member
    literal reached `typeRegistryGetStructFields` on a TU `payload_idx`, a garbage read → SEGV.
    Fixed by a `tagged_union_type` case in the generic field-access dispatch
    (`emitTaggedUnionInit`). Separately, BIN_EQ/BIN_NE on `tagged_union_type` operands now append
    `.tag` to each operand, so union `==` emits `s.tag == t.tag` (valid C; per operator ruling
    m0471, zig1 supersedes the zig0 oracle's rejection). Regression guard:
    `tagged_union_cmp_xmod`.
  - **Runtime-symbol gap (json_parser) — FIXED (std.arena migration).** `arena_alloc_default`
    was missing from `sf/src/include/zig_runtime.c`; resolved by the Zig-side `sf/src/std_arena.zig`
    module (`Arena{data,capacity,used}` over a static buffer) imported by the examples, removing
    the extern. Regression guard: `extern_runtime_symbol_xmod`.

### 1.18 Generated aggregate printers (Task 4, z98-print-formatting)

`{}` on `struct`/`union`/`tagged_union`/`packed_union`/`tuple` has no `std.fmt`
primitive (Z98 has no generics), so the emitter generates one `static` C printer
per printed aggregate type and `.print_val` calls it. Output matches Zig
0.15.2's `Io.Writer.printValue` aggregate arms byte-for-byte, including its
recursion cap (`std.fmt.default_max_depth = 3`, `kPrintAggMaxDepth`): a nested
aggregate at `d == 0` prints `.{ ... }`, and an untagged auto union always
prints `.{ ... }` (Zig never reads an untagged field).

- `aggPrinterName` → `z98_printStruct_<tid>` / `z98_printUnion_` /
  `z98_printTaggedUnion_` / `z98_printPackedUnion_` / `z98_printTuple_` (the
  `z98_` prefix avoids collision with `extern` source names).
- `collectPrintRoots` scans the module's fn slots for `.print_val` aggregate
  types; `emitGeneratedPrinters` (called from `emitModule`/`emitModuleFile`
  before the fn bodies) emits each root and its nested aggregate fields
  dependency-first, deduped. No forward declarations are needed; `static` makes
  cross-module duplicates safe.
- `emitAggPrinterDef` emits `static void <name>(<CType> v, int d)`: named fields
  as `v.<field>`, tuple elements as `v._<i>`, tagged unions as
  `switch (v.tag) { case <field-index>: ... v.payload.<field>._0; ... }` (Z98
  tagged unions always carry integer tags), packed struct/union fields via
  `emitPackedLoadBitfield` into declared scratch locals. Scalars route through
  `getPrintFnName(..., 'd')`; nested aggregates call their printer with `d - 1`.
  The emitted literals are Zig's exact separators (`".{"`, `" .a = "`,
  `", .b = "`, `" }"`; tuple `" "`/`", "`; packed-union `".{ "`/`", "`; tagged
  `".{ ."`/`<name>`/`" = "`).
- **Tuple C model**: `getCTypeName` gives tuple types a stable `Tup_<tid>` name
  (the generic `name_id==0` fallback would collapse every tuple onto the
  empty-name mangle); `emitTupleType` emits
  `typedef struct { <e0> _0; ... } <cname>;`; `ctypeGuardWrite` uses
  `ZIG_TUPLE_`; `tstEdgesCount`/`tstEdgesFill`/`tstIsDep` gained tuple element
  arms. Tuple typedefs are emitted ONLY for `C89Emitter.needed_tuple_set`
  (runtime hoisted temps / globals, collected at the pre-emit
  `phase_EmissionClassification` boundary by
  `type_resolver.collectNeededTuples` — P4 fix round 2 (was mid-`phase_C89Emission`);
  `emitNeededTupleTypes` runs at the end of
  `emitSpecialTypes` / `emitSharedHeader`): registry-only print-args tuples must
  not add C, or the 4-MD5 single-file dumps move. Needed tuples also join
  the shared group (**P4**: via `classifyTypeEmissionFinalize`) so the closure
  promotes pointer-only named element types into the
  shared header (definition-before-use).

### 1.19 Generated enum / error-set name printers (Task 5, z98-print-formatting)

`{}` on an enum prints `.member` and on an error set `error.Name` (explicit
enum `{d}`/`{x}` keep the numeric route; explicit error-set specs reject
`error[3013]`). There is no std.fmt primitive for this and `std_fmt.zig` must
not change (the dump carries the reachable std_fmt module C in full, so a new
function moves the four pinned 4-MD5 dumps), so the emitter generates one
`static` name-table printer per printed type:

- `namePrinterName` → `z98_printEnum_<tid>` / `z98_printErrorSet_<tid>` (shared
  `nm_mod.nameManglerMintIndexName` prefix+id builder; `printNameRouteKind` is the kind predicate).
- Static tables: `z98_etab_<tid>` = the concatenated member/tag name bytes,
  `z98_eoff_`/`z98_elen_` = per-entry byte offset/length, `z98_eval_` = the
  member values as `unsigned long long` (enums) or `z98_escode_` = the global
  `error_code_registry` codes as `int` (error sets). `emitNameBlob` /
  `emitNameOffLen` write them; `emitU64Dec`/`emitI64Dec` are the digit writers
  (`itoa64` writes digits before the trailing NUL, so the slice excludes it).
- `emitNamePrinterDef` emits `static void <name>(<CType> v)`: a linear scan of
  the value/code array, then `.` / `error.` + `stdFmtSourceSymbol("printStr")`
  on the matching table entry. Fallbacks: `@enumFromInt(<decimal>)` (Zig's
  non-exhaustive form; exhaustive-invalid is Zig UB) and `error.UnknownError`.
- `emitNamePrinterRec` is the deduped per-type emitter; `emitFieldPrinterRec`
  roots an aggregate's enum/error-set fields (non-packed), and
  `collectPrintRoots` roots top-level `.print_val`s only when `implicit != 0`.
  `emitGeneratedPrinters` dispatches each root to `emitAggPrinterRec` or
  `emitNamePrinterRec`.
- `stdFmtSourceSymbol` factors `getPrintFnName`'s mangling for an arbitrary
  source name (`printStr`), so the generated C calls the existing std.fmt
  function.

**Bounded residuals:** a packed enum/error-set aggregate field rejects
`error[3063]`; an enum member literal above u32 max truncates at the literal
(pre-existing sema `enum_value_table` `U32ToU32Map`; the runtime lookup is
exact).

### 1.20 Pointer / fn-pointer printers and float `{x}` hex-float (Task 6, z98-print-formatting)

`{}` on a pointer / fn-pointer, and float `{x}`, are the Task-6 surface.

- **Pointer `{}`** follows Zig 0.15.2's `Writer.zig:1337-1352` exactly (operator
  ruling R3: `T@<lowercase-hex>`, **no `0x`**):
  - `*struct` / `*union` / `*tagged_union` / `*tuple` / `*packed_*` delegates to
    the pointee's Task-4 generated printer with `*(value)` — depth is UNCHANGED
    by the pointer arm (top-level `kPrintAggMaxDepth`; aggregate field `d - 1`);
  - `*enum` delegates to the Task-5 `z98_printEnum_<tid>` name printer;
  - everything else (scalar/`void`/error-set/pointer/many/slice/array/optional/
    error-union/fn child) emits `std_print(<@typeName(child)> ++ "@")` followed
    by the EXISTING `std.fmt` `printHexU64` (cast `(unsigned long long)(unsigned
    int)`) — no new std_fmt function, so the 4-MD5 pins hold.
  - `zigPrintNameAppend` reproduces `@typeName` for the exact Z98 space
    (i8..i64/u8..u64/isize/usize/c_char/bool/f32/f64/void/noreturn, `uN`/`iN`,
    `error{A,B}` (comma, no space — `@typeName`'s error-set join), `?T`,
    `E!T`, `[]`/`[]const`, `[N]`, `*`/`[*]` + const/volatile quals, and
    `fn (p, ...) [callconv(.c)] ret`; `i64`/`u64`/`f64` keep their carrier names).
    **Task 8 (B2):** the renderer's fixed `kZigPrintNameCap = 512` buffer is
    mirrored byte-for-byte by the validator (`printFmtPointeeNameLen` incl. the
    trailing `@`), so an over-budget name (e.g. a >511-byte `error{...}`, or a
    many-param `fn (...)` name) rejects `error[3063]` at validation; a residual
    append failure is a `@panic` in `emitPtrValuePrint` — the value can never be
    silently dropped nor emit broken C.
  - **Named-composite residual:** a child name containing a NAMED
    struct/enum/union (`*?S`, `**S`, `*?E`) rejects `error[3063]` — Zig's
    `@typeName` container-qualifies those (`main.S`), which Z98 cannot
    reproduce. One-pointer-to-array `{}` stays 3013 (slice-delegate reject),
    `[*]T {}` 3013, byte-view `*const [N]u8 {s}`/`{x}` 3063 (Q3) — all Task-3
    validator decisions.
- **Aggregate fields:** Zig's aggregate arms print fields with `{any}` pointer
  semantics, so `printFmtAggFieldKindOk` and `emitAggValue` now route pointer /
  many-pointer / fn-pointer fields: `struct { p: *S }` → `.{ .p = .{ ... } }`,
  `struct { f: fn() void }` → `.{ .f = fn () void@addr }`, `[*]i32` field →
  `i32@addr` (`Writer.zig:1346-1352` + `printAddress`). A one-pointer-to-array
  field would print as a slice (`{ 1, 2, 3 }`) — the array/slice residual
  rejects the aggregate `error[3063]`. **Fix round 1 (review Critical 1):**
  delegation is a ONE-pointer rule; a many-pointer field is `printAddress`-only
  (`is_many` gate in `emitPtrValuePrint` + `printFmtPtrRouteOk`), so
  `[*]S`/`[*]E`/`[*]TU`/`[*]U`/`[*]PS` fields reject `error[3063]` (Zig prints
  the container-qualified `main.S@addr`) while `[*]i32` keeps `i32@addr`.
- **Type-dependency fix (pre-existing ordering defect):** a pointer member's C
  type IS its pointee's typedef (`*enum` → `E*`, `*fn` → the fn-pointer
  typedef), but the topological sort had no edge, so a value-shared type could
  be emitted before its pointee typedef (gcc `unknown type name`). `emitTypeDefOnce`
  (the four sub-pass bodies factored into one gated/bare writer) plus
  `emitTypeDeps`/`emitPointeeDep` now emit the referenced typedefs at the type's
  own emission site (recursing through ptr chains, optional/slice/array/eu
  payloads and fn; dedup via the pass's `seen` map, so a program whose order
  already worked is untouched). `c89NeedsEmitEdge` additionally treats
  `fn_type` as a value-embedding edge. **Task 8 (B3):** the walk's bail is the
  single 16 pointer-chain cap (`depth > 8` before), aligned with the validator
  and `zigPrintNameAppend`; pre-fix, a validator-accepted 10..14-wrapper chain
  emitted rc=0 C that referenced an unemitted wrapper typedef (gcc
  `unknown type name`). **Final-review Minor 3 correction:** beyond the print cap
  the ARGUMENT rejects `error[3063]` (e.g. a 16-wrapper `*A16`); a chain beyond
  the type resolver's own representation (a 17-wrapper declaration, pre-existing
  cap) fails earlier — the declaration does not resolve and the identifier
  reports `error[20] identifier '<name>' is not declared`, so no emission walk is
  reached.
- **Float `{x}`:** `Writer.zig:1572-1720` bit-for-bit (no precision option —
  Z98 has none): sign bit then `nan`/`inf`, zero `0x0.0p0`, denormals (exponent
  adjusted, no implicit bit), implicit-bit normalization, `mantissa_digits =
  (fractional_bits + 3) / 4` (13 for f64, 6 for f32 with the extra `<< 1`
  alignment), trailing-zero trim, `p` + decimal exponent. Emitted as static
  helpers `z98_printFloatHex32/64` on demand (`collectPrintRoots` sets
  `need_fhex32`/`need_fhex64`; `emitGeneratedPrinters` emits them before the
  printers/function bodies). The exponent prints through the existing mangled
  `std.fmt.printI32`. Verified against Zig 0.15.2 for `0x1.8p0`, `0x0.0p0`,
  `-0x0.0p0`, `0x1p1`, `-0x1p1`, `1/3` (`0x1.5555555555555p-2`, f32
  `0x1.99999ap-4`), `1e20`, a runtime-built denormal
  (`0x0.00000000316a2p-1022`), f32 `1e20`/max, and `inf`/`nan`.
  **Pre-existing literal residuals** (not the printer): Z98's float-literal
  parser underflows `5e-324` to `0.0` and is 1-2 ULP off on `1e-310`; `@bitCast`
  rejects an f64↔u64 pair — so the denormal fixture row is computed at runtime.

**Bounded residuals (Task 6, Zig-accepted / pre-existing):** composite pointee
names with a named aggregate (`*?S`, `**S`, `*?E`) reject `error[3063]`; a
MANY-pointer field to a named aggregate/enum/tuple/packed (`[*]S`, `[*]E`, ...)
rejects `error[3063]` (container-qualified `@typeName`; fix round 1 — only
`[*] <exactly-nameable child>` prints `T@addr`); a one-pointer-to-array field
rejects (slice residual); float-literal subnormals/ULP drift above;
`*const fn(...)` (the double-pointer spelling) remains the pre-existing
assignment anomaly.

**Task 7 closeout (2026-09-25):** the z98-print-formatting program is complete
(Tasks 1-6 landed, whole-set review done); the binding per-type route table and
the consolidated bounded-residual list live in
`docs/reference/Language_Spec_Z98.md` §4 "Formatted `print`". The dead
`emitZigRuntimeC`/`emitZigPalC` string mirrors were removed from `c89_emit.zig`
in the closeout cleanup commit (`emit_support.zig` is the only support-byte
source; `check_emit_support.sh` stays 7/7).

---

## 2. `cinclude.zig` — @cInclude Dedup (32 lines)

### Function

`cincludeUnionAll(module_reg, alloc)`:

```
cincludeUnionAll(module_reg, alloc) → []u32:
  1. temp = u32ArrayListInit(alloc)          ← result accumulator
  2. hint = Σ module.c_includes.len          ← capacity hint
  3. seen = u32ToU32MapInitCap(alloc, hint)  ← dedup tracker
  4. For each module in moduleRegistryGetModules(module_reg):
     a. For each c_include name_id in module.c_includes:
        i. If seen[ name_id ] exists → skip duplicate
        ii. Else: seen[name_id] = 1, append name_id to temp
  5. Return temp slice
```

This produces a flat deduplicated list of all `@cInclude` directives across all modules. Used by
`emitModuleHeader` to emit `#include` lines for the stdout single-file path. In the multi-module
path (§1.17), `emitModuleHeaderFile` does NOT use the global union — each module `.h` emits its
own `c_includes` directives directly (per-module `@cInclude`), so a directive only appears in the
header of the module that declared it.

### Struct — ModuleEntry Fields Touched

From `module_registry.zig`: `ModuleEntry` contains `c_includes: U32ArrayList` — a list of interned
name_ids for `@cInclude` strings.

---

## 3. `name_mangler.zig` — The minting authority [updated: 2026-10-12 — P1]

Revived (P1) as the **single C-identifier minter**. Contains the `NameMangler` struct and every
mint helper (moved verbatim from `c89_emit.zig` where they previously lived): `nameManglerInit`,
`nameManglerMangle`, `nameManglerMangleGlobal`, `writeHex`, `isTempOrBuiltin`, `isC89Keyword`,
`mangleC89Keyword`, `nameManglerPopulateKeywords`, plus the per-kind mint API of §1.3
(`nameManglerMintLocal`/`MintField`/`MintMember`/`MintTemp`/`MintSyntheticType`/`MintIndexName`/
`MintModuleStem`, `nameManglerFnScope`). The emitter's `c89_emit.zig` keeps 4 thin `pub`
forwarders (`NameMangler`, `nameManglerInit`, `nameManglerMangle`, `nameManglerMangleGlobal`) as
its external compatibility surface and calls `nm_mod.*` at every mint site; no minting logic
remains in the emitter (Fix round 1 truth-up: the `.undefined_const` array-of-struct zeroing path
`emitFlagOp` had 4 raw `stringInternerGet(sfe.name_id)` struct-field reads — routed through
`nameManglerMintField(mangler, sfe.name_id, uap.elem)`; post-fix the only raw name reads left in
the emitter are printer DISPLAY labels (`std_print` string literals, source names by design),
prefixed macro composites (`zTU_*`, enum/error tag macros — keyword-safe by construction), and the
`is_extern` source-name overrides (hard boundary) — none of which mint a listed-category C
identifier). Consumable from outside the emitter (P6 lowerer). The dead 7-line counter
stub this file used to be is gone. See §1.3.

---

## 4. Data Flow

```
Function-slot list (per module, spill-backed)
    │
    ▼
emitModule(...)
    │
    ├─ classification maps (pointer_only_map/needs_def_map/shared_set) loaded at c89EmitterInit (P4)
    ├─ tstTopologicalSort (Kahn) ← TypeRegistry (edges from type_registry.typeRefs, P2)
    ├─ emitErrorCodePrologue
    │
    ├─ emitSpecialTypes (type headers, topological order)
    │   ├─ Forward decls (typedef struct X X;)
    │   ├─ Pointer-only type definitions
    │   └─ Value-embedding type definitions
    │
    ├─ emitModuleHeader (includes + fn forward decls)
    │   └─ cincludeUnionAll → deduped #include lines
    │
    ├─ emitGlobalDecls (storage globals)
    │
    ├─ For each function:
    │   ├─ lirOptRun (LIR optimization pass)
    │   ├─ emitFunctionSignature → "return-type name(params) {"
    │   ├─ emitHoistedDecls → local temp variables (+DCE/nest/poison)
    │   └─ emitFunctionBody:
    │       ├─ decl_local hoisting (dedup, dead-name skip)
    │       └─ Basic blocks w/ emitInst
    │
    └─ emitModuleFooter → "/* EOF */\n"
            │
            ▼
        stdout (via BufferedWriter 4KB)
```

### Arena Usage

| Arena | Usage |
|-------|-------|
| Scratch (`alloc`, reset per function) | Type-propagation arrays (`d4_wtype`, `d4_wflag`, `d4_t2p`, `d4_dead`, `d4_local`, `d4_nodecl`, `d4_lread`), block-label flags (`bb_used`), nesting array (`nest_inl`), per-function DCE maps |
| Persistent (`persist_alloc`) | `C89Emitter` maps (`emitted_type_set`, `fwd_decl_set`, `reachable`, `temp_global_map`, `ts_ref_set`), `NameMangler` maps (cache, keyword_set, collision maps), `dedup_names`, `fl_name_ids`, `fl_temps` |
| Permanent (`permanent`) | **P4:** the classification maps (`pointer_only_map`, `needs_def_map`, `shared_set`) — allocated by `classifyTypeEmissionGroups`, loaded into the emitter at `c89EmitterInit` |

The multi-module path additionally writes into `DIR` via a per-file `BufferedWriter` plus the
`emit_support.zig` support files and companion build scripts (§6).

---

## 5. Debugging

### Marker Activation

Run compiler with `--markers` to emit phase trace to stderr:
```
$ zig1 --markers source.zig
C            ← Phase 8 start
FL:p<pos>    ← Buffer flush (Writes to stdout)
FE:p0        ← Flush done
...
FINAL_FLUSH  ← Emission complete
```

### C89 Output Comparison Against zig0

zig0 has `--dump-c89` flag that outputs its generated C89. zig1's output using the same input can be diffed:

```
$ zig0 --dump-c89 source.zig > /tmp/zig0.c 2>/dev/null
$ zig1 source.zig > /tmp/zig1.c
$ diff /tmp/zig0.c /tmp/zig1.c
```

Differences are expected due to:
- Name mangling scheme differences
- zig0 may emit dead code zig1 optimizes out
- zig0 works around C89 portability issues differently

### Type Emission Debug

Markers `D2:t`, `E2A:t`, `E2B:t`, `ET:t`, `ES:n`, `FE:` trace type emission order. Check that types are emitted before they are used in function bodies.

### Temp Type Propagation Debug

Markers `P0:`-`P3:`, `D4:`, `D7:`, `D9:`, `HTT:` show the type resolution for each hoisted temporary. `D7:` shows resolved type vs hoisted type. `D4: MISMATCH` indicates a type mismatch between hoisted and resolved type.

### Common Issues

- **Undefined C89 identifiers**: Check type emission order (topo sort). Forward declarations sufficient for pointer-only types.
- **Identifier too long**: 31-char C89 limit enforced in `nameManglerMangle`. Verify truncated names are still unique.
- **Collision warnings**: `collision_mod` map catches duplicate mangled names. Counter suffix appended automatically.
- **Missing main wrapper**: Check `func.is_pub == 1` and name is exactly `"main"`.
- **C89 keyword conflicts**: `isC89Keyword` + `mangleC89Keyword` adds `z_` prefix.

---

## 6. `emit_support.zig` — Self-Contained Output Support

`emit_support.zig` is the hand-written support-file emitter for the C89 backend. It holds
the canonical bytes of the compiler's runtime/platform support files as Z98 string
constants and writes them into the user's output directory, so the emitted tree is
self-contained (`-I .` + compiling every emitted `.c`). The canonical single sources of
truth on disk are `sf/src/include/zig_compat.h`, `zig_runtime.h`, `net_prelude.h`,
`std_os_prelude.h`, `std_time_prelude.h`, `zig_runtime.c`, `zig_pal.c`, and
`sf/src/c_exit.c`; `scripts/check_emit_support.sh` asserts emitted == canonical
byte-for-byte.

| Function | Writes |
|----------|--------|
| `emitZigCompatHSupport` | `zig_compat.h` (C89 compat typedefs incl. FX14 `Z98_ALIGN8` on `z64`/`zu64`/`f64`, `bool`, `NULL`, `Z98_STDCALL`) |
| `emitNetPreludeHSupport` | `net_prelude.h` (target-neutral Winsock/libc net include prelude + `_os` aliases) |
| `emitStdOsPreludeHSupport` | `std_os_prelude.h` (target-neutral OS include prelude) |
| `emitStdTimePreludeHSupport` | `std_time_prelude.h` (target-neutral time include prelude + monotonic probe) |
| `emitCExitCSupport` | `c_exit.c` (`void c_exit(int)`) |
| `emitZigRuntimeHSupport(writer, safe_checks)` | `zig_runtime.h` (PAL/print/checked-cast declarations; `-fsafe` adds poison + overflow/checked-cast helpers) |
| `emitZigRuntimeCSupport(writer, safe_checks)` | `zig_runtime.c` (runtime bodies; `-fsafe` adds `zig_poison_fill`) |
| `emitZigPalCSupport` | `zig_pal.c` (PAL: file I/O, printing, `pal_trap`, `pal_i64_to_str`/`pal_u64_to_str`/`pal_f64_to_str`, `pal_get_default_lib_path`) |

`emitSupportFiles` (`c89_emit.zig`) drives the writes through `openSupportOutputFile`
(fixed 512-byte path buffer; `error: output filename too long` + exit on overflow,
`error: cannot open output file` on open failure). It always writes `zig_compat.h`,
`zig_runtime.h`, `zig_runtime.c`, `zig_pal.c`, and `c_exit.c`. The three preludes are
**conditionally emitted**: `net_prelude.h` only when some reachable module's
`c_includes` names `<net_prelude.h>` (`scriptNetEmitted`), and likewise
`std_os_prelude.h` / `std_time_prelude.h` via `scriptStdOsEmitted` / `scriptStdTimeEmitted`.
Self-contained output means present iff referenced, so a stdio-only program carries no
net/OS/time prelude and needs no winsock link.

The `emitZigRuntimeC`/`emitZigPalC` dead stale mirrors were **removed** from
`c89_emit.zig` at the print-formatting plan closeout (Task 7, 2026-09-25); the live
bytes come from `emit_support.zig` only.

### 6.1 Companion build scripts

`emitBuildScripts` writes companion build scripts into the output dir, enumerating the
compiler-known emitted `.c` set (reachable module stems first, runtime sources
`zig_runtime.c`/`zig_pal.c`/`c_exit.c` last — deterministic link order) and passing
`-I .`. `build_target.sh` is emitted always; `build_target.bat` (MSVC `cl`) and
`build_owc.bat` (OpenWatcom `wcc386`/`wlink`) only when the target is Windows. Each adds
the winsock library (`-lwsock32` / `wsock32.lib` / `library wsock32`) **iff** a
`net_prelude.h` c-include was emitted. The scripts carry a warning policy comment (no
warnings-as-errors in `build_target.sh`; `/WX` and `/we` documented as removable in the
MSVC/OW scripts). The `emitBuildTarget*` functions are now live (previously dead
templates); `emitBuildScripts` is invoked from `phase_C89Emission`.

### 6.2 Module pruning in emission

`phase_C89Emission` computes a **value-reference reachability set** (`emitter.reachable`,
`emitter.prune_active`) from the root module: module-level LIR value references
(`call`/`call_direct`/`tail_call`/`func_ref`/`load_global`/`store_global` owning modules),
runtime-init roots, and by-value global type owners — not mere `@import`/re-export edges.
Only reachable modules are emitted (`.c`/`.h`) and listed by the build scripts; a module
header includes the headers of every module it value-references (the cross-module mangled
prototype lives only in the callee's header) unioned with surviving import edges.
`emitModuleInitCalls` also skips unreachable modules. This is what lets a stdio-only
`@import("std")` program emit no `std_net` and link without `-lwsock32`.

### 6.3 Emission-core compaction

Per function, `emitModule`/`emitModuleFile` run `lirOptRun` (the LIR optimization pass: copy
propagation, local const-fold, expression-nesting metadata) before emission. The duplicate
named-local store collapse and copy coalescing from the emission-core-compaction plan land at
their lowering source sites (the emitter stays a dumb printer); the emitter-side compaction is:

- **Dead-temp DCE** — `dceResultPos`/`dceMarkAllReads`/`dceMarkAllWritten` mark unread
  results; `emitter.d4_dead` suppresses their declarations and defs.
- **Expression nesting/coalescing** — `emitValueExpr`/`nestEmitDefRvalue` inline a
  single-use producer's rvalue into its consumer and suppress the temp decl/def
  (`nest_ok`/`nest_inl`, capped at `kEmitNestDepthCap = 32`).
- **Unused block-label pruning** — only blocks targeted by `jump`/`branch`/`switch_br`
  get a `z_bb_<id>:` label (`bb_used`/`bb_used_count`).
- **Dead local/name skip** — `isDeadLocalName` drops locals never read; a store to a dead
  name emits `(void)src;`.
- **Unused-parameter `(void)name;`** suppression for locals not otherwise used.

### 6.4 Packed, int-width, `volatile`, and calling-convention emission

- **Packed struct/union** — `typeRegistryIsPacked` types emit as a byte carrier
  `typedef struct { unsigned char _[N]; } <cname>;` (native C struct-by-value for
  param/return/assign/array/global); field access emits shift/mask via
  `emitPackedLoadBitfield`/`emitPackedStoreBitfield` (`bfByteRefWrite`). `packed_union`
  is a distinct `TypeKind` sharing the carrier shape (untagged, members at bit 0).
- **Arbitrary-width ints/enums** — `arb_uint_type`/`arb_int_type` map to a fixed C carrier
  by `size` (`unsigned char`/`short`/`int`/`unsigned long long`), and `enum(uN)` emits its
  backing carrier plus `#define` members. `width_wrap` masks/sign-extends to the declared
  width; `int_cast_checked` emits `zig_cast_checked_s/u`.
- **`volatile`** — carried on the pointer `Type.flags` bit; `getCTypeName` emits the
  pointee-qualified form (`volatile T *`), and `T * volatile` for pointer-to-pointer.
- **Calling convention** — `emitCallConv` writes `Z98_STDCALL ` before a `stdcall` extern
  signature and forward declaration; `emitFnPtrType` emits the `Z98_STDCALL` fn-pointer
  typedef (`FS_...`); `emitCalleeExpr` casts a stdcall callee at the use site to that
  typedef (the OS header stays the sole declaration source). `Z98_STDCALL` is defined in
  `zig_compat.h`. Unknown conventions are `error[3045]`; variadic `stdcall` is
  `error[3012]`; both are frontend rejects (0 `.c`).

### 6.5 C89-ahead guard emission (`-fsafe` / `-ffast`)

`C89Emitter.safe_checks` is set from the CLI. Under `-fsafe` (default), `zig_runtime.h`
and `zig_runtime.c` gain the poison/overflow/checked-cast helpers, and the emitter maps
the safety LIR ops to them:

- `poison_init` / `lir_fn.poison_uninit` → `zig_poison_fill((void*)&zT_N, sizeof zT_N);`
  (byte-exact `0xAA` fill for `undefined`); `-ffast` keeps deterministic zeroing.
- `add_with_overflow`/`sub_with_overflow`/`mul_with_overflow`/`shl_with_overflow` →
  `zig_wrap_<op>_<s|u>(...)`; `neg_with_overflow` → `zig_wrap_neg_<s|u>`.
- `overflow_flag` → `zig_overflow_flag_<op>_<s|u>(...)`.
- `int_cast_checked` → `zig_cast_checked_s`/`zig_cast_checked_u` (width/sign aware).

All helpers are header-`static` so every emitted TU is self-sufficient; `-ffast` output
is byte-unchanged (the helpers are omitted). The remaining `-fsafe` guards (division by
zero, shift count, null-unwrap, index bounds) are lowered to `pal_trap()` checks; `-ffast`
emits the unchecked form.

### 6.6 Self-contained f64 formatting

Floating-point formatting avoids the host `printf`: float literals emit via
`formatF64` (`util/format.zig`, a Z98 implementation), and runtime
`std.fmt.printF64` (`sf/src/std_fmt.zig`, Task 1) uses `pal_f64_to_str`
(integer part via `pal_i64_to_str`, up to 6 fractional digits, trailing zeros
trimmed) in `zig_pal.c`. Both are part of the emitted self-contained set. Before
Task 1 the printer body lived in the C runtime as `std_print_f64`.

Task 2 added the integral-value omission to `pal_f64_to_str` (both lockstep
copies): when `(f64)(i64)value == value`, the `'.'` + fraction is not emitted
(`7.0` → `7`, `100.0` → `100`, `0.0` → `0`), matching Zig. **Operator-ruled
bounded residuals (Q2, unchanged):** the non-integral path is still the 6-digit
truncating loop (`1.0/3.0` → `0.333333`, Zig `0.3333333333333333`); `1e20` hits
the `(i64)` cast UB and prints `-9223372036854775808…` (Zig
`100000000000000000000`); `-0.0` prints `0` (Zig `-0`). Full shortest-form
decimal is not implemented.

---

## 7. Removed: `@socket*` builtin emission (netbind S3)

The 11 `@socket*` networking builtins (`socketCreate`/`socketBindListen`/`socketAccept`/
`socketConnect`/`socketSend`/`socketRecv`/`socketSelect`/`socketFdZero`/`socketFdSet`/
`socketFdIsset`/`socketClose`) and their inline C-emission ports were **REMOVED**
(netbind S3, 2026-09-04): the emitter's net-gated include block and the per-builtin
`#ifdef _WIN32 / #else` bodies (helpers `emitSocketCreate`/`emitSocketSelect`/
`emitSocketClose`/`emitSocketWrite`/`emitSocketOptPtrValue`) are deleted. A direct
`@socket*` caller now fails `error[3000]: unsupported builtin function` (rc=2, 0 `.c`);
`repro/mi_matrix/net_builtin_test` is the green negative probe.

Networking is now the **std_net extern surface**: target-selected `extern "c"` bindings
(wsock32/libc) under `@cInclude("<net_prelude.h>")`, WSAStartup init in `std_net.init()`,
and the `createTcpClient` factory — see `sf/src/std_net.zig` and the QUICK_REF
"Post-netbind baseline". `emitBuiltinIncludes` now covers only stdio/exit/sleep/console
gating; there is no socket emission path in `c89_emit.zig`.
