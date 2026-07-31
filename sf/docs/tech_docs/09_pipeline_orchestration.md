# Pipeline Orchestration — main.zig, main_dump.zig

> Source: `sf/src/main.zig` (856 lines), `sf/src/main_dump.zig` (326 lines)

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

**File:** `main.zig:86-107` (20 fields)

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
| 13 | `dep_graph` | `*symbol_registrator.DepGraph` | module | Symbol dependency graph |
| 14 | `lir_fns` | `LirFunctionArrayList` | module | Compiled LIR functions |
| 15 | `enum_value_table` | `hash_mod.U32ToU32Map` | module | Enum field → value mapping |
| 16 | `call_arg_types` | `hash_mod.U32ToU32Map` | module | Per-call argument types |
| 17 | `call_param_map` | `hash_mod.U32ToU32Map` | module | Per-call parameter mapping |
| 18 | `comptime_values` | `hash_mod.U32ToU64Map` | module | Comptime-evaluated values |
| 19 | `pointer_only_ids` | `[*]u32` | permanent | Types emitted as pointers only |
| 20 | `pointer_only_len` | `u32` | (value) | Length of pointer-only list |

**Initialization order** (`main.zig:135-180`):
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

**File:** `main.zig:109-182`

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
  ├─ [NORMAL COMPILATION]
  │   ├─ initCompilerAlloc() + set max_mem
  │   ├─ Initialize all 8 subsystems (interner → comptime_values)
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

### Output Directory Isolation

The output directory is **not created or checked in main()**. It is stored in `cli.output_dir` (default `"."`) and used only by `phase_C89Emission` when `--dump-c89` is set. The C89 emitter writes to stdout via `BufferedWriter` — output directory is metadata for future file output.

---

## 5. `runCompiler` — Phase Orchestration

**File:** `main.zig:184-247`

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
  │     [ERROR CHECK] → pal.exit(2) if errors
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     marker: t2
  │
  ├── 4. phase_ComptimeEvaluation(ctx)
  │     marker: CE
  │
  ├── 5. phase_SemanticAnalysis(ctx)
  │     marker: RS, MZ, AD, DSE, DN, SA, sA, P0-P3, V2:, REG:tl, REG:tt
  │     [ERROR CHECK] → pal.exit(2) if errors
  │
  ├── 6. phase_StaticAnalyzers(ctx)
  │     marker: A
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [ERROR CHECK] → pal.exit(2) if errors
  │
  ├── 7. phase_LIRLowering(ctx)
  │     marker: L, M, R, F, A0
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [ERROR CHECK] → pal.exit(2) if errors
  │
  ├── 8. phase_C89Emission(ctx)
  │     marker: C, FINAL_FLUSH
  │     alloc_mod.checkCombinedPeak(ctx.alloc)
  │     [WARNING CHECK] → pal.exit(1) if warnings_as_errors or warn_error
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

### Diagnostic Exits

| Location | Condition | Exit Code |
|----------|-----------|-----------|
| After phase 3 | `diagnosticCollectorHasErrors` | 2 |
| After phase 5 | `diagnosticCollectorHasErrors` | 2 |
| After phase 6 | `diagnosticCollectorHasErrors` | 2 |
| After phase 7 | `diagnosticCollectorHasErrors` | 2 |
| After phase 8 | `warnings_as_errors or warn_error` + warning count > 0 | 1 |

---

## 6. Phase Function Details

### `phase_ImportResolution` — `main.zig:249-257`

**Calls:**
- `interner_mod.stringInternerIntern` — intern input file path
- `mr_mod.moduleRegistryAddModule` — register root module
- `mr_mod.importQueueEnqueue` — enqueue root for import resolution
- `import_resolver.moduleRegistryResolveImports` — drain import queue, parse all modules

**Markers:** `I` (start), `Z` (done)

**Arena:** Sand reset (scratch) at entry. Import queue and parsing temporaries use scratch.

### `phase_SymbolRegistration` — `main.zig:259-287`

**Calls:**
- `symbol_registrator.depGraphInit` — create dep graph in scratch
- `symbol_registrator.registerModuleSymbols` — register all symbols per module
- Root module AST walk: enumerate children, write AstKind enum values as markers

**Markers:** `S` (start), `S0` + per-decl kind values

**Arena:** Sand reset (scratch) at entry. DepGraph allocated in scratch.

### `phase_TypeResolution` — `main.zig:289-324`

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

### `phase_ComptimeEvaluation` — `main.zig:326-339`

**Calls:**
- `ce_mod.comptimeEvalInit` — init comptime evaluator
- `ce_mod.comptimeEvalEvaluate` — evaluate each `builtin_call` node
- `hash_mod.u32ToU64MapPut` — store evaluated values

**Markers:** `CE`

**Arena:** No sand reset — operates on existing data. Store results in `ctx.comptime_values` (module arena).

### `phase_SemanticAnalysis` — `main.zig:343-411`

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

### `resolveStmtTypes` — `main.zig:413-462`

Recursive helper called from `phase_SemanticAnalysis`. Walks statement nodes to pre-resolve type expressions before full semantic analysis.

**Logic:**
1. Depth limit of 16 (prevents infinite recursion on cyclic AST)
2. For `var_decl`: resolve type expression via `resolveTypeExpr`, store in `resolved_type_table`
3. For `array_init`/`struct_init`/`tuple_literal`: resolve child_0 type expression
4. For `block`: recurse into children
5. For any node: recurse into child_0 and child_1

**Markers:** `P0-P3` (pointer alignment bits in var_decl child_0), `R0n` (node index), `R1t` (type id), `R2s` (set), `AI` (array init), `FI` (failed init)

### `resolveTypeExpr` — `main.zig:464-467`

Thin wrapper around `type_resolver.resolveTypeExprFull`:
```zig
fn resolveTypeExpr(ctx: *CompilerContext, node_idx: u32) type_mod.TypeId {
    var env = type_resolver.TypeResolveEnv{ .store = ctx.store, .typereg = ctx.typereg, .symbol_reg = ctx.symbol_reg, .interner = ctx.interner };
    return type_resolver.resolveTypeExprFull(&env, node_idx, 0);
}
```

Built on the fly — no allocation. Returns `TYPE_UNDEFINED` if resolution fails.

### `phase_StaticAnalyzers` — `main.zig:470-503`

**Calls:**
- `az_mod.AnalyzerContext` construction with skip flags from CLI
- `az_mod.runAllAnalyzers` — run null/lifetime/leak analyzers per module

**Flags honored:** `no_null_check`, `no_lifetime_check`, `no_leak_check`, `warn_all`

**Markers:** `A`

**Arena:** Sand reset + reset peak (scratch) at entry. StateMap, defer queues in scratch.

### `phase_LIRLowering` — `main.zig:505-600`

**Calls:**
- `lower_mod.lowererInit` — init LIR lowerer per function
- `lower_mod.lowerFn` — lower function to LIR
- `lir_mod.lirFunctionArrayListAppend` — store compiled LIR function
- `mr_mod.moduleRegistryCollectIncludes` — collect C includes per module

**Markers:** `L` (start), `nodes=`, `extra=` (AST node counts), `M` (module index), `R` (root module), `F` (fn_decl), `A0` (decl kinds)

**Arena:** Sand reset (scratch) at entry. Per-function memory (BasicBlocks, insts) in scratch.

### `phase_C89Emission` — `main.zig:602-629`

**Calls:**
- `c89_mod.nameManglerInit` — init name mangler
- `c89_mod.c89EmitterInit` — init C89 emitter
- `c89_mod.bufferedWriterInit` — init buffered writer
- `c89_mod.emitIncludes` — emit C #include directives
- `cinclude.cincludeUnionAll` — collect all C includes
- `c89_mod.emitModule` — emit module to C89
- `c89_mod.bufferedWriterFlush` — final flush

**Early exit:** If `!ctx.cli.dump_c89` — return immediately (no emission).

**Markers:** `C` (start), `FINAL_FLUSH` (done)

**Arena:** Sand reset (scratch) at entry. BufferedWriter, NameMangler, C89Emitter in scratch.

---

## 7. CLI Helper Functions

### `parseArgs` — `main.zig:631-762`

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

### `matchFlag` — `main.zig:764-772`

Exact-length byte-by-byte comparison:
```zig
fn matchFlag(arg: []const u8, flag: []const u8) bool
```

Returns `true` if `arg.len == flag.len` and all bytes match.

**main_dump.zig variant** (`main_dump.zig:226-233`): Same logic, slightly different loop structure.

### `cstrToSlice` — `main.zig:774-780`

Convert null-terminated C string pointer to Zig slice:
```zig
fn cstrToSlice(ptr: [*]const u8) []const u8
```

Walks forward from `ptr` counting non-null bytes, returns `ptr[0..len]`.

**main_dump.zig variant** (`main_dump.zig:291-295`): Identical.

### `parseSize` — `main.zig:782-800`

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

### `parseU32` — `main.zig:802-814`

Parse decimal integer string to `u32`:
```zig
fn parseU32(ptr: [*]const u8) u32
```

Skips non-digit characters. No overflow detection.

**main_dump.zig variant** (`main_dump.zig:257-268`): Takes `[]const u8` directly.

### `parseColorMode` — `main.zig:816-823`

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

### `parseErrorFormat` — `main.zig:825-832`

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

### `writeU32` — `main.zig:834-851`

Write a `usize` value as decimal string via `pal.markerWrite`:
```zig
fn writeU32(val: usize) void
```

Custom itoa (not using format/itoa module) — builds digits right-to-left in a 16-byte stack buffer. Handles `val == 0` as special case (writes `"0"`). Used by `runCompiler` for `--track-memory` peak output.

### `printUsage` — `main.zig:853-856`

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
                                        ▼
                                   output.c
```

### Field Producers → Consumers

| Field | Produced By | Consumed By |
|-------|-------------|-------------|
| `cli.input_file` | `parseArgs` | `phase_ImportResolution` (path → module) |
| `cli.output_dir` | `parseArgs` | `phase_C89Emission` (future use) |
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
