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

> Skeleton — to be populated in full by Task 13. Key entry points listed below.

| Function | File | Line |
|----------|------|------|
| `runCompiler` | main.zig | 184 |
| `phase_ImportResolution` | main.zig | 249 |
| `phase_SymbolRegistration` | main.zig | 259 |
| `phase_TypeResolution` | main.zig | 289 |
| `phase_ComptimeEvaluation` | main.zig | 326 |
| `phase_SemanticAnalysis` | main.zig | 343 |
| `resolveStmtTypes` | main.zig | 413 |
| `resolveTypeExpr` | main.zig | 464 |
| `phase_StaticAnalyzers` | main.zig | 470 |
| `phase_LIRLowering` | main.zig | 505 |
| `phase_C89Emission` | main.zig | 602 |
| `parseArgs` | main.zig | 631 |
| `moduleRegistryResolveImports` | import_resolver.zig | — |
| `registerModuleSymbols` | symbol_registrator.zig | — |
| `typeResolverResolveNames` | type_resolver.zig | — |
| `typeResolverInit` | type_resolver.zig | — |
| `typeResolverBuild` | type_resolver.zig | — |
| `typeResolverResolve` | type_resolver.zig | — |
| `constAliasPrepass` | const_alias_prepass.zig | — |
| `comptimeEvalEvaluate` | comptime_eval.zig | — |
| `semanticAnalyzerResolveFnBody` | semantic_analyzer.zig | — |
| `semanticAnalyzerResolveExpr` | semantic_analyzer.zig | — |
| `runAllAnalyzers` | analyzer.zig | — |
| `lowererInit` | lower.zig | — |
| `lowerFn` | lower.zig | — |
| `c89EmitterInit` | c89_emit.zig | — |
| `emitModule` | c89_emit.zig | — |

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
