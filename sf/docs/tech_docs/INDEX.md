# zig1 Pipeline — Master Index [updated: 2026-09-21 — Task B2: Table B gains `containerAnonNameId`, `isContainerDeclKind`, `registerContainerType`, and `localTypeScopeInit`/`localTypeScopeLookup`/`localTypeScopePush` (type_resolver.zig)] [updated: 2026-09-20 — regenerated against current source and the refreshed 14 tech docs; line references removed, `phase_FrontResolution`/`phase_AsyncFrameSize` added, counts corrected]

> Source-files: `sf/src/*.zig` | Cross-reference for all 14 tech docs

## zig0 vs zig1: Oracle Relationship

zig0 is a C++98 bootstrap compiler. It emits valid C89 but:
- Its architecture is entangled, with patches everywhere
- It has workarounds and corner-cuts that mask real semantics
- It has advanced features (AST lifter) to ease C++ writing
- The "Z98 subset" spec documents what zig0 happens to compile — zig0 only barely matches it

**When to use zig0 as oracle:**
- C89 output comparison (`--dump-c89`) — valid diff target
- Runtime behavior of compiled programs — if same output, ok

**When NOT to trust zig0:**
- Internal representation — zig1 uses flat AstNode (24 bytes), zig0 uses pointer-based tree
- Type resolution — zig1 uses immutable types + Kahn, zig0 uses mutable placeholders
- Error recovery — zig0 uses mixed abort(), zig1 uses DiagnosticCollector
- Compiler flags — may differ between zig0 and zig1

**Semantic authority:** Real Zig language specification is the ultimate reference. If zig0 accepts something real Zig rejects, zig1 should reject it. If zig1 rejects something real Zig accepts, that is a bug. When in doubt about accept/reject: test against real `zig` compiler.

---

## A. Phase Flow Diagram

```
 source.zig
     │
     ▼
┌──────────────────────────────────────────────────────────────────────┐
│  1. Import Resolution      import_resolver.zig, module_registry.zig  │
│     markers: I, Z                                      arena: scratch│
└──────────────────────┬───────────────────────────────────────────────┘
                       │ runCompiler checkpoints: 2, 3, 3a, 4
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  2. Symbol Registration    symbol_registrator.zig, symbol_table.zig  │
│     markers: S, S0, Vi                                 arena: scratch│
└──────────────────────┬───────────────────────────────────────────────┘
                       │ suspensionAnalysisRun (populates suspending_fns)
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  3. Type Resolution        type_resolver.zig, type_registry.zig,     │
│     const_alias_prepass.zig   markers: T, T0    arena: scratch/perm  │
└──────────────────────┬───────────────────────────────────────────────┘
                       │ t1, t2 checkpoints + error check (exit 2)
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  4. Front Resolution       front_resolution.zig      marker: (none)  │
│                                                       arena: scratch │
└──────────────────────┬───────────────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  5. Comptime Evaluation    comptime_eval.zig          marker: CE     │
│                                                       arena: module  │
└──────────────────────┬───────────────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  6. Semantic Analysis      semantic_analyzer.zig, coercion.zig,      │
│     resolved_type_table.zig, constraint_checker.zig, assign_helper.zig│
│     markers: RS, MZ, AD, DSE, DN, SA, sA              arena: scratch  │
└──────────────────────┬───────────────────────────────────────────────┘
                       │ error check (exit 2 if errors)
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  7. Static Analyzers       analyzer.zig, state_map.zig               │
│     marker: A                                          arena: scratch│
└──────────────────────┬───────────────────────────────────────────────┘
                       │ error check (exit 2 if errors)
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  8. Async Frame Size       async_analysis.zig         marker: AFS    │
│                                                       arena: module  │
└──────────────────────┬───────────────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  9. LIR Lowering           lower.zig, lir.zig, lir_opt_pass.zig,     │
│     lir_stream.zig, spill_store.zig                                  │
│     markers: L, nodes=, extra=, M, R, F, A0           arena: scratch │
└──────────────────────┬───────────────────────────────────────────────┘
                       │ error check + resolvedTypeTableClose + module reset
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 10. C89 Emission           c89_emit.zig, name_mangler.zig,           │
│     cinclude.zig, emit_support.zig                                   │
│     markers: C, FINAL_FLUSH                  arena: emission/scratch │
└──────────────────────┬───────────────────────────────────────────────┘
                       ▼
                  output.c
```

| Phase | Function | Files | Key Markers | Arena Tier |
|-------|----------|-------|-------------|------------|
| 1 | `phase_ImportResolution` | import_resolver.zig, module_registry.zig | `I`, `Z` | scratch |
| 2 | `phase_SymbolRegistration` | symbol_registrator.zig, symbol_table.zig | `S`, `S0`, `Vi` | scratch |
| 3 | `phase_TypeResolution` | type_resolver.zig, type_registry.zig, const_alias_prepass.zig | `T`, `T0` | scratch (prepass: permanent) |
| 4 | `phase_FrontResolution` | front_resolution.zig | (none) | scratch |
| 5 | `phase_ComptimeEvaluation` | comptime_eval.zig | `CE` | module |
| 6 | `phase_SemanticAnalysis` | semantic_analyzer.zig, coercion.zig, resolved_type_table.zig, constraint_checker.zig, assign_helper.zig | `RS`, `MZ`, `AD`, `DSE`, `DN`, `SA`, `sA` | scratch |
| 7 | `phase_StaticAnalyzers` | analyzer.zig, state_map.zig | `A` | scratch |
| 8 | `phase_AsyncFrameSize` | async_analysis.zig | `AFS` | module |
| 9 | `phase_LIRLowering` | lower.zig, lir.zig, lir_opt_pass.zig, lir_stream.zig, spill_store.zig | `L`, `nodes=`, `extra=`, `M`, `R`, `F`, `A0` | scratch |
| 10 | `phase_C89Emission` | c89_emit.zig, name_mangler.zig, cinclude.zig, emit_support.zig | `C`, `FINAL_FLUSH` | emission/scratch |

`suspensionAnalysisRun` (`async_analysis.zig`) runs directly between phases 2 and 3; it is not a
`phase_*` function but owns `suspending_fns`. `phase_FrontResolution` writes no marker of its own.

---

## B. Function → File Index

Full alphabetical index of documented functions across all phases and modules, extracted from tech docs (00-12). Symbol → file, no line numbers.

| Function | File |
|----------|------|
| `__bootstrap_c_char_from_u8` | include/zig_runtime.c |
| `__bootstrap_f32_from_f64` | include/zig_runtime.c |
| `__bootstrap_i16_from_i32` | include/zig_runtime.c |
| `__bootstrap_i32_from_i64` | include/zig_runtime.c |
| `__bootstrap_i32_from_u32` | include/zig_runtime.c |
| `__bootstrap_i32_from_u8` | include/zig_runtime.c |
| `__bootstrap_i32_from_usize` | include/zig_runtime.c |
| `__bootstrap_i8_from_i32` | include/zig_runtime.c |
| `__bootstrap_print` | extern_c.zig |
| `__bootstrap_print_int` | extern_c.zig |
| `__bootstrap_u16_from_i32` | include/zig_runtime.c |
| `__bootstrap_u32_from_i32` | include/zig_runtime.c |
| `__bootstrap_u32_from_i64` | include/zig_runtime.c |
| `__bootstrap_u32_from_u64` | include/zig_runtime.c |
| `__bootstrap_u64_from_i64` | include/zig_runtime.c |
| `__bootstrap_u8_from_bool` | include/zig_runtime.c |
| `__bootstrap_u8_from_i32` | include/zig_runtime.c |
| `__bootstrap_u8_from_u32` | include/zig_runtime.c |
| `__bootstrap_u8_from_usize` | include/zig_runtime.c |
| `__bootstrap_usize_from_i32` | include/zig_runtime.c |
| `__bootstrap_usize_from_i64` | include/zig_runtime.c |
| `__bootstrap_usize_from_u64` | include/zig_runtime.c |
| `addLocalDecl` | lower.zig |
| `addTask` | std_async.zig |
| `addTypeDependencies` | symbol_registrator.zig |
| `aggregateKeyword` | c89_emit.zig |
| `alignUp` | type_registry.zig |
| `alignUp` | type_resolver.zig |
| `analyzeExpr` | analyzer.zig |
| `analyzeSignature` | analyzer.zig |
| `appendBucket` | string_interner.zig |
| `appendEntry` | string_interner.zig |
| `appendZigExt` | module_registry.zig |
| `applyCoercion` | lower.zig |
| `applyNoneCoercion` | lower.zig |
| `applyNullGuardRefinement` | analyzer.zig |
| `arenaGrew` | allocator.zig |
| `argCount` | pal.zig |
| `argGet` | pal.zig |
| `arrayAppend` | type_registry.zig |
| `arrayGrow` | type_registry.zig |
| `assertEqBool` | lexer.zig |
| `assertEqTokenKind` | lexer.zig |
| `assertEqU32` | lexer.zig |
| `assertEqU8` | lexer.zig |
| `astBlockAdvanceHead` | ast.zig |
| `astBlockFaultIn` | ast.zig |
| `astBlockSpillHead` | ast.zig |
| `astKindToString` | dump_ast.zig |
| `astNodeArrayListAppend` | growable_array.zig |
| `astNodeArrayListEnsureCapacity` | growable_array.zig |
| `astNodeArrayListGetSlice` | growable_array.zig |
| `astNodeArrayListInit` | growable_array.zig |
| `astSlotAcquire` | ast.zig |
| `astSlotEnsureNodeCap` | ast.zig |
| `astSlotEnsurePayloadCap` | ast.zig |
| `astStoreAddCharLiteral` | ast.zig |
| `astStoreAddExtraChildren` | ast.zig |
| `astStoreAddFloatLiteral` | ast.zig |
| `astStoreAddFnProto` | ast.zig |
| `astStoreAddIdentifier` | ast.zig |
| `astStoreAddIntLiteral` | ast.zig |
| `astStoreAddNode` | ast.zig |
| `astStoreAddStringLiteral` | ast.zig |
| `astStoreCloseSpill` | ast.zig |
| `astStoreComputeMemory` | ast.zig |
| `astStoreExtraChildAtRaw` | ast.zig |
| `astStoreExtraRangeAt` | ast.zig |
| `astStoreGetExtraChildAt` | ast.zig |
| `astStoreGetExtraChildCount` | ast.zig |
| `astStoreGetExtraChildrenCopy` | ast.zig |
| `astStoreIdentifier` | ast.zig |
| `astStoreInit` | ast.zig |
| `astStoreIntValue` | ast.zig |
| `astStoreNodeAppend` | ast.zig |
| `astStoreNodeAt` | ast.zig |
| `astStoreNodeExtraChildAt` | ast.zig |
| `astStoreNodeExtraChildCount` | ast.zig |
| `astStoreNodeExtraChildrenCopy` | ast.zig |
| `astStoreNodePayload` | ast.zig |
| `astStoreNodePayloadPacked` | ast.zig |
| `astStoreSetSpillPath` | ast.zig |
| `astStoreSetValuePoolSpillPath` | ast.zig |
| `astSubtreeHasBreak` | semantic_analyzer.zig |
| `astSwitchExhaustive` | semantic_analyzer.zig |
| `astSwitchTerminates` | semantic_analyzer.zig |
| `astTerminates` | semantic_analyzer.zig |
| `astWhileTerminates` | semantic_analyzer.zig |
| `asyncEmitFrameInit` | async_state_machine.zig |
| `asyncFrameSizeRun` | async_analysis.zig |
| `asyncKey` | async_analysis.zig |
| `asyncLayoutFrame` | async_frame_layout.zig |
| `asyncLayoutPublish` | async_frame_layout.zig |
| `asyncStateTypeForCount` | async_analysis.zig |
| `asyncTransform` | async_state_machine.zig |
| `awaitTask` | std_async.zig |
| `bfByteRefWrite` | c89_emit.zig |
| `binary_search` | util/mem.zig |
| `bindOptionalCapture` | lower.zig |
| `bufferedWriterFlush` | c89_emit.zig |
| `bufferedWriterInit` | c89_emit.zig |
| `bufferedWriterInitFd` | c89_emit.zig |
| `bufferedWriterWrite` | c89_emit.zig |
| `bufferedWriterWriteByte` | c89_emit.zig |
| `bufferedWriterWriteIndent` | c89_emit.zig |
| `byteArrayListAppend` | growable_array.zig |
| `byteArrayListGetSlice` | growable_array.zig |
| `byteArrayListGrow` | growable_array.zig |
| `byteArrayListInit` | growable_array.zig |
| `c89EmitterInit` | c89_emit.zig |
| `c89NeedsEmitEdge` | c89_emit.zig |
| `c_exit` | c_exit.c |
| `c_exit` | pal.zig |
| `canLiteralFitInType` | type_registry.zig |
| `cancel` | std_async.zig |
| `cancelAll` | std_async.zig |
| `checkCombinedPeak` | allocator.zig |
| `checkLeaksOnScopeExit` | analyzer.zig |
| `checkReturnProvenance` | analyzer.zig |
| `checkReturnType` | constraint_checker.zig |
| `checkSwitchExhaust` | constraint_checker.zig |
| `cincludeUnionAll` | cinclude.zig |
| `classifyCoercion` | coercion.zig |
| `classifyExpr` | analyzer.zig |
| `classifyProvenance` | analyzer.zig |
| `classifyTypeEmissionGroups` | type_resolver.zig |
| `coalesceArgCopies` | lir_opt_pass.zig |
| `coalesceJoinCopies` | lir_opt_pass.zig |
| `coercionTableAdd` | coercion.zig |
| `coercionTableEnsureCapacity` | coercion.zig |
| `coercionTableGet` | coercion.zig |
| `coercionTableInit` | coercion.zig |
| `compareDiag` | diagnostics.zig |
| `compareDiag` | util/diagnostic_sort.zig |
| `compositeNameId` | analyzer.zig |
| `comptimeEvalBinOp` | comptime_eval.zig |
| `comptimeEvalBuiltin` | comptime_eval.zig |
| `comptimeEvalEvaluate` | comptime_eval.zig |
| `comptimeEvalEvaluateDepth` | comptime_eval.zig |
| `comptimeEvalInit` | comptime_eval.zig |
| `comptimeEvalResolveTypeArg` | comptime_eval.zig |
| `computeNestMetadata` | lir_opt_pass.zig |
| `computeSharedSet` | c89_emit.zig |
| `constAliasPrepass` | const_alias_prepass.zig |
| `containerAnonNameId` | type_resolver.zig |
| `constraintCheckerCheckBreakContinue` | constraint_checker.zig |
| `contextAlloc` | std_async.zig |
| `contextInit` | std_async.zig |
| `contextMark` | std_async.zig |
| `contextRelease` | std_async.zig |
| `copyPropagate` | lir_opt_pass.zig |
| `copyStr` | util/format.zig |
| `countUntypedGlobals` | front_resolution.zig |
| `createBlock` | lower.zig |
| `cstrToSlice` | main.zig |
| `cstrToSlice` | main_dump.zig |
| `ctypeGuardWrite` | c89_emit.zig |
| `dbgPrintU32` | c89_emit.zig |
| `dceMarkAllReads` | c89_emit.zig |
| `dceMarkAllWritten` | c89_emit.zig |
| `dceReleaseOperands` | c89_emit.zig |
| `dceResultPos` | c89_emit.zig |
| `defInfoPure` | lir_opt_pass.zig |
| `deferQueueEnsureCapacity` | analyzer.zig |
| `depGraphAddEdge` | symbol_registrator.zig |
| `depGraphEnsureCapacity` | symbol_registrator.zig |
| `depGraphFinalize` | symbol_registrator.zig |
| `depGraphInit` | symbol_registrator.zig |
| `dependEnsureCapacity` | type_resolver.zig |
| `detectNullGuard` | analyzer.zig |
| `detectorVisit` | analyzer.zig |
| `diagnosticArrayListAppend` | diagnostics.zig |
| `diagnosticArrayListEnsureCapacity` | diagnostics.zig |
| `diagnosticArrayListGetSlice` | diagnostics.zig |
| `diagnosticArrayListInit` | diagnostics.zig |
| `diagnosticBuilderMakeMsg` | diagnostics.zig |
| `diagnosticCollectorAdd` | diagnostics.zig |
| `diagnosticCollectorAddNote` | diagnostics.zig |
| `diagnosticCollectorAddRelatedSpan` | diagnostics.zig |
| `diagnosticCollectorErrorCount` | diagnostics.zig |
| `diagnosticCollectorFlushAndExit` | diagnostics.zig |
| `diagnosticCollectorHasErrors` | diagnostics.zig |
| `diagnosticCollectorInit` | diagnostics.zig |
| `diagnosticCollectorIntern` | diagnostics.zig |
| `diagnosticCollectorMarkNodeOnce` | diagnostics.zig |
| `diagnosticCollectorPrintAll` | diagnostics.zig |
| `diagnosticCollectorWarningCount` | diagnostics.zig |
| `dirExists` | pal.zig |
| `dumpAst` | dump_ast.zig |
| `dumpTokens` | dump_tokens.zig |
| `emAppend` | type_registry.zig |
| `emitArith` | lower.zig |
| `emitArithNeg` | lower.zig |
| `emitArrayType` | c89_emit.zig |
| `emitAwait` | async_state_machine.zig |
| `emitBaseIdxAccess` | c89_emit.zig |
| `emitBuildOwcBat` | c89_emit.zig |
| `emitBuildScripts` | c89_emit.zig |
| `emitBuildTargetBat` | c89_emit.zig |
| `emitBuildTargetSh` | c89_emit.zig |
| `emitBuiltinIncludes` | c89_emit.zig |
| `emitCExitCSupport` | emit_support.zig |
| `emitCStringLiteral` | c89_emit.zig |
| `emitCallConv` | c89_emit.zig |
| `emitCalleeExpr` | c89_emit.zig |
| `emitEnumType` | c89_emit.zig |
| `emitErrorCodePrologue` | c89_emit.zig |
| `emitErrorSetType` | c89_emit.zig |
| `emitErrorUnionType` | c89_emit.zig |
| `emitFieldAssign` | c89_emit.zig |
| `emitFlagOp` | c89_emit.zig |
| `emitFnPtrType` | c89_emit.zig |
| `emitFunctionBody` | c89_emit.zig |
| `emitFunctionForwardDecl` | c89_emit.zig |
| `emitFunctionSignature` | c89_emit.zig |
| `emitGlobalDecls` | c89_emit.zig |
| `emitHoistedDecls` | c89_emit.zig |
| `emitIncludes` | c89_emit.zig |
| `emitInst` | c89_emit.zig |
| `emitInst` | lower.zig |
| `emitInt64Type` | c89_emit.zig |
| `emitMainDriver` | async_state_machine.zig |
| `emitMainWrapper` | c89_emit.zig |
| `emitModule` | c89_emit.zig |
| `emitModuleFile` | c89_emit.zig |
| `emitModuleFooter` | c89_emit.zig |
| `emitModuleHeader` | c89_emit.zig |
| `emitModuleHeaderFile` | c89_emit.zig |
| `emitModuleInitCalls` | c89_emit.zig |
| `emitNetPreludeHSupport` | emit_support.zig |
| `emitOptionalType` | c89_emit.zig |
| `emitOverflowTrap` | lower.zig |
| `emitPackedLoadBitfield` | c89_emit.zig |
| `emitPackedStoreBitfield` | c89_emit.zig |
| `emitSafeCheckDivMod` | lower.zig |
| `emitSafeCheckIndex` | lower.zig |
| `emitSafeCheckShift` | lower.zig |
| `emitSatBinary` | c89_emit.zig |
| `emitSharedHeader` | c89_emit.zig |
| `emitSliceType` | c89_emit.zig |
| `emitSpecialTypes` | c89_emit.zig |
| `emitStdOsPreludeHSupport` | emit_support.zig |
| `emitStdTimePreludeHSupport` | emit_support.zig |
| `emitStdargInclude` | c89_emit.zig |
| `emitStructType` | c89_emit.zig |
| `emitSupportFiles` | c89_emit.zig |
| `emitTaggedUnionInit` | lower.zig |
| `emitTaggedUnionType` | c89_emit.zig |
| `emitTypeDefinition` | c89_emit.zig |
| `emitUint64Type` | c89_emit.zig |
| `emitUnionType` | c89_emit.zig |
| `emitValueExpr` | c89_emit.zig |
| `emitWrapNeg` | c89_emit.zig |
| `emitWrapOp` | c89_emit.zig |
| `emitZigCompatHSupport` | emit_support.zig |
| `emitZigPalC` | c89_emit.zig |
| `emitZigPalCSupport` | emit_support.zig |
| `emitZigRuntimeC` | c89_emit.zig |
| `emitZigRuntimeCSupport` | emit_support.zig |
| `emitZigRuntimeHSupport` | emit_support.zig |
| `enAppend` | type_registry.zig |
| `ensureCapacityBuckets` | string_interner.zig |
| `ensureCapacityEntries` | string_interner.zig |
| `errLitSrcType` | semantic_analyzer.zig |
| `errorCodeRegistryFinalize` | main.zig |
| `errorSetIsSubset` | type_registry.zig |
| `esAppend` | type_registry.zig |
| `euAppend` | type_registry.zig |
| `evalConstI64Full` | type_resolver.zig |
| `evalConstModuleOfExpr` | type_resolver.zig |
| `evalConstU32Full` | type_resolver.zig |
| `executeDeferQueue` | analyzer.zig |
| `exit` | pal.zig |
| `expandDefers` | lower.zig |
| `f64ArrayListAppend` | growable_array.zig |
| `f64ArrayListAppendInner` | ast.zig |
| `f64ArrayListEnsureCapacity` | growable_array.zig |
| `f64ArrayListGetSlice` | growable_array.zig |
| `f64ArrayListInit` | growable_array.zig |
| `faultIn` | c89_emit.zig |
| `fclose` | pal.zig |
| `feAppend` | type_registry.zig |
| `fieldEmbedsByValue` | type_resolver.zig |
| `fileClose` | pal.zig |
| `fileExists` | pal.zig |
| `fileOpen` | pal.zig |
| `fileRead` | pal.zig |
| `fileWrite` | pal.zig |
| `findCalleeFnTypeId` | c89_emit.zig |
| `findLocalTemp` | lower.zig |
| `findTailCall` | lower.zig |
| `fmtBnMulSmall` | util/format.zig |
| `fmtCopyOut` | util/format.zig |
| `fnAppend` | type_registry.zig |
| `fnProtoArrayListAppend` | growable_array.zig |
| `fnProtoArrayListAppendInner` | ast.zig |
| `fnProtoArrayListEnsureCapacity` | growable_array.zig |
| `fnProtoArrayListGetSlice` | growable_array.zig |
| `fnProtoArrayListInit` | growable_array.zig |
| `fnReturnRequiresValue` | semantic_analyzer.zig |
| `fnv1a` | util/hash.zig |
| `fopen` | pal.zig |
| `formatF64` | util/format.zig |
| `formatU32` | diagnostics.zig |
| `formatU32` | lexer.zig |
| `formatU32` | util/format.zig |
| `formatU64` | util/format.zig |
| `fread` | pal.zig |
| `frontResolveModuleInits` | front_resolution.zig |
| `fseek` | pal.zig |
| `ftell` | pal.zig |
| `fwrite` | pal.zig |
| `getBinOpStr` | c89_emit.zig |
| `getByte` | main_dump.zig |
| `getCTypeName` | c89_emit.zig |
| `getCheckedCastFnName` | c89_emit.zig |
| `getDefaultLibPath` | pal.zig |
| `getInfixInfo` | parser.zig |
| `getLevelName` | diagnostics.zig |
| `getPrintFnName` | c89_emit.zig |
| `getTempTypeByIndex` | c89_emit.zig |
| `getUnOpStr` | c89_emit.zig |
| `growDep` | const_alias_prepass.zig |
| `growLocalDecls` | lower.zig |
| `growWpEdges` | type_resolver.zig |
| `growableSandGrow` | allocator.zig |
| `growableSandInit` | allocator.zig |
| `handleAllocAssign` | analyzer.zig |
| `handleAllocCall` | analyzer.zig |
| `handleFreeCall` | analyzer.zig |
| `handleNullAssign` | analyzer.zig |
| `handleNullVarDecl` | analyzer.zig |
| `handleOwnershipPass` | analyzer.zig |
| `handleOwnershipReturn` | analyzer.zig |
| `hasOtherConsumers` | lower.zig |
| `hashSpillReadU32` | module_registry.zig |
| `hashSpillWriteMap` | module_registry.zig |
| `hashSpillWriteU32` | module_registry.zig |
| `hexDigitValue` | lexer.zig |
| `hoistTemps` | lower.zig |
| `iceAddrOfLValueUnsupported` | lower.zig |
| `importEdgesAppend` | module_registry.zig |
| `importEdgesEnsureCapacity` | module_registry.zig |
| `importQueueDequeue` | module_registry.zig |
| `importQueueEnqueue` | module_registry.zig |
| `importQueueInit` | module_registry.zig |
| `importQueuePendingAppend` | module_registry.zig |
| `importQueuePendingEnsureCapacity` | module_registry.zig |
| `importQueuePendingPop` | module_registry.zig |
| `inDegreeEnsureCapacity` | type_resolver.zig |
| `initArgs` | pal.zig |
| `initArray` | type_registry.zig |
| `initCompilerAlloc` | allocator.zig |
| `initKeywordTable` | token.zig |
| `isAllocCall` | analyzer.zig |
| `isAlpha` | lexer.zig |
| `isAlphaNum` | lexer.zig |
| `isBShapeMismatch` | semantic_analyzer.zig |
| `isBasePtrToArray` | c89_emit.zig |
| `isC89Keyword` | c89_emit.zig |
| `isContainerDeclKind` | type_resolver.zig |
| `isDeadLocalName` | c89_emit.zig |
| `isDigit` | lexer.zig |
| `isDigitInBase` | lexer.zig |
| `isFreeCall` | analyzer.zig |
| `isIdentExpr` | analyzer.zig |
| `isMarkersEnabled` | pal.zig |
| `isNullExpr` | analyzer.zig |
| `isTempOrBuiltin` | c89_emit.zig |
| `isU64MaxLiteral` | lexer.zig |
| `isValueDependency` | type_registry.zig |
| `itoa` | util/itoa.zig |
| `itoa64` | util/itoa.zig |
| `joinPath` | module_registry.zig |
| `layoutAddFieldEdges` | type_resolver.zig |
| `layoutAddTypeEdge` | type_resolver.zig |
| `layoutFieldNeedsEdge` | type_resolver.zig |
| `lexerAdvance` | lexer.zig |
| `lexerInit` | lexer.zig |
| `lexerIsAtEnd` | lexer.zig |
| `lexerMakeErrorToken` | lexer.zig |
| `lexerMakeToken` | lexer.zig |
| `lexerMatch` | lexer.zig |
| `lexerNextToken` | lexer.zig |
| `lexerParseEscapeSequence` | lexer.zig |
| `lexerParseHexEscape` | lexer.zig |
| `lexerPeek` | lexer.zig |
| `lexerPeekN` | lexer.zig |
| `lexerRunAllTests` | lexer.zig |
| `lexerScanBuiltinIdentifier` | lexer.zig |
| `lexerScanChar` | lexer.zig |
| `lexerScanIdentifierOrKeyword` | lexer.zig |
| `lexerScanNumber` | lexer.zig |
| `lexerScanString` | lexer.zig |
| `lexerSkipWSC` | lexer.zig |
| `lexerTestBuiltinIdentifier` | lexer.zig |
| `lexerTestDiagnostics` | lexer.zig |
| `lexerTestHelpers` | lexer.zig |
| `lexerTestIdentifierKeywords` | lexer.zig |
| `lexerTestOperators` | lexer.zig |
| `lexerTestSanityCheck` | lexer.zig |
| `lexerTestScanChar` | lexer.zig |
| `lexerTestScanNumber` | lexer.zig |
| `lexerTestScanString` | lexer.zig |
| `lexerTestSkipWhitespaceAndComments` | lexer.zig |
| `lirOptNestCandidate` | lir_opt_pass.zig |
| `lirOptNestConsLoc` | lir_opt_pass.zig |
| `lirOptNestDefLoc` | lir_opt_pass.zig |
| `lirOptNestDepthOf` | lir_opt_pass.zig |
| `lirOptRun` | lir_opt_pass.zig |
| `lirStreamAppend` | lir_stream.zig |
| `lirStreamBeginRead` | lir_stream.zig |
| `lirStreamBeginWrite` | lir_stream.zig |
| `lirStreamEndRead` | lir_stream.zig |
| `lirStreamReadFunction` | lir_stream.zig |
| `localConstScopeInit` | type_resolver.zig |
| `localConstScopeLookup` | type_resolver.zig |
| `localConstScopePush` | type_resolver.zig |
| `localTypeScopeInit` | type_resolver.zig |
| `localTypeScopeLookup` | type_resolver.zig |
| `localTypeScopePush` | type_resolver.zig |
| `lookupKeyword` | token.zig |
| `lowerAppendSwitchCaseItem` | lower.zig |
| `lowerAssignLValue` | lower.zig |
| `lowerCompoundLValueStore` | lower.zig |
| `lowerDeclCallConvFlag` | lower.zig |
| `lowerExpr` | lower.zig |
| `lowerExprImpl` | lower.zig |
| `lowerFieldStore` | lower.zig |
| `lowerFn` | lower.zig |
| `lowerLValueAddr` | lower.zig |
| `lowerModuleInit` | lower.zig |
| `lowerPackedChainAnalyze` | lower.zig |
| `lowerStmt` | lower.zig |
| `lowerStmtBody` | lower.zig |
| `lowererInit` | lower.zig |
| `main` | ast_dump_main.zig |
| `main` | main.zig |
| `main` | main_dump.zig |
| `main` | main_exp.zig |
| `main` | strip_main.zig |
| `mainCRTStartup` | include/zig_pal.c |
| `mangleC89Keyword` | c89_emit.zig |
| `mangleLocalName` | c89_emit.zig |
| `mangleTempName` | c89_emit.zig |
| `mapCapacityFromHint` | util/hash.zig |
| `markerWrite` | pal.zig |
| `markerWriteInt` | pal.zig |
| `markerWriteInt64` | pal.zig |
| `markersEnabled` | pal.zig |
| `matchFlag` | main.zig |
| `matchFlag` | main_dump.zig |
| `matchMMFlag` | main.zig |
| `matchSFlag` | main.zig |
| `materializeInto` | lower.zig |
| `materializeShiftLhs` | lower.zig |
| `max` | util/util.zig |
| `maxTempOf` | lir_opt_pass.zig |
| `maybeEmitWidthWrap` | lower.zig |
| `maybeExtractSlicePtr` | lower.zig |
| `measureMarkerWrite` | pal.zig |
| `measureMarkerWriteInt` | pal.zig |
| `measureMarkerWriteInt64` | pal.zig |
| `mem_eql` | util/mem.zig |
| `min` | util/util.zig |
| `moduleDirPath` | module_registry.zig |
| `moduleEntryArrayListAppend` | module_registry.zig |
| `moduleEntryArrayListEnsureCapacity` | module_registry.zig |
| `moduleEntryArrayListGetSlice` | module_registry.zig |
| `moduleEntryArrayListInit` | module_registry.zig |
| `moduleHasConsoleBuiltin` | c89_emit.zig |
| `moduleHasExitBuiltin` | c89_emit.zig |
| `moduleHasSleepBuiltin` | c89_emit.zig |
| `moduleHasStdioBuiltin` | c89_emit.zig |
| `moduleHasVaInsts` | c89_emit.zig |
| `moduleQualifiedName` | c89_emit.zig |
| `moduleRegistryAddImport` | module_registry.zig |
| `moduleRegistryAddModule` | module_registry.zig |
| `moduleRegistryAssertPathToIdResident` | module_registry.zig |
| `moduleRegistryCollectIncludes` | module_registry.zig |
| `moduleRegistryFaultInPathToId` | module_registry.zig |
| `moduleRegistryGetModules` | module_registry.zig |
| `moduleRegistryGetOrCreateModule` | module_registry.zig |
| `moduleRegistryInit` | module_registry.zig |
| `moduleRegistryParseModule` | import_resolver.zig |
| `moduleRegistryPathToIdGet` | module_registry.zig |
| `moduleRegistryResolveImport` | module_registry.zig |
| `moduleRegistryResolveImports` | import_resolver.zig |
| `moduleRegistrySetSourceMan` | module_registry.zig |
| `moduleRegistrySortModules` | module_registry.zig |
| `moduleRegistrySpillHashMaps` | module_registry.zig |
| `moduleRegistryVerifyOrder` | module_registry.zig |
| `moduleResolverAddSearchDir` | module_registry.zig |
| `moduleResolverInit` | module_registry.zig |
| `moduleResolverResolve` | module_registry.zig |
| `moduleResolverTryDir` | module_registry.zig |
| `nameCacheGet` | type_registry.zig |
| `nameCachePut` | type_registry.zig |
| `nameManglerInit` | c89_emit.zig |
| `nameManglerInit` | name_mangler.zig |
| `nameManglerMangle` | c89_emit.zig |
| `nameManglerMangleGlobal` | c89_emit.zig |
| `nestEmitBinExpr` | c89_emit.zig |
| `nestEmitDefRvalue` | c89_emit.zig |
| `nestEmitUnaryExpr` | c89_emit.zig |
| `nextTemp` | lower.zig |
| `nodeChildIsNode` | ast.zig |
| `nodeGetNameId` | dump_ast.zig |
| `nodeHasExtraChildren` | ast.zig |
| `nodeHasNodeExtraChildren` | ast.zig |
| `normalizePath` | util/path.zig |
| `onDoubleFreeStmt` | analyzer.zig |
| `onLifetimeStmt` | analyzer.zig |
| `onNullStmt` | analyzer.zig |
| `openSupportOutputFile` | c89_emit.zig |
| `optAppend` | type_registry.zig |
| `pal_abort` | include/zig_pal.c |
| `pal_dir_exists` | include/zig_pal.c |
| `pal_dir_exists` | pal.zig |
| `pal_f64_to_str` | include/zig_pal.c |
| `pal_file_close` | include/zig_pal.c |
| `pal_file_close` | pal.zig |
| `pal_file_open` | include/zig_pal.c |
| `pal_file_open` | pal.zig |
| `pal_file_read` | include/zig_pal.c |
| `pal_file_read` | pal.zig |
| `pal_file_write` | include/zig_pal.c |
| `pal_file_write` | pal.zig |
| `pal_get_default_lib_path` | include/zig_pal.c |
| `pal_get_default_lib_path` | pal.zig |
| `pal_i64_to_str` | include/zig_pal.c |
| `pal_memcpy` | include/zig_pal.c |
| `pal_print_stderr` | include/zig_pal.c |
| `pal_print_stdout` | include/zig_pal.c |
| `pal_reverse` | include/zig_pal.c |
| `pal_set_trap_handler` | include/zig_pal.c |
| `pal_strlen` | include/zig_pal.c |
| `pal_trap` | include/zig_pal.c |
| `pal_trap` | pal.zig |
| `pal_u64_to_str` | include/zig_pal.c |
| `pal_u64_to_str_buf` | include/zig_pal.c |
| `panicHandler` | panic.zig |
| `parseArbIntWidth` | type_registry.zig |
| `parseArgs` | main.zig |
| `parseArgs` | main_dump.zig |
| `parseColorMode` | main.zig |
| `parseColorMode` | main_dump.zig |
| `parseErrorFormat` | main.zig |
| `parseErrorFormat` | main_dump.zig |
| `parseF64` | lexer.zig |
| `parseMMBytes` | main.zig |
| `parseSLevel` | main.zig |
| `parseSize` | main.zig |
| `parseSize` | main_dump.zig |
| `parseTargetIsWindows` | main.zig |
| `parseU32` | main.zig |
| `parseU32` | main_dump.zig |
| `parseU64` | lexer.zig |
| `parserAddBinary` | parser.zig |
| `parserAddError` | parser.zig |
| `parserAddErrorCode` | parser.zig |
| `parserAdvance` | parser.zig |
| `parserClassifyCallConv` | parser.zig |
| `parserConsumeCurrent` | parser.zig |
| `parserEmitErrorNode` | parser.zig |
| `parserExpect` | parser.zig |
| `parserInit` | parser.zig |
| `parserInitCommon` | parser.zig |
| `parserInitStreaming` | parser.zig |
| `parserParseAnonymousLiteral` | parser.zig |
| `parserParseArrayLiteral` | parser.zig |
| `parserParseBlock` | parser.zig |
| `parserParseBoolLiteral` | parser.zig |
| `parserParseBracketType` | parser.zig |
| `parserParseBreakExpr` | parser.zig |
| `parserParseBreakStmt` | parser.zig |
| `parserParseBuiltinCall` | parser.zig |
| `parserParseCInclude` | parser.zig |
| `parserParseCatchRHS` | parser.zig |
| `parserParseCharLiteral` | parser.zig |
| `parserParseContainerDecl` | parser.zig |
| `parserParseContinueExpr` | parser.zig |
| `parserParseContinueStmt` | parser.zig |
| `parserParseDeferStmt` | parser.zig |
| `parserParseDotAccess` | parser.zig |
| `parserParseEnumLiteral` | parser.zig |
| `parserParseEnumType` | parser.zig |
| `parserParseErrdeferStmt` | parser.zig |
| `parserParseErrorLiteral` | parser.zig |
| `parserParseErrorSetDecl` | parser.zig |
| `parserParseErrorSetDeclBody` | parser.zig |
| `parserParseErrorUnionType` | parser.zig |
| `parserParseExportDecl` | parser.zig |
| `parserParseExprPrec` | parser.zig |
| `parserParseExprStmt` | parser.zig |
| `parserParseExternDecl` | parser.zig |
| `parserParseExternFnType` | parser.zig |
| `parserParseFieldInitListNamed` | parser.zig |
| `parserParseFloatLiteral` | parser.zig |
| `parserParseFnCall` | parser.zig |
| `parserParseFnDecl` | parser.zig |
| `parserParseFnType` | parser.zig |
| `parserParseForStmt` | parser.zig |
| `parserParseGroupedExpr` | parser.zig |
| `parserParseIdentExpr` | parser.zig |
| `parserParseIfExpr` | parser.zig |
| `parserParseIfStmt` | parser.zig |
| `parserParseImportExpr` | parser.zig |
| `parserParseIndexOrSlice` | parser.zig |
| `parserParseIntLiteral` | parser.zig |
| `parserParseLabeledBlockExpr` | parser.zig |
| `parserParseLabeledStmt` | parser.zig |
| `parserParseModuleRoot` | parser.zig |
| `parserParseOptionalType` | parser.zig |
| `parserParseOrelseRHS` | parser.zig |
| `parserParsePostfixChain` | parser.zig |
| `parserParsePrefixUnary` | parser.zig |
| `parserParsePrimary` | parser.zig |
| `parserParsePtrQualifiers` | parser.zig |
| `parserParsePtrType` | parser.zig |
| `parserParsePubDecl` | parser.zig |
| `parserParseReturnExpr` | parser.zig |
| `parserParseReturnStmt` | parser.zig |
| `parserParseSingleToken` | parser.zig |
| `parserParseStatement` | parser.zig |
| `parserParseStringLiteral` | parser.zig |
| `parserParseStructInit` | parser.zig |
| `parserParseStructType` | parser.zig |
| `parserParseSwitchExpr` | parser.zig |
| `parserParseSwitchProng` | parser.zig |
| `parserParseSwitchStmt` | parser.zig |
| `parserParseTestDecl` | parser.zig |
| `parserParseTryExpr` | parser.zig |
| `parserParseType` | parser.zig |
| `parserParseTypeName` | parser.zig |
| `parserParseUnionType` | parser.zig |
| `parserParseVarDecl` | parser.zig |
| `parserParseWhileStmt` | parser.zig |
| `parserPeek` | parser.zig |
| `parserPeekN` | parser.zig |
| `parserPullOne` | parser.zig |
| `parserPushU32` | parser.zig |
| `parserSetImportScratch` | parser.zig |
| `parserSetModuleContext` | parser.zig |
| `parserSynchronize` | parser.zig |
| `parserTokenText` | parser.zig |
| `payloadEnsure` | type_registry.zig |
| `phase_ASTLowering` | main_dump.zig |
| `phase_AsyncFrameSize` | main.zig |
| `phase_C89Emission` | main.zig |
| `phase_C89Emission` | main_dump.zig |
| `phase_ComptimeEvaluation` | main.zig |
| `phase_FrontResolution` | main.zig |
| `phase_ImportResolution` | main.zig |
| `phase_ImportResolution` | main_dump.zig |
| `phase_LIRLowering` | main.zig |
| `phase_SemanticAnalysis` | main.zig |
| `phase_SemanticAnalysis` | main_dump.zig |
| `phase_StaticAnalyzers` | main.zig |
| `phase_SymbolRegistration` | main.zig |
| `phase_SymbolRegistration` | main_dump.zig |
| `phase_TypeResolution` | main.zig |
| `phase_TypeResolution` | main_dump.zig |
| `pkFieldAppend` | type_registry.zig |
| `pkSetFields` | type_registry.zig |
| `pkStructAppend` | type_registry.zig |
| `pkUnSetFields` | type_registry.zig |
| `pkUnStructAppend` | type_registry.zig |
| `pointerQualifiersMonotone` | type_registry.zig |
| `poolPeak` | allocator.zig |
| `poolPtr` | allocator.zig |
| `popExpectedType` | semantic_analyzer.zig |
| `popFreeBestFit` | allocator.zig |
| `populateTypePayload` | symbol_registrator.zig |
| `precFromInt` | parser.zig |
| `precToInt` | parser.zig |
| `printDecompParseAndValidate` | print_decomposition.zig |
| `printDecompScanFormat` | print_decomposition.zig |
| `printUsage` | main.zig |
| `printUsage` | main_dump.zig |
| `printUsize` | allocator.zig |
| `ptrAppend` | type_registry.zig |
| `pushDefer` | lower.zig |
| `pushExpectedType` | semantic_analyzer.zig |
| `readFile` | pal.zig |
| `registerContainerType` | type_resolver.zig |
| `registerDecl` | symbol_registrator.zig |
| `registerLocalDecl` | semantic_analyzer.zig |
| `registerModuleSymbols` | symbol_registrator.zig |
| `registerPrimitive` | type_registry.zig |
| `registerPrimitiveName` | type_registry.zig |
| `removeTask` | std_async.zig |
| `requiresFullDef` | type_resolver.zig |
| `resolveAggregateFieldTypesAll` | type_resolver.zig |
| `resolveAssignedLocalTemp` | assign_helper.zig |
| `resolveDeclAggregateFieldTypes` | type_resolver.zig |
| `resolveFnSignatures` | type_resolver.zig |
| `resolveImportFieldAlias` | type_resolver.zig |
| `resolveImportFieldAliases` | type_resolver.zig |
| `resolveNamedTypeExpressions` | type_resolver.zig |
| `resolveOrigin` | analyzer.zig |
| `resolveReturnStmt` | semantic_analyzer.zig |
| `resolveStmtTypes` | front_resolution.zig |
| `resolveStmtTypesRec` | front_resolution.zig |
| `resolveTempName` | c89_emit.zig |
| `resolveTypeExpr` | front_resolution.zig |
| `resolveTypeExprFull` | type_resolver.zig |
| `resolveWellKnownTypeName` | const_alias_prepass.zig |
| `resolvedSourceTableGet` | resolved_type_table.zig |
| `resolvedSourceTableSet` | resolved_type_table.zig |
| `resolvedTypeTableClose` | resolved_type_table.zig |
| `resolvedTypeTableGet` | resolved_type_table.zig |
| `resolvedTypeTableInit` | resolved_type_table.zig |
| `resolvedTypeTableReserve` | resolved_type_table.zig |
| `resolvedTypeTableSet` | resolved_type_table.zig |
| `resolvedTypeTableSetSpillPath` | resolved_type_table.zig |
| `rttBlockEnsure` | resolved_type_table.zig |
| `rttExtend` | resolved_type_table.zig |
| `rttReadU32` | resolved_type_table.zig |
| `rttWriteU32` | resolved_type_table.zig |
| `runAllAnalyzers` | analyzer.zig |
| `runCompiler` | main.zig |
| `runCompiler` | main_dump.zig |
| `runConstFold` | lir_opt_pass.zig |
| `runDoubleFreeAnalyzer` | analyzer.zig |
| `runLifetimeAnalyzer` | analyzer.zig |
| `runNullAnalyzer` | analyzer.zig |
| `runSignatureAnalyzer` | analyzer.zig |
| `sandAlloc` | allocator.zig |
| `sandInit` | allocator.zig |
| `sandReallocInPlace` | allocator.zig |
| `sandReset` | allocator.zig |
| `sandResetPeak` | allocator.zig |
| `sandTryReallocInPlace` | allocator.zig |
| `schedulerInit` | std_async.zig |
| `scriptNetEmitted` | c89_emit.zig |
| `scriptStdOsEmitted` | c89_emit.zig |
| `scriptStdTimeEmitted` | c89_emit.zig |
| `searchDirArrayListAppend` | module_registry.zig |
| `searchDirArrayListEnsureCapacity` | module_registry.zig |
| `semaTraceStep` | semantic_analyzer.zig |
| `semanticAnalyzerBuiltinNameEq` | semantic_analyzer.zig |
| `semanticAnalyzerCaptureType` | semantic_analyzer.zig |
| `semanticAnalyzerDiagAsyncBuiltinInDefer` | semantic_analyzer.zig |
| `semanticAnalyzerDiagAsyncOutsideSuspending` | semantic_analyzer.zig |
| `semanticAnalyzerFnPtrConvMismatch` | semantic_analyzer.zig |
| `semanticAnalyzerGateEnumModuleDecl` | semantic_analyzer.zig |
| `semanticAnalyzerGateEnumTypeDecl` | semantic_analyzer.zig |
| `semanticAnalyzerGatePackedFields` | semantic_analyzer.zig |
| `semanticAnalyzerGatePackedUnionMembers` | semantic_analyzer.zig |
| `semanticAnalyzerGrowLocalDecls` | semantic_analyzer.zig |
| `semanticAnalyzerInit` | semantic_analyzer.zig |
| `semanticAnalyzerIsBuiltinSupported` | semantic_analyzer.zig |
| `semanticAnalyzerIsTypeValueCast` | semantic_analyzer.zig |
| `semanticAnalyzerMaybeDiagVolatileDrop` | semantic_analyzer.zig |
| `semanticAnalyzerMaybeGateAliasDecl` | semantic_analyzer.zig |
| `semanticAnalyzerPackedFieldTypeAllowed` | semantic_analyzer.zig |
| `semanticAnalyzerPackedStructDeclForType` | semantic_analyzer.zig |
| `semanticAnalyzerPtrCastDropsVolatile` | semantic_analyzer.zig |
| `semanticAnalyzerResolveArithmetic` | semantic_analyzer.zig |
| `semanticAnalyzerResolveArrayInit` | semantic_analyzer.zig |
| `semanticAnalyzerResolveAssign` | semantic_analyzer.zig |
| `semanticAnalyzerResolveBitNot` | semantic_analyzer.zig |
| `semanticAnalyzerResolveBitwise` | semantic_analyzer.zig |
| `semanticAnalyzerResolveComparison` | semantic_analyzer.zig |
| `semanticAnalyzerResolveEnumLiteral` | semantic_analyzer.zig |
| `semanticAnalyzerResolveExpr` | semantic_analyzer.zig |
| `semanticAnalyzerResolveFieldAccess` | semantic_analyzer.zig |
| `semanticAnalyzerResolveFnBody` | semantic_analyzer.zig |
| `semanticAnalyzerResolveFnCall` | semantic_analyzer.zig |
| `semanticAnalyzerResolveForHeader` | semantic_analyzer.zig |
| `semanticAnalyzerResolveIdent` | semantic_analyzer.zig |
| `semanticAnalyzerResolveIfExpr` | semantic_analyzer.zig |
| `semanticAnalyzerResolveIfHeader` | semantic_analyzer.zig |
| `semanticAnalyzerResolveIndexAccess` | semantic_analyzer.zig |
| `semanticAnalyzerResolveLogical` | semantic_analyzer.zig |
| `semanticAnalyzerResolveNegate` | semantic_analyzer.zig |
| `semanticAnalyzerResolveOrelseExpr` | semantic_analyzer.zig |
| `semanticAnalyzerResolveSliceExpr` | semantic_analyzer.zig |
| `semanticAnalyzerResolveStmt` | semantic_analyzer.zig |
| `semanticAnalyzerResolveStmtIter` | semantic_analyzer.zig |
| `semanticAnalyzerResolveStructInit` | semantic_analyzer.zig |
| `semanticAnalyzerResolveSwitchExpr` | semantic_analyzer.zig |
| `semanticAnalyzerResolveTryExpr` | semantic_analyzer.zig |
| `semanticAnalyzerResolveTupleLiteral` | semantic_analyzer.zig |
| `semanticAnalyzerResolveWhileHeader` | semantic_analyzer.zig |
| `semanticAnalyzerStmtWorkPush` | semantic_analyzer.zig |
| `semanticAnalyzerVolatileCastValid` | semantic_analyzer.zig |
| `semanticAnalyzerVolatileDrop` | semantic_analyzer.zig |
| `sliceAppend` | type_registry.zig |
| `sortDiagnostics` | diagnostics.zig |
| `sortDiagnostics` | util/diagnostic_sort.zig |
| `sourceFileArrayListAppend` | source_manager.zig |
| `sourceFileArrayListEnsureCapacity` | source_manager.zig |
| `sourceFileArrayListGetSlice` | source_manager.zig |
| `sourceFileArrayListInit` | source_manager.zig |
| `sourceManagerAddFile` | source_manager.zig |
| `sourceManagerAddFileTransient` | source_manager.zig |
| `sourceManagerCopyToArena` | source_manager.zig |
| `sourceManagerFaultIn` | source_manager.zig |
| `sourceManagerGetFileName` | source_manager.zig |
| `sourceManagerGetLineOffsets` | source_manager.zig |
| `sourceManagerGetLocation` | source_manager.zig |
| `sourceManagerGetSourceContent` | source_manager.zig |
| `sourceManagerInit` | source_manager.zig |
| `sourceManagerResetFaults` | source_manager.zig |
| `spillBackendFor` | spill_store.zig |
| `spillReadAt` | spill_store.zig |
| `spillSeek` | spill_store.zig |
| `spillSetLevel` | spill_store.zig |
| `spillWriteAt` | spill_store.zig |
| `stAppend` | type_registry.zig |
| `stateMapFork` | state_map.zig |
| `stateMapGet` | state_map.zig |
| `stateMapGetEntries` | state_map.zig |
| `stateMapInit` | state_map.zig |
| `stateMapMergeStates` | state_map.zig |
| `stateMapSet` | state_map.zig |
| `std_checked_cast_i16` | include/zig_runtime.c |
| `std_checked_cast_i32` | include/zig_runtime.c |
| `std_checked_cast_i64` | include/zig_runtime.c |
| `std_checked_cast_i8` | include/zig_runtime.c |
| `std_checked_cast_u16` | include/zig_runtime.c |
| `std_checked_cast_u32` | include/zig_runtime.c |
| `std_checked_cast_u64` | include/zig_runtime.c |
| `std_checked_cast_u8` | include/zig_runtime.c |
| `std_panic` | include/zig_runtime.c |
| `std_print` | include/zig_runtime.c |
| `std_print_bool` | include/zig_runtime.c |
| `std_print_char` | include/zig_runtime.c |
| `std_print_f64` | include/zig_runtime.c |
| `std_print_hex_i32` | include/zig_runtime.c |
| `std_print_hex_i64` | include/zig_runtime.c |
| `std_print_hex_u32` | include/zig_runtime.c |
| `std_print_hex_u64` | include/zig_runtime.c |
| `std_print_i32` | include/zig_runtime.c |
| `std_print_i64` | include/zig_runtime.c |
| `std_print_len` | include/zig_runtime.c |
| `std_print_str` | include/zig_runtime.c |
| `std_print_u32` | include/zig_runtime.c |
| `std_print_u64` | include/zig_runtime.c |
| `stderr_write` | pal.zig |
| `stdout_write` | pal.zig |
| `streamClose` | pal.zig |
| `streamOpen` | pal.zig |
| `streamRead` | pal.zig |
| `streamSeek` | pal.zig |
| `streamWrite` | pal.zig |
| `stringInternerCopyToArena` | string_interner.zig |
| `stringInternerGet` | string_interner.zig |
| `stringInternerGrowBuckets` | string_interner.zig |
| `stringInternerInit` | string_interner.zig |
| `stringInternerIntern` | string_interner.zig |
| `suspend` | std_async.zig |
| `suspendUntil` | std_async.zig |
| `suspensionAnalysisRun` | async_analysis.zig |
| `symbolIsPublic` | symbol_table.zig |
| `symbolLookupAllModules` | type_resolver.zig |
| `symbolRegistryEnsureCapacity` | symbol_table.zig |
| `symbolRegistryGetTable` | symbol_table.zig |
| `symbolRegistryInit` | symbol_table.zig |
| `symbolRegistryQualifiedLookup` | symbol_table.zig |
| `symbolTableEnsureCapacity` | symbol_table.zig |
| `symbolTableInit` | symbol_table.zig |
| `symbolTableInsert` | symbol_table.zig |
| `symbolTableLookup` | symbol_table.zig |
| `tempFnTypeId` | c89_emit.zig |
| `tick` | std_async.zig |
| `tokenKindLabel` | parser.zig |
| `tokenKindToString` | dump_tokens.zig |
| `topExpectedType` | semantic_analyzer.zig |
| `trackingAlloc` | allocator.zig |
| `trackingAllocatorInit` | allocator.zig |
| `trackingAllocatorReport` | allocator.zig |
| `trackingPeak` | allocator.zig |
| `trackingReset` | allocator.zig |
| `tryRecordCoercion` | semantic_analyzer.zig |
| `tstEdgesCount` | c89_emit.zig |
| `tstEdgesFill` | c89_emit.zig |
| `tstIsDep` | c89_emit.zig |
| `tstSeenInRange` | c89_emit.zig |
| `tstTopologicalSort` | c89_emit.zig |
| `tuAppend` | type_registry.zig |
| `tupAppend` | type_registry.zig |
| `typeDbOom` | type_registry.zig |
| `typeKindSrcStr` | diagnostics.zig |
| `typeKindTgtStr` | diagnostics.zig |
| `typeRegistryAppend` | type_registry.zig |
| `typeRegistryArrayByteSize` | type_registry.zig |
| `typeRegistryComputePackedLayout` | type_registry.zig |
| `typeRegistryComputePackedUnionLayout` | type_registry.zig |
| `typeRegistryEnsureCapacity` | type_registry.zig |
| `typeRegistryEnumBackingType` | type_registry.zig |
| `typeRegistryEnumHasExplicitBacking` | type_registry.zig |
| `typeRegistryErrorSetMemberIndex` | type_registry.zig |
| `typeRegistryGetOrCreateArbInt` | type_registry.zig |
| `typeRegistryGetOrCreateArray` | type_registry.zig |
| `typeRegistryGetOrCreateErrorSet` | type_registry.zig |
| `typeRegistryGetOrCreateErrorUnion` | type_registry.zig |
| `typeRegistryGetOrCreateFn` | type_registry.zig |
| `typeRegistryGetOrCreateManyPtr` | type_registry.zig |
| `typeRegistryGetOrCreateManyPtrQ` | type_registry.zig |
| `typeRegistryGetOrCreateModule` | type_registry.zig |
| `typeRegistryGetOrCreateOptional` | type_registry.zig |
| `typeRegistryGetOrCreatePtr` | type_registry.zig |
| `typeRegistryGetOrCreatePtrQ` | type_registry.zig |
| `typeRegistryGetOrCreateSlice` | type_registry.zig |
| `typeRegistryGetOrCreateTuple` | type_registry.zig |
| `typeRegistryGetPackedBitFields` | type_registry.zig |
| `typeRegistryGetPackedTotalBits` | type_registry.zig |
| `typeRegistryGetPackedUnionBitFields` | type_registry.zig |
| `typeRegistryGetPackedUnionTotalBits` | type_registry.zig |
| `typeRegistryGetPointeeType` | type_registry.zig |
| `typeRegistryGetSliceElem` | type_registry.zig |
| `typeRegistryGetStructFields` | type_registry.zig |
| `typeRegistryGetTypeState` | type_registry.zig |
| `typeRegistryGetUnionFields` | type_registry.zig |
| `typeRegistryIndexedElemType` | type_registry.zig |
| `typeRegistryInit` | type_registry.zig |
| `typeRegistryIntIsSigned` | type_registry.zig |
| `typeRegistryIntWidthBits` | type_registry.zig |
| `typeRegistryIsAssignable` | type_registry.zig |
| `typeRegistryIsErrorSet` | type_registry.zig |
| `typeRegistryIsInteger` | type_registry.zig |
| `typeRegistryIsNumeric` | type_registry.zig |
| `typeRegistryIsOptional` | type_registry.zig |
| `typeRegistryIsPacked` | type_registry.zig |
| `typeRegistryIsPointer` | type_registry.zig |
| `typeRegistryIsSlice` | type_registry.zig |
| `typeRegistryIsUnsigned` | type_registry.zig |
| `typeRegistryMarkFnPtrUsed` | type_registry.zig |
| `typeRegistryRegisterNamedType` | type_registry.zig |
| `typeRegistryRegisterPrimitives` | type_registry.zig |
| `typeRegistrySetPacked` | type_registry.zig |
| `typeResolverAddEdge` | type_resolver.zig |
| `typeResolverBuild` | type_resolver.zig |
| `typeResolverBuildDependencyGraph` | type_resolver.zig |
| `typeResolverGetSorted` | type_resolver.zig |
| `typeResolverInit` | type_resolver.zig |
| `typeResolverResolve` | type_resolver.zig |
| `typeResolverResolveLayout` | type_resolver.zig |
| `typeResolverResolveNames` | type_resolver.zig |
| `typeWidthBitsForKind` | type_registry.zig |
| `u32ArrayListAppend` | growable_array.zig |
| `u32ArrayListAppendInner` | ast.zig |
| `u32ArrayListAppendInner` | parser.zig |
| `u32ArrayListEnsureCapacity` | growable_array.zig |
| `u32ArrayListGetSlice` | growable_array.zig |
| `u32ArrayListInit` | growable_array.zig |
| `u32ArrayListPopOrNull` | growable_array.zig |
| `u32ToU32MapGet` | util/hash.zig |
| `u32ToU32MapGetOrAddDense` | util/hash.zig |
| `u32ToU32MapGrow` | util/hash.zig |
| `u32ToU32MapInit` | util/hash.zig |
| `u32ToU32MapInitCap` | util/hash.zig |
| `u32ToU32MapPut` | util/hash.zig |
| `u32ToU64MapGet` | util/hash.zig |
| `u32ToU64MapGrow` | util/hash.zig |
| `u32ToU64MapInit` | util/hash.zig |
| `u32ToU64MapInitCap` | util/hash.zig |
| `u32ToU64MapPut` | util/hash.zig |
| `u64ArrayListAppend` | growable_array.zig |
| `u64ArrayListAppendInner` | ast.zig |
| `u64ArrayListEnsureCapacity` | growable_array.zig |
| `u64ArrayListGetSlice` | growable_array.zig |
| `u64ArrayListInit` | growable_array.zig |
| `u64ToU32MapGet` | util/hash.zig |
| `u64ToU32MapGrow` | util/hash.zig |
| `u64ToU32MapInit` | util/hash.zig |
| `u64ToU32MapInitCap` | util/hash.zig |
| `u64ToU32MapPut` | util/hash.zig |
| `unAppend` | type_registry.zig |
| `unrAppend` | type_registry.zig |
| `vaListArgTemp` | lower.zig |
| `validateSignatureType` | analyzer.zig |
| `valuePoolAppend` | ast.zig |
| `valuePoolCacheSlot` | ast.zig |
| `valuePoolClose` | ast.zig |
| `valuePoolGetValue` | ast.zig |
| `valuePoolInit` | ast.zig |
| `valuePoolOpen` | ast.zig |
| `valuePoolResident` | ast.zig |
| `varDeclInitNeedsNameCache` | type_resolver.zig |
| `visitPreOrder` | ast.zig |
| `visitStatement` | analyzer.zig |
| `waitAll` | std_async.zig |
| `waitFor` | std_async.zig |
| `walkBlock` | analyzer.zig |
| `worklistEnsureCapacity` | type_resolver.zig |
| `worklistPop` | type_resolver.zig |
| `worklistPush` | type_resolver.zig |
| `write` | extern_c.zig |
| `writeHex` | c89_emit.zig |
| `writeStr` | diagnostics.zig |
| `writeU32` | main.zig |
| `writeUsizeExact` | allocator.zig |
| `xnAppend` | type_registry.zig |
| `xtAppend` | type_registry.zig |
| `zeroCallCFG` | lower.zig |
| `zeroChainInsts` | lower.zig |
| `zig_poison_fill` | include/zig_runtime.c |

---

## C. Marker → Phase → Meaning

### Phase Entry/Exit Markers

| Marker | Phase | Meaning |
|--------|-------|---------|
| `I` | phase_ImportResolution | Start of import resolution |
| `Z` | phase_ImportResolution | Import queue drained, all modules parsed |
| `S` | phase_SymbolRegistration | Start of symbol registration |
| `S0` | phase_SymbolRegistration | Listing root module decl kinds (AstKind enum values) |
| `Vi` | phase_SymbolRegistration | Variable info dump |
| `T` | phase_TypeResolution | Start of type resolution |
| `T0` | phase_TypeResolution | Listing root module decl kinds (AstKind enum values) |
| (none) | phase_FrontResolution | Phase writes no marker |
| `CE` | phase_ComptimeEvaluation | Start of comptime evaluation |
| `RS` | phase_SemanticAnalysis | Start of semantic analysis |
| `MZ` | phase_SemanticAnalysis | Module with zero ast_root (skip) |
| `AD` | phase_SemanticAnalysis | Accessing module decls |
| `DSE` | phase_SemanticAnalysis | After decl scope enumeration |
| `DN` | phase_SemanticAnalysis | Per-declaration processing |
| `SA` | phase_SemanticAnalysis | Before semanticAnalyzerResolveFnBody |
| `sA` | phase_SemanticAnalysis | After semanticAnalyzerResolveFnBody |
| `A` | phase_StaticAnalyzers | Start of static analysis |
| `AFS` | phase_AsyncFrameSize | Start of async frame-size pass |
| `L` | phase_LIRLowering | Start of LIR lowering |
| `nodes=` / `extra=` | phase_LIRLowering | AST node / extra-children counts |
| `M` | phase_LIRLowering | Module index marker |
| `R` | phase_LIRLowering | Root module marker |
| `F` | phase_LIRLowering | fn_decl found, emitting LirFunction |
| `A0` | phase_LIRLowering | Listing root module decl AstKind indices |
| `C` | phase_C89Emission | Start of C89 emission |
| `FINAL_FLUSH` | phase_C89Emission | Final buffer flush, emission complete |

### runCompiler Checkpoint Markers

| Marker | Location | Meaning |
|--------|----------|---------|
| `2` | runCompiler | After ImportResolution + peak check |
| `3` | runCompiler | Before SymbolRegistration |
| `3a` | runCompiler | Before SymbolRegistration (cont.) |
| `4` | runCompiler | Before SymbolRegistration (cont.) |
| `t1` | runCompiler | After TypeResolution + peak check |
| `t2` | runCompiler | After t1 + error check |

### Sub-phase / Debug Markers

> Detailed sub-phase markers are documented per-file in the individual tech docs (sections 00-12). These are included here for cross-reference.

| Marker | File | Meaning |
|--------|------|---------|
| `CAP:ent` | const_alias_prepass.zig | Enter const alias prepass |
| `CAP:tlm` | const_alias_prepass.zig | Top-level module count |
| `CAP:ac` / `CAP:ac0` | const_alias_prepass.zig | Alias count after catalog / none found |
| `GATE:g0`-`g3` | const_alias_prepass.zig | Gate checks in alias detection |
| `CAT:ik` / `CAT:dn` | const_alias_prepass.zig | Catalog: init kind / dependency name_id |
| `KAHN:start` / `KAHN:end` | const_alias_prepass.zig | Kahn layout algorithm start / end |
| `Ra` | symbol_registrator.zig | Register alias |
| `Rs` | symbol_registrator.zig | Register symbol |
| `Rf` | symbol_registrator.zig | Register function |
| `RCA:p/i/H` | symbol_registrator.zig | Register const alias (payload / ident / hash) |
| `IMR:n<m>` | symbol_registrator.zig | Import resolution marker |
| `M5:p<id>` | symbol_registrator.zig | Module import path payload |
| `FIX1:mid=<target_mtid>t=<target_mtid>n=<mod_id>` | symbol_registrator.zig | Module-import fixup: `mid` and `t` are the target module id (`mtid`); `n` is the declaring module id |
| `BOP:tk` | parser.zig | Binary op: token kind |
| `PF:` | parser.zig | Parser function entry |
| `PSWE:` | parser.zig | Parse switch expression |
| `PCB:` | parser.zig | Parse case body |
| `CPT:` | parser.zig | Capture pattern |
| `PPL:` | parser.zig | Payload list |
| `PSTK:` | parser.zig | Parse stmt/token kind |
| `VARC` | parser.zig | Parse const var decl |
| `VARV` | parser.zig | Parse var var decl |
| `V` / `v` | parser.zig | Var decl / var decl (ok) |
| `PDVx` | parser.zig | Parse var decl extra |
| `Fv` / `Fk` | parser.zig | Fn decl (var) / fn decl (kind) |
| `PIF:` | parser.zig | Parse if conditional |
| `PTC2:` | parser.zig | Parse for/while continue expr |
| `PBX:` | parser.zig | Parse block extent |
| `PLEN:` | parser.zig | Parse local length |
| `DP:` | parser.zig | Dump/panic: child buf stale |
| `CC:nul` | coercion.zig | Coercion: null target |
| `CLS:p` | coercion.zig | Coercion: ptr-to-slice base |

---

## D. Sentinel TypeId Table

> Defined in `type_registry.zig`. Source of truth — values below verified against source.

| ID | Constant | Zig Type |
|----|----------|----------|
| 1 | `TYPE_VOID` | `void` |
| 2 | `TYPE_BOOL` | `bool` |
| 3 | `TYPE_NORETURN` | `noreturn` |
| 4 | `TYPE_I8` | `i8` |
| 5 | `TYPE_I16` | `i16` |
| 6 | `TYPE_I32` | `i32` |
| 7 | `TYPE_I64` | `i64` |
| 8 | `TYPE_U8` | `u8` |
| 9 | `TYPE_U16` | `u16` |
| 10 | `TYPE_U32` | `u32` |
| 11 | `TYPE_U64` | `u64` |
| 12 | `TYPE_ISIZE` | `isize` |
| 13 | `TYPE_USIZE` | `usize` |
| 14 | `TYPE_C_CHAR` | `c_char` |
| 15 | `TYPE_F32` | `f32` |
| 16 | `TYPE_F64` | `f64` |
| 17 | `TYPE_NULL` | `@TypeOf(null)` |
| 18 | `TYPE_UNDEFINED` | `@TypeOf(undefined)` |
| 19 | `TYPE_INT_LIT` | (integer literal type) |
| 20 | `TYPE_TYPE` | `type` |
| 21 | `TYPE_VA_LIST` | `va_list` |

### Synthetic Field Indices

| Constant | Value | Used For |
|----------|-------|----------|
| `SLICE_FIELD_PTR` | 0 | `slice.ptr` field access |
| `SLICE_FIELD_LEN` | 1 | `slice.len` field access |
| `TU_FIELD_TAG` | 0 | Tagged union tag field |
| `TU_FIELD_PAYLOAD` | 1 | Tagged union payload field |
| `FIRST_USER_TYPE` | 20 | Stale — see note |

**Note:** `FIRST_USER_TYPE = 20` is stale. `TYPE_VA_LIST = 21` is now a primitive, so user
types in practice start at TypeId ≥ 22. The constant was already behind (`TYPE_TYPE` was a
primitive while `FIRST_USER_TYPE` read 20); the source constant is left unchanged (docs-only).
`TYPE_I64 = 7` and `TYPE_F64 = 16`.

---

## E. Data Structure → File

| Data Structure | File | Notes |
|----------------|------|-------|
| `AstNode` | ast.zig | 24-byte flat node (kind, flags, span_len, span_start, child_0-2); payload lives in the store's parallel payload block |
| `AstKind` | ast.zig | 112 variants (enum u8: 0-111); `mod_assign=74`, `swt_ex=56` |
| `AstStore` | ast.zig | Disk-backed node + payload blocks; `AstValuePool` for extra_children/extra_ranges/identifiers/int_values; growable arrays for float_values/string_values/fn_protos; block_table, 8 resident slots, spill |
| `AstValuePool` | ast.zig | Write-once append-only disk-backed pool (4/8-byte elements) with resident tail block + 8-slot fault-in cache |
| `FnProto` | ast.zig | Function prototype (name_id, params_start, params_count, call_conv, return_type_node) |
| `Type` | type_registry.zig | 32-byte runtime type descriptor (kind, state, flags, is_signed, width_bits, size, alignment, name_id, c_name_id, module_id, payload_idx) |
| `TypeKind` | type_registry.zig | 44 variants (enum u8: 0-43) |
| `TypeRegistry` | type_registry.zig | Type storage + per-kind payload arrays + ptr/slice/optional/array/eu/es/name caches |
| `TypeId` | type_registry.zig | Alias for `u32` |
| `LirInst` | lir.zig | 82-variant untagged union (LIR instruction) |
| `LirFunction` | lir.zig | Compiled function (name, module, blocks, params, hoisted temps, switch cases, side table, flags) |
| `LirSlot` / `LirSlotArrayList` | lir.zig | Spill-stream location of one serialized function / dynamic array of slots |
| `LirSideEntry` / `CallDirectData` / `TailCallData` | lir.zig | Side-table operand storage for `call_direct`/`tail_call` |
| `BasicBlock` | lir.zig | Control-flow block (id, insts, is_terminated) |
| `LirParam` | lir.zig | LIR function parameter (name_id, type_id, temp_id) |
| `TempDecl` | lir.zig | Temporary declaration (temp_id, type_id) |
| `SwitchCase` | lir.zig | LIR switch case (value, target_bb) |
| `ModuleGlobalDecl` | lir.zig | Module-scope global (name_id, module_id, type_id, has_runtime_init) |
| `Symbol` | symbol_table.zig | Symbol entry (name_id, type_id, kind, flags, decl_node, module_id, scope_level) |
| `SymbolKind` | symbol_table.zig | local/param/global/function/type_alias/module/test_sym |
| `SymbolTable` / `SymbolRegistry` | symbol_table.zig | Per-module symbol array / array of per-module tables |
| `ModuleEntry` | module_registry.zig | Module descriptor (id, path_id, source_file_id, state, ast_root, imports, symbol_table, type_offset, c_includes) |
| `ModuleRegistry` | module_registry.zig | Module graph registry (modules, import_edges, resolver, path/content maps + spill, import_queue) |
| `ModuleResolver` / `ImportQueue` | module_registry.zig | Import path resolution / LIFO import worklist |
| `ModuleState` | module_registry.zig | pending/parsing/parsed/resolved/failed |
| `StateMap` / `StateEntry` | state_map.zig | Delta-linked parent chain for forking state / name_id + state byte |
| `CompilerContext` | main.zig | Global compiler state (34 fields) |
| `CompilerCli` | main.zig | CLI argument struct (26 fields) |
| `Sand` / `SandSegment` / `GrowableSand` | allocator.zig | Bump allocator / one growable segment / growable tier header |
| `CompilerAlloc` | allocator.zig | 5-tier arena container (permanent, module, scratch, lir_read, emission) + pool budget |
| `TrackingAllocator` | allocator.zig | Per-allocation counters — kept but not wired into the pipeline |
| `StringInterner` / `InternEntry` | string_interner.zig | FNV-1a string interning |
| `SourceManager` / `SourceFile` | source_manager.zig | File source-text management + lazy fault-in |
| `DiagnosticCollector` / `Diagnostic` | diagnostics.zig | Error/warning collector |
| `CoercionTable` | coercion.zig | Type coercion rules |
| `ResolvedTypeTable` | resolved_type_table.zig | Dense block-addressed node → TypeId spill table + sparse source map |
| `U32ArrayList` / `U8ArrayList` | growable_array.zig | Generic dynamic u32 / u8 arrays |
| `PtrPayload`, `ArrayPayload`, `SlicePayload` | type_registry.zig | Type payload structs |
| `PackedBitField` / `PackedStructInfo` | type_registry.zig | Packed layout side tables |
| `NameMangler` | c89_emit.zig | C89 name mangling (inline; `name_mangler.zig` is a minimal counter) |
| `BufferedWriter` | c89_emit.zig | 4 KB buffered C89 output writer (fd sink) |
| `AsyncFrameLayout` | async_frame_layout.zig | Async frame layout (fields, size, state widths) |
| `AsyncTransformCtx` | async_state_machine.zig | Async step-machine transform context |

---

## F. AstKind → Handling Phases

| AstKind Group | Phases |
|---------------|--------|
| Declarations (var_decl, fn_decl, struct_decl, enum_decl, union_decl, field_decl, param_decl, test_decl, error_set_decl) | 1 (parser creates), 2 (symbol registration), 3 (type resolution), 6 (semantic analysis), 9 (LIR lowering) |
| Expressions (int_literal through builtin_call, operators, unary) | 1 (parser), 5 (comptime eval for builtin_call), 6 (semantic type-checking), 9 (LIR lowering) |
| Assignments (plain_assign, add_assign..or_assign, mod_assign) | 1 (parser), 6 (semantic), 9 (LIR lowering) |
| Wrapping / saturating ops (wrap_add..sat_shl_assign, 97-111) | 1 (parser), 6 (semantic), 9 (LIR lowering) |
| Statements (if_stmt, while_stmt, for_stmt, block, return_stmt, break_stmt, continue_stmt, defer_stmt, errdefer_stmt, labeled_stmt, expr_stmt, swt_ex/swt_prong) | 1 (parser), 6 (semantic), 7 (static analyzers), 9 (LIR lowering) |
| Types (ptr_type, many_ptr_type, array_type, slice_type, optional_type, error_union_type, fn_type) | 1 (parser), 3 (type resolution), 6 (semantic), 9 (lower: type metadata) |
| Literals & Constants | 1 (parser), 6 (semantic), 7 (static analyzers), 9 (LIR) |
| `range_exclusive` / `range_inclusive` | 1 (parser), 6 (semantic: switch ranges), 9 (LIR) |
| `payload_capture` | 1 (parser), 6 (semantic: if/while/for captures) |
| `import_expr`, `module_root`, `c_include` | 1 (parser + import resolution), 2 (symbol registration) |
| `builtin_call` | 1 (parser), 5 (comptime eval), 6 (semantic), 9 (LIR) |

---

## G. Arena Tier → Who Uses It

### Pool (256 MiB — `memory_pool_buf[POOL_SIZE]`, `POOL_SIZE = 268435456`)

One static pool backs all five tier arenas. `pool` is a monotonic bump `Sand` over it
and is never reset; a tier grows by carving a segment from the pool (or reusing a freed
segment). `checkCombinedPeak` compares `pool.peak / 1024` against the configured budget
(`max_mem` KB; the full pool when `max_mem == 0`).

### Tier Arenas

Each tier is a `GrowableSand` seeded with a 4 KB first segment. `growableSandGrow`
doubles the segment size (capped at 1 MiB; exact-fit when a single request is larger),
reuses a best-fit segment from the cross-arena free list after a reset, or carves a new
segment + `SandSegment` node from the pool.

| Arena | Contents | Reset Behavior |
|-------|----------|----------------|
| Permanent | StringInterner, SourceManager, DiagnosticCollector, interned strings, ModuleRegistry, SymbolRegistry, keyword table, const-alias prepass, type-name resolution | Never reset |
| Module | AstStore, ResolvedTypeTable, CoercionTable, `ctx.dep_graph` (dead field), enum_value_table, call_arg_types/call_param_map, comptime_values, async tables (suspending_fns, frame_sizes, state_widths, awaited_fns, async_hidden_fns, driver_targets, parent_result_*, async_layouts) | Reset once at the lowering→emission boundary; earlier phases share it |
| Scratch | Per-phase temporaries: input source read, parser tokens, per-phase DepGraph, TypeResolver workspace, semantic analyzer state, lowerer BasicBlocks | Reset at phase start; `sandResetPeak` at StaticAnalyzers entry |
| lir_read | LIR functions reloaded from the spill stream during C89 emission | Never reset |
| emission | LIR slots, error_code_registry, exported, global_decls, name mangler, module/type-group tables, emitted runtime support | Never reset |

Additional pool-backed growable sands live outside `CompilerAlloc`: the TypeRegistry
`type_db_arena`, the import resolver's `parser_arena` / `import_scratch_gs` / `src_arena`,
and the SourceManager diagnostic fault-in arena (`fault`, created lazily on first fault-in).

### CompilerAlloc Init Sequence (main.zig)

```
initCompilerAlloc():
  pool       ← sandInit(memory_pool_buf[0..POOL_SIZE])
  permanent  ← growableSandInit(&pool, 4096, "perm")
  module     ← growableSandInit(&pool, 4096, "module")
  scratch    ← growableSandInit(&pool, 4096, "scratch")
  lir_read   ← growableSandInit(&pool, 4096, "lir_read")
  emission   ← growableSandInit(&pool, 4096, "emission")
  max_mem = DEV_MAX_MEM
```

`main` overrides `max_mem` from the parsed `--max-mem`/`-mm` value and sets the spill
level (`-s<N>`). Per-tier peaks are read from each tier's `peak` field; the unwired
`TrackingAllocator` is not used by the pipeline.

### Per-Phase Scratch Users

| Phase | Data in Scratch |
|-------|-----------------|
| 1 — Import Resolution | Import queue, parsing temporaries |
| 2 — Symbol Registration | DepGraph per run, per-module state |
| 3 — Type Resolution | TypeResolver workspace, DepGraph |
| 4 — Front Resolution | Module-init resolution workspace |
| 5 — Comptime Evaluation | (minimal — operates on existing data) |
| 6 — Semantic Analysis | Analyzer state, expected-type stack |
| 7 — Static Analyzers | StateMap per function (delta-linked), defer queues |
| 8 — Async Frame Size | (module arena — publishes frame/state maps) |
| 9 — LIR Lowering | Lowerer struct, per-function BasicBlocks, insts |
| 10 — C89 Emission | NameMangler, BufferedWriter, C89Emitter (scratch + emission) |

---

## Tech Doc Index

| File | Covers | Phase |
|------|--------|-------|
| `INDEX.md` | All — master cross-reference | — |
| `00_shared_infra.md` | `allocator.zig`, `string_interner.zig`, `source_manager.zig`, `diagnostics.zig`, `pal.zig`, `growable_array.zig`, `panic.zig`, `config.zig`, `util/` | Infra |
| `00_lexer_parser.md` | `token.zig`, `lexer.zig`, `parser.zig`, `ast.zig`, `print_decomposition.zig`, `dump_ast.zig`, `dump_tokens.zig`, `ast_dump_main.zig` | Pre-phase |
| `01_import_resolution.md` | `import_resolver.zig`, `module_registry.zig` | Phase 1 |
| `02_symbol_registration.md` | `symbol_registrator.zig`, `symbol_table.zig` | Phase 2 |
| `03_type_resolution.md` | `type_resolver.zig`, `type_registry.zig`, `const_alias_prepass.zig`, `front_resolution.zig` | Phases 3-4 |
| `04_comptime_eval.md` | `comptime_eval.zig` | Phase 5 |
| `05_semantic_analysis.md` | `semantic_analyzer.zig`, `coercion.zig`, `resolved_type_table.zig`, `constraint_checker.zig`, `assign_helper.zig` | Phase 6 |
| `06_static_analyzers.md` | `analyzer.zig`, `state_map.zig` | Phase 7 |
| `07_lir_lowering.md` | `lower.zig`, `lir.zig`, `lir_opt_pass.zig`, `lir_stream.zig`, `spill_store.zig` | Phase 9 |
| `08_c89_emission.md` | `c89_emit.zig`, `name_mangler.zig`, `cinclude.zig`, `emit_support.zig` | Phase 10 |
| `09_pipeline_orchestration.md` | `main.zig`, `main_dump.zig`, `main_exp.zig`, `strip_main.zig` | Orchestration |
| `10_c_runtime.md` | `sf/src/include/*`, `c_exit.c`, `extern_c.zig`, `extern_c_z98.zig` | C runtime |
| `11_build_system.md` | `sf/scripts/*`, `scripts/seed/*`, `release/seed/*` | Build system |
| `12_async_coroutines.md` | `async_analysis.zig`, `async_frame_layout.zig`, `async_state_machine.zig`, `std_async.zig` | Phase 8 / async |

### Variant counts

| Enum | Variants | Source |
|------|----------|--------|
| `TokenKind` | 108 (0..107) | `token.zig` |
| `AstKind` | 112 (0..111) | `ast.zig` |
| `TypeKind` | 44 (0..43) | `type_registry.zig` |
| `LirInst` | 82 | `lir.zig` |
| `TypeId` sentinels | 21 (1..21) | `type_registry.zig` |
