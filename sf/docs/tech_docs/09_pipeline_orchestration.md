# 09 — Pipeline Orchestration [updated: 2026-09-25 — Task 10 (z98-print-formatting Amendment 1, B8): the std_fmt auto-import in `phase_ImportResolution` is now lenient — `astStoreHasPrintRef` over-approximates, so the probe (`moduleResolverResolve`) skips silently on a resolve miss and `phase_LIRLowering` re-raises the same `error[3048]` only when `lowerPrintFmt` actually lowered a `.print_val` (`SemanticContext.print_value_lowered`) and no `std_fmt.zig` module is in the graph; an unrelated identifier named `print` no longer fails on a lib dir without std_fmt.zig, while the alias auto-import (`const p = io.print; p(...)`) is preserved (with std_fmt absent the real-print diagnostics keep the same `error[3048]` code/text and rc 2 / 0 `.c`, but are NOT byte-identical in count — final-review Minor 1, 2026-09-25: through `@import("std")` the base emitted the 3048 twice (the auto-import attempt plus `std.zig`'s own `std_fmt.zig` import), the fixed compiler once (direct `std_io` import probes emit once on both), and the diagnostic now fires for otherwise-clean programs after LIR lowering instead of during import resolution; with std_fmt still absent and an earlier error, the fixed compiler reports only that error — its post-sema gate exits before the deferred 3048 — where the base reported only the 3048).] [updated: 2026-09-25 — Task 9 fix round 3 (z98-print-formatting Amendment 1, B5; operator ruling Q7): at the end of `phase_LIRLowering` the new `computeModuleInitOrder` stable-topologically orders the modules from the `ctx.module_init_deps` edges recorded by `lowerModuleInit` (registry order unless a global initializer of one module reads another module's global) into `ctx.module_init_order`, which `phase_C89Emission` hands to the emitter for `emitModuleInitCalls`; a cross-module initializer cycle emits `error[3064]` at a referencing declaration. Doc 07 covers the same-module order.] [updated: 2026-09-24 — Task 1 (z98-print-formatting) fix round 1: the auto-import scan is `astStoreHasPrintRef` and matches ANY `ident_expr`/`field_access` payload named `print`, not just a `fn_call` callee — the alias shape `const p = io.print; p(...)` is intercepted by the lowerer's print special case but has no `print` callee, so the call-only scan left std_fmt out of the graph and the emitter wrote an unmangled `printI32(...)` (link error); over-approximation only adds std_fmt to the graph and an unreferenced std_fmt is pruned] [updated: 2026-09-24 — Task 1 (z98-print-formatting): `phase_ImportResolution` gained the std_fmt auto-import — after the first parse pass, a linear AST scan (`astStoreHasPrintRef`) detects a reference named `print` and, if present, resolves `std_fmt.zig` as an import of the root module and runs `moduleRegistryResolveImports` a second time; `phase_C89Emission` gains `moduleIdForBasename` (locates the std_fmt module for the emitter's mangled print calls) and seeds a `ref_edges` value-reference for every `.print_val` so std_fmt is reachable and its header is included] [updated: 2026-09-23 — Task 4 (coercion into typed slots): `phase_ComptimeEvaluation` stores the exact `ComptimeVal` in the new `ctx.comptime_folds` (`ComptimeFoldTable`) instead of a u64 pattern, and `phase_SemanticAnalysis`'s `var_decl` arm re-types an unannotated binding whose folded integer init does not fit i32 (value-based U32/I64/U64 slot); the lowering phase's new `error[3000]` materialisation checks are turned into rc=2 / 0 `.c` by the existing post-`phase_LIRLowering` `hasErrors` gate] [updated: 2026-09-23 — Task 3 (signedness-free comparisons): `phase_ComptimeEvaluation` gains a third visitor arm — every capture-free no-`else` `if_expr` condition is folded and stored (Task 1 §7), so lowering's `if_expr` `ie_fold` path elides the untaken branch and module-scope conditions are runtime-equal to Zig] [updated: 2026-09-22 — Task 7D: a function-local declaration that shadows an outer-scope identifier emits level-0 `error[3057]` (`ERR_3057_LOCAL_SHADOW`) in `phase_SemanticAnalysis` (`semanticAnalyzerCheckLocalShadow`); the post-sema `hasErrors` gate prints it and exits rc=2 with 0 `.c`] [updated: 2026-09-22 — Task 7B: assignment to an immutable l-value emits level-0 `error[3002]` in `phase_SemanticAnalysis` (`semanticAnalyzerResolveAssign` + `semanticAnalyzerIsLValueConst`); the post-sema `hasErrors` gate prints it and exits rc=2 with 0 `.c`] [updated: 2026-09-22 — Task 6F: an undeclared identifier now emits `error[3001]` (code 20) in `phase_SemanticAnalysis` (`semanticAnalyzerResolveIdent`); the post-sema `hasErrors` gate (`main.zig:370-373`, after `phase_SemanticAnalysis` and before `phase_StaticAnalyzers`) prints all diagnostics and exits rc=2 with 0 `.c`, so the program never reaches `phase_LIRLowering`] [updated: 2026-09-22 — Task 6D: the same post-`phase_LIRLowering` `hasErrors` gate turns the new lowering-emitted `error[3056]` (a call whose callee is not a function) into rc=2 with 0 `.c`] [updated: 2026-09-22 — Task 6B: the post-`phase_LIRLowering` `hasErrors` gate is what turns a lowering-emitted `error[3042]` (an undefined member of a nested module, `std.io.<name>`) into rc=2 with 0 `.c`; the fix lives in `lower.zig`, not here] [updated: 2026-09-21 — Task 11J: `phase_TypeResolution` now calls `type_resolver.enumReevaluateAll` after `typeResolverResolve` and before `classifyTypeEmissionGroups`] [updated: 2026-09-20 — refreshed against current source: added `phase_FrontResolution`/`phase_AsyncFrameSize`, `-fsafe`/`-ffast` and target/output flags, self-contained output-dir orchestration, and the tooling mains; line references and dated evidence removed]

> Covers: `main.zig`, `main_dump.zig`, `main_exp.zig`, `strip_main.zig`

## 1. Overview

`sf/src` has four `main` entry points:

| Binary | File | Purpose |
|--------|------|---------|
| `zig1` | `main.zig` | Full 10-phase compiler pipeline: source → C89 |
| `zig1-dump` | `main_dump.zig` | Standalone dump binary (tokens, AST only) |
| (bootstrap smoke) | `main_exp.zig` | 5-line extern-C smoke entry (`__bootstrap_print`) |
| (strip tool) | `strip_main.zig` | Minimal name-mangler link-check entry |

`main.zig` and `main_dump.zig` share the `CompilerCli`/`CompilerContext` shape and a CLI-helper naming convention (`matchFlag`, `cstrToSlice`, `parseSize`, `parseU32`, `parseColorMode`, `parseErrorFormat`). `main.zig` additionally has `matchMMFlag`, `matchSFlag`, `parseMMBytes`, `parseSLevel`, `parseTargetIsWindows`, `writeU32`, and `printUsage`; `main_dump.zig` has `getByte`. `main_dump.zig` carries `phase_*` empty stubs for compilation compatibility; only `main.zig` implements the full pipeline.

`main.zig`'s `phase_*` set is: `phase_ImportResolution`, `phase_SymbolRegistration`, `phase_TypeResolution`, `phase_FrontResolution`, `phase_ComptimeEvaluation`, `phase_SemanticAnalysis`, `phase_StaticAnalyzers`, `phase_AsyncFrameSize`, `phase_LIRLowering`, `phase_C89Emission` (10 phases), plus the `runCompiler` orchestrator.

---

## 2. `CompilerCli` — CLI Argument Struct

**File:** `main.zig` (26 fields)

| # | Field | Type | Default | Flag(s) |
|---|-------|------|---------|---------|
| 1 | `input_file` | `[]const u8` | `""` | positional |
| 2 | `output_dir` | `[]const u8` | `"."` | `--output-dir`, `-o` |
| 3 | `output_dir_set` | `bool` | `false` | set when `--output-dir`/`-o` seen |
| 4 | `dump_types` | `bool` | `false` | `--dump-types`, `-y` (declared; never matched — see §9 Known Issues) |
| 5 | `dump_lir` | `bool` | `false` | `--dump-lir`, `-l` (declared; never matched) |
| 6 | `dump_c89` | `bool` | `false` | `--dump-c89` |
| 7 | `max_mem` | `u32` | `DEFAULT_MAX_MEM_KB` (64 MiB) | `--max-mem`, `-m`, `-mm<N>` |
| 8 | `spill_level` | `u32` | `0` | `-s<N>` (0 = all spills on disk) |
| 9 | `max_errors` | `u32` | `256` | `--max-errors`, `-e` |
| 10 | `color` | `ColorMode` | `.auto` | `--color` |
| 11 | `error_format` | `ErrorFormat` | `.human` | `--error-format` |
| 12 | `warnings_as_errors` | `bool` | `false` | `--warnings-as-errors`, `-W`, `--warn-error` |
| 13 | `quiet` | `bool` | `false` | `--quiet`, `-q` |
| 14 | `test_mode` | `bool` | `false` | `--test` |
| 15 | `sanity_test_mode` | `bool` | `false` | `--sanity-test` |
| 16 | `track_memory` | `bool` | `false` | `--track-memory` |
| 17 | `no_null_check` | `bool` | `false` | `--no-null-check` |
| 18 | `no_lifetime_check` | `bool` | `false` | `--no-lifetime-check` |
| 19 | `no_leak_check` | `bool` | `false` | `--no-leak-check` |
| 20 | `safe_checks` | `bool` | `true` | `-fsafe` (default) / `-ffast` (disables) |
| 21 | `warn_all` | `bool` | `false` | `--warn-all` |
| 22 | `warn_error` | `bool` | `false` | `--warn-error` |
| 23 | `show_markers` | `bool` | `false` | `--markers` |
| 24 | `include_dirs` | `[16][]const u8` | `undefined` | `-I`, `--lib-dir` |
| 25 | `include_count` | `u32` | `0` | (implicit from `-I`/`--lib-dir` count) |
| 26 | `target_is_windows` | `bool` | `false` | `-osw`, `--target windows`; `-osl`/`--target linux` sets false |

`-fsafe`/`-ffast` toggle `safe_checks`, which flows into the C89 emitter and the LIR lowerer as the c89-ahead runtime-check switch (see 07/08). `target_is_windows` is the single target-platform flip point consumed by `phase_ComptimeEvaluation` (`@isWindows`); `config.zig`'s `host_is_windows` is unwired (see 04).

**main_dump.zig variant:** (16 fields) — replaces `dump_types`/`dump_lir`/`dump_c89` with `dump_tokens`/`dump_ast`, adds `print_usage`, omits `output_dir_set`, `spill_level`, analyzer/safe-check toggle flags (`no_null_check`, `no_lifetime_check`, `no_leak_check`, `safe_checks`, `warn_all`, `warn_error`, `show_markers`), and `target_is_windows`; uses a fixed 16 MiB `max_mem` default.

---

## 3. `CompilerContext` — Global Compiler State

**File:** `main.zig` (34 fields)

| # | Field | Type | Arena | Subsystem |
|---|-------|------|-------|-----------|
| 1 | `cli` | `CompilerCli` | (value) | CLI arguments snapshot |
| 2 | `alloc` | `*CompilerAlloc` | — | 3-tier memory allocator |
| 3 | `interner` | `*StringInterner` | permanent | String interning |
| 4 | `diag` | `*DiagnosticCollector` | permanent | Error/warning collection |
| 5 | `source_man` | `*SourceManager` | permanent | Source file text storage |
| 6 | `name_mangler` | `*NameMangler` | (stack) | C89 name mangling |
| 7 | `module_reg` | `*ModuleRegistry` | permanent | Module graph + imports |
| 8 | `typereg` | `*TypeRegistry` | type_db (growable sand) | Type system registry |
| 9 | `store` | `*AstStore` | module | AST node store |
| 10 | `symbol_reg` | `*SymbolRegistry` | permanent | Symbol table per module |
| 11 | `resolved_types` | `*ResolvedTypeTable` | module | Type expr → TypeId mapping |
| 12 | `coercion_table` | `*CoercionTable` | module | Coercion rule storage |
| 13 | `dep_graph` | `*symbol_registrator.DepGraph` | module (UNUSED) | Symbol dependency graph — **dead field**: initialized in `main` but never populated/consumed by the pipeline (see §5 DepGraph Lifecycle). Live graphs are scratch-local per phase. |
| 14 | `lir_slots` | `LirSlotArrayList` | emission | Ordered slot index into the LIR stream |
| 15 | `lir_stream` | `lir_stream.LirStream` | emission | Offset-addressed spill stream of lowered LIR |
| 16 | `enum_value_table` | `hash_mod.U32ToU32Map` | module | Enum field → value mapping |
| 17 | `error_code_registry` | `hash_mod.U32ToU32Map` | emission | Dense error-code assignment |
| 18 | `call_arg_types` | `hash_mod.U32ToU32Map` | module | Per-call argument types |
| 19 | `call_param_map` | `hash_mod.U32ToU32Map` | module | Per-call parameter mapping |
| 20 | `comptime_folds` | `ComptimeFoldTable` | module | Exact comptime fold values (node → `ComptimeVal`) |
| 21 | `pointer_only_ids` | `[*]u32` | permanent | Types emitted as pointers only |
| 22 | `pointer_only_len` | `u32` | (value) | Length of pointer-only list |
| 23 | `global_decls` | `lir_mod.GlobalDeclArrayList` | emission | Module-global declarations for emission |
| 24 | `exported` | `hash_mod.U64ToU32Map` | emission | Exported fn/global set (`module<<35 | kind<<32 | name_id`) |
| 25 | `suspending_fns` | `hash_mod.U64ToU32Map` | module | Async: functions that can suspend |
| 26 | `frame_sizes` | `hash_mod.U64ToU32Map` | module | Async: frame sizes |
| 27 | `state_widths` | `hash_mod.U64ToU32Map` | module | Async: state field widths |
| 28 | `awaited_fns` | `hash_mod.U64ToU32Map` | module | Async: awaited callee map |
| 29 | `async_hidden_fns` | `hash_mod.U64ToU32Map` | module | Async: hidden transformed fns |
| 30 | `driver_targets` | `hash_mod.U64ToU32Map` | module | Async: root-driver targets |
| 31 | `parent_result_type_list` | `ga_mod.U32ArrayList` | module | Async: parent result types |
| 32 | `parent_result_start` | `hash_mod.U64ToU32Map` | module | Async: parent result start offsets |
| 33 | `parent_result_count` | `hash_mod.U64ToU32Map` | module | Async: parent result counts |
| 34 | `async_layouts` | `hash_mod.U64ToU32Map` | module | Async: published frame layouts |

**Initialization order** (inside `main`):
1. `initCompilerAlloc()` — 3-tier arena; set `max_mem = cli.max_mem`; `spillSetLevel(cli.spill_level)`
2. `pal.readFile` — root source into scratch
3. `stringInternerInit` — string interning (capacity derived from source length)
4. `sourceManagerInit` — source text manager
5. `diagnosticCollectorInit` — diagnostic collector; set `max_diagnostics = cli.max_errors`
6. `initKeywordTable` — lexer keyword lookup
7. `nameManglerInit` — C89 name mangler
8. `moduleRegistryInit` + `moduleRegistrySetSourceMan` — import system
9. `growableSandInit` (type_db) + `typeRegistryInit` + `typeRegistryRegisterPrimitives` — type system
10. `astStoreInit` + `astStoreSetSpillPath` / `astStoreSetValuePoolSpillPath` — AST store and its 5 spill temp paths (AST, side pools 0/1, extra ec/er); dir = `--output-dir` or `.`
11. `symbolRegistryInit` — symbol registry
12. `resolvedTypeTableInit` + `resolvedTypeTableSetSpillPath` — resolved type table
13. `coercionTableInit` — coercion table
14. `lirSlotArrayListInit` (emission) + `lirStreamInit` — LIR storage
15. `depGraphInit` — dependency graph (module arena; unwired)
16. Hash maps and fold table: `enum_value_table`, `error_code_registry`, `call_arg_types`, `call_param_map`, `comptime_folds` (`ComptimeFoldTable`), `exported`
17. Async maps: `suspending_fns`, `frame_sizes`, `state_widths`, `awaited_fns`, `async_hidden_fns`, `driver_targets`, `parent_result_start`, `parent_result_count`, `async_layouts` + `parent_result_type_list`
18. `globalDeclArrayListInit` (emission) — module globals
19. Construct `CompilerContext`; call `runCompiler(&ctx)`

**main_dump.zig variant:** Only has `cli`, `alloc`, `interner`, `diag`, `source_man`, `name_mangler` (6 fields).

---

## 4. `main` — Entry Point

**File:** `main.zig`

### Flow

```
main(argc, argv)
  │
  ├─ pal.initArgs(argc, argv)
  ├─ pal.markerWrite("START\n")
  ├─ cli = parseArgs()
  ├─ if cli.show_markers → pal.markersEnabled(1)
  │
  ├─ [SANITY TEST] cli.sanity_test_mode
  │   ├─ initCompilerAlloc, interner, source_man, diag, keyword table
  │   ├─ lexerTestSanityCheck()
  │   └─ return
  │
  ├─ [TEST MODE] cli.test_mode
  │   ├─ print "error: use test_main.zig for test mode\n"
  │   └─ pal.exit(1)
  │
  ├─ [NO INPUT] cli.input_file.len == 0
  │   ├─ printUsage()
  │   └─ return
  │
  ├─ [OUTPUT DIR CHECK] cli.output_dir_set and !pal.dirExists(cli.output_dir)
  │   ├─ "error: output directory does not exist: <dir>\n" → stderr
  │   └─ pal.exit(1)
  │
  ├─ [ROOT FILE CHECK] pal.readFile(cli.input_file, &compiler_alloc.scratch) orelse {…}
  │   ├─ "error: could not read input file\n" → stderr
  │   └─ pal.exit(1)
  │
  ├─ [NORMAL COMPILATION]
  │   ├─ initCompilerAlloc() + set max_mem + spillSetLevel
  │   ├─ Initialize all subsystems (interner → async maps / global_decls)
  │   ├─ Construct CompilerContext
  │   └─ runCompiler(&ctx)
  │
```

### Early Exits

| Condition | Action |
|-----------|--------|
| `cli.sanity_test_mode` | Lexer sanity check, return immediately |
| `cli.test_mode` | Print error, `pal.exit(1)` — test_main.zig is the test entry |
| `cli.input_file.len == 0` | `printUsage()`, return |
| `cli.output_dir_set` and dir missing | `pal.dirExists` false → `error: output directory does not exist: <dir>\n` on stderr, `pal.exit(1)` |
| **input file missing or empty** | `pal.readFile` returns null → `error: could not read input file\n` on stderr, `pal.exit(1)` — one message covers both missing and empty, matching the `main_dump.zig` pattern. Previously this was silent (exit 0 + boilerplate C on stdout or junk `.c/.h` files on `--output-dir`) |

### Output Directory Isolation

`cli.output_dir` is **live**: when `--dump-c89 --output-dir DIR` (or `-o DIR`, which implies
emission) is set, `phase_C89Emission` writes per-module `.c`/`.h` files plus `zig_special_types.h`,
the self-contained support files (`emitSupportFiles`), and the companion build scripts
(`emitBuildScripts`) into `DIR` (via the `BufferedWriter` fd sink + `pal.fileOpen`/`fileWrite`/
`fileClose`; see 08 §1.17/§6). `main` now **checks** that the directory exists (`pal.dirExists`)
before compiling and exits 1 if it does not, but it does **not create** it — callers must
`mkdir -p DIR` first. When `--output-dir` is set, the AST/resolved-type/hash/LIR spill temp files
(`.zig1_*.tmp`) are also rooted in `DIR` rather than `.`. Bare `--dump-c89` (no `--output-dir`)
keeps the stdout single-file path byte-identical — stdout-path preservation is a hard gate.

---

## 5. `runCompiler` — Phase Orchestration

**File:** `main.zig`

### Phase Sequence (ordered)

```
runCompiler(ctx)
  │
  ├── 1. phase_ImportResolution(ctx)
  │     marker: I, Z
  │     marker: 2
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     marker: 3, 3a, 4
  │
  ├── 2. phase_SymbolRegistration(ctx)
  │     marker: S, S0
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     async_analysis.suspensionAnalysisRun(...)   ← not a phase_*; populates suspending_fns
  │
  ├── 3. phase_TypeResolution(ctx)
  │     marker: T, T0
  │     marker: t1
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     marker: t2
  │     [ERROR CHECK] → pal.exit(2) if errors
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │
  ├── 4. phase_FrontResolution(ctx)
  │     (no marker) frontResolveModuleInits
  │
  ├── 5. phase_ComptimeEvaluation(ctx)
  │     marker: CE
  │
  ├── 6. phase_SemanticAnalysis(ctx)
  │     marker: RS, MZ, AD, DSE, DN, SA, sA
  │     [ERROR CHECK] → pal.exit(2) if errors
  │
  ├── 7. phase_StaticAnalyzers(ctx)
  │     marker: A
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [ERROR CHECK] → pal.exit(2) if errors
  │
  ├── 8. phase_AsyncFrameSize(ctx)
  │     marker: AFS
  │
  ├── 9. phase_LIRLowering(ctx)
  │     marker: L, nodes=, extra=, M, R, F, A0
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [ERROR CHECK] → pal.exit(2) if errors
  │     resolvedTypeTableClose + module sandReset
  │
  ├── 10. phase_C89Emission(ctx)
  │     marker: C, FINAL_FLUSH
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [WARNING CHECK] → pal.exit(1) if warnings_as_errors or warn_error
  │
  ├── [TRACK MEMORY] if cli.track_memory
  │     print perm / mod / scr / pool / type_db / total (KB)
  │
  └── diagnosticCollectorPrintAll(ctx.diag)  — final output
```

`phase_FrontResolution` and `phase_AsyncFrameSize` are the two phases added after the doc's
original 8-phase form. `suspensionAnalysisRun` is invoked directly by `runCompiler` between
phases 2 and 3 (it owns `suspending_fns`; see 12).

### Memory Checkpoints

| Location | Call | Purpose |
|----------|------|---------|
| After phase 1 | `checkCombinedPeak(ctx.alloc)` | Peak memory after import resolution |
| After phase 2 | `checkCombinedPeak(ctx.alloc)` | Peak after symbol registration |
| After phase 3 | `checkCombinedPeak(ctx.alloc)` | Peak after type resolution, before the `t2` marker |
| After phase 3 (post error check) | `checkCombinedPeak(ctx.alloc)` | Second call, after the first `hasErrors` gate |
| After phase 7 | `checkCombinedPeak(ctx.alloc)` | Peak after static analyzers |
| After phase 9 | `checkCombinedPeak(ctx.alloc)` | Peak after LIR lowering |
| After phase 10 | `checkCombinedPeak(ctx.alloc)` | Peak after C89 emission |

### Diagnostic Exits

| Location | Condition | Exit Code |
|----------|-----------|-----------|
| After phase 3 (TypeResolution) | `diagnosticCollectorHasErrors` | 2 |
| After phase 6 (SemanticAnalysis) | `diagnosticCollectorHasErrors` | 2 |
| After phase 7 (StaticAnalyzers) | `diagnosticCollectorHasErrors` | 2 |
| After phase 9 (LIRLowering) | `diagnosticCollectorHasErrors` | 2 |
| After phase 10 (C89Emission) | `warnings_as_errors or warn_error` + warning count > 0 | 1 |
| `main()` output-dir check | `pal.dirExists` false (dir missing) | 1 |
| `main()` root check | `pal.readFile` null (input missing/empty) | 1 |

**Exit asymmetry:** dependency file failures surface as `error[3048]` diagnostics in phase 1
(`import_resolver.zig` empty dep; `module_registry.zig` missing dep) and are caught by the
**first** `hasErrors` gate after phase 3 → `pal.exit(2)` — the same path as all other
diagnostics. The root input file uses a separate pre-phase check with exit **1** (the I/O/usage
class, matching `main_dump.zig`). The 1-vs-2 split is deliberate; both calls use the
`pal.exit(code)` convention.

**Lowering-emitted diagnostics** `[updated: 2026-09-22 — Task 6B]`. Some diagnostics are emitted
during `phase_LIRLowering` rather than by the semantic analyzer (e.g. `error[3042]: non-value base
expression in field access`, emitted by `lower.zig` when a callee base is a module used as a value).
They are collected in the same `DiagnosticCollector` and caught by the `hasErrors` gate after phase
9 → `pal.exit(2)` with 0 `.c`. Task 6B relies on this path: an unresolvable nested-module member
call (`std.io.printt(...)`) now falls through to the generic call path, which emits `error[3042]`
(+ `warning[3023]`), so it exits 2 with 0 `.c` instead of silently returning temp 0. Task 6D adds a
second lowering-emitted diagnostic on the same gate: `error[3056]: expression is not callable`, when
the generic call path's lowered callee temp is not a function (nor a pointer to one), so a
non-callable call also exits 2 with 0 `.c`.

**Semantic-analysis-emitted `error[3001]`** `[updated: 2026-09-22 — Task 6F]`. An undeclared
identifier now emits `error[3001]` (numeric code 20) from `semanticAnalyzerResolveIdent` during
`phase_SemanticAnalysis`; the **post-sema** `hasErrors` gate at `main.zig:370-373` (after
`phase_SemanticAnalysis`, before `phase_StaticAnalyzers`) prints all diagnostics and exits 2 with
0 `.c`. Because it is caught here — before `phase_LIRLowering` — an undeclared-identifier callee
never reaches the Task 6D variant-C `error[3056]` path or the Task 6B `error[3042]` path (both
unchanged for their own shapes).

**Semantic-analysis-emitted `error[3002]`** `[added: 2026-09-22 — Task 7B]`. Assignment to an
immutable l-value now emits level-0 `error[3002]` "cannot assign to immutable variable" from
`semanticAnalyzerResolveAssign` (via `semanticAnalyzerIsLValueConst`) during
`phase_SemanticAnalysis`; the same **post-sema** `hasErrors` gate prints all diagnostics and exits 2
with 0 `.c`, before `phase_LIRLowering`. The numeric literal `3002` is passed to
`diagnosticCollectorAdd` (the `ERR_3002_INVALID_ASSIGNMENT` enum ordinal is 21, so the enum value is
NOT used — matching the hardcoded `3000` at the type-mismatch sites).

**Semantic-analysis-emitted `error[3057]`** `[added: 2026-09-22 — Task 7D]`. A function-local
declaration that shadows an outer-scope identifier (or redeclares a same-scope one) now emits
level-0 `error[3057]` (`ERR_3057_LOCAL_SHADOW`, numeric literal `3057`) from
`semanticAnalyzerCheckLocalShadow` during `phase_SemanticAnalysis`; the same **post-sema**
`hasErrors` gate prints all diagnostics and exits 2 with 0 `.c`, before `phase_LIRLowering`. The
check is invoked immediately before every local-registration site and rejects both local↔local
(any depth / same scope) and local/param/capture → container-level (`global`/`function`/
`type_alias`/`module`) shadowing, matching official Zig 0.15.2. `_` (the discard) is exempt.

### `--track-memory` output

When `cli.track_memory` is set, `runCompiler` prints one line via `pal.measureMarkerWrite` (always
live, unlike `pal.markerWrite`) after phase 10:

```
track-memory: perm=<n>K mod=<n>K scr=<n>K pool=<n>K type_db=<n>K total=<n>K
```

`total` is `perm + mod + scr` (the three arena tiers; `pool`/`type_db` are reported separately and
not summed). `type_db` is the growable sand backing the `TypeRegistry`. Values are peaks, not
current usage. (Earlier docs recorded per-example numbers against pre-upgrade examples; those
dated traces are removed — run `--markers --track-memory --dump-c89` against a current example to
regenerate.)

### DepGraph Lifecycle

The live `DepGraph` is **scratch-local and rebuilt per phase**; there is no phase 2→3 handoff.

- `phase_SymbolRegistration` creates a **local** `dep_graph` in scratch and passes it only to
  `registerModuleSymbols`; the graph is never consumed inside phase 2 (no `typeResolverBuild`).
- `phase_TypeResolution` resets scratch (wiping the phase-2 edges), creates its **own** local
  `dep_graph`, re-runs the identical `registerModuleSymbols` loop, and consumes it via
  `typeResolverBuild`, which copies the edges into the TypeResolver's own `depend_items` arrays.
- `ctx.dep_graph` (the module-arena field in `CompilerContext`) is **never populated by the
  pipeline** — it is a dead field, left in place for the `TYPE_SYSTEM_p2.md §2.4` design.
- **Implication for phase isolation:** no cross-phase heap handoff is relied upon for DepGraph.

### `--dump-c89` vs no-dump — phase skipping

**No pipeline phase is skipped when C89 emission is disabled.** Only `phase_C89Emission`
early-returns (`if (!ctx.cli.dump_c89 and !ctx.cli.output_dir_set) return;`). A no-dump run still
emits the phase marker set (`I Z S T CE RS A AFS L C`) and LIR lowering still builds the LIR stream,
but no `FINAL_FLUSH` marker and 0 bytes to stdout. `--dump-types` and `--dump-lir` are declared in
`CompilerCli` but never matched in `parseArgs`, and **no phase consults them** — they have no
effect on the current pipeline. The LIR lowering + scratch work for an un-emitted build is wasted.

---

## 6. Phase Function Details

### `phase_ImportResolution` — `main.zig`

**Calls:**
- `alloc_mod.sandReset` — reset scratch at entry
- `mr_mod.moduleResolverAddSearchDir` — add each `-I`/`--lib-dir` dir, plus the default lib path from `pal.getDefaultLibPath` when it exists (`pal.dirExists`, a directory probe — Task 5B; the default lib path `<exe_dir>/lib` is a directory, and the old `pal.fileExists` `fopen` probe failed on win32). [updated: 2026-09-22 — Task 5B]
- `path_mod.normalizePath` — normalize the input path (when it fits 512 bytes)
- `interner_mod.stringInternerIntern` — intern the root module path
- `mr_mod.moduleRegistryAddModule` — register root module
- `mr_mod.importQueueEnqueue` — enqueue root for import resolution
- `import_resolver.moduleRegistryResolveImports` — drain import queue, parse all modules
- `astStoreHasPrintRef` — Task 1 (fix round 1): linear AST scan for ANY `ident_expr`/`field_access`
  payload named `print`. This covers a direct `fn_call` callee AND a reference used only as an alias
  initializer (`const p = io.print; p(...)`) — the lowerer's print special case is keyed on the
  resolved fn `name_id`, so it intercepts an indirect alias call while no `print` callee exists.
  **Task 10 (B8):** the scan over-approximates, so the auto-import probes the search dirs first
  (`mr_mod.moduleResolverResolve`) and skips silently when `std_fmt.zig` is absent; on a hit,
  `moduleRegistryResolveImport("std_fmt.zig", root)` + a second `moduleRegistryResolveImports`
  bring the formatting module (and its PAL backing) into the graph — the user needs no new import.
  A missing `std_fmt.zig` is reported as `error[3048]` at the end of `phase_LIRLowering` (the same
  code/message the import path used), and only when `lowerPrintFmt` actually lowered a `.print_val`
  (`SemanticContext.print_value_lowered`); an unrelated identifier named `print`, or a
  `print("literal", .{})` that needs only the C-runtime `std_print`, stays error-free. When
  std_fmt IS resolvable, the over-approximation only adds it to the graph and an unreferenced
  module is pruned at emission.
  [updated: 2026-09-24 — Task 1 fix round 1; updated: 2026-09-25 — Task 10]
- `mr_mod.moduleRegistrySpillHashMaps` — set the registry hash-spill temp path (rooted in `--output-dir` or `.`)

**Markers:** `I` (start), `Z` (done)

**Arena:** Sand reset (scratch) at entry. Import queue and parsing temporaries use scratch.

**Dependency diagnostics fire in this phase:** an empty dep fails `pal.readFile` in
`import_resolver.zig` → `error[3048]: could not read imported file '<path>'` + `ModuleState.failed`;
a missing dep (never resolves in the 3-tier search) errors at the `moduleRegistryResolveImport`
null choke point in `module_registry.zig` → `error[3048]: could not resolve imported file
'<path>'`. Both are caught by the first `hasErrors` gate (after phase 3) → exit 2. The
std_fmt auto-import path is the exception (Task 10, B8): its resolve miss is silent in this
phase and is re-raised as the same `error[3048]` after `phase_LIRLowering`, only when a print
value was actually lowered and no `std_fmt.zig` module is in the graph.

### `phase_SymbolRegistration` — `main.zig`

**Calls:**
- `symbol_registrator.depGraphInit` — create a **local** dep graph in scratch
- `symbol_registrator.registerModuleSymbols(..., true)` — register all symbols per module
- Root module AST walk: enumerate children, write AstKind enum values as markers

**Markers:** `S` (start), `S0` + per-decl kind values

**Arena:** Sand reset (scratch) at entry. DepGraph allocated in scratch (not consumed here).

### `phase_TypeResolution` — `main.zig`

**Calls:**
- `resolved_type_table.resolvedTypeTableReserve` — reserve table slots for `store.nodes.len`
- `symbol_registrator.registerModuleSymbols(..., false)` — re-run symbol registration for type context
- `const_alias_prepass.constAliasPrepass` — detect const alias dependency cycles
- `type_resolver.typeResolverResolveNames` — resolve type expression names
- `type_resolver.typeResolverInit` — create type resolver
- `type_resolver.typeResolverBuildDependencyGraph` — build real by-value field edges
- `type_resolver.typeResolverBuild` — build type dependency graph (Kahn)
- `type_resolver.typeResolverResolve` — resolve all types in topological order
- `type_resolver.enumReevaluateAll` — **Task 11J** post-layout enum re-evaluation: re-walk every module enum with a fresh `auto_val` cascade, overwrite `em_items[].value` (fold integer/builtin initializers, including named-aggregate introspection), reject unfoldable/duplicate with `ERR_3055`
- `type_resolver.classifyTypeEmissionGroups` — classify pointer-only types
- Sets `ctx.pointer_only_ids` and `ctx.pointer_only_len`

**Markers:** `T` (start), `T0` + per-decl kind values

**Arena:** Sand reset (scratch) at entry. Const alias prepass uses permanent. TypeResolver workspace in scratch.

### `phase_FrontResolution` — `main.zig`

Builds a `FrontResCtx` (`store`, `typereg`, `symbol_reg`, `resolved_types`, `module_reg`,
`interner`, `diag`, `scratch`, `coercion_table`, `enum_value_table`, `error_code_registry`,
`call_arg_types`, `call_param_map`, `suspending_fns`) and calls
`front_res.frontResolveModuleInits` to resolve module-level initializer/type-annotation
expressions into the `ResolvedTypeTable`. The pass logic lives in `front_resolution.zig` and is
covered by 03_type_resolution.md.

**Markers:** none (no marker is written)

**Arena:** Works in scratch; results recorded in the module-arena `ResolvedTypeTable`.

### `phase_ComptimeEvaluation` — `main.zig`

**Calls:**
- `ce_mod.comptimeEvalInit` — init comptime evaluator
- `ce.host_is_windows = ctx.cli.target_is_windows` — set the `@isWindows` flip point
- `ce_mod.comptimeEvalEvaluate` — evaluate each `builtin_call` node **and** each module-scope
  `const var_decl` whose init is a bare arithmetic node, **and** each capture-free no-`else`
  `if_expr` condition (Task 3, Task 1 §7)
- `ce_mod.comptimeFoldTablePut` — **Task 4:** store the EXACT folded `ComptimeVal` in
  `ctx.comptime_folds` (`ComptimeFoldTable` — node→slot + dense `ComptimeVal` array; replaces
  `ctx.comptime_values`/`comptimeValStoreU64`). An integer outside `[i64 min, u64 max]` is
  stored too; the lowering materialisation site rejects it with `error[3000]` (Task 1 §8 risk 1)

**Three-arm visitor:** the per-node sweep over `ctx.store.nodes` has three arms:
1. `builtin_call` nodes — evaluate via `comptimeEvalEvaluate`.
2. `var_decl` nodes whose `child_1` init kind is one of the arithmetic ops (`add`..`shr`, i.e.
   AstKind 33-42, plus `negate`=62 / `bit_not`=64) AND whose `flags & 1 == 0` (`const`, not `var`) —
   evaluate the **init expression** and store under the init node. The evaluator
   itself folds `ident_expr` const chains, so inits referencing other consts also fold. (Foldable
   builtin set and value semantics: see 04.)
3. **Task 3** `if_expr` nodes with `child_2 == 0` (no `else`) and `payload == 0` (capture-free) —
   evaluate the **condition** and, when it folds to a `KIND_BOOL`, store it under the condition
   node. Lowering's `if_expr` `ie_fold` path then elides the untaken
   branch, making module-scope conditions runtime-equal to Zig (step-0 S3/S5/E12). `if_stmt`
   conditions and `if_expr` with an `else` are deliberately not stored; a function-local condition
   operand is invisible to this module-scope sweep (no local-const scope), so its runtime branch
   stays.

**Markers:** `CE`

**Arena:** No sand reset — operates on existing data. Store results in `ctx.comptime_folds` (module arena).

### `phase_SemanticAnalysis` — `main.zig`

**Calls:**
- `alloc_mod.sandReset` — reset scratch at entry and per module
- Builds a `FrontResCtx` identical to `phase_FrontResolution`
- Per module (`ast_root == 0` → `MZ` and skip): `sa_mod.semanticAnalyzerInit`, then per top-level decl:
  - `fn_decl` → `front_res.resolveStmtTypes` (fn body) then `sa_mod.semanticAnalyzerResolveFnBody`
  - `var_decl` whose init is `struct_decl`/packed `union_decl` → `sa_mod.semanticAnalyzerGateModulePackedDecl`;
    init `enum_decl` → `sa_mod.semanticAnalyzerGateEnumModuleDecl`
  - bare `enum_decl` → `sa_mod.semanticAnalyzerGateEnumModuleDecl`

**Markers:** `RS`, `MZ`, `AD`, `DSE`, `DN`, `SA`, `sA`

**Arena:** Sand reset (scratch) at entry and per module. Analyzer workspace in scratch.

**Statement type pre-resolution (moved):** `resolveStmtTypes` and `resolveTypeExpr` now live in
`front_resolution.zig` and are covered by
03_type_resolution.md; `phase_SemanticAnalysis` calls `front_res.resolveStmtTypes` per function
body before `semanticAnalyzerResolveFnBody`. The module-scope var_decl type threading
(previously described here) is likewise owned by `front_resolution.zig`/`semantic_analyzer.zig`.

### `phase_StaticAnalyzers` — `main.zig`

**Calls:**
- `alloc_mod.sandReset` + `alloc_mod.sandResetPeak` — reset scratch and its peak at entry
- Skips the whole pass when all three `no_*_check` flags are true
- Per module: `sym_mod.symbolRegistryGetTable`, build `az_mod.AnalyzerContext` (skip flags from
  CLI, `warn_all`, `on_stmt_cb = onNullStmt`), `az_mod.runAllAnalyzers`

**Flags honored:** `no_null_check`, `no_lifetime_check`, `no_leak_check`, `warn_all`

**Markers:** `A`

**Arena:** Sand reset + reset peak (scratch) at entry; per-module reset. StateMap, defer queues in scratch.

### `phase_AsyncFrameSize` — `main.zig`

**Calls:**
- `async_analysis.asyncFrameSizeRun` — compute async frame sizes/state widths and publish the
  driver/parent-result maps: `suspending_fns`, `frame_sizes`, `state_widths`, `awaited_fns`,
  `async_hidden_fns`, `driver_targets`, `parent_result_type_list`, `parent_result_start`,
  `parent_result_count`

**Markers:** `AFS`

**Arena:** Module arena. Consumed by `phase_LIRLowering`'s async phase A. See 12.

### `phase_LIRLowering` — `main.zig`

**Calls:**
- `alloc_mod.sandReset`; reset `ctx.lir_slots.len`; set the LIR spill temp path (`--output-dir` or `.`)
- `lir_stream.lirStreamBeginWrite` — open the offset-addressed LIR stream
- Build `SemanticContext` (`safe_checks` from CLI, `comptime_folds`, async maps)
- Per module (`M`): `mr_mod.moduleRegistryCollectIncludes`; per top-level decl (`R`, `F`, `A0`):
  - `fn_decl` → `lower_mod.lowererInit` + `lower_mod.lowerFn`; if
    `async_analysis.asyncIsSuspending` → `async_frame_layout.asyncLayoutFrame` +
    `asyncLayoutPublish` and retain the LIR for phase B; else `lir_stream.lirStreamAppend` +
    `lir_mod.lirSlotArrayListAppend`
  - exported fn (`flags & 0x08`) → record in `ctx.exported`
  - global `var_decl` → `lir_mod.globalDeclArrayListAppend` (+ `ctx.exported` when exported)
- `lower_mod.lowerModuleInit` when a module has a runtime-initialized global
- Phase B: `async_state_machine.asyncTransform` on each retained suspending function
- `lir_stream.lirStreamFinishWrite`

**Markers:** `L` (start), `nodes=`, `extra=` (AST node counts), `M` (module index), `R` (root module), `F` (fn_decl), `A0` (decl kinds)

**Arena:** Sand reset (scratch) at entry. Per-function memory (BasicBlocks, insts) in scratch;
retained async LIR also lives in scratch, so resets are deferred once a suspending function is retained.

### `phase_C89Emission` — `main.zig`

**Early exit:** if `!ctx.cli.dump_c89 and !ctx.cli.output_dir_set` — return immediately after the
`C` marker (no emission, no files written). `-o`/`--output-dir` therefore implies emission.

Builds the name mangler, `C89Emitter`, `errorCodeRegistryFinalize`, global-decl slice, and the LIR
read stream; computes the **reachable module set** (value/type reference edges, runtime-init roots,
by-value globals) so only reachable modules are emitted (module pruning). Task 1: before the scan,
`moduleIdForBasename(..., "std_fmt.zig")` sets `emitter.std_fmt_module_id` (the id `getPrintFnName`
mangles against, `0xFFFFFFFF` when absent); during the LIR scan every `.print_val` instruction adds
a `ref_edges` src→std_fmt entry (the mangled print call is not a LIR call, so nothing else would
keep std_fmt reachable or include its header). [updated: 2026-09-24 — Task 1]

- **Stdout branch (no `--output-dir`)** — the classic single-file path, kept byte-identical:
  `emitIncludes` preamble → `cincludeUnionAll` → `emitModule("output", …)` → final flush.
- **Multi-module branch (`--output-dir DIR`)** — `tstTopologicalSort` once →
  `emitSupportFiles` (self-contained runtime/platform support files) →
  `emitSharedHeader` (writes `DIR/zig_special_types.h`) → stable-group `lir_slots` by owning module
  → per reachable module: derive the output stem from `moduleQualifiedName(&emitter, m.id)`
  (basename clamped 64 + `_` + 8-hex FNV-1a of the full path — see 08 §1.17), guard the length
  (`od.len + 1 + base.len + 3 > 511` → error + exit 1), build the module's fn slice + dep-module-id
  list from `import_edges_items[M.imports_start .. M.imports_start+M.import_count]` unioned with
  value-ref targets, then `pal.fileOpen(DIR/<qualified>.h)` (fd `usize`, `== pal.INVALID_FD` on
  failure) → `bufferedWriterInitFd` → `emitModuleHeaderFile` → flush/close/`FINAL_FLUSH`, then the
  same for `.c` via `emitModuleFile`. Finally `emitBuildScripts` (companion build scripts; see 08 §6).

**Calls (stdout branch):**
- `c89_mod.nameManglerInit` — init name mangler
- `c89_mod.c89EmitterInit` — init C89 emitter
- `c89_mod.bufferedWriterInit` — init buffered writer (fd=1 stdout)
- `c89_mod.emitIncludes` — emit C #include directives
- `cinclude.cincludeUnionAll` — collect all C includes
- `c89_mod.emitModule` — emit module to C89
- `c89_mod.bufferedWriterFlush` — final flush

**Calls (multi-module branch):** `c89_mod.tstTopologicalSort`, `c89_mod.emitSupportFiles`,
`c89_mod.emitSharedHeader`, `c89_mod.emitModuleHeaderFile`, `c89_mod.emitModuleFile`,
`c89_mod.emitBuildScripts`, plus `pal.fileOpen`/`pal.fileWrite`/`pal.fileClose` via
`bufferedWriterInitFd`/`bufferedWriterFlush`.

**Markers:** `C` (start), `FINAL_FLUSH` (per file in multi-module mode; once for stdout).

**Arena:** No reset at phase entry — `runCompiler` resets the module arena immediately before calling this phase; the emitter's scratch arena is reset per function inside the emission loops. BufferedWriter, NameMangler, C89Emitter in scratch/emission.

---

## 7. CLI Helper Functions

### `parseArgs` — `main.zig`

Iterates `pal.argCount()` from index 1, dispatching by `matchFlag` (and the prefix matchers
`matchMMFlag`/`matchSFlag`):

```
parseArgs() → CompilerCli
  for i in 1..argc:
    arg = cstrToSlice(pal.argGet(i))
    if arg[0] == '-':
      match --dump-c89
            --max-mem/-m (next arg → parseSize) | -mm<N> (matchMMFlag → parseMMBytes)
            -s<N> (matchSFlag → parseSLevel)
            --max-errors/-e (next arg → parseU32)
            --output-dir/-o (next arg → cstrToSlice; sets output_dir_set)
            --quiet/-q | --test | --sanity-test
            --warnings-as-errors/-W | --warn-error (also sets warn_error)
            --color (next arg → parseColorMode) | --error-format (next arg → parseErrorFormat)
            --track-memory | --no-null-check | --no-lifetime-check
            --no-leak-check | --warn-all | --markers
            -I/--lib-dir (next arg → include_dirs[include_count++], max 16)
            -osl (target_is_windows=false) | -osw (target_is_windows=true)
            --target (next arg → parseTargetIsWindows)
            -ffast (safe_checks=false) | -fsafe (safe_checks=true)
      else → input_file = cstrToSlice(arg_ptr)
    else → input_file = cstrToSlice(arg_ptr)
```

Unrecognized flags (including the declared-but-unmatched `--dump-types`/`-y`/`--dump-lir`/`-l`/`-a`)
are treated as positional `input_file` (no error).

### `matchFlag` — `main.zig`

Exact-length byte-by-byte comparison:
```zig
fn matchFlag(arg: []const u8, flag: []const u8) bool
```

Returns `true` if `arg.len == flag.len` and all bytes match. `matchMMFlag` (`-mm` prefix) and
`matchSFlag` (`-s` prefix) are prefix checks used for the `-mm<N>`/`-s<N>` forms.

**main_dump.zig variant:** Same logic, slightly different loop structure.

### `cstrToSlice` — `main.zig`

Convert null-terminated C string pointer to Zig slice:
```zig
fn cstrToSlice(ptr: [*]const u8) []const u8
```

Walks forward from `ptr` counting non-null bytes, returns `ptr[0..len]`.

**main_dump.zig variant:** Identical.

### `parseSize` — `main.zig`

Parse human-readable memory size string to `u32` bytes:
```zig
fn parseSize(ptr: [*]const u8) u32
```

| Suffix | Multiplier |
|--------|-----------|
| `k`/`K` | ×1024 |
| `m`/`M` | ×1,048,576 |
| `g`/`G` | ×1,073,741,824 |

Digits accumulate via `val = val * 10 + digit`. Non-digit/non-suffix characters are silently ignored.

**main_dump.zig variant:** Takes `[]const u8` directly (not `[*]const u8`), no `'g'`/`'G'` suffix support.

### `parseU32` — `main.zig`

Parse decimal integer string to `u32`:
```zig
fn parseU32(ptr: [*]const u8) u32
```

Skips non-digit characters. No overflow detection.

**main_dump.zig variant:** Takes `[]const u8` directly.

### `parseMMBytes` — `main.zig`

Parse the decimal MB suffix of `-mm<N>` (already stripped of the `-mm` prefix) to a `u32` KB
budget. Clamps at the `POOL_SIZE` ceiling; a bare `-mm` or trailing non-digit exits 1. `-mm0` is
allowed (the `max_mem == 0` relax path in `checkCombinedPeak`).

### `parseSLevel` — `main.zig`

Parse the decimal level of `-s<N>` (already stripped of the `-s` prefix) to a `u32` in
`0..spill_store_mod.SPILL_COUNT` (0 = all spills on disk, higher = more RAM). Bare `-s`,
non-digit, or out-of-range exits 1.

### `parseColorMode` — `main.zig`

Parse color mode string to `ColorMode` enum:
```zig
fn parseColorMode(ptr: [*]const u8) ColorMode
```

| Input | Returns |
|-------|---------|
| `"always"` | `.always` |
| `"never"` | `.never` |
| anything else | `.auto` |

Uses `matchFlag` for comparison.

**main_dump.zig variant:** Checks first character: `'a'` → `.always`, `'n'` → `.never`, else `.auto`.

### `parseErrorFormat` — `main.zig`

Parse error format string to `ErrorFormat` enum:
```zig
fn parseErrorFormat(ptr: [*]const u8) ErrorFormat
```

| Input | Returns |
|-------|---------|
| `"json"` | `.json` |
| `"sarif"` | `.sarif` |
| anything else | `.human` |

Uses `matchFlag` for comparison.

**main_dump.zig variant:** Checks first character: `'j'` → `.json`, else `.human`.

### `parseTargetIsWindows` — `main.zig`

Parse the `--target` argument: `"windows"` → `true`, `"linux"` → `false`; anything else prints
`error: --target must be 'linux' or 'windows'` and exits 1.

### `writeU32` — `main.zig`

Write a `usize` value as decimal string via `pal.measureMarkerWrite`:
```zig
fn writeU32(val: usize) void
```

Custom itoa (not using the format/itoa module) — builds digits right-to-left in a 16-byte stack
buffer. Handles `val == 0` as a special case (writes `"0"`). Used by `runCompiler` for
`--track-memory` peak output.

### `printUsage` — `main.zig`

Prints the usage banner plus the `-mm<N>`, `-s<N>`, `-osl`/`-osw`, and `--target` help lines to
stderr:
```
zig1 - Z98 self-hosted compiler - usage: zig1 [options] <input.zig>
  -mm<N>    hard pool budget in MB (default 64; pool.peak over budget -> ICE rc=3)
  -s<N>     spill level 0..6 (default 0 = all spills on disk; -s1..-s6 deactivate the ...
  -osl       compile target = linux (default); -osw = windows
  --target <linux|windows>  long-form target alias for -osl/-osw
```

**main_dump.zig variant:** More detailed, lists `--test`/`-t`, `--dump-tokens`, `--dump-ast` flags.

---

## 8. Data Flow

```
CLI args (argv)
    │
    ▼
parseArgs()
    │
    ▼
CompilerCli (26 fields)
    │
    ▼
main() constructs CompilerContext (34 fields)
    │
    ▼
runCompiler(ctx)
    │
    ├─ phase_ImportResolution     → ModuleRegistry populated
    ├─ phase_SymbolRegistration   → SymbolRegistry populated
    ├─ suspensionAnalysisRun      → suspending_fns
    ├─ phase_TypeResolution       → TypeRegistry, ResolvedTypeTable, pointer_only_ids
    ├─ phase_FrontResolution      → module-init/type-annotation resolution
    ├─ phase_ComptimeEvaluation   → comptime_folds table
    ├─ phase_SemanticAnalysis     → CoercionTable, resolved_types, enum_value_table
    ├─ phase_StaticAnalyzers      → AnalyzerContext (scratch, discarded)
    ├─ phase_AsyncFrameSize       → frame_sizes / state_widths / async maps
    ├─ phase_LIRLowering          → lir_stream + lir_slots, global_decls
    └─ phase_C89Emission          → C89 output via BufferedWriter
                                        │
                    ┌───────────────────┴────────────────────┐
                    ▼                                        ▼
   stdout single-file (bare --dump-c89)      DIR/*.c + DIR/*.h + DIR/zig_special_types.h
                output.c                     + support files + build scripts
                                             (multi-module, --output-dir/-o DIR)
```

### Field Producers → Consumers

| Field | Produced By | Consumed By |
|-------|-------------|-------------|
| `cli.input_file` | `parseArgs` | `phase_ImportResolution` (path → module) |
| `cli.output_dir` / `output_dir_set` | `parseArgs` | spill-path setup (`main`), `phase_LIRLowering`, `phase_C89Emission` (live — multi-module file emission) |
| `cli.dump_c89` | `parseArgs` | `phase_C89Emission` |
| `cli.safe_checks` | `parseArgs` | `phase_LIRLowering` (SemanticContext), `phase_C89Emission` |
| `cli.target_is_windows` | `parseArgs` | `phase_ComptimeEvaluation` (`@isWindows`), `phase_C89Emission` (build scripts) |
| `cli.*_check` flags | `parseArgs` | `phase_StaticAnalyzers` |
| `cli.track_memory` | `parseArgs` | `runCompiler` (final print) |
| `store` (AstStore) | `phase_ImportResolution` (parser) | All phases |
| `symbol_reg` | `phase_SymbolRegistration` | Phases 3-9 |
| `typereg` | Init (primitives) + phase 3 | Phases 2-10 |
| `resolved_types` | `phase_FrontResolution`, `phase_TypeResolution` | `phase_LIRLowering`, emission |
| `coercion_table` | Init | `phase_FrontResolution`, `phase_SemanticAnalysis`, `phase_LIRLowering` |
| `comptime_folds` | `phase_ComptimeEvaluation` | `phase_LIRLowering` |
| `pointer_only_ids` | `phase_TypeResolution` | `phase_C89Emission` |
| `lir_stream` / `lir_slots` | `phase_LIRLowering` | `phase_C89Emission` |
| `global_decls` | `phase_LIRLowering` | `phase_C89Emission` |
| async maps (`frame_sizes`, `state_widths`, …) | `phase_AsyncFrameSize` | `phase_LIRLowering` (async phase A/B) |

---

## 9. Debugging

### Adding Diagnostic Markers

The marker system (`pal.markerWrite`) writes to stderr when `--markers` is enabled. To add a new marker:

```zig
var my_marker: []const u8 = "MY_MARKER\n";
pal.markerWrite(my_marker);
```

For integer values in markers:
```zig
var buf: [20]u8 = undefined;
var len = itoa_mod.itoa(value, buf[0..]);
var start: usize = 19 - len;
pal.markerWrite(buf[start..19]);  // right-aligned in 19-char field
```

### Skipping Phases

To skip a phase, comment out the call in `runCompiler` or add a conditional early return at the top of the phase function:

```zig
fn phase_C89Emission(ctx: *CompilerContext) void {
    if (!ctx.cli.dump_c89 and !ctx.cli.output_dir_set) return;  // real early exit
    // ... normal body
}
```

Note: Skipping phases breaks downstream consumers. For example, skipping TypeResolution means `pointer_only_ids` stays undefined, which crashes C89Emission.

### Phase Isolation

Each phase resets the scratch arena on entry (`alloc_mod.sandReset(&ctx.alloc.scratch)`). To preserve data across a phase, allocate from module or permanent arena before the phase runs.

### Common Debug Patterns

1. **Check arena pressure:** Enable `--track-memory` to see per-arena peak usage
2. **Trace phase entry/exit:** Enable `--markers` and grep for phase markers
3. **Inspect AST before a phase:** Add a `dump_ast` call at the phase entry
4. **Force error exit:** Trigger `diagnosticCollectorHasErrors` early to test error path

### Marker Coverage

Per-phase marker inventory (all written by `main.zig`):

| Phase | Markers | Density |
|-------|---------|---------|
| 1 import | `I`, `Z` | thin — entry/exit only, no per-module detail |
| 2 symreg | `S`, `S0` + per-decl AstKind values | dense — one line per root decl |
| 3 typeres | `T`, `T0` + per-decl AstKind values | dense |
| 4 front-resolution | (none) | none — pass is silent |
| 5 comptime | `CE` | thin — single marker, no per-node detail |
| 6 sema | `RS MZ AD DSE DN SA sA` | densest (per-decl) |
| 7 analyzers | `A` | thin — single marker, no per-function detail |
| 8 async frame size | `AFS` | thin |
| 9 lir | `L nodes= extra= M R F A0` | dense |
| 10 c89 | `C`, `FINAL_FLUSH` | thin — entry/exit only |

The `runCompiler` inter-phase markers `2 3 3a 4` and `t1`/`t2` bracket the import/type boundaries.
`front_resolution.zig` emits no markers of its own. The sema-phase switch (`P0:`/`PL0:n`) and
name-cache (`REG:cp`/`REG:ct`) sub-markers live in `semantic_analyzer.zig` and are documented in 05.

Gaps: phases 1, 4, 5, 7, 8, 10 have entry/exit markers only; internal behavior of comptime eval,
static analyzers, and C89 emission is invisible to `--markers` alone.

### Known Issues

- **`--dump-types`/`-y` and `--dump-lir`/`-l` are declared but dead.** The `dump_types` and
  `dump_lir` fields exist in `CompilerCli`, but `parseArgs` never matches the flags and no phase
  consults the fields. The `-y`/`-l`/`-a` string constants are declared but never compared. Passing
  any of them falls through to the positional `input_file` branch.
- **`main_dump.zig`'s `--sanity-test` is parsed but not acted on**, and its `-o`/`--output` sets
  `output_dir`, which `main_dump` never reads.
- **`main_dump.zig`'s `-e` short flag is shadowed:** the `--error-format` branch tests `-e` before
  the `--max-errors` branch, so `-e` sets `error_format` rather than `max_errors`.
- **`main_dump.zig`'s `runCompiler` and `phase_*` bodies are stubs** (the `phase_ASTLowering` stub
  has no counterpart in `main.zig`).
- **`config.zig`'s `host_is_windows` is unwired** — nothing imports `config.zig`; the `@isWindows`
  value comes from `ComptimeEval.host_is_windows`, set by `main.zig` from `cli.target_is_windows`
  (see 04 §`host_is_windows`).
- **`ctx.dep_graph` is a dead field** — initialized in `main` but never populated; live DepGraphs
  are scratch-local (see §5 DepGraph Lifecycle).

---

## 10. `main_dump.zig` — Standalone Dump Binary

**File:** `main_dump.zig`

Entry for token/AST dumping without running the full pipeline.

### Differences from main.zig

| Aspect | main.zig | main_dump.zig |
|--------|----------|---------------|
| CompilerCli fields | 26 | 16 |
| CompilerContext fields | 34 | 6 |
| Phase implementations | Full 10-phase pipeline | Empty stubs (`_ = ctx;`) |
| Dump targets | c89 (stdout) / multi-module tree | tokens, ast |
| `--sanity-test` | Lexer test | Parsed but not acted on |
| `parseSize` suffix | k, m, g | k, m only |
| `parseColorMode` | `matchFlag` | First-character check |
| `parseErrorFormat` | `matchFlag` | First-character check |
| Default max_mem | `DEFAULT_MAX_MEM_KB` (64 MiB) | fixed 16 MiB |
| `output_dir` use | live (emission + spill paths) | parsed, unused |

### Entry Flow

```
main(argc, argv)
  ├─ parseArgs()
  ├─ if cli.input_file.len == 0 → printUsage() (stdout), return
  ├─ if cli.dump_ast:
  │     ├─ initCompilerAlloc, interner, source_man, diag, keyword table
  │     ├─ pal.readFile(cli.input_file, &compiler_alloc.permanent)
  │     ├─ Two-pass lex: count tokens → allocate array → fill
  │     ├─ parserParseModuleRoot → AST
  │     └─ dump_ast.dumpAst(store, root, interner)
  └─ else: error "no mode selected, use --dump-ast" → stderr, exit 1
```

`main_dump.zig`'s `parseArgs` starts at index 0 (unlike `main.zig`'s index 1), accepts
`--dump-tokens`/`--dump-ast`, `--test`/`-t`, `--sanity-test`, `-o`/`--output`, `--color`/`-c`,
`--error-format`/`-e`, `--warnings-as-errors`/`-w`, `--quiet`/`-q`, `--max-mem`/`-m`,
`--max-errors`, `--track-memory`, and `--include`/`-I`, and errors on any other `-`-prefixed
argument.

### Phase Stubs

All `phase_*` functions are empty stubs (`_ = ctx;`), present for compilation compatibility with
shared test infrastructure that expects the function signatures. The set is
`phase_ImportResolution`, `phase_SymbolRegistration`, `phase_TypeResolution`,
`phase_SemanticAnalysis`, `phase_ASTLowering` (no live counterpart), and `phase_C89Emission`, plus
a stub `runCompiler(source, ctx)`.

---

## 11. Tooling Mains

### `main_exp.zig`

A 5-line bootstrap smoke entry: imports `extern_c.zig` and calls
`ext_c.__bootstrap_print("zig1 bootstrap test\n")` then `ext_c.__bootstrap_print_int(42)`. Used to
validate the extern-C print surface, not the compiler pipeline.

### `strip_main.zig`

A 9-line link-check entry: imports `pal.zig` and `name_mangler.zig` (`NameMangler`,
`nameManglerInit`), calls `nameManglerInit()`, and writes `"zig1\n"` to stderr. Used to confirm the
name-mangler object links standalone; it runs no pipeline phase.
