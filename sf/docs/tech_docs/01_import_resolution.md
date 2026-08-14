# 01 — Import Resolution

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ModuleState` variants | 5 | `pending(0)`, `parsing(1)`, `parsed(2)`, `resolved(3)`, `failed(4)` |
| `ModuleEntry` fields | 10 | id, path_id, source_file_id, state, ast_root, import_count, imports_start, symbol_table, type_offset, c_includes |
| `ImportQueue` | LIFO stack | Enqueue dedup (linear scan), dequeue pop-back |
| Search dir resolution | 3-tier | Importer dir → search dirs → `.` current dir |
| Topological sort | Kahn's algorithm | Stack-based worklist, fixed-size `[256]u32` arrays, O(V+E). **Not wired into the main pipeline** — `moduleRegistrySortModules` is called only from tests (`sf/src/tests/test_mod_reg_bin.zig`, `test_sym_reg_bin.zig`), never from `main.zig` |
| Debug markers | ~20 | `I`, `Z`, `IRP:*`, `IRD:*`, `IRV:*`, `IRN:n`, `IRE:x`, `ECB0-2:*`, `ECD0-2:*`, `ECBED` |

---

## import_resolver.zig (`sf/src/import_resolver.zig`, 160 lines)

Orchestrates the on-demand parsing loop: dequeue module ID → lex → parse → extract imports → enqueue dependencies.

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `tokenArrayEnsureCapacity` | 15 | private | `[inference: 2x growth, sand alloc for Token, min 64]` | Grows token array. Bumps to `max(new_cap, cap*2, 64)`. Copies old items to new allocation. |
| `tokenArrayAppend` | 27 | private | `[inference: ensure capacity + store + increment]` | Appends Token to dynamic array. Delegates capacity check to `tokenArrayEnsureCapacity`. |
| `moduleRegistryParseModule` | 33 | private | `[inference: lex full token stream, parse module root, ECB/ECD debugging]` | Full lex→parse pipeline for one module. Lexes content to token array, creates parser, parses `module_root`. **Debug:** snapshots `extra_children[0..2]` before/after parse (`ECB0-2:`/`ECD0-2:`) and writes `ECBED` if indices 0-2 changed (fires on any module whose parse grows the shared extra-children array — normally the first module parsed). Returns `ast_root` or null on parse failure. |
| `moduleRegistryResolveImports` | 82 | pub | `[inference: on-demand loop: queue→parse→enqueue imports, then verify pass]` | **Core import resolution loop.** See [Data Flow](#data-flow) for detailed walkthrough. |

---

## module_registry.zig (`sf/src/module_registry.zig`, 452 lines)

Module graph data structures + topological sort. Contains `ModuleState`, `ModuleEntry`, `ModuleRegistry`, `ModuleResolver`, `ImportQueue`, and Kahn's algorithm.

### Types

| Type | Line | Description |
|------|------|-------------|
| `ModuleState` (enum u8) | 15 | `pending` (not yet processed), `parsing` (currently being lexed/parsed), `parsed` (AST available, imports extracted), `resolved` (topologically sorted, ready for later phases), `failed` (parse error or circular dependency) |
| `ModuleEntry` (struct) | 23 | Module descriptor: `id(u32)`, `path_id(u32, interned)`, `source_file_id(u32)`, `state(ModuleState)`, `ast_root(u32)`, `import_count(u32)`, `imports_start(u32)`, `symbol_table(u32)`, `type_offset(u32)`, `c_includes(U32ArrayList)` |
| `ModuleEntryArrayList` (struct) | 36 | Dynamic array of `ModuleEntry`: `items([*]ModuleEntry)`, `len(usize)`, `capacity(usize)`, `allocator(*Sand)` |
| `SearchDirArrayList` (struct) | 78 | Dynamic array of interned search directory path IDs |
| `ModuleResolver` (struct) | 103 | Import path resolution: `search_dirs(SearchDirArrayList)`, `interner(*StringInterner)`, `diag(*DiagnosticCollector)` |
| `ModuleRegistry` (struct) | 163 | Central module graph: `modules(ModuleEntryArrayList)`, `import_edges_items([*]u32)`, `import_edges_len/cap`, `resolver(ModuleResolver)`, `interner(*StringInterner)`, `diag(*DiagnosticCollector)`, `source_man(*SourceManager)`, `alloc(*Sand)`, `next_id(u32)`, `path_to_id(U32ToU32Map)`, `import_queue(ImportQueue)` |
| `ImportQueue` (struct) | 271 | LIFO import worklist: `pending_items([*]u32)`, `pending_len/cap`, `pending_alloc(*Sand)`, `diag(*DiagnosticCollector)` |

### Functions

#### ModuleEntryArrayList

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `moduleEntryArrayListInit` | 43 | pub | `[inference: ensure capacity for initial_capacity]` | Allocates initial `ModuleEntry` array. |
| `moduleEntryArrayListEnsureCapacity` | 54 | pub | `[inference: 2x growth, sand alloc, min 8]` | Grows `ModuleEntry` array. `new_cap = max(requested, cap*2, 8)`. |
| `moduleEntryArrayListAppend` | 68 | pub | `[inference: ensure capacity + store]` | Appends `ModuleEntry`. |
| `moduleEntryArrayListGetSlice` | 74 | pub | `[inference: slice from items[0..len]]` | Returns `[]ModuleEntry` view. |

#### SearchDirArrayList (private helpers)

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `searchDirArrayListEnsureCapacity` | 85 | private | `[inference: 2x growth, sand alloc, min 2]` | Grows search dir array. |
| `searchDirArrayListAppend` | 97 | private | `[inference: ensure capacity + store]` | Appends search dir path ID. |

#### ModuleResolver

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `joinPath` | 109 | private | `[inference: dir + '/' + rel, sand alloc]` | Concatenates directory path and relative path with `/` separator. |
| `moduleDirPath` | 121 | private | `[inference: scan back for '/', returns prefix or ""]` | Extracts directory portion from path. Returns `""` if no `/`. |
| `moduleResolverInit` | 131 | pub | `[inference: zero-init SearchDirArrayList]` | Creates `ModuleResolver` with empty search dirs. |
| `moduleResolverAddSearchDir` | 139 | pub | `[inference: intern path, append to search_dirs]` | Adds a search directory. |
| `moduleResolverResolve` | 144 | pub | `[inference: 3-tier: importer_dir → search_dirs → '.' ]` | **Import path resolution.** Tries: (1) relative to importer's directory, (2) each registered search dir, (3) current dir `.`. Returns interned resolved path ID or null. |

#### Internal helpers

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `importEdgesEnsureCapacity` | 179 | private | `[inference: 2x growth, sand alloc, min 8]` | Grows import edges array. |
| `importEdgesAppend` | 191 | private | `[inference: ensure capacity + store]` | Appends import edge (u32 module ID) to flat array. |
| `importQueuePendingEnsureCapacity` | 279 | private | `[inference: 2x growth, sand alloc, min 8]` | Grows import queue pending array. |
| `importQueuePendingAppend` | 291 | private | `[inference: ensure capacity + store]` | Appends to pending queue array. |
| `importQueuePendingPop` | 297 | private | `[inference: len check, decrement, return items[len]]` | Pops from back of pending queue (LIFO). |

#### ModuleRegistry — Lifecycle

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `moduleRegistryInit` | 199 | pub | `[inference: alloc ModuleEntryArrayList(8), init hash map, init ImportQueue]` | Creates `ModuleRegistry`. Uses `source_man_stub` (1 byte) as placeholder `SourceManager` — replaced by `moduleRegistrySetSourceMan`. |
| `moduleRegistrySetSourceMan` | 217 | pub | `[inference: pointer assignment]` | Sets real `SourceManager` after init. |
| `moduleRegistryAddModule` | 221 | pub | `[inference: create ModuleEntry(pending), append, increment next_id]` | Creates new `ModuleEntry` with `state=pending`. Returns new module ID. |
| `moduleRegistryGetModules` | 240 | pub | `[inference: slice from items[0..len]]` | Returns `[]ModuleEntry` of all registered modules. |
| `moduleRegistryGetOrCreateModule` | 244 | pub | `[inference: hash lookup → add if missing, cache path_id→mod_id]` | Looks up existing module by path ID; creates new if not found. Also stores mapping in `path_to_id` hash map. |
| `moduleRegistryAddImport` | 252 | pub | `[inference: append to import_edges, set imports_start on first import, increment count]` | Records import dependency: `importer_id` imports `imported_id`. `imports_start` is set once on first call (no update on subsequent calls). |

#### Import Queue

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `importQueueInit` | 303 | pub | `[inference: zero-init pending array]` | Creates empty `ImportQueue`. |
| `importQueueEnqueue` | 314 | pub | `[inference: linear dedup scan, append if unique]` | Enqueues module ID. **Dedup:** linear scan of `pending_items` — skips if already enqueued. |
| `importQueueDequeue` | 323 | pub | `[inference: delegate to importQueuePendingPop]` | Dequeues module ID (LIFO pop-back). Returns null if empty. |

#### Import Resolution Entry Point

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `moduleRegistryResolveImport` | 260 | pub | `[inference: resolve path, get-or-create module, record import, enqueue]` | Resolves an `@import("path")` reference: calls `moduleResolverResolve` → `moduleRegistryGetOrCreateModule` → `moduleRegistryAddImport` → `importQueueEnqueue`. Returns resolved module ID or null. |

#### Topological Sort

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `moduleRegistrySortModules` | 327 | pub | `[inference: Kahn's algorithm, fixed-size [256] arrays, circular dep detection]` | **Kahn's algorithm** on module graph. See [Kahn's Algorithm](#kahns-algorithm) below. |
| `moduleRegistryVerifyOrder` | 414 | pub | `[inference: scan all resolved modules, check all imports resolved/failed]` | Post-sort verification: every import of every resolved module must be `resolved` or `failed`. Emits `ERR_4000` on violation. |

#### Post-processing

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `moduleRegistryCollectIncludes` | 439 | pub | `[inference: scan decls for c_include nodes, append to c_includes]` | Collects C include directives from module AST. Checks both top-level `c_include` decls and `var_decl` init values that are `c_include`. |

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

[updated: 2026-08-01] **How phases actually skip failed modules — `ast_root == 0`, NOT `ModuleState.failed`:** no later phase checks `ModuleState.failed` at all. The per-phase skip is by `ast_root == 0` — a module that failed to read (F-S10) or failed to parse never gets `ast_root` set (it stays 0), and each phase tests `mods[i].ast_root != 0` before walking the AST (e.g. `main.zig:314` `T0` gate). This is undocumented elsewhere: `ModuleState.failed` is set by the import resolver for bookkeeping but is invisible to phases 2-8.

---

## On-Demand Parsing Loop

The core loop in `moduleRegistryResolveImports` (import_resolver.zig:82-138):

```
while queue not empty:
    mod_id = dequeue()
    if mod_id.state != pending → skip (already processed)

    scratch.reset()

    entry.state = parsing

    content = readFile(path)          ← file I/O
    if content missing → emit ERR_3048 diagnostic, state = failed, continue   ← F-S10
      (was silent pre-F-S10; now `error[3048]: could not read imported file '<path>'`)

    ast_root = moduleRegistryParseModule(
        reg, mod_id, content,         ← lex → tokenize → parse
        module_arena, scratch, shared_store
    )
    if parse failed → state = failed, continue

    entry.ast_root = ast_root
    entry.state = parsed

    for each import in entry:
        if imported_module.state == pending:
            queue.enqueue(imported_module_id)
```

[updated: 2026-08-01] **F-S10 missing-dependency choke point:** a dep that never resolves in the
3-tier search fails *before* `readFile` — `moduleResolverResolve` (`module_registry.zig:144-161`)
gates on `fileExists` and returns null, so `moduleRegistryResolveImport`
(`module_registry.zig:260-274`) returns null and emits `error[3048]: could not resolve imported
file '<path>'` at the resolve-null point (`module_registry.zig:263-270`). Pre-F-S10 this was
silent: `parser.zig:641-643` discarded the null result, no module was registered, and no
`readFile` was attempted. So the import_resolver.zig:96 site only fires for **empty** deps; the
module_registry.zig:263 site covers genuinely **missing** deps.

Then a verification pass (import_resolver.zig:139-159) iterates all modules, dumping `IRV:m`/`IRV:c`/`IRV:n` markers, and finally writes `IRN:n` (total node count) and `IRE:x` (extra children count).

---

## Kahn's Algorithm (`moduleRegistrySortModules`)

`module_registry.zig:327-412`

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
phase_ImportResolution (main.zig:249)
    │  marker: "I\n"
    │
    ├─ moduleRegistryAddModule → ModuleEntry { state: pending }
    ├─ importQueueEnqueue(root_module)
    │
    ▼
moduleRegistryResolveImports (import_resolver.zig:82)
    │
    ├─ LOOP:
    │   ├─ importQueueDequeue → module ID
    │   ├─ readFile → source content
    │   ├─ moduleRegistryParseModule:
    │   │   ├─ sourceManagerAddFile → file_id → ModuleEntry.source_file_id
    │   │   ├─ lexerInit → lexerNextToken (full token stream)
    │   │   ├─ parserInit → parserParseModuleRoot → AstStore
    │   │   └─ returns ast_root
    │   ├─ store ast_root + state = parsed
    │   ├─ extract imports from ModuleEntry.import_edges
    │   └─ enqueue pending import modules
    │
    ├─ Verification pass: IRV markers for all modules
    └─ IRN:n / IRE:x summary markers
    │
    ▼
marker: "Z\n" (queue drained, all modules parsed)
    │
    ▼
moduleRegistrySortModules (Kahn's algorithm)   ← NOT CALLED in the compile pipeline
    │     main.zig ends import resolution at moduleRegistryResolveImports (main.zig:255);
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
    │   1. importer_dir + target → fileExists?
    │   2. each search_dir + target → fileExists?
    │   3. "." + target → fileExists?
    │
    ├─ moduleRegistryGetOrCreateModule (dedup via path_to_id hash)
    ├─ moduleRegistryAddImport (edge: importer_id → imported_id)
    └─ importQueueEnqueue(imported_id)
    │
    ▼
ModuleEntry created (pending) → eventually parsed by main loop
```

### Per-Module Header Include Chain (multi-module emission) — [updated: 2026-08-01]

In the multi-module C89 output (`zig1 --dump-c89 --output-dir DIR`), each module's emitted header
`<module>.h` includes the `.h` of every **direct** import — the import-edge targets
`import_edges_items[M.imports_start .. M.imports_start+M.import_count]` (recorded by
`moduleRegistryAddImport`, module_registry.zig:252) — as `#include "<dep>.h"` using the dep's
**qualified** name (`moduleQualifiedName`, `c89_emit.zig:1895`: `<basename clamped 64>_<FNV1a8>`,
the same scheme as the filenames — see 08 §1.17; the self edge is skipped). The order
follows the direct-edge iteration, i.e. `@import` declaration order. Transitive includes resolve
through the deps' own headers plus the shared `zig_special_types.h`; include guards
(`ZIG_MODULE_<NAME>_H`, and the per-type `ZIG_<TAG>_<cname>` guards) make the include graph
cycle-safe. This is the `emitModuleHeaderFile` dep-include loop (`c89_emit.zig:1980-1988`) — the
emission uses **direct-edge iteration**, not `moduleRegistrySortModules`. F-S7 changed the include
name from the bare basename to the qualified stem (the old bare-basename scheme silently overwrote
same-named modules and emitted duplicate `#include "util.h"` lines).

---

## Debugging

### CLI Flags

| Flag | Effect |
|------|--------|
| `--dump-ast` | Dumps AST tree (phase-independent, but AST populated during import resolution) |

### Phase Entry/Exit Markers — [updated: 2026-08-01]

| Marker | Function | Description |
|--------|----------|-------------|
| `I` | phase_ImportResolution (main.zig:252) | Phase entry — start of import resolution. **NOTE:** `c89_emit.zig:2273` also emits `I\n` during C89 emission, so only the first `I` (plus the `Z` immediately after `IRE:x`) bounds the import-resolution phase |
| `Z` | phase_ImportResolution (main.zig:258) | Phase exit — queue drained, all modules parsed |
| `M` | post-importResolve (main.zig:537) | Module dump — iterates modules, writes `M<id>:<ast_root>:R<decl_count>` |

### Import Resolution Parse Markers (import_resolver.zig)

| Marker | Location | Description |
|--------|----------|-------------|
| `ECB0:<val>` | 58 | `extra_children` value at index 0 before parse |
| `ECB1:<val>` | 59 | `extra_children` value at index 1 before parse |
| `ECB2:<val>` | 60 | `extra_children` value at index 2 before parse |
| `ECD0:<val>` | 69 | `extra_children` value at index 0 after parse |
| `ECD1:<val>` | 70 | `extra_children` value at index 1 after parse |
| `ECD2:<val>` | 71 | `extra_children` value at index 2 after parse |
| `ECBED` | 73 | Written if any of `extra_children[0..2]` changed during the module's own parse. **Fires normally** — the first module parsed always grows the shared array from empty (all 4 examples show `ECBED` right before `IRP:m0`). It is not a corruption indicator. |
| `IRP:m<mod_id>` | 112 | Module being parsed (module ID) |
| `IRP:n<node>` | 113 | AST root node index |
| `IRP:p<payload>` | 114 | Module root payload — packed `(extra_children start << 16) | decl_count` (ast.zig:308), unpacked by `astStoreGetExtraChildren` |
| `IRD:c<count>` | 116 | Child declaration count |
| `IRD:n<decl_id>` | 119 | Per-declaration node index |

### Import Resolution Verify Markers (import_resolver.zig)

| Marker | Location | Description |
|--------|----------|-------------|
| `IRV:m<mod_id>` | 145 | Module being verified |
| `IRV:c<count>` | 147 | Child declaration count |
| `IRV:n<decl_id>` | 150 | Per-declaration node index |

### Import Resolution Summary Markers (import_resolver.zig)

| Marker | Location | Description |
|--------|----------|-------------|
| `IRN:n<count>` | 157 | `shared_store.nodes.len` after all modules parsed |
| `IRE:x<count>` | 158 | `shared_store.extra_children.len` after all modules parsed |

### Topological Sort / Circular Dep Markers

| Marker | Function | Description |
|--------|----------|-------------|
| `circular import detected in module '...'` | moduleRegistrySortModules (line 400) | Diagnostic message for circular dependency |

### Diagnostic Error Codes — [updated: 2026-08-01]

| Code | Constant | Description |
|------|----------|-------------|
| `ERR_3005` | `CIRCULAR_TYPE_DEPENDENCY` | Circular import detected during topological sort |
| `ERR_3048` | `CANNOT_READ_FILE` | **F-S10** — dependency file unreadable/unresolvable. Two call sites: empty dep at `import_resolver.zig:96-105` → `error[3048]: could not read imported file '<path>'`; missing dep (never resolves in the 3-tier search) at the resolve-null choke point `module_registry.zig:263-270` → `error[3048]: could not resolve imported file '<path>'`. Both are level-0 diagnostics → `error_count` → exit 2 at `main.zig:205`. |
| `ERR_4000` | `INVALID_CONTROL_FLOW` | Topological sort violation — import not resolved |

### Known Issues [updated: 2026-07-31]

1. **Fixed-size arrays** (module_registry.zig:329,341): `in_degree` and `worklist` are `[256]u32` — hard limit of 256 modules. Exceeding this causes silent out-of-bounds writes.
2. **Import dedup O(n)** (module_registry.zig:316-319): `importQueueEnqueue` does linear scan of pending items. LIFO stack means worst-case O(n²) across all enqueues.
3. **No post-parse cycle detection**: The parsing loop does not detect cycles — they surface later in `moduleRegistrySortModules` (ERR_3005). The loop itself cannot hang on a cycle: `import_resolver.zig:130` enqueues only modules still in `pending` state and `import_resolver.zig:87` skips non-pending modules, so the queue always drains. In the compile pipeline (sort not invoked) a cycle would be silently tolerated with no diagnostic.
4. **`source_man_stub`** (module_registry.zig:197): One-byte stub used as placeholder `SourceManager` until `moduleRegistrySetSourceMan` is called. If `moduleRegistryResolveImports` runs before `setSourceMan`, the pointer dereference will crash.
5. **No path normalization** (module_resolver.zig:109-119,144-161): `joinPath` and `moduleResolverResolve` do not resolve `..` or `.` — only simple concatenation.

### D1 Gap: Search-Path Wiring — FIXED [updated: 2026-08-14]

> Task F implemented the search path (operator ruling 2026-08-14): bare `@import("std")` now
> resolves through user `-I`/`--lib-dir` dirs then a compiler-binary-relative default install
> path, with `.zig` auto-append for bare names.

**Resolver behavior (file:line).** `@import("...")` is parsed in `parserParseImportExpr`
(`parser.zig:615-647`); the raw string literal is interned as `path_id` (`parser.zig:629`) and,
while parsing, `moduleRegistryResolveImport` is called (`parser.zig:642`). That call resolves via
`moduleResolverResolve` (`module_registry.zig:166-183`), which tries four tiers via
`moduleResolverTryDir` (`module_registry.zig:144-151`): (1) importer's own directory
(`moduleDirPath` :121 + `joinPath` :109); (2) the `search_dirs` list; (3) `.` — the current working
directory. At each tier `moduleResolverTryDir` tries `target` first, then `target + ".zig"`
(`appendZigExt`, `module_registry.zig:131-142`) — so a bare `@import("std")` maps to `std.zig`
(ruling 3b), while an explicit `@import("std.zig")` resolves unchanged on the first try
(byte-neutral). `moduleRegistryResolveImports` (`import_resolver.zig:82`) then loops the queue,
`readFile`s each resolved path, and parses.

**Resolution (implemented 2026-08-14).**
1. **`.zig` auto-append for bare names** — `moduleResolverTryDir`/`appendZigExt`
   (`module_registry.zig:131-151`), used by all four tiers of `moduleResolverResolve`.
2. **CLI `--lib-dir` alias of `-I`** — `parseArgs` matches `--lib-dir` on the `-I` branch
   (`main.zig:964`, const `s_lib_dir` at `main.zig:899`), repeatable into `cli.include_dirs[16]` in
   CLI order.
3. **Search-dir seeding** — `phase_ImportResolution` (`main.zig:262-282`) iterates
   `cli.include_dirs` in CLI order calling `moduleResolverAddSearchDir` (`main.zig:265-268`), then
   appends the default install path if it exists on disk (`main.zig:269-276`). User dirs precede the
   default path (ruling 5).
4. **Default install path** (ruling 2, Option B) — new PAL helper `pal_get_default_lib_path`
   (`sf/src/include/zig_pal.c:219-251`, `_WIN32` `GetModuleFileNameA` / Linux
   `readlink("/proc/self/exe")`) returns `<exe_dir>/lib`; declared `sf/src/pal.zig:14` and wrapped
   `pal.getDefaultLibPath` (`pal.zig:93-95`). Seeded only when `pal.fileExists` confirms the dir.

**Behavior.** `@import("std")` resolves: (1) importer's own dir; (2) each `-I`/`--lib-dir` dir in
CLI order; (3) `<exe_dir>/lib` if present; (4) `.` (CWD). The `std_import_bare_xmod` repro is GREEN
two ways: `--lib-dir repro/mi_matrix/std_import_bare_xmod/local` (or `-I`) and, with
`std.zig`+`std_io.zig` copied to `<exe_dir>/lib`, with no flag — both print `42`. The 4 MD5 gates
(gol/lisp/json/mud) stay byte-identical, and the corpus gains no regression (see task-F-report).

**Blast radius (migration scope — Task F-MIGRATE, not this task).** Every `std.zig`/`std_io.zig`
byte-identical copy is a candidate for deletion once the search path works: 19
`examples/z98/*/std.zig` trees (21 z98 example dirs total; 19 also carry `std_io.zig`) plus 7
`examples/zig0/*/std.zig`; 54 `repro/mi_matrix/*` dirs carry `std.zig`/`std_io.zig` (247 repro dirs
total) plus 1 nested copy in `std_import_bare_xmod/local/`; 82 `std.zig` and 75 `std_io.zig` files
exist tree-wide outside `sf/`. A committed `sf/lib/std.zig` stub already exists (tracked, "Z98
Standard Library stub" — currently only `debug.print`/`mem.eql`/`io.Writer`/`ArrayList` placeholders,
dormant; it is `std.zig` not a bare `std` file, and the `@import("std")` in `semantic.zig:65`/
`c89_types.zig:16` is dead code not in the compile graph).


---

## Evidence: 4 Working Examples (Deep-Dive P1)

Traces generated by `zig1 --markers --dump-c89` (P0) at `/tmp/dd/*.mrk`. Module→file mapping
verified with GDB on a debug build of the same source `[gdb]` (break on `moduleRegistryParseModule`,
dump interned path string). The debug build reproduces the P1 marker section byte-identically
`[markers]`.

### Module graphs (module_id → file)

Module ids are assigned in first-reference order (`moduleRegistryGetOrCreateModule`,
module_registry.zig:244-250) as each importer parses. Dedup verified: `file.zig` is imported by
both `main.zig` and `json.zig` yet is registered once (m1) and parsed once.

| Example | m0 | m1 | m2 | m3 | m4 | m5 | m6 | m7 | m8 | m9 | Modules |
|---------|----|----|----|----|----|----|----|----|----|----|:-------:|
| mud_server | main.zig | std.zig | util.zig | std_debug.zig | - | - | - | - | - | - | 4 |
| game_of_life | main.zig | std.zig | std_debug.zig | - | - | - | - | - | - | - | 3 |
| lisp_interpreter_curr | main.zig | sand.zig | value.zig | token.zig | parser.zig | env.zig | eval.zig | builtins.zig | util.zig | deep_copy.zig | 10 |
| json_parser | main.zig | file.zig | json.zig | - | - | - | - | - | - | - | 3 |

Notable: json_parser's `arena.zig` declares `extern fn arena_alloc_default` but is imported by
nobody → never registered, never parsed (module graph has no `arena` module).

### Parse order (markers `IRP:m<id>`, import_resolver.zig:112)

| Example | `IRP:m` sequence (parse order) | LIFO? |
|---------|-------------------------------|-------|
| mud_server | 0 → 2 → 1 → 3 | yes |
| game_of_life | 0 → 1 → 2 | yes |
| lisp_interpreter_curr | 0 → 9 → 8 → 7 → 6 → 5 → 4 → 3 → 2 → 1 | yes |
| json_parser | 0 → 2 → 1 | yes |

The queue is LIFO (`importQueueDequeue` = pop-back, module_registry.zig:297-301). Imports are
enqueued in source order while a module parses; the last-imported module is parsed next (reverse
DFS). lisp's `main.zig` imports sand→…→deep_copy in source order; parse order is the exact
reverse. Per-module decl counts (`IRD:c`) match each file's top-level declaration count.

Verbatim excerpt — json_parser.mrk (P1 section, abridged):

```
I
ECB0:0
...
ECBEDIRP:m0
IRP:n292
IRD:c13
IRD:n2
... (11 further IRD:n lines, ending IRD:n291)
...
IRP:m2
IRP:n1375
IRD:c20
...
IRP:m1
IRP:n1567
IRD:c16
...
IRV:m0 IRV:c13 ... IRV:m1 IRV:c16 ... IRV:m2 IRV:c20
IRN:n1568
IRE:x534
Z
```

### Questionnaire answers (all with evidence)

1. **Modules per example + module graph** — table above. Counts from `IRP:m`/`IRV:m` coverage
   `[markers]`; id→file mapping from GDB `[gdb]`. Totals (`IRN:n` nodes / `IRE:x` extra-children):
   mud_server 944/343, game_of_life 807/382, lisp_interpreter_curr 3854/1307, json_parser
   1568/534.
2. **Parse order vs Kahn topological sort** — parse order is LIFO queue order (reverse DFS), NOT
   topological: the root always parses first, before its dependencies. A Kahn sort of the same
   graphs would emit dependencies first (e.g. mud_server: std_debug, util, std, main). Moreover
   `moduleRegistrySortModules` is never invoked in the compile pipeline (main.zig:255 calls only
   `moduleRegistryResolveImports`), so no topological sort occurs at all. `[markers]` + `[inference]`
3. **Modules in `ModuleState.failed`** — none. Every module id is covered by `IRP:m` and `IRV:m`
   in all four traces, and no diagnostic text (`ERR_3005`/`ERR_4000`/"circular"/"fail") appears
   between `I` and `Z`. `[markers]`
4. **Circular imports** — none in the real graphs. Detection exists only in
   `moduleRegistrySortModules` (ERR_3005, module_registry.zig:394-410) which the pipeline never
   runs. The parse loop cannot hang on a cycle anyway: import_resolver.zig:130 enqueues only
   `pending` modules. Queue drained (`Z` reached) in all four traces. `[markers]` + `[inference]`
5. **On-demand loop in markers** — parse→enqueue→pop→next IS visible: `IRP:m`/`IRD:c`/`IRD:n`
   (parse) per module, next module's `IRP:m` in LIFO order (pop+parse), ending with the `IRV:*`
   verify pass and `IRN:n`/`IRE:x` summaries before `Z`. The loop pseudocode in the "On-Demand
   Parsing Loop" section matches import_resolver.zig:82-138; the doc's only errors are the
   sort-after-`Z` step and the `ECBED` semantics (see table below). `[markers]`
6. **json_parser `arena_alloc_default` extern** — no cross-module resolution issue. Extern fn
   declarations never call `moduleRegistryResolveImport`; GDB on `moduleRegistryResolveImport`
    shows the only 3 import-resolution calls are the @import edges (main->file, json->file, all correctly attributed [fixed 2026-07-31]), none
   json.zig:253 each self-contain the extern; `arena.zig` (a third declarer) is never imported and
   so never enters the graph. `[gdb]` + `[markers]`

### Doc inaccuracies found (item 5)

| Doc location (pre-edit) | Claim | Reality |
|-------------------------|-------|---------|
| this doc :11, :152, :267-278 | Kahn sort runs after import resolution; modules reach `resolved` | `moduleRegistrySortModules` never called from main.zig — only from tests. Modules stay `parsed`. |
| this doc :26, :73, :326 | `ECBED` indicates store corruption, should not happen | Fires normally on the first module parsed (shared `extra_children` grows from empty). |
| this doc :365 | Import cycle can cause infinite parse loop | Impossible: enqueue gated on `pending` (import_resolver.zig:130); queue always drains. |
| this doc :12, :320-346 | Marker table lists only `ECB0`/`ECD0` | Also `ECB1`, `ECB2`, `ECD1`, `ECD2` (import_resolver.zig:59-71). |
