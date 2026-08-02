# Pipeline Orchestration — main.zig, main_dump.zig

> Source: `sf/src/main.zig` (957 lines), `sf/src/main_dump.zig` (326 lines)

## 1. Overview

Two entry-point binaries share the same phase naming convention:

| Binary | File | Purpose |
|--------|------|---------|
| `zig1` | `main.zig` | Full 8-phase compiler pipeline: source → C89 |
| `zig1-dump` | `main_dump.zig` | Standalone dump binary (tokens, AST only) |

Both define `CompilerCli`, `CompilerContext`, `matchFlag`, `cstrToSlice`, `parseSize`, `parseU32`, `parseColorMode`, `parseErrorFormat`, and `phase_*` stubs (main_dump has empty stubs). Only `main.zig` implements the full pipeline.

---

## 2. `CompilerCli` — CLI Argument Struct

**File:** `main.zig:61-84` (22 fields)

| # | Field | Type | Default | Flag(s) |
|---|-------|------|---------|---------|
| 1 | `input_file` | `[]const u8` | `""` | positional |
| 2 | `output_dir` | `[]const u8` | `"."` | `--output-dir`, `-o` |
| 3 | `dump_types` | `bool` | `false` | `--dump-types`, `-y` |
| 4 | `dump_lir` | `bool` | `false` | `--dump-lir`, `-l` |
| 5 | `dump_c89` | `bool` | `false` | `--dump-c89` |
| 6 | `max_mem` | `u32` | `DEV_MAX_MEM` | `--max-mem`, `-m` |
| 7 | `max_errors` | `u32` | `256` | `--max-errors`, `-e` |
| 8 | `color` | `ColorMode` | `.auto` | `--color` |
| 9 | `error_format` | `ErrorFormat` | `.human` | `--error-format` |
| 10 | `warnings_as_errors` | `bool` | `false` | `--warnings-as-errors`, `-W` |
| 11 | `quiet` | `bool` | `false` | `--quiet`, `-q` |
| 12 | `test_mode` | `bool` | `false` | `--test` |
| 13 | `sanity_test_mode` | `bool` | `false` | `--sanity-test` |
| 14 | `track_memory` | `bool` | `false` | `--track-memory` |
| 15 | `no_null_check` | `bool` | `false` | `--no-null-check` |
| 16 | `no_lifetime_check` | `bool` | `false` | `--no-lifetime-check` |
| 17 | `no_leak_check` | `bool` | `false` | `--no-leak-check` |
| 18 | `warn_all` | `bool` | `false` | `--warn-all` |
| 19 | `warn_error` | `bool` | `false` | `--warn-error` |
| 20 | `show_markers` | `bool` | `false` | `--markers` |
| 21 | `include_dirs` | `[16][]const u8` | `undefined` | `-I` |
| 22 | `include_count` | `u32` | `0` | (implicit from -I count) |

**main_dump.zig variant:** `main_dump.zig:35-52` (15 fields) — replaces `dump_types`/`dump_lir`/`dump_c89` with `dump_tokens`/`dump_ast`, adds `print_usage`, omits analyzer toggle flags (`no_null_check`, `no_lifetime_check`, `no_leak_check`, `warn_all`, `warn_error`, `show_markers`), uses fixed 16MB `max_mem` default.

---

## 3. `CompilerContext` — Global Compiler State

**File:** `main.zig:87-109` (20 fields)

| # | Field | Type | Arena | Subsystem |
|---|-------|------|-------|-----------|
| 1 | `cli` | `CompilerCli` | (value) | CLI arguments snapshot |
| 2 | `alloc` | `*CompilerAlloc` | — | 3-tier memory allocator |
| 3 | `interner` | `*StringInterner` | permanent | String interning |
| 4 | `diag` | `*DiagnosticCollector` | permanent | Error/warning collection |
| 5 | `source_man` | `*SourceManager` | permanent | Source file text storage |
| 6 | `name_mangler` | `*NameMangler` | (stack) | C89 name mangling |
| 7 | `module_reg` | `*ModuleRegistry` | permanent | Module graph + imports |
| 8 | `typereg` | `*TypeRegistry` | type_db (128KB sand) | Type system registry |
| 9 | `store` | `*AstStore` | module | AST node store |
| 10 | `symbol_reg` | `*SymbolRegistry` | permanent | Symbol table per module |
| 11 | `resolved_types` | `*ResolvedTypeTable` | module | Type expr → TypeId mapping |
| 12 | `coercion_table` | `*CoercionTable` | module | Coercion rule storage |
| 13 | `dep_graph` | `*symbol_registrator.DepGraph` | module (UNUSED) | Symbol dependency graph — **dead field**: initialized at `main.zig:162` but never populated/consumed by the pipeline (see §5 DepGraph Lifecycle). Live graphs are scratch-local per phase. |
| 14 | `lir_fns` | `LirFunctionArrayList` | module | Compiled LIR functions |
| 15 | `enum_value_table` | `hash_mod.U32ToU32Map` | module | Enum field → value mapping |
| 16 | `call_arg_types` | `hash_mod.U32ToU32Map` | module | Per-call argument types |
| 17 | `call_param_map` | `hash_mod.U32ToU32Map` | module | Per-call parameter mapping |
| 18 | `comptime_values` | `hash_mod.U32ToU64Map` | module | Comptime-evaluated values |
| 19 | `pointer_only_ids` | `[*]u32` | permanent | Types emitted as pointers only |
| 20 | `pointer_only_len` | `u32` | (value) | Length of pointer-only list |

**Initialization order** (`main.zig:137-166`):
1. `initCompilerAlloc()` — 3-tier arena
2. `stringInternerInit` — string interning
3. `sourceManagerInit` — source text manager
4. `diagnosticCollectorInit` — diagnostic collector
5. `initKeywordTable` — lexer keyword lookup
6. `nameManglerInit` — C89 name mangler
7. `moduleRegistryInit` + `moduleRegistrySetSourceMan` — import system
8. `sandInit` (128KB type_db) + `typeRegistryInit` + `typeRegistryRegisterPrimitives` — type system
9. `astStoreInit` — AST node store
10. `symbolRegistryInit` — symbol registry
11. `resolvedTypeTableInit` — resolved type table
12. `coercionTableInit` — coercion table
13. `lirFunctionArrayListInit` — LIR function list
14. `depGraphInit` — dependency graph
15. Hash maps: `enum_value_table`, `call_arg_types`, `call_param_map`, `comptime_values`

**main_dump.zig variant:** Only has `cli`, `alloc`, `interner`, `diag`, `source_man`, `name_mangler` (6 fields, `main_dump.zig:54-61`).

---

## 4. `main` — Entry Point

**File:** `main.zig:111-190`

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
  │   ├─ print "use test_main.zig for test mode"
  │   └─ pal.exit(1)
  │
  ├─ [NO INPUT] cli.input_file.len == 0
  │   ├─ printUsage()
  │   └─ return
  │
  ├─ [ROOT FILE CHECK] pal.readFile(cli.input_file, &compiler_alloc.permanent) orelse {…}   ← F-S10
  │   ├─ "error: could not read input file\n" → stderr
  │   └─ pal.exit(1)
  │
  ├─ [NORMAL COMPILATION]
  │   ├─ initCompilerAlloc() + set max_mem
  │   ├─ Initialize all 8 subsystems (interner → comptime_values)
  │   ├─ Construct CompilerContext
  │   └─ runCompiler(&ctx)
  │
```

### Early Exits — [updated: 2026-08-01]

| Condition | Action |
|-----------|--------|
| `cli.sanity_test_mode` | Lexer sanity check, return immediately |
| `cli.test_mode` | Print error, `pal.exit(1)` — test_main.zig is the test entry |
| `cli.input_file.len == 0` | `printUsage()`, return |
| **input file missing or empty (F-S10)** | `pal.readFile` returns null → `error: could not read input file\n` on stderr, `pal.exit(1)` (`main.zig:139-144`) — one message covers both missing and empty, matching the `main_dump.zig:73-79` pattern. Previously this was silent (exit 0 + 243-byte boilerplate C on stdout or junk `.c/.h` files on `--output-dir`) |

### Output Directory Isolation

[updated: 2026-08-01] `cli.output_dir` is now **live**: when `--dump-c89 --output-dir DIR` is
set, `phase_C89Emission` writes per-module `.c`/`.h` files plus `zig_special_types.h` into `DIR`
(via the `BufferedWriter` fd sink + `pal.fileOpen`/`fileWrite`/`fileClose`). The output directory
is still **not created or checked in main()** — callers must `mkdir -p DIR` first (the
QUICK_REF/NOTES.md recipes do). Bare `--dump-c89` (no `--output-dir`, default `"."` unchanged)
keeps the stdout single-file path byte-identical — stdout-path preservation is a hard gate.

---

## 5. `runCompiler` — Phase Orchestration

**File:** `main.zig:192-255`

### Phase Sequence (ordered)

```
runCompiler(ctx)
  │
  ├── 1. phase_ImportResolution(ctx)
  │     marker: I, Z
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     marker: 2, 3, 3a, 4
  │
  ├── 2. phase_SymbolRegistration(ctx)
  │     marker: S, S0
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │
  ├── 3. phase_TypeResolution(ctx)
  │     marker: T, T0
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     marker: t1
  │     [ERROR CHECK] → pal.exit(2) if errors    ← main.zig:205 (F-S10)
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     marker: t2
  │
  ├── 4. phase_ComptimeEvaluation(ctx)
  │     marker: CE
  │
  ├── 5. phase_SemanticAnalysis(ctx)
  │     marker: RS, MZ, AD, DSE, DN, SA, sA, P0-P3, V2:, REG:tl, REG:tt
  │     [ERROR CHECK] → pal.exit(2) if errors    ← main.zig:212
  │
  ├── 6. phase_StaticAnalyzers(ctx)
  │     marker: A
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [ERROR CHECK] → pal.exit(2) if errors    ← main.zig:218
  │
  ├── 7. phase_LIRLowering(ctx)
  │     marker: L, M, R, F, A0
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [ERROR CHECK] → pal.exit(2) if errors    ← main.zig:224
  │
  ├── 8. phase_C89Emission(ctx)
  │     marker: C, FINAL_FLUSH
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [WARNING CHECK] → pal.exit(1) if warnings_as_errors or warn_error   ← main.zig:230
  │
  ├── [TRACK MEMORY] if cli.track_memory
  │     print perm_kb / mod_kb / scr_kb / total_kb
  │
  └── diagnosticCollectorPrintAll(ctx.diag)  — final output
```

### Memory Checkpoints

| Location | Call | Purpose |
|----------|------|---------|
| After phase 1 | `checkCombinedPeak(ctx.alloc)` | Peak memory after import resolution |
| After phase 1 | `checkCombinedPeak(ctx.alloc)` | (second call, same point — see code line 187) |
| After phase 2 | `checkCombinedPeak(ctx.alloc)` | Peak after symbol registration |
| After phase 3 | `checkCombinedPeak(ctx.alloc)` | Peak after type resolution |
| After phase 3 | `checkCombinedPeak(ctx.alloc)` | (second call, between t1 and t2 markers) |
| After phase 6 | `checkCombinedPeak(ctx.alloc)` | Peak after static analyzers |
| After phase 7 | `checkCombinedPeak(ctx.alloc)` | Peak after LIR lowering |
| After phase 8 | `checkCombinedPeak(ctx.alloc)` | Peak after C89 emission |

### Diagnostic Exits — [updated: 2026-08-01]

| Location | Condition | Exit Code |
|----------|-----------|-----------|
| After phase 3 | `diagnosticCollectorHasErrors` | 2 |
| After phase 5 | `diagnosticCollectorHasErrors` | 2 |
| After phase 6 | `diagnosticCollectorHasErrors` | 2 |
| After phase 7 | `diagnosticCollectorHasErrors` | 2 |
| After phase 8 | `warnings_as_errors or warn_error` + warning count > 0 | 1 |
| **main() root check (F-S10)** | `pal.readFile` null (input missing/empty) | **1** (`main.zig:139-144`) |

**F-S10 note (exit asymmetry):** dependency file failures surface as `error[3048]` diagnostics in
phase 1 (`import_resolver.zig:96-105` empty dep; `module_registry.zig:263-270` missing dep) and are
caught by the **first** `hasErrors` gate at `main.zig:205` → `pal.exit(2)` — the same path as all
other diagnostics. The root input file uses a separate pre-phase check with exit **1** (the I/O/usage
class, matching `main_dump.zig:78`). The 1-vs-2 split is deliberate. Both `pal.exit` calls use the
`pal.exit(code)` convention.

### Empirical Arena Peaks — `--track-memory` (P10 evidence) `[markers]` + `[fprintf]` — [updated: 2026-08-01]

Final `--track-memory` line (`main.zig:234-253`) on the release zig1, all 4 examples
(`--markers --track-memory --dump-c89`, exit 0, zero diagnostics):

| Example | perm | mod | scr | total | AST nodes (`L\nnodes=` `main.zig:515`) |
|---------|------|-----|-----|-------|----------------------------------------|
| `mud_server` | 72K | 103K | 184K | 359K | 944 |
| `game_of_life` | 65K | 92K | 186K | 343K | 807 |
| `lisp_interpreter_curr` | 118K | 412K | 844K | 1374K | 3854 |
| `json_parser` | 52K | 197K | 376K | 625K | 1568 |

All well under the 4 MB static arena total (`allocator.zig:74-76`) and 8 MB `DEV_MAX_MEM`
(`allocator.zig:78`).

**Per-phase peaks** `[fprintf]` (debug build `/tmp/z1`, values in KB; perm/mod/scr = `peak` of
each tier read at the phase boundary — matches release `--track-memory` byte-for-byte):

| Phase boundary | mud perm/mod/scr | gol perm/mod/scr | lisp perm/mod/scr | json perm/mod/scr |
|----------------|------------------|------------------|-------------------|-------------------|
| after import | 26/57/103 | 15/58/100 | 75/229/208 | 29/114/101 |
| after symreg | 28/57/103 | 16/58/100 | 79/229/208 | 32/114/101 |
| after typeres | 32/61/103 | 19/59/100 | 87/237/208 | 37/120/101 |
| after comptime | 32/62/103 | 19/61/100 | 87/238/208 | 37/121/101 |
| after sema | 32/96/103 | 19/90/100 | 87/399/208 | 37/191/101 |
| after analyzers | 32/96/**0** | 19/90/**0** | 87/399/**0** | 37/191/**0** |
| after lir | 33/103/155 | 19/92/162 | 87/412/715 | 37/197/319 |
| after c89 | 72/103/184 | 65/92/186 | 118/412/844 | 52/197/376 |

Observations:
- **scratch `scr=` drops to 0 after phase 6**: `phase_StaticAnalyzers` calls
  `sandResetPeak` (`main.zig:481`) right after `sandReset`. The final `track-memory` `scr=`
  therefore reports the peak of **phases 6-8 only** (max of LIR lowering / C89 emission) — any
  earlier-phase scratch pressure (phases 1-5 here peak ~100-208K) is masked by the reset.
- **module `mod=` grows most during phase 5** (sema): mud 62→96K, gol 61→90K, lisp 238→399K,
  json 121→191K — `ResolvedTypeTable`/`CoercionTable`/`enum_value_table` writes in module arena.
- **permanent `perm=` grows most during phase 8** (C89 emission): mud 33→72K, gol 19→65K,
  lisp 87→118K — the emitter interns emitted type/ident names into the permanent arena.
- The `TypeRegistry` type_db sand is a **separate 128KB stack buffer** (`main.zig:153-154`),
  not part of the 3-tier arena and not included in `track-memory`.

### DepGraph Lifecycle — Cross-Phase Data Persistence (Q3) `[fprintf]`

The pre-plan audit asked "how does DepGraph survive phase 2→3?". Answer: **it does not, and it
does not need to — each phase builds its own scratch-local graph, and phase 3 rebuilds it.**
Evidence from instrumenting the generated C89 (`/tmp/z1`, `main.c` phase functions):

```
mud:  DG:S2:init  local dg=0xff9d5b8c scratch.pos=0  ctx->dep_graph=0xff9d6194 module-dg.len=0
      DG:S2:end   local dg len=15 scratch.pos=192  module-dg.len=0
      DG:T3:entry PRE-reset scratch.pos=192        ← phase-2 edges still physically present
      DG:T3:post-reset scratch.pos=0               ← sandReset (main.zig:299) wipes them
      DG:T3:after reg local dg len=15              ← phase 3 rebuilt the SAME 15 edges
```

Edge counts (identical between phase 2 and phase 3, proving full rebuild): mud 15, gol 4,
lisp 19, json 11.

- `phase_SymbolRegistration` creates a **local** `dep_graph` in scratch (`main.zig:270`) and
  passes it only to `registerModuleSymbols`; the graph is **never consumed inside phase 2**
  (no `typeResolverBuild`). It is write-only work.
- `phase_TypeResolution` resets scratch (`main.zig:299`), wiping the phase-2 edges, then
  creates its **own** local `dep_graph` in scratch (`main.zig:300`), re-runs the identical
  `registerModuleSymbols` loop (`main.zig:304`), and consumes it via `typeResolverBuild`
  (`main.zig:309`), which copies the edges into the TypeResolver's own `depend_items` arrays.
- `ctx.dep_graph` (the module-arena field initialized at `main.zig:162`) is **never populated
  by the pipeline** — `module-dg.len` stays 0 for all 4 examples. It is a dead field.
  → Correct the CompilerContext table (row 13): the live DepGraph is scratch-local and per-phase;
  the module-arena `ctx.dep_graph` is unused.
- **Implication for phase isolation:** no cross-phase heap handoff is relied upon for DepGraph;
  the 00 doc "Module arena contains DepGraph" claim (00_shared_infra.md "Who Allocates Where")
  describes the dead `ctx.dep_graph` field, not the live pipeline.

### Phase Timing — marker deltas (Q4) `[fprintf]`

Markers carry no timestamps, so per-phase wall-clock was measured by instrumenting the
generated C89 with `gettimeofday` at each phase boundary in `runCompiler` (`/tmp/z1/main.c`).
Values are wall-clock ms on this Linux host, 32-bit `-O0` debug build — treat as **relative**
proportions, not absolute perf.

**lisp_interpreter_curr** (largest example):

| Phase | ms | % |
|-------|----|---|
| import | 48.8 | 9.2% |
| symreg | 1.0 | 0.2% |
| typeres | 10.1 | 1.9% |
| comptime | 0.5 | 0.1% |
| sema | 125.8 | 23.7% |
| analyzers | 0.01 | ~0% |
| lir | 118.3 | 22.3% |
| c89 | 226.4 | 42.7% |

C89 emission dominates (~43%), then sema (~24%), then LIR lowering (~22%). Import is ~9%.
Smaller examples share the shape: mud 12.3/0.4/3.3/0.6/30.7/0.01/27.3/41.0 ms;
gol 9.7/0.2/1.5/1.0/19.7/0.01/24.0/44.4 ms; json 20.0/0.4/4.2/0.2/51.4/0.01/52.1/91.9 ms.
Phases 2, 4, 6 are negligible on all 4 examples.

### `--dump-c89` vs no-dump — phase skipping (Q5) `[markers]` + source — [updated: 2026-08-01]

**No pipeline phase is skipped when `--dump-c89` is absent.** Only `phase_C89Emission`
early-returns (`main.zig:612` `if (!ctx.cli.dump_c89) return;`). Evidence: a no-dump run
emits the same `I Z S T CE RS A L C` marker set and LIR lowering still builds `lir_fns`, but
no `FINAL_FLUSH` marker (`main.zig:730`) and 0 bytes to stdout. `--dump-types` and `--dump-lir`
are declared (`main.zig:734-735`) but never matched in `parseArgs` and **no phase consults them** —
they have no effect on the current pipeline. The LIR lowering + scratch work for an un-emitted build is wasted.

---

## 6. Phase Function Details

### `phase_ImportResolution` — `main.zig:257-265`

**Calls:**
- `interner_mod.stringInternerIntern` — intern input file path
- `mr_mod.moduleRegistryAddModule` — register root module
- `mr_mod.importQueueEnqueue` — enqueue root for import resolution
- `import_resolver.moduleRegistryResolveImports` — drain import queue, parse all modules

**Markers:** `I` (start), `Z` (done)

**Arena:** Sand reset (scratch) at entry. Import queue and parsing temporaries use scratch.

[updated: 2026-08-01] **F-S10 dependency diagnostics fire in this phase:** an empty dep fails
`pal.readFile` at `import_resolver.zig:96-105` → `error[3048]: could not read imported file '<path>'`
+ `ModuleState.failed`; a missing dep (never resolves in the 3-tier search) errors at the
`moduleRegistryResolveImport` null choke point `module_registry.zig:263-270` →
`error[3048]: could not resolve imported file '<path>'`. Both are caught by the first `hasErrors`
gate at `main.zig:205` → exit 2.

### `phase_SymbolRegistration` — `main.zig:267-287`

**Calls:**
- `symbol_registrator.depGraphInit` — create dep graph in scratch
- `symbol_registrator.registerModuleSymbols` — register all symbols per module
- Root module AST walk: enumerate children, write AstKind enum values as markers

**Markers:** `S` (start), `S0` + per-decl kind values

**Arena:** Sand reset (scratch) at entry. DepGraph allocated in scratch.

### `phase_TypeResolution` — `main.zig:297-324`

**Calls:**
- `symbol_registrator.registerModuleSymbols` — re-run symbol registration for type context
- `const_alias_prepass.constAliasPrepass` — detect const alias dependency cycles
- `type_resolver.typeResolverResolveNames` — resolve type expression names
- `type_resolver.typeResolverInit` — create type resolver
- `type_resolver.typeResolverBuild` — build type dependency graph (Kahn)
- `type_resolver.typeResolverResolve` — resolve all types in topological order
- `type_resolver.classifyTypeEmissionGroups` — classify pointer-only types
- Sets `ctx.pointer_only_ids` and `ctx.pointer_only_len`

**Markers:** `T` (start), `T0` + per-decl kind values

**Arena:** Sand reset (scratch) at entry. Const alias prepass uses permanent. TypeResolver workspace in scratch.

### `phase_ComptimeEvaluation` — `main.zig:334-341`

**Calls:**
- `ce_mod.comptimeEvalInit` — init comptime evaluator
- `ce_mod.comptimeEvalEvaluate` — evaluate each `builtin_call` node
- `hash_mod.u32ToU64MapPut` — store evaluated values

**Markers:** `CE`

**Arena:** No sand reset — operates on existing data. Store results in `ctx.comptime_values` (module arena).

### `phase_SemanticAnalysis` — `main.zig:351-419`

**Calls:**
- `sa_mod.semanticAnalyzerInit` — init semantic analyzer per module
- `resolveStmtTypes(ctx, decl.child_0, 0)` — resolve types in fn_decl body
- `sa_mod.semanticAnalyzerResolveFnBody` — type-check function body
- `resolveTypeExpr(ctx, decl.child_0)` — resolve var_decl type expression
- `resolved_type_table.resolvedTypeTableSet` — store resolved types
- `sa_mod.semanticAnalyzerResolveExpr` — type-check initialization expression
- `type_mod.nameCachePut` — cache resolved type for ident expressions

**Markers:** `RS`, `MZ`, `AD`, `DSE`, `DN`, `SA`, `sA`, `P0-P3`, `V2:`, `REG:tl`, `REG:tt`

**Arena:** Sand reset (scratch) at entry. Analyzer workspace in scratch.

### `resolveStmtTypes` — `main.zig:421-470`

Recursive helper called from `phase_SemanticAnalysis`. Walks statement nodes to pre-resolve type expressions before full semantic analysis.

**Logic:**
1. Depth limit of 16 (prevents infinite recursion on cyclic AST)
2. For `var_decl`: resolve type expression via `resolveTypeExpr`, store in `resolved_type_table`
3. For `array_init`/`struct_init`/`tuple_literal`: resolve child_0 type expression
4. For `block`: recurse into children
5. For any node: recurse into child_0 and child_1

**Markers:** `P0-P3` (pointer alignment bits in var_decl child_0), `R0n` (node index), `R1t` (type id), `R2s` (set), `AI` (array init), `FI` (failed init)

### `resolveTypeExpr` — `main.zig:472-476`

Thin wrapper around `type_resolver.resolveTypeExprFull`:
```zig
fn resolveTypeExpr(ctx: *CompilerContext, node_idx: u32) type_mod.TypeId {
    var env = type_resolver.TypeResolveEnv{ .store = ctx.store, .typereg = ctx.typereg, .symbol_reg = ctx.symbol_reg, .interner = ctx.interner };
    return type_resolver.resolveTypeExprFull(&env, node_idx, 0);
}
```

Built on the fly — no allocation. Returns `TYPE_UNDEFINED` if resolution fails.

### `phase_StaticAnalyzers` — `main.zig:478-503`

**Calls:**
- `az_mod.AnalyzerContext` construction with skip flags from CLI
- `az_mod.runAllAnalyzers` — run null/lifetime/leak analyzers per module

**Flags honored:** `no_null_check`, `no_lifetime_check`, `no_leak_check`, `warn_all`

**Markers:** `A`

**Arena:** Sand reset + reset peak (scratch) at entry. StateMap, defer queues in scratch.

### `phase_LIRLowering` — `main.zig:513-608` — [updated: 2026-08-01]

**Calls:**
- `lower_mod.lowererInit` — init LIR lowerer per function
- `lower_mod.lowerFn` — lower function to LIR
- `lir_mod.lirFunctionArrayListAppend` — store compiled LIR function
- `mr_mod.moduleRegistryCollectIncludes` — collect C includes per module

**Markers:** `L` (start), `nodes=`, `extra=` (AST node counts), `M` (module index), `R` (root module), `F` (fn_decl), `A0` (decl kinds)

**Arena:** Sand reset (scratch) at entry. Per-function memory (BasicBlocks, insts) in scratch.

### `phase_C89Emission` — `main.zig:610-732`

[updated: 2026-08-01] Branches on `--output-dir` (with `--dump-c89`):
- **Stdout branch (no `--output-dir`)** — the classic single-file path below, kept byte-identical:
  `emitIncludes` preamble → `cincludeUnionAll` → `emitModule("output", …)` → final flush.
- **Multi-module branch (`--output-dir DIR`)** — `tstTopologicalSort` once →
  `emitSharedHeader` (writes `DIR/zig_special_types.h`) → per-module loop over
  `moduleRegistryGetModules`: derive the output stem from `moduleQualifiedName(&emitter, m.id)`
  (basename clamped 64 + `_` + 8-hex FNV-1a of the full path — see 08 §1.17; replaces the old
  basename-only derivation and its duplicated copy in `emitModuleHeaderFile`), guard the length
  (`main.zig:665`, `od.len + base.len + 3 > 511` → error + exit 1), build the module's fn slice +
  dep-module-id list from
  `import_edges_items[M.imports_start .. M.imports_start+M.import_count]`, then
  `pal.fileOpen(DIR/<qualified>.h)` (fd `usize`, `== pal.INVALID_FD` on failure) →
  `bufferedWriterInitFd` → `emitModuleHeaderFile` →
  flush/close, then the same for `.c` via `emitModuleFile`. Per-file `FINAL_FLUSH`.

**Calls (stdout branch):**
- `c89_mod.nameManglerInit` — init name mangler
- `c89_mod.c89EmitterInit` — init C89 emitter
- `c89_mod.bufferedWriterInit` — init buffered writer (fd=1 stdout)
- `c89_mod.emitIncludes` — emit C #include directives
- `cinclude.cincludeUnionAll` — collect all C includes
- `c89_mod.emitModule` — emit module to C89
- `c89_mod.bufferedWriterFlush` — final flush

**Calls (multi-module branch):** `c89_mod.tstTopologicalSort`, `c89_mod.emitSharedHeader`,
`c89_mod.emitModuleHeaderFile`, `c89_mod.emitModuleFile`, plus
`pal.fileOpen`/`pal.fileWrite`/`pal.fileClose` via `bufferedWriterInitFd`/`bufferedWriterFlush`.

**Early exit:** If `!ctx.cli.dump_c89` — return immediately (no emission, no files written).

**Markers:** `C` (start), `FINAL_FLUSH` (per file in multi-module mode; once for stdout).

**Arena:** Sand reset (scratch) at entry. BufferedWriter, NameMangler, C89Emitter in scratch.

---

## 7. CLI Helper Functions

### `parseArgs` — `main.zig:734-863`

Iterates `pal.argCount()` from index 1, dispatches by `matchFlag`:

```
parseArgs() → CompilerCli
  for i in 1..argc:
    arg = cstrToSlice(pal.argGet(i))
    if arg[0] == '-':
      match --dump-types/-y | --dump-lir/-l | --dump-c89
            --max-mem/-m (next arg → parseSize)
            --max-errors/-e (next arg → parseU32)
            --output-dir/-o (next arg → cstrToSlice)
            --quiet/-q | --test | --sanity-test
            --warnings-as-errors/-W | --color (next arg → parseColorMode)
            --error-format (next arg → parseErrorFormat)
            --track-memory | --no-null-check | --no-lifetime-check
            --no-leak-check | --warn-all | --warn-error | --markers
            -I (next arg → include_dirs[include_count++], max 16)
      else → input_file = cstrToSlice(arg_ptr)
    else → input_file = cstrToSlice(arg_ptr)
```

Unrecognized flags are treated as positional input_file (no error).

### `matchFlag` — `main.zig:865-873`

Exact-length byte-by-byte comparison:
```zig
fn matchFlag(arg: []const u8, flag: []const u8) bool
```

Returns `true` if `arg.len == flag.len` and all bytes match.

**main_dump.zig variant** (`main_dump.zig:226-233`): Same logic, slightly different loop structure.

### `cstrToSlice` — `main.zig:875-881`

Convert null-terminated C string pointer to Zig slice:
```zig
fn cstrToSlice(ptr: [*]const u8) []const u8
```

Walks forward from `ptr` counting non-null bytes, returns `ptr[0..len]`.

**main_dump.zig variant** (`main_dump.zig:291-295`): Identical.

### `parseSize` — `main.zig:883-901`

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

**main_dump.zig variant** (`main_dump.zig:240-255`): Takes `[]const u8` directly (not `[*]const u8`), no `'g'`/`'G'` suffix support.

### `parseU32` — `main.zig:903-915`

Parse decimal integer string to `u32`:
```zig
fn parseU32(ptr: [*]const u8) u32
```

Skips non-digit characters. No overflow detection.

**main_dump.zig variant** (`main_dump.zig:257-268`): Takes `[]const u8` directly.

### `parseColorMode` — `main.zig:917-924`

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

**main_dump.zig variant** (`main_dump.zig:270-279`): Checks first character: `'a'` → `.always`, `'n'` → `.never`, else `.auto`.

### `parseErrorFormat` — `main.zig:926-933`

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

**main_dump.zig variant** (`main_dump.zig:281-289`): Checks first character: `'j'` → `.json`, else `.human`.

### `writeU32` — `main.zig:935-952`

Write a `usize` value as decimal string via `pal.markerWrite`:
```zig
fn writeU32(val: usize) void
```

Custom itoa (not using format/itoa module) — builds digits right-to-left in a 16-byte stack buffer. Handles `val == 0` as special case (writes `"0"`). Used by `runCompiler` for `--track-memory` peak output.

### `printUsage` — `main.zig:954-957`

Prints usage banner:
```
zig1 - Z98 self-hosted compiler - usage: zig1 [options] <input.zig>
```

**main_dump.zig variant** (`main_dump.zig:110-113`): More detailed, lists `--test`/`-t`, `--dump-tokens`, `--dump-ast` flags.

---

## 8. Data Flow

```
CLI args (argv)
    │
    ▼
parseArgs()
    │
    ▼
CompilerCli (22 fields)
    │
    ▼
main() constructs CompilerContext (20 fields)
    │
    ▼
runCompiler(ctx)
    │
    ├─ phase_ImportResolution    → ModuleRegistry populated
    ├─ phase_SymbolRegistration  → SymbolRegistry populated
    ├─ phase_TypeResolution       → TypeRegistry, ResolvedTypeTable
    ├─ phase_ComptimeEvaluation   → comptime_values hash map
    ├─ phase_SemanticAnalysis     → CoercionTable, resolved_types, enum_value_table
    ├─ phase_StaticAnalyzers      → AnalyzerContext (scratch, discarded)
    ├─ phase_LIRLowering           → LirFunctionArrayList (lir_fns)
    └─ phase_C89Emission         → C89 output via BufferedWriter
                                        │
                    ┌───────────────────┴────────────────────┐
                    ▼                                        ▼
   stdout single-file (bare --dump-c89)      DIR/*.c + DIR/*.h + DIR/zig_special_types.h
                output.c                     (multi-module, --output-dir DIR)
```

### Field Producers → Consumers

| Field | Produced By | Consumed By |
|-------|-------------|-------------|
| `cli.input_file` | `parseArgs` | `phase_ImportResolution` (path → module) |
| `cli.output_dir` | `parseArgs` | `phase_C89Emission` (live — multi-module file emission, `[updated: 2026-08-01]`) |
| `cli.dump_*` flags | `parseArgs` | `phase_LIRLowering`, `phase_C89Emission` |
| `cli.*_check` flags | `parseArgs` | `phase_StaticAnalyzers` |
| `cli.track_memory` | `parseArgs` | `runCompiler` (final print) |
| `store` (AstStore) | `phase_ImportResolution` (parser) | All phases 2-8 |
| `symbol_reg` | `phase_SymbolRegistration` | Phases 3, 5, 6, 7 |
| `typereg` | Init (primitives) + phase 3 | Phases 2-8 |
| `resolved_types` | Phases 3, 5 | Phases 5, 7 |
| `coercion_table` | Init | Phase 5, 7 |
| `lir_fns` | `phase_LIRLowering` | `phase_C89Emission` |
| `comptime_values` | `phase_ComptimeEvaluation` | Phase 7 |
| `pointer_only_ids` | `phase_TypeResolution` | `phase_C89Emission` |

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
fn phase_TypeResolution(ctx: *CompilerContext) void {
    if (ctx.cli.dump_types) return;  // example: skip if not dumping
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

### Marker Coverage Assessment (Q6) `[markers]` + `[fprintf]` — [updated: 2026-08-01]

Per-phase marker inventory (`main.zig` line refs):

| Phase | Markers | Density |
|-------|---------|---------|
| 1 import | `I`, `Z` (`258`, `264`) | thin — entry/exit only, no per-module detail |
| 2 symreg | `S`, `S0` + per-decl AstKind values (`268`, `282-283`) | dense — one line per root decl |
| 3 typeres | `T`, `T0` + per-decl AstKind values (`298`, `319-320`) | dense |
| 4 comptime | `CE` (`335`) | thin — single marker, no per-node detail |
| 5 sema | `RS MZ AD DSE DN SA sA V2: V49:p/t/k REG:tl/tt P0-P3 R0n R1t R2s AI FI` (`351-419`) | densest |
| 6 analyzers | `A` (`479`) | thin — single marker, no per-function detail |
| 7 lir | `L nodes= extra= M R F A0` (`514-592`) | dense |
| 8 c89 | `C`, `FINAL_FLUSH` (`611`, `695/718/730`) | thin — entry/exit only |

Gaps: phases 1, 4, 6, 8 have entry/exit markers only; internal behavior of comptime eval,
static analyzers, and C89 emission is invisible to `--markers` alone.

**The 5 pre-plan tech-doc gaps — resolution method classification** (which need markers vs
GDB/fprintf):

| Gap | Resolved by | Marker-resolvable? |
|-----|-------------|--------------------|
| 1 comptime scope incomplete | P4 (`[markers]`+`[fprintf]`+`[inference]`) | Partially — the sema/lower boundary needed fprintf/source |
| 2 cross-phase DepGraph persistence | **P10 this task** (`[fprintf]`) | **No** — no marker exposes arena state or edge counts |
| 3 symbol resolution priority order | P5 (`[fprintf]` primary, `[markers]` confirm paths) | Partially — markers show which path fired, not the order |
| 4 coercion table 5→7 handoff | P7 (`[markers]` CEM/CEP per lowerExpr + `[fprintf]`) | **Yes** — CEP/CEM markers distinguish the paths |
| 5 StateMap fork/merge precision | P6 (`[markers]`+`[fprintf]`+`[gdb]`) | Partially — merge-to-99/branch-drop visible via markers; counters needed fprintf |
| (new) phase timing | P10 this task (`[fprintf]`) | **No** — markers carry no timestamps |

**Method summary:** 1 gap fully marker-resolvable (4), 3 partially (1, 3, 5), 2 need fprintf
(2, 6/timing). None required GDB on this task; P5/P6 used GDB for specific values.

---

## 10. `main_dump.zig` — Standalone Dump Binary

**File:** `main_dump.zig` (326 lines)

Entry for token/AST dumping without running the full pipeline.

### Differences from main.zig

| Aspect | main.zig | main_dump.zig |
|--------|----------|---------------|
| CompilerCli fields | 22 | 15 |
| CompilerContext fields | 20 | 6 |
| Phase implementations | Full | Empty stubs (`_ = ctx;`) |
| Dump targets | types, lir, c89 | tokens, ast |
| `--sanity-test` | Lexer test | Not supported |
| `parseSize` suffix | k, m, g | k, m only |
| `parseColorMode` | `matchFlag` | First-character check |
| `parseErrorFormat` | `matchFlag` | First-character check |
| Default max_mem | `DEV_MAX_MEM` | 16MB |

### Entry Flow

```
main(argc, argv)
  ├─ parseArgs()
  ├─ if cli.input_file.len == 0 → printUsage(), return
  ├─ if cli.dump_ast:
  │     ├─ initCompilerAlloc, interner, source_man, diag, keyword table
  │     ├─ pal.readFile → source buffer
  │     ├─ Two-pass lex: count tokens → allocate array → fill
  │     ├─ parserParseModuleRoot → AST
  │     └─ dump_ast.dumpAst(...)
  └─ else: error "no mode selected, use --dump-ast"
```

### Phase Stubs

All `phase_*` functions are empty stubs (`_ = ctx;`), present for compilation compatibility with shared test infrastructure that expects the function signatures.
