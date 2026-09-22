# 01 — Import Resolution [updated: 2026-09-20 — refreshed resolver/registry API, pool-backed src_arena read path, hash-spill dedup, and module pruning cross-reference]

> Covers: `import_resolver.zig`, `module_registry.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ModuleState` variants | 5 | `pending(0)`, `parsing(1)`, `parsed(2)`, `resolved(3)`, `failed(4)` |
| Path normalization | `util/path.zig` | `normalizePath(buf, src)` collapses `.`/`..`/`//`; wired into `joinPath` (the sole path constructor), root path (`main.zig`), and search dirs |
| `ModuleEntry` fields | 10 | id, path_id, source_file_id, state, ast_root, import_count, imports_start, symbol_table, type_offset, c_includes |
| `ImportQueue` | LIFO stack | Enqueue dedup (linear scan), dequeue pop-back |
| Search dir resolution | 3-tier | Importer dir → search dirs → `.` current dir; each tier probes `target` then `target.zig` |
| Module dedup | 3-layer | `path_to_id` (canonical path) → `content_to_id` (FNV-1a source hash) → `moduleRegistryGetOrCreateModule` |
| Topological sort | Kahn's algorithm | Stack-based worklist, fixed-size `[256]u32` arrays, O(V+E). **Not wired into the main pipeline** — `moduleRegistrySortModules` is called only from tests (`sf/src/tests/test_mod_reg_bin.zig`, `test_sym_reg_bin.zig`), never from `main.zig` |
| Module pruning | emission-time | Needed-only std modules are pruned at emission from the LIR value-reference graph (see 08/09); import resolution parses every `@import`-reachable module |
| Debug markers | ~20 | `I`, `Z`, `IRP:*`, `IRD:*`, `IRV:*`, `IRN:n`, `IRE:x`, `ECB0-2:*`, `ECD0-2:*`, `ECBED` |

---

## import_resolver.zig (`sf/src/import_resolver.zig`, 151 lines)

Orchestrates the on-demand parsing loop: dequeue module ID → read the module source
into the resolver's own pool-backed `src_arena` → lex → parse → extract imports →
enqueue dependencies. Also emits the import-resolution markers and the verify/summary
pass.

### Functions

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `moduleRegistryParseModule` | private | `[inference: lex full token stream, parse module root, ECB/ECD debugging]` | Full lex→parse pipeline for one module. Adds `content` to the `SourceManager` as a transient file (`sourceManagerAddFileTransient`) and stores the returned file ID in `ModuleEntry.source_file_id`. Lexes with `lexerInit`, builds a streaming parser via `parserInitStreaming` (not the old token-array `parserInit`), sets the module context (`parserSetModuleContext`) and import scratch (`parserSetImportScratch`), then parses `module_root`. **Debug:** snapshots raw `extra_children[0..5]` before/after parse (`ECB0-2:`/`ECD0-2:` markers) and writes `ECBED` if indices 0-2 changed. Returns `ast_root` or null on parse failure. |
| `moduleRegistryResolveImports` | pub | `[inference: on-demand loop: queue→parse→enqueue imports, then verify pass]` | **Core import resolution loop.** Owns three pool-backed `GrowableSand` arenas — `parser_arena` (4 KB), `import_scratch` (256 B), `src_arena` (4 KB) — reset per module. See [On-Demand Parsing Loop](#on-demand-parsing-loop) for the walkthrough. |

---

## module_registry.zig (`sf/src/module_registry.zig`, 742 lines)

Module graph data structures + path/content dedup + hash-map disk spill + topological sort.
Contains `ModuleState`, `ModuleEntry`, `ModuleEntryArrayList`, `SearchDirArrayList`,
`ModuleResolver`, `HashMapSpillMeta`, `ModuleRegistry`, `ImportQueue`, and Kahn's algorithm.

### Types

| Type | Description |
|------|-------------|
| `ModuleState` (enum u8) | `pending` (not yet processed), `parsing` (currently being lexed/parsed), `parsed` (AST available, imports extracted), `resolved` (topologically sorted, ready for later phases), `failed` (parse error or circular dependency) |
| `ModuleEntry` (struct) | Module descriptor: `id(u32)`, `path_id(u32, interned)`, `source_file_id(u32)`, `state(ModuleState)`, `ast_root(u32)`, `import_count(u32)`, `imports_start(u32)`, `symbol_table(u32)`, `type_offset(u32)`, `c_includes(U32ArrayList)` |
| `ModuleEntryArrayList` (struct) | Dynamic array of `ModuleEntry`: `items([*]ModuleEntry)`, `len(usize)`, `capacity(usize)`, `allocator(*Sand)` |
| `SearchDirArrayList` (struct) | Dynamic array of interned search-directory path IDs: `items([*]u32)`, `len`, `capacity`, `alloc(*Sand)` |
| `ModuleResolver` (struct) | Import path resolution: `search_dirs(SearchDirArrayList)`, `interner(*StringInterner)`, `diag(*DiagnosticCollector)` |
| `HashMapSpillMeta` (struct) | Per-map disk-spill bookkeeping: `disk_off(u32)`, `capacity(usize)`, `count(usize)`, `spilled(u8)` |
| `ModuleRegistry` (struct) | Central module graph: `modules(ModuleEntryArrayList)`, `import_edges_items([*]u32)`, `import_edges_len/cap`, `import_edges_alloc(*Sand)`, `resolver(ModuleResolver)`, `interner(*StringInterner)`, `diag(*DiagnosticCollector)`, `source_man(*SourceManager)`, `alloc(*Sand)`, `next_id(u32)`, `path_to_id(U32ToU32Map)`, `content_to_id(U32ToU32Map)`, `hash_spill_path([512]u8)`, `hash_spill_path_len`, `spill(SpillStore)`, `path_to_id_spill(HashMapSpillMeta)`, `content_to_id_spill(HashMapSpillMeta)`, `import_queue(ImportQueue)` |
| `ImportQueue` (struct) | LIFO import worklist: `pending_items([*]u32)`, `pending_len/cap`, `pending_alloc(*Sand)`, `diag(*DiagnosticCollector)` |

### Functions

#### ModuleEntryArrayList

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `moduleEntryArrayListInit` | pub | `[inference: ensure capacity for initial_capacity]` | Allocates initial `ModuleEntry` array. |
| `moduleEntryArrayListEnsureCapacity` | pub | `[inference: 2x growth, sand alloc, min 8]` | Grows `ModuleEntry` array. `new_cap = max(requested, cap*2, 8)`; tries in-place realloc first. |
| `moduleEntryArrayListAppend` | pub | `[inference: ensure capacity + store]` | Appends `ModuleEntry`. |
| `moduleEntryArrayListGetSlice` | pub | `[inference: slice from items[0..len]]` | Returns `[]ModuleEntry` view. |

#### SearchDirArrayList (private helpers)

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `searchDirArrayListEnsureCapacity` | private | `[inference: 2x growth, sand alloc, min 2]` | Grows search dir array. |
| `searchDirArrayListAppend` | private | `[inference: ensure capacity + store]` | Appends search dir path ID. |

#### ModuleResolver

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `joinPath` | private | `[inference: dir + '/' + rel, sand alloc, normalize . and ..]` | Concatenates directory path and relative path with `/` separator, then normalizes `.`/`..`/`//` in place via `util/path.zig` `normalizePath` so the interned path is canonical. Output length <= input length, so the single scratch allocation is sufficient. |
| `moduleDirPath` | private | `[inference: scan back for '/', returns prefix or ""]` | Extracts directory portion from path. Returns `""` if no `/`. |
| `appendZigExt` | private | `[inference: target + ".zig", sand alloc]` | Appends `.zig` to a bare target in scratch. Used for the two-step probe. |
| `moduleResolverTryDir` | private | `[inference: fileExists(target) then fileExists(target+".zig"), intern hit]` | Tries `dir/target` first, then `dir/target.zig`, returning the interned resolved path ID for the first that exists, else null. |
| `moduleResolverInit` | pub | `[inference: zero-init SearchDirArrayList]` | Creates `ModuleResolver` with empty search dirs. |
| `moduleResolverAddSearchDir` | pub | `[inference: normalize + intern path, append to search_dirs]` | Adds a search directory (canonicalized via `normalizePath`, then interned). |
| `moduleResolverResolve` | pub | `[inference: 3-tier: importer_dir → search_dirs → '.' ]` | **Import path resolution.** Tries: (1) relative to importer's directory, (2) each registered search dir in order, (3) current dir `.`. Returns interned resolved path ID or null. |

#### Internal helpers

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `importEdgesEnsureCapacity` | private | `[inference: 2x growth, sand alloc, min 8]` | Grows import edges array. |
| `importEdgesAppend` | private | `[inference: ensure capacity + store]` | Appends import edge (u32 module ID) to flat array. |
| `importQueuePendingEnsureCapacity` | private | `[inference: 2x growth, sand alloc, min 8]` | Grows import queue pending array. |
| `importQueuePendingAppend` | private | `[inference: ensure capacity + store]` | Appends to pending queue array. |
| `importQueuePendingPop` | private | `[inference: len check, decrement, return items[len]]` | Pops from back of pending queue (LIFO). |

#### ModuleRegistry — Lifecycle

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `moduleRegistryInit` | pub | `[inference: alloc ModuleEntryArrayList(8), MapInitCap(32) path/content maps, spillStoreInit, ImportQueue]` | Creates `ModuleRegistry`. Uses `source_man_stub` (1 byte) as placeholder `SourceManager` — replaced by `moduleRegistrySetSourceMan`. |
| `moduleRegistrySetSourceMan` | pub | `[inference: pointer assignment]` | Sets real `SourceManager` after init. |
| `moduleRegistryAddModule` | pub | `[inference: create ModuleEntry(pending), append, increment next_id]` | Creates new `ModuleEntry` with `state=pending`. Returns new module ID. |
| `moduleRegistryGetModules` | pub | `[inference: slice from items[0..len]]` | Returns `[]ModuleEntry` of all registered modules. |
| `moduleRegistryGetOrCreateModule` | pub | `[inference: hash lookup → add if missing, cache path_id→mod_id]` | Looks up existing module by path ID; creates new if not found. Stores the mapping in `path_to_id`. |
| `moduleRegistryAddImport` | pub | `[inference: append to import_edges, set imports_start on first import, increment count]` | Records import dependency: `importer_id` imports `imported_id`. `imports_start` is set once on the first import (no update on subsequent calls). |

#### Import Resolution Entry Point

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `moduleRegistryResolveImport` | pub | `[inference: resolve path, path-dedup, content-hash dedup, get-or-create module, record import, enqueue]` | Resolves an `@import("path")` reference. Three-layer dedup: (1) canonical path lookup in `path_to_id` (path normalization makes syntactic aliases equal); (2) resolve-time content-hash double-guard — reads the module source, `fnv1a`-hashes it, and reuses the already-registered module id if the hash is in `content_to_id` (no duplicate entry is ever created); (3) `moduleRegistryGetOrCreateModule` only on a full miss. Returns resolved module ID, or null after emitting `ERR_3048` when no tier resolves. |

#### Hash-Map Disk Spill

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `moduleRegistryAssertPathToIdResident` | private | `[inference: panic if path_to_id spilled]` | Guards direct `path_to_id` access after a disk spill. |
| `moduleRegistrySpillHashMaps` | pub | `[inference: disk spill of path/content maps, or keep resident in Ram mode]` | Spills `path_to_id`/`content_to_id` to a disk `SpillStore` and drops the resident arrays; no-op in Ram mode. |
| `moduleRegistryFaultInPathToId` | private | `[inference: read spill header + arrays, validate cap/count, rebuild map]` | Faults the spilled `path_to_id` map back into memory. |
| `moduleRegistryPathToIdGet` | pub | `[inference: fault-in then map get]` | Public accessor for `path_to_id` that faults the map in first. |
| `hashSpillWriteU32` / `hashSpillReadU32` / `hashSpillWriteMap` | private | `[inference: little-endian u32 spill I/O]` | Spill serialization helpers for the hash maps. |

#### Import Queue

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `importQueueInit` | pub | `[inference: zero-init pending array]` | Creates empty `ImportQueue`. |
| `importQueueEnqueue` | pub | `[inference: linear dedup scan, append if unique]` | Enqueues module ID. **Dedup:** linear scan of `pending_items` — skips if already enqueued. |
| `importQueueDequeue` | pub | `[inference: delegate to importQueuePendingPop]` | Dequeues module ID (LIFO pop-back). Returns null if empty. |

#### Topological Sort

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `moduleRegistrySortModules` | pub | `[inference: Kahn's algorithm, fixed-size [256] arrays, circular dep detection]` | **Kahn's algorithm** on the module graph. See [Kahn's Algorithm](#kahns-algorithm) below. **Not wired into the compile pipeline** — called only from tests. |
| `moduleRegistryVerifyOrder` | pub | `[inference: scan all resolved modules, check all imports resolved/failed]` | Post-sort verification: every import of every resolved module must be `resolved` or `failed`. Emits `ERR_4000` on violation. |

#### Post-processing

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `moduleRegistryCollectIncludes` | pub | `[inference: scan decls for c_include nodes, append to c_includes]` | Collects C include directives from a module AST. Checks both top-level `c_include` decls and `var_decl` init values that are `c_include`. |

---

## ModuleState Transitions

```
                ┌──────────┐
                │  pending │ ←── moduleRegistryAddModule
                └────┬─────┘
                     │ importQueueDequeue
                     ▼
                ┌──────────┐
         ┌──────│ parsing  │ ←── moduleRegistryParseModule starts
         │      └────┬─────┘
         │           │ parse succeeds
         │           ▼
         │      ┌──────────┐
         │      │  parsed  │ ←── ast_root stored, imports extracted
         │      └────┬─────┘
         │           │ moduleRegistrySortModules
         │           ▼
         │      ┌───────────┐
         │      │ resolved  │ ←── topological sort complete
         │      └───────────┘
         │
         │      ┌──────────┐
         └──────│  failed  │ ←── readFile fail (now ERR_3048 diagnostic, F-S10) OR parse error OR circular dep
                └──────────┘
```

**Key:** `failed` is a sink state. `resolved` is only reached via Kahn's algorithm, not during the parsing loop. **In the compile pipeline `resolved` is never reached** — `moduleRegistrySortModules` is not called from `main.zig`, so every parsed module stays `parsed` and later phases never consult `state`. Modules in `failed` state are excluded from topological sort (in_degree set to 0 but `state == failed` check skips them).

[updated: 2026-08-01] **How phases actually skip failed modules — `ast_root == 0`, NOT `ModuleState.failed`:** no later phase checks `ModuleState.failed` at all. The per-phase skip is by `ast_root == 0` — a module that failed to read (F-S10) or failed to parse never gets `ast_root` set (it stays 0), and each phase tests `mods[i].ast_root != 0` before walking the AST. This is undocumented elsewhere: `ModuleState.failed` is set by the import resolver for bookkeeping but is invisible to the later phases.

---

## On-Demand Parsing Loop

The core loop is `moduleRegistryResolveImports` (`import_resolver.zig`):

```
while queue not empty:
    mod_id = dequeue()
    if mod_id.state != pending → skip (already processed)

    reset scratch, parser_arena.view, src_arena.view

    entry.state = parsing

    content = readFile(path, src_arena.view)   ← file I/O
    if content missing → emit ERR_3048 diagnostic, state = failed, continue   ← F-S10
      (was silent pre-F-S10; now `error[3048]: could not read imported file '<path>'`)

    ast_root = moduleRegistryParseModule(
        reg, mod_id, content,          ← lex → parse (streaming)
        module_arena, scratch, shared_store,
        parser_arena.view, import_scratch.view
    )
    if parse failed → state = failed, continue

    entry.ast_root = ast_root
    entry.state = parsed

    emit IRP/IRD markers

    for each import in entry:
        if imported_module.state == pending:
            queue.enqueue(imported_module_id)
```

**F-S10 missing-dependency choke point:** a dep that never resolves in the 3-tier
search fails *before* `readFile` — `moduleResolverResolve` gates on `fileExists` and
returns null, so `moduleRegistryResolveImport` returns null and emits
`error[3048]: could not resolve imported file '<path>'` at the resolve-null point.
Pre-F-S10 this was silent: the parser discarded the null result, no module was
registered, and no `readFile` was attempted. The parse-loop `readFile` site only fires
for a resolved path that then fails to read (empty/removed file); the
`moduleRegistryResolveImport` site covers genuinely missing deps.

Then a verification pass iterates all parsed modules, dumping `IRV:m`/`IRV:c`/`IRV:n`
markers, and finally writes `IRN:n` (total node count) and `IRE:x` (extra children
count).

---

## Kahn's Algorithm (`moduleRegistrySortModules`)

`moduleRegistrySortModules` in `module_registry.zig`.

```
Input: ModuleRegistry with parsed modules and import edges

1. Compute in_degree:
   for each module i:
       if state != failed → in_degree[i] = module.import_count

2. Initialize worklist (stack):
   for each module i:
       if in_degree[i] == 0 and state != failed → push i

3. Sort worklist ascending ID (bubble sort, O(n²) but n ≤ 256):

4. Process worklist:
   while worklist not empty:
       id = pop()
       if state == failed → continue
       state = resolved
       sorted_count += 1
       for each module ii:
           if state != failed:
               scan ii's import edges
               if edge == id:
                   in_degree[ii] -= 1
                   if in_degree[ii] == 0 → push ii

5. Circular dependency detection:
   if sorted_count < module_count:
       for each module with in_degree > 0 and state != failed:
           emit ERR_3005_CIRCULAR_TYPE_DEPENDENCY diagnostic
           state = failed

6. moduleRegistryVerifyOrder — validation pass
```

**Limitations:**
- Fixed-size `[256]u32` arrays for `in_degree` and `worklist` — hard cap of 256 modules.
- Bubble sort on worklist (ascending ID) — O(n²) but max 256 elements.
- Import edge scanning is O(V×E) — for each processed node, scans all modules' edges.

---

## Data Flow

```
Input file path (CLI arg)
    │
    ▼
phase_ImportResolution (main.zig)
    │  marker: "I\n"
    │  seed search dirs from -I/--lib-dir, then default install path
    │  normalize root path
    │
    ├─ moduleRegistryAddModule → ModuleEntry { state: pending }
    ├─ importQueueEnqueue(root_module)
    │
    ▼
moduleRegistryResolveImports (import_resolver.zig)
    │  owns pool-backed GrowableSand arenas: parser_arena (4 KB),
    │  import_scratch (256 B), src_arena (4 KB)
    │
    ├─ LOOP (per dequeued pending module):
    │   ├─ importQueueDequeue → module ID
    │   ├─ reset scratch + parser_arena.view + src_arena.view
    │   ├─ readFile → src_arena.view (source text)
    │   ├─ moduleRegistryParseModule:
    │   │   ├─ sourceManagerAddFileTransient → file_id → ModuleEntry.source_file_id
    │   │   ├─ lexerInit (streaming)
    │   │   ├─ parserInitStreaming → parserParseModuleRoot → shared AstStore
    │   │   └─ returns ast_root
    │   ├─ store ast_root + state = parsed
    │   ├─ emit IRP/IRD markers
    │   └─ for each edge in import_edges[entry.imports_start..+import_count]:
    │       if imported module is pending → enqueue
    │
    ├─ Verification pass: IRV markers for all modules
    └─ IRN:n / IRE:x summary markers
    │
    ▼
marker: "Z\n" (queue drained, all modules parsed; hash maps spilled just before Z)
    │
    ▼
moduleRegistrySortModules (Kahn's algorithm)   ← NOT CALLED in the compile pipeline
    │     moduleRegistrySortModules is invoked only from unit tests
    │     (sf/src/tests/test_mod_reg_bin.zig, test_sym_reg_bin.zig). Documented here as a
    │     standalone capability, not part of the phase flow.
    ├─ in_degree computation
    ├─ worklist processing → state = resolved
    ├─ circular dependency detection
    └─ moduleRegistryVerifyOrder
    │
    ▼
Sorted module IDs (topological order, available via moduleRegistryGetModules)
```

### Import Resolution Path

```
@import("relative/path.zig")
    │
    ▼
moduleRegistryResolveImport
    │
    ├─ moduleResolverResolve (3-tier):
    │   1. importer_dir + target, then target + ".zig" → fileExists?
    │   2. each search_dir + target, then target + ".zig" → fileExists?
    │   3. "." + target, then target + ".zig" → fileExists?
    │   (joinPath normalizes each joined path before interning)
    │
    ├─ no tier matches → emit error[3048], return null
    │
    ├─ path_to_id[resolved_path_id] hit → reuse existing module id
    │
    ├─ (path miss) resolve-time content-hash double-guard:
    │    readFile(resolved_path) → fnv1a(content)
    │    content_to_id[hash] hit → reuse that module id (no entry created)
    │    (read failure → fall through to create; parse loop reports error[3048])
    │
    ├─ (content miss) moduleRegistryGetOrCreateModule
    │    → record content_to_id[hash] = mod_id
    │
    ├─ moduleRegistryAddImport (edge: importer_id → imported_id)
    └─ importQueueEnqueue(imported_id)
    │
    ▼
ModuleEntry created (pending) → eventually parsed by main loop
```

### Import Edges and Emission (cross-reference)

`moduleRegistryAddImport` records each direct import as a `u32` module ID in the flat
`import_edges_items` array and sets `imports_start` on the importer's first import;
`import_count` grows with each edge. Edges are recorded in `@import` declaration order.

Emission-time header dependencies and module pruning are owned by
`08_c89_emission.md` / `09_pipeline_orchestration.md`: the emitter unions surviving
import-edge targets with the module-level LIR value-reference graph, restricted to the
reachable (emitted) module set, and includes the corresponding qualified headers. Import
resolution itself neither prunes nor orders modules — see
[Search-Dir Resolution](#search-dir-resolution).

---

## Debugging

### CLI Flags

| Flag | Effect |
|------|--------|
| `--dump-ast` | Dumps the AST tree (dump tool, `main_dump.zig`; the AST is populated during import resolution) |

### Phase Entry/Exit Markers

| Marker | Function | Description |
|--------|----------|-------------|
| `I` | `phase_ImportResolution` (`main.zig`) | Phase entry — start of import resolution. **NOTE:** `c89_emit.zig` also emits `I\n` during C89 emission, so only the first `I` (plus the `Z` immediately after `IRE:x`) bounds the import-resolution phase |
| `Z` | `phase_ImportResolution` (`main.zig`) | Phase exit — queue drained, all modules parsed, hash maps spilled |
| `M` | lowering pass (`main.zig`) | Per-module dump — writes `M<id>:<ast_root>:R<decl_count>` |

### Import Resolution Parse Markers (`import_resolver.zig`)

| Marker | Emitted by | Description |
|--------|------------|-------------|
| `ECB0:<val>` | `moduleRegistryParseModule` | `extra_children` value at index 0 before parse |
| `ECB1:<val>` | `moduleRegistryParseModule` | `extra_children` value at index 1 before parse |
| `ECB2:<val>` | `moduleRegistryParseModule` | `extra_children` value at index 2 before parse |
| `ECD0:<val>` | `moduleRegistryParseModule` | `extra_children` value at index 0 after parse |
| `ECD1:<val>` | `moduleRegistryParseModule` | `extra_children` value at index 1 after parse |
| `ECD2:<val>` | `moduleRegistryParseModule` | `extra_children` value at index 2 after parse |
| `ECBED` | `moduleRegistryParseModule` | Written if any of `extra_children[0..2]` changed during the module's own parse. **Fires normally** — the first module parsed always grows the shared array from empty. It is not a corruption indicator. |
| `IRP:m<mod_id>` | `moduleRegistryResolveImports` | Module being parsed (module ID) |
| `IRP:n<node>` | `moduleRegistryResolveImports` | AST root node index |
| `IRP:p<payload>` | `moduleRegistryResolveImports` | Module root payload — low 32 bits of the packed extra-children range (`ast.zig` `astStoreNodePayloadPacked`, which for `module_root` returns the `(start << 32) | count` range value), unpacked by `astStoreNodeExtraChildCount`/`astStoreNodeExtraChildAt` |
| `IRD:c<count>` | `moduleRegistryResolveImports` | Child declaration count |
| `IRD:n<decl_id>` | `moduleRegistryResolveImports` | Per-declaration node index |

`moduleRegistryParseModule` also snapshots raw `extra_children` indices 3-5
(`astStoreExtraChildAtRaw`), but those values are unused: no `ECB3-5`/`ECD3-5` markers are
emitted and they are not part of the `ECBED` comparison.

### Import Resolution Verify Markers (`import_resolver.zig`)

| Marker | Emitted by | Description |
|--------|------------|-------------|
| `IRV:m<mod_id>` | `moduleRegistryResolveImports` | Module being verified |
| `IRV:c<count>` | `moduleRegistryResolveImports` | Child declaration count |
| `IRV:n<decl_id>` | `moduleRegistryResolveImports` | Per-declaration node index |

### Import Resolution Summary Markers (`import_resolver.zig`)

| Marker | Emitted by | Description |
|--------|------------|-------------|
| `IRN:n<count>` | `moduleRegistryResolveImports` | `shared_store.nodes.len` after all modules parsed |
| `IRE:x<count>` | `moduleRegistryResolveImports` | `shared_store.extra_children.len` after all modules parsed |

### Topological Sort / Circular Dep Markers

| Marker | Function | Description |
|--------|----------|-------------|
| `circular import detected in module '...'` | `moduleRegistrySortModules` (`module_registry.zig`) | Diagnostic message for circular dependency |

### Diagnostic Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| `ERR_3005` | `ERR_3005_CIRCULAR_TYPE_DEPENDENCY` | Circular import detected during topological sort |
| `ERR_3048` | `ERR_3048_CANNOT_READ_FILE` | **F-S10** — dependency file unreadable/unresolvable. Two call sites: a resolved path that then fails to read at `moduleRegistryResolveImports` (`import_resolver.zig`) → `error[3048]: could not read imported file '<path>'`; a missing dep (never resolves in the 3-tier search) at the resolve-null choke point in `moduleRegistryResolveImport` (`module_registry.zig`) → `error[3048]: could not resolve imported file '<path>'`. Both are level-0 diagnostics → `error_count` → non-zero exit. |
| `ERR_4000` | `ERR_4000_INVALID_CONTROL_FLOW` | Topological sort violation — import not resolved (`moduleRegistryVerifyOrder`) |

### Known Issues

1. **Fixed-size arrays** (`moduleRegistrySortModules`, `module_registry.zig`): `in_degree` and `worklist` are `[256]u32` — hard limit of 256 modules. Exceeding this causes silent out-of-bounds writes.
2. **Import dedup O(n)** (`importQueueEnqueue`, `module_registry.zig`): linear scan of pending items. LIFO stack means worst-case O(n²) across all enqueues.
3. **No post-parse cycle detection**: the parsing loop does not detect cycles — they surface only in `moduleRegistrySortModules` (ERR_3005), which the compile pipeline never calls. The loop itself cannot hang on a cycle: `moduleRegistryResolveImports` enqueues only modules still in `pending` state and skips non-pending modules, so the queue always drains. In the compile pipeline (sort not invoked) a cycle is silently tolerated with no diagnostic.
4. **`source_man_stub`** (`module_registry.zig`): one-byte stub used as placeholder `SourceManager` until `moduleRegistrySetSourceMan` is called. If `moduleRegistryResolveImports` runs before `setSourceMan`, the pointer dereference will crash.
5. **No path normalization** — **FIXED [updated: 2026-08-14 — F-PATHNORM]:** `util/path.zig` `normalizePath` collapses `.`/`..`/`//` in place; wired into `joinPath` (the sole path constructor, `module_registry.zig`), the root input path (`main.zig`), and search dirs. Normalization happens at the string source, before interning, so the interned path id (module dedup key), the stored `path_id`, the importer-dir derivation, `readFile`, and the source-manager filename all see canonical strings. Byte-identity is preserved for canonical imports (normalizePath is the identity on dot-free paths). The `.zig` two-step probe (bare-then-`appendZigExt`) is untouched.
6. **Resolve-time content-hash double-guard** (`content_to_id`, `module_registry.zig`): a backstop that catches what lexical path normalization cannot (symlink/realpath aliases, absolute-vs-relative root variants, future spellings). When the resolved path is not already in `path_to_id`, `moduleRegistryResolveImport` reads the module source, `fnv1a`-hashes it, and reuses the already-registered module id if the hash is in `content_to_id` (no duplicate entry is created). Hash collisions are not verified by content equality — a 32-bit FNV collision would merge two distinct files, an accepted documented risk.
7. **Hash-map disk spill** (`moduleRegistrySpillHashMaps`, `module_registry.zig`): after import resolution, `phase_ImportResolution` spills `path_to_id`/`content_to_id` to a disk `SpillStore` at `<output_dir>/.zig1_hash.tmp` (or `./.zig1_hash.tmp`) and drops the resident arrays. Direct `path_to_id` access after a spill panics via `moduleRegistryAssertPathToIdResident`; callers must go through `moduleRegistryPathToIdGet`, which faults the map back in. `content_to_id` is never faulted back in — it is dead after resolution. In Ram spill mode the maps stay resident and nothing is written.

## Search-Dir Resolution

`@import("...")` is parsed in `parserParseImportExpr` (`parser.zig`); the raw string
literal is interned as `path_id` and, while parsing, `moduleRegistryResolveImport` is
called. That call resolves through `moduleResolverResolve` (`module_registry.zig`),
which tries three tiers via `moduleResolverTryDir`:

1. the importer's own directory (`moduleDirPath` + `joinPath`);
2. each registered `search_dirs` entry, in insertion order;
3. `.` — the current working directory.

At each tier `moduleResolverTryDir` tries `target` first, then `target + ".zig"`
(`appendZigExt`) — so a bare `@import("std")` maps to `std.zig`, while an explicit
`@import("std.zig")` resolves unchanged on the first try (byte-neutral). Every joined
path passes through `joinPath`, which normalizes `.`/`..`/`//` in place via
`util/path.zig` `normalizePath` before interning.

Search dirs are seeded by `phase_ImportResolution` (`main.zig`):

1. `cli.include_dirs`, in CLI order — populated by `-I <dir>` / `--lib-dir <dir>`
   (repeatable, capped at 16), each added via `moduleResolverAddSearchDir`, which
   normalizes and interns the directory; then
2. the compiler-binary-relative default install path (`pal.getDefaultLibPath`,
   `<exe_dir>/lib`), appended only when `pal.dirExists` confirms it (the path
   names a **directory**; `pal.fileExists` is a `fopen("rb")` file probe and
   fails on a directory on win32 — Task 5B fix). [updated: 2026-09-22 — Task 5B]

User dirs therefore precede the default install path. The effective `@import("std")`
search order is: importer dir → `-I`/`--lib-dir` dirs (CLI order) → `<exe_dir>/lib`
(if present) → `.` (CWD).

`moduleRegistryResolveImports` (`import_resolver.zig`) then loops the queue, reads
each resolved path into the resolver's `src_arena`, and parses it.

**Module pruning (needed-only std) is not done here.** Import resolution registers and
parses every module reachable through `@import` edges; re-exports keep their target
modules in the graph. Unreferenced modules are pruned later, at emission, from the
module-level LIR value-reference graph (owned by `08_c89_emission.md` /
`09_pipeline_orchestration.md`) — so a stdio-only `@import("std")` program emits no
`std_net` and needs no `-lwsock32`. The graph described in this document is the
parse-time module graph, not the emitted set.

