# zig1 Pipeline — Master Index

> Source-files: `sf/src/*.zig` | Cross-reference for all 13 tech docs

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
┌─────────────────────────────────────────────────────────────────────┐
│  1. Import Resolution          import_resolver.zig   I⇄Z   scratch  │
│     module_registry.zig                 markers: I, Z               │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ 2, 3, 3a, 4 (runCompiler checkpoints)
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  2. Symbol Registration        symbol_registrator.zig  S     scratch │
│     symbol_table.zig                    markers: S, S0, Vi          │
└─────────────────────┬───────────────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  3. Type Resolution            type_resolver.zig       T     perm   │
│     type_registry.zig, const_alias_prepass.zig   markers: T, T0     │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ t1, t2 (runCompiler checkpoints + error check)
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  4. Comptime Evaluation        comptime_eval.zig      CE    (none)  │
│                                    marker: CE                       │
└─────────────────────┬───────────────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  5. Semantic Analysis          semantic_analyzer.zig  RS     scr    │
│     coercion.zig, resolved_type_table.zig, constraint_checker.zig   │
│     markers: RS, MZ, AD, DSE, DN, SA, sA, P0-P3, V2, REG          │
├─────────────────────┬───────────────────────────────────────────────┤
│                     │ error check (exit 2 if errors)                │
└─────────────────────┬───────────────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  6. Static Analyzers           analyzer.zig            A     scr    │
│     state_map.zig                       markers: A                  │
├─────────────────────┬───────────────────────────────────────────────┤
│                     │ error check (exit 2 if errors)                │
└─────────────────────┬───────────────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  7. LIR Lowering               lower.zig               L     scr    │
│     lir.zig                     markers: L, M, R, F, A0            │
├─────────────────────┬───────────────────────────────────────────────┤
│                     │ error check (exit 2 if errors)                │
└─────────────────────┬───────────────────────────────────────────────┘
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  8. C89 Emission               c89_emit.zig            C     scr    │
│     name_mangler.zig, cinclude.zig   markers: C, FINAL_FLUSH       │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
                 output.c
```

| Phase | Function | Files | Key Markers | Arena Tier |
|-------|----------|-------|-------------|------------|
| 1 | `phase_ImportResolution` | import_resolver.zig, module_registry.zig | `I`, `Z` | scratch |
| 2 | `phase_SymbolRegistration` | symbol_registrator.zig, symbol_table.zig | `S`, `S0`, `Vi` | scratch |
| 3 | `phase_TypeResolution` | type_resolver.zig, type_registry.zig, const_alias_prepass.zig | `T`, `T0` | permanent |
| 4 | `phase_ComptimeEvaluation` | comptime_eval.zig | `CE` | (none) |
| 5 | `phase_SemanticAnalysis` | semantic_analyzer.zig, coercion.zig, resolved_type_table.zig, constraint_checker.zig | `RS`, `MZ`, `AD`, `DSE`, `DN`, `SA`, `sA`, `P0-P3`, `V2`, `REG` | scratch |
| 6 | `phase_StaticAnalyzers` | analyzer.zig, state_map.zig | `A` | scratch |
| 7 | `phase_LIRLowering` | lower.zig, lir.zig | `L`, `M`, `R`, `F` | scratch |
| 8 | `phase_C89Emission` | c89_emit.zig, name_mangler.zig, cinclude.zig | `C`, `FINAL_FLUSH` | scratch |

---

## B. Function → File Index

Full alphabetical index of all documented functions across all phases and modules, extracted from tech docs (00-11).

| Function | File | Line |
|----------|------|------|
| `__bootstrap_panic` | zig_runtime.c | 70 |
| `__bootstrap_print` | zig_runtime.c | 67 |
| `__bootstrap_print_char` | zig_runtime.c | 69 |
| `__bootstrap_print_int` | zig_runtime.c | 68 |
| `__bootstrap_sleep_ms` | zig_runtime.c | 72 |
| `__bootstrap_write` | zig_runtime.c | 71 |
| `addLocalDecl` | lower.zig | 470 |
| `addTypeDependencies` | symbol_registrator.zig | 70 |
| `alignUp` | type_registry.zig | 261 |
| `alignUp` | type_resolver.zig | 99 |
| `analyzeExpr` | analyzer.zig | 449 |
| `analyzeSignature` | analyzer.zig | 392 |
| `appendBucket` | string_interner.zig | 52 |
| `appendEntry` | string_interner.zig | 58 |
| `applyCoercion` | lower.zig | 3991 |
| `applyNullGuardRefinement` | analyzer.zig | 568 |
| `arena_alloc` | zig_runtime.c | 93 |
| `arena_alloc_default` | zig_runtime.c | 154 |
| `arena_create` | zig_runtime.c | 71 |
| `arena_destroy` | zig_runtime.c | 142 |
| `arena_free` | zig_runtime.c | 158 |
| `arena_reset` | zig_runtime.c | 131 |
| `argCount` | pal.zig | 80 |
| `argGet` | pal.zig | 84 |
| `arrayAppend` | type_registry.zig | 181 |
| `astNodeArrayListAppend` | growable_array.zig | 124 |
| `astNodeArrayListAppendInner` | ast.zig | 144 |
| `astNodeArrayListEnsureCapacity` | growable_array.zig | 110 |
| `astNodeArrayListGetSlice` | growable_array.zig | 130 |
| `astNodeArrayListInit` | growable_array.zig | 99 |
| `astStoreAddCharLiteral` | ast.zig | 323 |
| `astStoreAddExtraChildren` | ast.zig | 301 |
| `astStoreAddFloatLiteral` | ast.zig | 329 |
| `astStoreAddFnProto` | ast.zig | 352 |
| `astStoreAddIdentifier` | ast.zig | 346 |
| `astStoreAddIntLiteral` | ast.zig | 317 |
| `astStoreAddNode` | ast.zig | 289 |
| `astStoreAddStringLiteral` | ast.zig | 340 |
| `astStoreComputeMemory` | ast.zig | 402 |
| `astStoreGetExtraChildren` | ast.zig | 311 |
| `astStoreInit` | ast.zig | 267 |
| `binary_search` | mem.zig | 9 |
| `bufferedWriterFlush` | c89_emit.zig | 36 |
| `bufferedWriterInit` | c89_emit.zig | 32 |
| `bufferedWriterWrite` | c89_emit.zig | 44 |
| `bufferedWriterWriteByte` | c89_emit.zig | 59 |
| `bufferedWriterWriteIndent` | c89_emit.zig | 65 |
| `byteArrayListAppend` | growable_array.zig | 80 |
| `byteArrayListGetSlice` | growable_array.zig | 86 |
| `byteArrayListGrow` | growable_array.zig | 66 |
| `byteArrayListInit` | growable_array.zig | 57 |
| `c89EmitterInit` | c89_emit.zig | 457 |
| `c89NeedsEmitEdge` | c89_emit.zig | 740 |
| `canLiteralFitInType` | type_registry.zig | 884 |
| `checkCombinedPeak` | allocator.zig | 94 |
| `checkLeaksOnScopeExit` | analyzer.zig | 270 |
| `checkReturnProvenance` | analyzer.zig | 102 |
| `checkReturnType` | constraint_checker.zig | 11 |
| `checkSwitchExhaust` | constraint_checker.zig | 30 |
| `cincludeUnionAll` | cinclude.zig | 7 |
| `classifyCoercion` | coercion.zig | 85 |
| `classifyExpr` | analyzer.zig | 499 |
| `classifyProvenance` | analyzer.zig | 61 |
| `classifyTypeEmissionGroups` | type_resolver.zig | 332 |
| `coercionTableAdd` | coercion.zig | 65 |
| `coercionTableEnsureCapacity` | coercion.zig | 43 |
| `coercionTableGet` | coercion.zig | 79 |
| `coercionTableInit` | coercion.zig | 35 |
| `compareDiag` | diagnostics.zig | 154 |
| `compositeNameId` | analyzer.zig | 211 |
| `comptimeEvalBinOp` | comptime_eval.zig | 41 |
| `comptimeEvalBuiltin` | comptime_eval.zig | 96 |
| `comptimeEvalEvaluate` | comptime_eval.zig | 141 |
| `comptimeEvalInit` | comptime_eval.zig | 28 |
| `comptimeEvalResolveTypeArg` | comptime_eval.zig | 88 |
| `constAliasPrepass` | const_alias_prepass.zig | 58 |
| `constraintCheckerCheckBreakContinue` | constraint_checker.zig | 70 |
| `copyStr` | format.zig | 1 |
| `createBlock` | lower.zig | 364 |
| `cstrToSlice` | main.zig | 774 |
| `dbgPrintU32` | c89_emit.zig | 75 |
| `deferQueueEnsureCapacity` | analyzer.zig | 379 |
| `dependEnsureCapacity` | type_resolver.zig | 52 |
| `depGraphAddEdge` | symbol_registrator.zig | 48 |
| `depGraphEnsureCapacity` | symbol_registrator.zig | 38 |
| `depGraphFinalize` | symbol_registrator.zig | 54 |
| `depGraphInit` | symbol_registrator.zig | 27 |
| `detectNullGuard` | analyzer.zig | 539 |
| `diagnosticArrayListAppend` | diagnostics.zig | 205 |
| `diagnosticArrayListEnsureCapacity` | diagnostics.zig | 191 |
| `diagnosticArrayListGetSlice` | diagnostics.zig | 211 |
| `diagnosticArrayListInit` | diagnostics.zig | 182 |
| `diagnosticBuilderMakeMsg` | diagnostics.zig | 340 |
| `diagnosticCollectorAdd` | diagnostics.zig | 250 |
| `diagnosticCollectorAddNote` | diagnostics.zig | 298 |
| `diagnosticCollectorAddRelatedSpan` | diagnostics.zig | 307 |
| `diagnosticCollectorErrorCount` | diagnostics.zig | 290 |
| `diagnosticCollectorFlushAndExit` | diagnostics.zig | 335 |
| `diagnosticCollectorHasErrors` | diagnostics.zig | 286 |
| `diagnosticCollectorInit` | diagnostics.zig | 228 |
| `diagnosticCollectorIntern` | diagnostics.zig | 246 |
| `diagnosticCollectorPrintAll` | diagnostics.zig | 359 |
| `diagnosticCollectorWarningCount` | diagnostics.zig | 294 |
| `emAppend` | type_registry.zig | 233 |
| `emitArrayType` | c89_emit.zig | 1163 |
| `emitBaseIdxAccess` | c89_emit.zig | 144 |
| `emitCStringLiteral` | c89_emit.zig | 2241 |
| `emitEnumType` | c89_emit.zig | 1286 |
| `emitErrorSetType` | c89_emit.zig | 1255 |
| `emitErrorUnionType` | c89_emit.zig | 1410 |
| `emitFieldAssign` | c89_emit.zig | 181 |
| `emitFnPtrType` | c89_emit.zig | 1224 |
| `emitFunctionBody` | c89_emit.zig | 3685 |
| `emitFunctionForwardDecl` | c89_emit.zig | 1518 |
| `emitFunctionSignature` | c89_emit.zig | 1452 |
| `emitHoistedDecls` | c89_emit.zig | 1684 |
| `emitInst` | c89_emit.zig | 2272 |
| `emitInst` | lower.zig | 321 |
| `emitInt64Type` | c89_emit.zig | 1316 |
| `emitModule` | c89_emit.zig | 1600 |
| `emitModuleFooter` | c89_emit.zig | 1595 |
| `emitModuleHeader` | c89_emit.zig | 1558 |
| `emitOptionalType` | c89_emit.zig | 1366 |
| `emitSliceType` | c89_emit.zig | 1334 |
| `emitSpecialTypes` | c89_emit.zig | 884 |
| `emitStructType` | c89_emit.zig | 1132 |
| `emitTaggedUnionType` | c89_emit.zig | 999 |
| `emitTypeDefinition` | c89_emit.zig | 1195 |
| `emitUint64Type` | c89_emit.zig | 1325 |
| `enAppend` | type_registry.zig | 209 |
| `ensureCapacityBuckets` | string_interner.zig | 24 |
| `ensureCapacityEntries` | string_interner.zig | 38 |
| `errLitSrcType` | semantic_analyzer.zig | 622 |
| `esAppend` | type_registry.zig | 197 |
| `euAppend` | type_registry.zig | 193 |
| `evalConstU32Full` | type_resolver.zig | 557 |
| `executeDeferQueue` | analyzer.zig | 604 |
| `exit` | pal.zig | 67 |
| `expandDefers` | lower.zig | 3922 |
| `extractDigit` | format.zig | 48 |
| `f64ArrayListAppend` | growable_array.zig | 208 |
| `f64ArrayListAppendInner` | ast.zig | 178 |
| `f64ArrayListEnsureCapacity` | growable_array.zig | 194 |
| `f64ArrayListGetSlice` | growable_array.zig | 214 |
| `f64ArrayListInit` | growable_array.zig | 183 |
| `feAppend` | type_registry.zig | 229 |
| `fieldEmbedsByValue` | type_resolver.zig | 323 |
| `fileExists` | pal.zig | 45 |
| `findLocalTemp` | lower.zig | 940 |
| `fnAppend` | type_registry.zig | 201 |
| `fnProtoArrayListAppend` | growable_array.zig | 252 |
| `fnProtoArrayListAppendInner` | ast.zig | 195 |
| `fnProtoArrayListEnsureCapacity` | growable_array.zig | 238 |
| `fnProtoArrayListGetSlice` | growable_array.zig | 258 |
| `fnProtoArrayListInit` | growable_array.zig | 227 |
| `fnv1a` | hash.zig | 4 |
| `formatF64` | format.zig | 61 |
| `formatU32` | diagnostics.zig | 134 |
| `formatU32` | format.zig | 10 |
| `formatU64` | format.zig | 29 |
| `getBinOpStr` | c89_emit.zig | 2189 |
| `getCheckedCastFnName` | c89_emit.zig | 2215 |
| `getCTypeName` | c89_emit.zig | 509 |
| `getInfixInfo` | parser.zig | 1815 |
| `getLevelName` | diagnostics.zig | 109 |
| `getPrintFnName` | c89_emit.zig | 2229 |
| `getTempTypeByIndex` | c89_emit.zig | 696 |
| `getUnOpStr` | c89_emit.zig | 2209 |
| `growDep` | const_alias_prepass.zig | 41 |
| `growWpEdges` | type_resolver.zig | 535 |
| `handleAllocAssign` | analyzer.zig | 285 |
| `handleAllocCall` | analyzer.zig | 235 |
| `handleFreeCall` | analyzer.zig | 240 |
| `handleNullAssign` | analyzer.zig | 593 |
| `handleNullVarDecl` | analyzer.zig | 581 |
| `handleOwnershipPass` | analyzer.zig | 328 |
| `handleOwnershipReturn` | analyzer.zig | 316 |
| `hexDigitValue` | lexer.zig | 432 |
| `hoistTemps` | lower.zig | 3942 |
| `importEdgesAppend` | module_registry.zig | 191 |
| `importEdgesEnsureCapacity` | module_registry.zig | 179 |
| `importQueueDequeue` | module_registry.zig | 323 |
| `importQueueEnqueue` | module_registry.zig | 314 |
| `importQueueInit` | module_registry.zig | 303 |
| `importQueuePendingAppend` | module_registry.zig | 291 |
| `importQueuePendingEnsureCapacity` | module_registry.zig | 279 |
| `importQueuePendingPop` | module_registry.zig | 297 |
| `inDegreeEnsureCapacity` | type_resolver.zig | 90 |
| `initArgs` | pal.zig | 75 |
| `initCompilerAlloc` | allocator.zig | 81 |
| `initKeywordTable` | token.zig | 133 |
| `isAllocCall` | analyzer.zig | 172 |
| `isAlpha` | lexer.zig | 420 |
| `isAlphaNum` | lexer.zig | 428 |
| `isBasePtrToArray` | c89_emit.zig | 130 |
| `isC89Keyword` | c89_emit.zig | 125 |
| `isDigit` | lexer.zig | 424 |
| `isDigitInBase` | lexer.zig | 482 |
| `isFreeCall` | analyzer.zig | 192 |
| `isIdentExpr` | analyzer.zig | 531 |
| `isNullExpr` | analyzer.zig | 521 |
| `isTempOrBuiltin` | c89_emit.zig | 113 |
| `isU64MaxLiteral` | lexer.zig | 596 |
| `isValueDependency` | type_registry.zig | 665 |
| `itoa` | itoa.zig | 1 |
| `itoa64` | itoa.zig | 19 |
| `joinPath` | module_registry.zig | 109 |
| `lexerAdvance` | lexer.zig | 155 |
| `lexerInit` | lexer.zig | 29 |
| `lexerIsAtEnd` | lexer.zig | 179 |
| `lexerMakeErrorToken` | lexer.zig | 243 |
| `lexerMakeToken` | lexer.zig | 233 |
| `lexerMatch` | lexer.zig | 183 |
| `lexerNextToken` | lexer.zig | 45 |
| `lexerParseEscapeSequence` | lexer.zig | 456 |
| `lexerParseHexEscape` | lexer.zig | 439 |
| `lexerPeek` | lexer.zig | 168 |
| `lexerPeekN` | lexer.zig | 173 |
| `lexerRunAllTests` | lexer.zig | 679 |
| `lexerScanBuiltinIdentifier` | lexer.zig | 404 |
| `lexerScanChar` | lexer.zig | 291 |
| `lexerScanIdentifierOrKeyword` | lexer.zig | 377 |
| `lexerScanNumber` | lexer.zig | 320 |
| `lexerScanString` | lexer.zig | 253 |
| `lexerSkipWSC` | lexer.zig | 189 |
| `lexerTestBuiltinIdentifier` | lexer.zig | 908 |
| `lexerTestDiagnostics` | lexer.zig | 926 |
| `lexerTestHelpers` | lexer.zig | 702 |
| `lexerTestIdentifierKeywords` | lexer.zig | 880 |
| `lexerTestOperators` | lexer.zig | 752 |
| `lexerTestSanityCheck` | lexer.zig | 696 |
| `lexerTestScanChar` | lexer.zig | 857 |
| `lexerTestScanNumber` | lexer.zig | 794 |
| `lexerTestScanString` | lexer.zig | 834 |
| `lexerTestSkipWhitespaceAndComments` | lexer.zig | 739 |
| `lookupKeyword` | token.zig | 178 |
| `lowerAssignLValue` | lower.zig | 694 |
| `lowererInit` | lower.zig | 256 |
| `lowerExpr` | lower.zig | 446 |
| `lowerExprImpl` | lower.zig | 1032 |
| `lowerFn` | lower.zig | 4092 |
| `lowerLValueAddr` | lower.zig | 640 |
| `lowerStmt` | lower.zig | 3197 |
| `main` | main.zig | 109 |
| `mainCRTStartup` | zig_pal.c | 182 |
| `mangleLocalName` | c89_emit.zig | 1436 |
| `mangleTempName` | c89_emit.zig | 1667 |
| `markersEnabled` | pal.zig | 90 |
| `markerWrite` | pal.zig | 96 |
| `markerWriteInt` | pal.zig | 102 |
| `matchFlag` | main.zig | 764 |
| `materializeInto` | lower.zig | 852 |
| `max` | util.zig | 9 |
| `mem_eql` | mem.zig | 1 |
| `min` | util.zig | 1 |
| `moduleDirPath` | module_registry.zig | 121 || `moduleEntryArrayListAppend` | module_registry.zig | 68 |
| `moduleEntryArrayListEnsureCapacity` | module_registry.zig | 54 |
| `moduleEntryArrayListGetSlice` | module_registry.zig | 74 |
| `moduleEntryArrayListInit` | module_registry.zig | 43 |
| `moduleRegistryAddImport` | module_registry.zig | 252 |
| `moduleRegistryAddModule` | module_registry.zig | 221 |
| `moduleRegistryCollectIncludes` | module_registry.zig | 439 |
| `moduleRegistryGetModules` | module_registry.zig | 240 |
| `moduleRegistryGetOrCreateModule` | module_registry.zig | 244 |
| `moduleRegistryInit` | module_registry.zig | 231 |
| `moduleRegistryParseModule` | import_resolver.zig | 33 |
| `moduleRegistryResolveImport` | module_registry.zig | 293 |
| `moduleRegistryResolveImports` | import_resolver.zig | 82 |
| `moduleRegistrySetSourceMan` | module_registry.zig | 217 |
| `moduleRegistrySortModules` | module_registry.zig | 327 |
| `moduleRegistryVerifyOrder` | module_registry.zig | 414 |
| `moduleResolverAddSearchDir` | module_registry.zig | 164 |
| `moduleResolverInit` | module_registry.zig | 131 |
| `moduleResolverResolve` | module_registry.zig | 144 |
| `nameCacheGet` | type_registry.zig | 304 |
| `nameCachePut` | type_registry.zig | 313 |
| `nameManglerMangle` | c89_emit.zig | 379 |
| `nextTemp` | lower.zig | 325 |
| `nodeHasExtraChildren` | ast.zig | 358 |
| `normalizePath` | util/path.zig | 25 |
| `onDoubleFreeStmt` | analyzer.zig | 723 |
| `onLifetimeStmt` | analyzer.zig | 704 |
| `onNullStmt` | analyzer.zig | 700 |
| `optAppend` | type_registry.zig | 189 |
| `pal_abort` | zig_pal.c | 106 |
| `pal_f64_to_str` | zig_pal.c | 141 |
| `pal_i64_to_str` | zig_pal.c | 115 |
| `pal_memcpy` | zig_pal.c | 33 |
| `pal_print_stderr` | zig_pal.c | 76 |
| `pal_print_stdout` | zig_pal.c | 91 |
| `pal_reverse` | zig_pal.c | 44 |
| `pal_strlen` | zig_pal.c | 22 |
| `pal_u64_to_str` | zig_pal.c | 136 |
| `pal_u64_to_str_buf` | zig_pal.c | 57 |
| `panicHandler` | panic.zig | 4 |
| `parseArgs` | main.zig | 631 |
| `parseColorMode` | main.zig | 816 |
| `parseErrorFormat` | main.zig | 825 |
| `parseF64` | lexer.zig | 536 |
| `parserAddBinary` | parser.zig | 230 |
| `parserAddError` | parser.zig | 160 |
| `parserAdvance` | parser.zig | 109 |
| `parserEmitErrorNode` | parser.zig | 1225 |
| `parserExpect` | parser.zig | 143 |
| `parserInit` | parser.zig | 56 |
| `parserParseAnonymousLiteral` | parser.zig | 702 |
| `parserParseArrayLiteral` | parser.zig | 736 |
| `parserParseBlock` | parser.zig | 1745 |
| `parserParseBoolLiteral` | parser.zig | 526 |
| `parserParseBracketType` | parser.zig | 943 |
| `parserParseBreakExpr` | parser.zig | 1604 |
| `parserParseBreakStmt` | parser.zig | 1643 |
| `parserParseBuiltinCall` | parser.zig | 565 |
| `parserParseCatchRHS` | parser.zig | 418 |
| `parserParseCharLiteral` | parser.zig | 520 |
| `parserParseCInclude` | parser.zig | 651 |
| `parserParseContainerDecl` | parser.zig | 1684 |
| `parserParseContinueExpr` | parser.zig | 1621 |
| `parserParseContinueStmt` | parser.zig | 1648 |
| `parserParseDeferStmt` | parser.zig | 1653 |
| `parserParseDotAccess` | parser.zig | 355 |
| `parserParseEnumLiteral` | parser.zig | 728 |
| `parserParseEnumType` | parser.zig | 1086 |
| `parserParseErrdeferStmt` | parser.zig | 1664 |
| `parserParseErrorLiteral` | parser.zig | 680 |
| `parserParseErrorSetDecl` | parser.zig | 1027 |
| `parserParseErrorSetDeclBody` | parser.zig | 1032 |
| `parserParseErrorUnionType` | parser.zig | 986 |
| `parserParseExprPrec` | parser.zig | 179 |
| `parserParseExprStmt` | parser.zig | 1255 |
| `parserParseExternDecl` | parser.zig | 1333 |
| `parserParseFieldInitListNamed` | parser.zig | 447 |
| `parserParseFloatLiteral` | parser.zig | 503 |
| `parserParseFnCall` | parser.zig | 394 |
| `parserParseFnDecl` | parser.zig | 1346 |
| `parserParseFnType` | parser.zig | 994 |
| `parserParseForStmt` | parser.zig | 1537 |
| `parserParseGroupedExpr` | parser.zig | 556 |
| `parserParseIdentExpr` | parser.zig | 540 |
| `parserParseIfExpr` | parser.zig | 766 |
| `parserParseIfStmt` | parser.zig | 1420 |
| `parserParseImportExpr` | parser.zig | 614 |
| `parserParseIndexOrSlice` | parser.zig | 371 |
| `parserParseIntLiteral` | parser.zig | 497 |
| `parserParseLabeledBlockExpr` | parser.zig | 1271 |
| `parserParseLabeledStmt` | parser.zig | 1261 |
| `parserParseModuleRoot` | parser.zig | 1232 |
| `parserParseOptionalType` | parser.zig | 978 |
| `parserParseOrelseRHS` | parser.zig | 440 |
| `parserParsePostfixChain` | parser.zig | 331 |
| `parserParsePrefixUnary` | parser.zig | 548 |
| `parserParsePrimary` | parser.zig | 284 |
| `parserParsePtrType` | parser.zig | 928 |
| `parserParsePubDecl` | parser.zig | 1321 |
| `parserParseReturnExpr` | parser.zig | 1590 |
| `parserParseReturnStmt` | parser.zig | 1638 |
| `parserParseSingleToken` | parser.zig | 534 |
| `parserParseStatement` | parser.zig | 1192 |
| `parserParseStringLiteral` | parser.zig | 514 |
| `parserParseStructInit` | parser.zig | 472 |
| `parserParseStructType` | parser.zig | 1056 |
| `parserParseSwitchExpr` | parser.zig | 786 |
| `parserParseSwitchProng` | parser.zig | 818 |
| `parserParseSwitchStmt` | parser.zig | 1586 |
| `parserParseTestDecl` | parser.zig | 1667 |
| `parserParseTryExpr` | parser.zig | 694 |
| `parserParseType` | parser.zig | 905 |
| `parserParseTypeName` | parser.zig | 1174 |
| `parserParseUnionType` | parser.zig | 1126 |
| `parserParseVarDecl` | parser.zig | 1284 |
| `parserParseWhileStmt` | parser.zig | 1486 |
| `parserPeek` | parser.zig | 98 |
| `parserPeekN` | parser.zig | 103 |
| `parserSetModuleContext` | parser.zig | 86 |
| `parserSynchronize` | parser.zig | 165 |
| `parserTokenText` | parser.zig | 92 |
| `parseSize` | main.zig | 782 |
| `parseU32` | main.zig | 802 |
| `parseU64` | lexer.zig | 492 |
| `phase_C89Emission` | main.zig | 602 |
| `phase_ComptimeEvaluation` | main.zig | 326 |
| `phase_ImportResolution` | main.zig | 249 |
| `phase_LIRLowering` | main.zig | 505 |
| `phase_SemanticAnalysis` | main.zig | 343 |
| `phase_StaticAnalyzers` | main.zig | 470 |
| `phase_SymbolRegistration` | main.zig | 259 |
| `phase_TypeResolution` | main.zig | 289 |
| `popExpectedType` | semantic_analyzer.zig | 1459 |
| `populateTypePayload` | symbol_registrator.zig | 84 |
| `precFromInt` | parser.zig | 1806 |
| `precToInt` | parser.zig | 1802 |
| `printUsage` | main.zig | 853 |
| `printUsize` | allocator.zig | 114 |
| `ptrAppend` | type_registry.zig | 177 |
| `pushDefer` | lower.zig | 3914 |
| `pushExpectedType` | semantic_analyzer.zig | 1443 |
| `readFile` | pal.zig | 16 |
| `registerDecl` | symbol_registrator.zig | 213 |
| `registerLocalDecl` | semantic_analyzer.zig | 154 |
| `registerModuleSymbols` | symbol_registrator.zig | 399 |
| `registerPrimitive` | type_registry.zig | 246 |
| `registerPrimitiveName` | type_registry.zig | 621 |
| `resolveAggregateFieldTypesAll` | type_resolver.zig | 973 |
| `resolveDeclAggregateFieldTypes` | type_resolver.zig | 884 |
| `resolvedSourceTableGet` | resolved_type_table.zig | 86 |
| `resolvedSourceTableSet` | resolved_type_table.zig | 86 |
| `resolvedTypeTableEnsureCapacity` | resolved_type_table.zig | 37 |
| `resolvedTypeTableGet` | resolved_type_table.zig | 65 |
| `resolvedTypeTableInit` | resolved_type_table.zig | 37 |
| `resolvedTypeTableSet` | resolved_type_table.zig | 51 |
| `resolveFnSignatures` | type_resolver.zig | 993 |
| `resolveForHeader` | semantic_analyzer.zig | 1491 |
| `resolveIfHeader` | semantic_analyzer.zig | 1470 |
| `resolveNamedTypeExpressions` | type_resolver.zig | 949 |
| `resolveOrigin` | analyzer.zig | 49 |
| `resolveReturnStmt` | semantic_analyzer.zig | 633 |
| `resolveStmtTypes` | main.zig | 413 |
| `resolveTempName` | c89_emit.zig | 2259 |
| `resolveTypeExpr` | main.zig | 464 |
| `resolveTypeExprFull` | type_resolver.zig | 587 |
| `resolveWellKnownTypeName` | const_alias_prepass.zig | 15 |
| `resolveWhileHeader` | semantic_analyzer.zig | 1523 |
| `runAllAnalyzers` | analyzer.zig | 772 |
| `runCompiler` | main.zig | 184 |
| `runDoubleFreeAnalyzer` | analyzer.zig | 765 |
| `runLifetimeAnalyzer` | analyzer.zig | 747 |
| `runNullAnalyzer` | analyzer.zig | 740 |
| `runSignatureAnalyzer` | analyzer.zig | 736 |
| `sandAlloc` | allocator.zig | 26 |
| `sandInit` | allocator.zig | 12 |
| `sandReallocInPlace` | allocator.zig | 55 |
| `sandReset` | allocator.zig | 47 |
| `sandResetPeak` | allocator.zig | 51 |
| `searchDirArrayListAppend` | module_registry.zig | 97 |
| `searchDirArrayListEnsureCapacity` | module_registry.zig | 85 |
| `semanticAnalyzerCaptureType` | semantic_analyzer.zig | 165 |
| `semanticAnalyzerGrowLocalDecls` | semantic_analyzer.zig | 136 |
| `semanticAnalyzerInit` | semantic_analyzer.zig | 63 |
| `semanticAnalyzerIsTypeValueCast` | semantic_analyzer.zig | 126 |
| `semanticAnalyzerResolveArithmetic` | semantic_analyzer.zig | 487 |
| `semanticAnalyzerResolveArrayInit` | semantic_analyzer.zig | 1818 |
| `semanticAnalyzerResolveAssign` | semantic_analyzer.zig | 971 |
| `semanticAnalyzerResolveBitNot` | semantic_analyzer.zig | 588 |
| `semanticAnalyzerResolveBitwise` | semantic_analyzer.zig | 513 |
| `semanticAnalyzerResolveComparison` | semantic_analyzer.zig | 524 |
| `semanticAnalyzerResolveEnumLiteral` | semantic_analyzer.zig | 838 |
| `semanticAnalyzerResolveExpr` | semantic_analyzer.zig | 1131 |
| `semanticAnalyzerResolveFieldAccess` | semantic_analyzer.zig | 230 |
| `semanticAnalyzerResolveFnBody` | semantic_analyzer.zig | 1384 |
| `semanticAnalyzerResolveFnCall` | semantic_analyzer.zig | 649 |
| `semanticAnalyzerResolveIdent` | semantic_analyzer.zig | 174 |
| `semanticAnalyzerResolveIfExpr` | semantic_analyzer.zig | 822 |
| `semanticAnalyzerResolveIndexAccess` | semantic_analyzer.zig | 1745 |
| `semanticAnalyzerResolveLogical` | semantic_analyzer.zig | 569 |
| `semanticAnalyzerResolveNegate` | semantic_analyzer.zig | 579 |
| `semanticAnalyzerResolveOrelseExpr` | semantic_analyzer.zig | 794 |
| `semanticAnalyzerResolveSliceExpr` | semantic_analyzer.zig | 1782 |
| `semanticAnalyzerResolveStmt` | semantic_analyzer.zig | 1839 |
| `semanticAnalyzerResolveStmtIter` | semantic_analyzer.zig | 1539 |
| `semanticAnalyzerResolveStructInit` | semantic_analyzer.zig | 903 |
| `semanticAnalyzerResolveSwitchExpr` | semantic_analyzer.zig | 1018 |
| `semanticAnalyzerResolveTryExpr` | semantic_analyzer.zig | 782 |
| `semanticAnalyzerResolveTupleLiteral` | semantic_analyzer.zig | 1804 |
| `semanticAnalyzerStmtWorkPush` | semantic_analyzer.zig | 1427 |
| `semaTraceStep` | semantic_analyzer.zig | 1725 |
| `sliceAppend` | type_registry.zig | 185 |
| `sortDiagnostics` | diagnostics.zig | 161 |
| `sourceFileArrayListAppend` | source_manager.zig | 44 |
| `sourceFileArrayListEnsureCapacity` | source_manager.zig | 30 |
| `sourceFileArrayListGetSlice` | source_manager.zig | 50 |
| `sourceFileArrayListInit` | source_manager.zig | 21 |
| `sourceManagerAddFile` | source_manager.zig | 75 |
| `sourceManagerCopyToArena` | source_manager.zig | 151 |
| `sourceManagerGetFileName` | source_manager.zig | 103 |
| `sourceManagerGetLineOffsets` | source_manager.zig | 121 |
| `sourceManagerGetLocation` | source_manager.zig | 130 |
| `sourceManagerGetSourceContent` | source_manager.zig | 112 |
| `sourceManagerInit` | source_manager.zig | 65 |
| `sourceTableEnsureCapacity` | resolved_type_table.zig | 73 |
| `stAppend` | type_registry.zig | 205 |
| `stateMapFork` | state_map.zig | 62 |
| `stateMapGet` | state_map.zig | 39 |
| `stateMapGetEntries` | state_map.zig | 107 |
| `stateMapInit` | state_map.zig | 17 |
| `stateMapMergeStates` | state_map.zig | 73 |
| `stateMapSet` | state_map.zig | 49 |
| `std_checked_cast_i16` | zig_runtime.c | 86 |
| `std_checked_cast_i32` | zig_runtime.c | 96 |
| `std_checked_cast_i64` | zig_runtime.c | 106 |
| `std_checked_cast_i8` | zig_runtime.c | 76 |
| `std_checked_cast_u16` | zig_runtime.c | 91 |
| `std_checked_cast_u32` | zig_runtime.c | 101 |
| `std_checked_cast_u64` | zig_runtime.c | 111 |
| `std_checked_cast_u8` | zig_runtime.c | 81 |
| `std_panic` | zig_runtime.c | 14 |
| `std_print` | zig_runtime.c | 22 |
| `std_print_bool` | zig_runtime.c | 55 |
| `std_print_char` | zig_runtime.c | 60 |
| `std_print_f64` | zig_runtime.c | 49 |
| `std_print_i32` | zig_runtime.c | 25 |
| `std_print_i64` | zig_runtime.c | 37 |
| `std_print_len` | zig_runtime.c | 23 |
| `std_print_str` | zig_runtime.c | 62 |
| `std_print_u32` | zig_runtime.c | 31 |
| `std_print_u64` | zig_runtime.c | 43 |
| `stderr_write` | pal.zig | 63 |
| `stdout_write` | pal.zig | 59 |
| `stringInternerCopyToArena` | string_interner.zig | 128 |
| `stringInternerGet` | string_interner.zig | 124 |
| `stringInternerGrowBuckets` | string_interner.zig | 136 |
| `stringInternerInit` | string_interner.zig | 64 |
| `stringInternerIntern` | string_interner.zig | 88 |
| `symbolIsPublic` | symbol_table.zig | 115 |
| `symbolLookupAllModules` | type_resolver.zig | 578 |
| `symbolRegistryEnsureCapacity` | symbol_table.zig | 80 |
| `symbolRegistryGetTable` | symbol_table.zig | 101 |
| `symbolRegistryInit` | symbol_table.zig | 92 |
| `symbolRegistryQualifiedLookup` | symbol_table.zig | 119 |
| `symbolTableEnsureCapacity` | symbol_table.zig | 40 |
| `symbolTableInit` | symbol_table.zig | 31 |
| `symbolTableInsert` | symbol_table.zig | 52 |
| `symbolTableLookup` | symbol_table.zig | 64 |
| `tokenArrayAppend` | import_resolver.zig | 27 |
| `tokenArrayEnsureCapacity` | import_resolver.zig | 15 |
| `tokenKindLabel` | parser.zig | 116 |
| `trackingAlloc` | allocator.zig | 137 |
| `trackingAllocatorInit` | allocator.zig | 128 |
| `trackingAllocatorReport` | allocator.zig | 156 |
| `trackingPeak` | allocator.zig | 152 |
| `trackingReset` | allocator.zig | 147 |
| `tryRecordCoercion` | semantic_analyzer.zig | 597 |
| `tstTopologicalSort` | c89_emit.zig | 959 |
| `tuAppend` | type_registry.zig | 217 |
| `tupAppend` | type_registry.zig | 221 |
| `typeKindSrcStr` | diagnostics.zig | 492 |
| `typeKindTgtStr` | diagnostics.zig | 553 |
| `typeRegistryAppend` | type_registry.zig | 153 |
| `typeRegistryErrorSetMemberIndex` | type_registry.zig | 543 |
| `typeRegistryGetOrCreateArray` | type_registry.zig | 441 |
| `typeRegistryGetOrCreateErrorSet` | type_registry.zig | 524 |
| `typeRegistryGetOrCreateErrorUnion` | type_registry.zig | 412 |
| `typeRegistryGetOrCreateFn` | type_registry.zig | 497 |
| `typeRegistryGetOrCreateManyPtr` | type_registry.zig | 342 |
| `typeRegistryGetOrCreateModule` | type_registry.zig | 559 |
| `typeRegistryGetOrCreateOptional` | type_registry.zig | 388 |
| `typeRegistryGetOrCreatePtr` | type_registry.zig | 326 |
| `typeRegistryGetOrCreateSlice` | type_registry.zig | 358 |
| `typeRegistryGetOrCreateTuple` | type_registry.zig | 486 |
| `typeRegistryGetPointeeType` | type_registry.zig | 735 |
| `typeRegistryGetSliceElem` | type_registry.zig | 741 |
| `typeRegistryGetStructFields` | type_registry.zig | 778 |
| `typeRegistryGetTypeState` | type_registry.zig | 678 |
| `typeRegistryIndexedElemType` | type_registry.zig | 751 |
| `typeRegistryInit` | type_registry.zig | 271 |
| `typeRegistryIsAssignable` | type_registry.zig | 786 |
| `typeRegistryIsErrorSet` | type_registry.zig | 774 |
| `typeRegistryIsInteger` | type_registry.zig | 700 |
| `typeRegistryIsNumeric` | type_registry.zig | 682 |
| `typeRegistryIsOptional` | type_registry.zig | 770 |
| `typeRegistryIsPointer` | type_registry.zig | 726 |
| `typeRegistryIsSlice` | type_registry.zig | 731 |
| `typeRegistryIsUnsigned` | type_registry.zig | 716 |
| `typeRegistryMarkFnPtrUsed` | type_registry.zig | 520 |
| `typeRegistryRegisterNamedType` | type_registry.zig | 629 |
| `typeRegistryRegisterPrimitives` | type_registry.zig | 579 |
| `typeResolverAddEdge` | type_resolver.zig | 62 |
| `typeResolverBuild` | type_resolver.zig | 243 |
| `typeResolverGetSorted` | type_resolver.zig | 553 |
| `typeResolverInit` | type_resolver.zig | 225 |
| `typeResolverResolve` | type_resolver.zig | 268 |
| `typeResolverResolveLayout` | type_resolver.zig | 103 |
| `typeResolverResolveNames` | type_resolver.zig | 1060 |
| `u32ArrayListAppend` | growable_array.zig | 34 |
| `u32ArrayListAppendInner` | ast.zig | 127 |
| `u32ArrayListAppendInner` | parser.zig | 480 |
| `u32ArrayListEnsureCapacity` | growable_array.zig | 20 |
| `u32ArrayListGetSlice` | growable_array.zig | 46 |
| `u32ArrayListInit` | growable_array.zig | 11 |
| `u32ArrayListPopOrNull` | growable_array.zig | 40 |
| `u32ToU32MapGet` | hash.zig | 29 |
| `u32ToU32MapGrow` | hash.zig | 40 |
| `u32ToU32MapInit` | hash.zig | 22 |
| `u32ToU32MapPut` | hash.zig | 73 |
| `u32ToU64MapGet` | hash.zig | 179 |
| `u32ToU64MapGrow` | hash.zig | 190 |
| `u32ToU64MapInit` | hash.zig | 172 |
| `u32ToU64MapPut` | hash.zig | 223 |
| `u64ArrayListAppend` | growable_array.zig | 166 |
| `u64ArrayListAppendInner` | ast.zig | 161 |
| `u64ArrayListEnsureCapacity` | growable_array.zig | 152 |
| `u64ArrayListGetSlice` | growable_array.zig | 172 |
| `u64ArrayListInit` | growable_array.zig | 141 |
| `u64ToU32MapGet` | hash.zig | 104 |
| `u64ToU32MapGrow` | hash.zig | 115 |
| `u64ToU32MapInit` | hash.zig | 97 |
| `u64ToU32MapPut` | hash.zig | 148 |
| `unAppend` | type_registry.zig | 213 |
| `unrAppend` | type_registry.zig | 225 |
| `validateSignatureType` | analyzer.zig | 409 |
| `varDeclInitNeedsNameCache` | type_resolver.zig | 937 |
| `visitPreOrder` | ast.zig | 376 |
| `visitStatement` | analyzer.zig | 637 |
| `walkBlock` | analyzer.zig | 618 |
| `worklistEnsureCapacity` | type_resolver.zig | 68 |
| `worklistPop` | type_resolver.zig | 84 |
| `worklistPush` | type_resolver.zig | 78 |
| `writeHex` | c89_emit.zig | 92 |
| `writeStr` | diagnostics.zig | 150 |
| `writeU32` | main.zig | 834 |
| `xnAppend` | type_registry.zig | 241 |
| `xtAppend` | type_registry.zig | 237 |

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
| `CE` | phase_ComptimeEvaluation | Start of comptime evaluation |
| `RS` | phase_SemanticAnalysis | Start of semantic analysis |
| `MZ` | phase_SemanticAnalysis | Module with zero ast_root (skip) |
| `AD` | phase_SemanticAnalysis | Accessing module decls |
| `DSE` | phase_SemanticAnalysis | After decl scope enumeration |
| `DN` | phase_SemanticAnalysis | Per-declaration processing |
| `SA` | phase_SemanticAnalysis | Before semanticAnalyzerResolveFnBody |
| `sA` | phase_SemanticAnalysis | After semanticAnalyzerResolveFnBody |
| `A` | phase_StaticAnalyzers | Start of static analysis |
| `L` | phase_LIRLowering | Start of LIR lowering |
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

> Detailed sub-phase markers are documented per-file in the individual tech docs (sections 00-11). These are included here for cross-reference.

| Marker | File | Meaning |
|--------|------|---------|
| `P0`-`P3` | main.zig (resolveStmtTypes) | Pointer alignment bits in var_decl child_0 |
| `R0n` | main.zig (resolveStmtTypes) | Resolve init node index (array/struct/tuple) |
| `R1t` | main.zig (resolveStmtTypes) | Resolved type id |
| `R2s` | main.zig (resolveStmtTypes) | Resolved type set in table |
| `AI` | main.zig (resolveStmtTypes) | Array/struct init processing |
| `FI` | main.zig (resolveStmtTypes) | Failed init (TYPE_UNDEFINED) |
| `V2:` | main.zig (phase_SemanticAnalysis) | Var decl init type |
| `REG:tl` | main.zig (phase_SemanticAnalysis) | Name cache put: local name + type |
| `REG:tt` | main.zig (phase_SemanticAnalysis) | Name cache put: type table entry |
| `CAP:ent` | const_alias_prepass.zig | Enter const alias prepass |
| `CAP:tlm` | const_alias_prepass.zig | Top-level module count |
| `GATE:g0`-`g3` | const_alias_prepass.zig | Gate checks in alias detection |
| `KAHN:start` | const_alias_prepass.zig | Kahn layout algorithm start |
| `KAHN:end` | const_alias_prepass.zig | Kahn layout algorithm end |
| `Ra` | symbol_registrator.zig | Register alias |
| `Rs` | symbol_registrator.zig | Register symbol |
| `Rf` | symbol_registrator.zig | Register function |
| `RCA:` | symbol_registrator.zig | Register const alias |
| `IMR:` | symbol_registrator.zig | Import resolution marker |
| `M5:` | symbol_registrator.zig | Module 5 path (init_node.payload) |
| `FIX1:` | symbol_registrator.zig | Fixup 1: module id + type id |
| `BOP:tk` | parser.zig | Binary op: token kind |
| `PF:` | parser.zig | Parser function entry |
| `PSWE:` | parser.zig | Parse switch expression |
| `PCB:` | parser.zig | Parse case body |
| `CPT:` | parser.zig | Capture pattern |
| `PPL:` | parser.zig | Payload list |
| `PSTK:` | parser.zig | Parse stmt/token kind |
| `VARC` | parser.zig | Parse const var decl |
| `VARV` | parser.zig | Parse var var decl |
| `V` | parser.zig | Var decl |
| `v` | parser.zig | Var decl (ok) |
| `PDVx` | parser.zig | Parse var decl extra |
| `Fv` | parser.zig | Fn decl (var) |
| `Fk` | parser.zig | Fn decl (kind) |
| `PIF:` | parser.zig | Parse if conditional |
| `PTC2:` | parser.zig | Parse for/while continue expr |
| `PBX:` | parser.zig | Parse block extent |
| `PLEN:` | parser.zig | Parse local length |
| `DP:` | parser.zig | Dump/panic: child buf stale |
| `CC:nul` | coercion.zig | Coercion: null target |
| `CLS:p` | coercion.zig | Coercion: ptr-to-slice base |
| `nodes=` | lower.zig | LIR: node count |
| `extra=` | lower.zig | LIR: extra children count |
| `M` | lower.zig | Module index marker |
| `R` | lower.zig | Root module marker |

---

## D. Sentinel TypeId Table

> Defined in `type_registry.zig:11-38`. Source of truth — values below verified against source.

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

### Synthetic Field Indices

| Constant | Value | Used For |
|----------|-------|----------|
| `SLICE_FIELD_PTR` | 0 | `slice.ptr` field access |
| `SLICE_FIELD_LEN` | 1 | `slice.len` field access |
| `TU_FIELD_TAG` | 0 | Tagged union tag field |
| `TU_FIELD_PAYLOAD` | 1 | Tagged union payload field |
| `FIRST_USER_TYPE` | 20 | First user-defined TypeId (== TYPE_TYPE) |

**Verification:**
- `TYPE_BOOL` = 2 ✓ (line 12)
- `TYPE_F64` = 16 (brief spec says 7 — **source-corrected**: TYPE_I64=7, TYPE_F64=16)
- `TYPE_TYPE` = 20 ✓ (line 30)

---

## E. Data Structure → File

| Data Structure | File | Notes |
|----------------|------|-------|
| `AstNode` | ast.zig:101 | 24-byte flat node (kind, flags, span_len, span_start, child_0-2, payload) |
| `AstKind` | ast.zig:1 | 97 variants (enum u8: 0-96) |
| `AstStore` | ast.zig:212 | 7 parallel arrays (nodes, extra_children, identifiers, int_values, float_values, string_values, fn_protos) |
| `FnProto` | ast.zig:115 | Function prototype (name_id, params_start/count, return_type_node) |
| `Type` | type_registry.zig:58 | Runtime type descriptor (kind, state, flags, size, alignment, payload) |
| `TypeKind` | type_registry.zig:40 | 30+ type kind variants (enum u8) |
| `TypeRegistry` | type_registry.zig:— | Type storage, ptr/slice/optional/error caches |
| `TypeId` | type_registry.zig:9 | Alias for `u32` |
| `LirInst` | lir.zig:22 | 45-variant untagged union (LIR instruction) |
| `LirFunction` | lir.zig:326 | Compiled function (name, module, blocks, params, hoisted temps, switch cases) |
| `LirFunctionArrayList` | lir.zig:285 | Dynamic array of LirFunction |
| `BasicBlock` | lir.zig:119 | Control-flow block (id, insts, is_terminated) |
| `LirParam` | lir.zig:11 | LIR function parameter (name_id, type_id, temp_id) |
| `TempDecl` | lir.zig:17 | Temporary declaration (temp_id, type_id) |
| `SwitchCase` | lir.zig:6 | LIR switch case (value, target_bb) |
| `Symbol` | symbol_table.zig:4 | Symbol entry (name_id, type_id, kind, flags, decl_node, module_id, scope_level) |
| `SymbolKind` | symbol_table.zig:14 | local/param/global/function/type_alias/module/test_sym |
| `SymbolTable` | symbol_table.zig:24 | Per-module symbol array |
| `ModuleEntry` | module_registry.zig:23 | Module descriptor (id, path_id, state, ast_root, imports, symbol_table, type_offset) |
| `ModuleRegistry` | module_registry.zig:163 | Module graph registry |
| `ModuleState` | module_registry.zig:15 | pending/parsing/parsed/resolved/failed |
| `StateMap` | state_map.zig:9 | Delta-linked parent chain for forking state |
| `StateEntry` | state_map.zig:4 | name_id + state byte |
| `CompilerContext` | main.zig:86 | Global compiler state (all subsystems) |
| `CompilerCli` | main.zig:61 | CLI argument struct (19 fields) |
| `Sand` | allocator.zig:1 | Linear arena allocator (start, pos, end, peak, name) |
| `CompilerAlloc` | allocator.zig:67 | 3-tier arena (permanent 1MB, module 1.5MB, scratch 1.5MB) |
| `StringInterner` | string_interner.zig | FNV-1a string interning |
| `SourceManager` | source_manager.zig | File source text management |
| `DiagnosticCollector` | diagnostics.zig | Error/warning collector |
| `CoercionTable` | coercion.zig | Type coercion rules |
| `ResolvedTypeTable` | resolved_type_table.zig | Type expression → TypeId mapping |
| `U32ArrayList` | growable_array.zig:4 | Generic dynamic u32 array |
| `U8ArrayList` | growable_array.zig | Generic dynamic u8 array |
| `PtrPayload`, `ArrayPayload`, `SlicePayload` | type_registry.zig:71-78 | Type payload structs |
| `NameMangler` | name_mangler.zig | C89 name mangling with deterministic counter |
| `BufferedWriter` | c89_emit.zig | 4KB buffered C89 output writer |

---

## F. AstKind → Handling Phases

| AstKind Group | Phases |
|---------------|--------|
| Declarations (var_decl, fn_decl, struct_decl, enum_decl, union_decl, field_decl, param_decl, test_decl, error_set_decl) | 1 (parser creates), 2 (symbol registration), 3 (type resolution), 5 (semantic analysis), 7 (LIR lowering) |
| Expressions (int_literal through builtin_call, operators, unary) | 1 (parser), 5 (semantic type-checking), 7 (LIR lowering), 4 (comptime eval for builtin_call) |
| Statements (if_stmt, while_stmt, for_stmt, block, return_stmt, break_stmt, continue_stmt, defer_stmt, etc.) | 1 (parser), 5 (semantic), 7 (LIR lowering) |
| Types (ptr_type, many_ptr_type, array_type, slice_type, optional_type, error_union_type, fn_type) | 1 (parser), 3 (type resolution), 5 (semantic), 7 (lower: type metadata) |
| Literals & Constants | 1 (parser), 5 (semantic), 6 (static analyzers), 7 (LIR) |
| `import_expr`, `module_root`, `c_include` | 1 (parser + import resolution), 2 (symbol registration) |
| `builtin_call` | 1 (parser), 4 (comptime eval), 5 (semantic), 7 (LIR) |

---

## G. Arena Tier → Who Uses It

### Permanent Arena (1 MB — `perm_arena_buf[1048576]`)

Initialized at startup, never reset. Holds data that lives for the entire compilation.

| Data | Initialized In | Size |
|------|----------------|------|
| `StringInterner` | main.zig:137 | ~4K + interned strings |
| `SourceManager` | main.zig:138 | ~1K + source text |
| `DiagnosticCollector` | main.zig:139 | ~1K + diagnostic buffer |
| Keyword table (TokenKind lookup) | main.zig:141 | ~2K |
| `ModuleRegistry` | main.zig:143 | ~1K + ModuleEntry array |
| `SymbolRegistry` | main.zig:150 | ~1K + Symbol arrays per module |
| `TypeRegistry` (type_db 128KB) | main.zig:146-148 | 128KB dedicated buf + type data |
| Hash maps (enum_value_table, etc.) | main.zig:155-158 | per-map ~1K |
| Const alias prepass data | const_alias_prepass.zig | Type dependency graph |
| Type resolution intermediates | type_resolver.zig | Pointer group classification |

### Module Arena (1.5 MB — `mod_arena_buf[1572864]`)

Lives across the pipeline, accumulates module-scoped data.

| Data | Initialized In | Notes |
|------|----------------|-------|
| `AstStore` (all AST nodes) | main.zig:149 | Core AST — grows with each parsed file |
| `ResolvedTypeTable` | main.zig:151 | Type expression → TypeId mapping |
| `CoercionTable` | main.zig:152 | Coercion rule storage |
| `LirFunctionArrayList` | main.zig:153 | All LIR functions |
| DepGraph allocation | main.zig:154 | Symbol dependency graph |
| `call_arg_types`, `call_param_map` | main.zig:156-157 | Per-call argument/param maps |
| `comptime_values` | main.zig:158 | Comptime-evaluated values |

### Scratch Arena (1.5 MB — `scr_arena_buf[1572864]`)

Reset at the start of each phase. Temporary per-phase data.

| Phase | Data in Scratch |
|-------|-----------------|
| 1 — Import Resolution | Import queue, parsing temporaries |
| 2 — Symbol Registration | DepGraph per run, per-module state |
| 3 — Type Resolution | TypeResolver workspace, DepGraph |
| 4 — Comptime Evaluation | (minimal — operates on existing data) |
| 5 — Semantic Analysis | Analyzer state, expected-type stack |
| 6 — Static Analyzers | StateMap per function (delta-linked), defer queues |
| 7 — LIR Lowering | Lowerer struct, per-function BasicBlocks, insts |
| 8 — C89 Emission | NameMangler, BufferedWriter, C89Emitter |

---

## Tech Doc Index

| # | File | Covers | Phase |
|---|------|--------|-------|
| 00 | `INDEX.md` | All — master cross-reference | — |
| 01 | `00_lexer_parser.md` | token.zig, lexer.zig, parser.zig, ast.zig | Pre-phase |
| 02 | `00_shared_infra.md` | allocator.zig, string_interner.zig, source_manager.zig, diagnostics.zig, pal.zig, growable_array.zig, util/ | Infra |
| 03 | `01_import_resolution.md` | import_resolver.zig, module_registry.zig | Phase 1 |
| 04 | `02_symbol_registration.md` | symbol_registrator.zig, symbol_table.zig | Phase 2 |
| 05 | `03_type_resolution.md` | type_resolver.zig, type_registry.zig, const_alias_prepass.zig | Phase 3 |
| 06 | `04_comptime_eval.md` | comptime_eval.zig | Phase 4 |
| 07 | `05_semantic_analysis.md` | semantic_analyzer.zig, coercion.zig, resolved_type_table.zig, constraint_checker.zig | Phase 5 |
| 08 | `06_static_analyzers.md` | analyzer.zig, state_map.zig | Phase 6 |
| 09 | `07_lir_lowering.md` | lower.zig, lir.zig | Phase 7 |
| 10 | `08_c89_emission.md` | c89_emit.zig, name_mangler.zig, cinclude.zig | Phase 8 |
| 11 | `09_pipeline_orchestration.md` | main.zig, main_dump.zig | Orchestration |
| 12 | `10_c_runtime.md` | sf/src/include/* | C runtime |
| 13 | `11_build_system.md` | sf/scripts/* | Build system |
