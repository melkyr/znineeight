# 01 — Import Resolution

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `ModuleState` variants | 5 | `pending(0)`, `parsing(1)`, `parsed(2)`, `resolved(3)`, `failed(4)` |
| `ModuleEntry` fields | 10 | id, path_id, source_file_id, state, ast_root, import_count, imports_start, symbol_table, type_offset, c_includes |
| `ImportQueue` | LIFO stack | Enqueue dedup (linear scan), dequeue pop-back |
| Search dir resolution | 3-tier | Importer dir → search dirs → `.` current dir |
| Topological sort | Kahn's algorithm | Stack-based worklist, fixed-size `[256]u32` arrays, O(V+E) |
| Debug markers | ~15+ | `I`, `Z`, `IRP:*`, `IRD:*`, `IRV:*`, `IRN:n`, `IRE:x`, `ECB*`, `ECD*` |

---

## import_resolver.zig (`sf/src/import_resolver.zig`, 160 lines)

Orchestrates the on-demand parsing loop: dequeue module ID → lex → parse → extract imports → enqueue dependencies.

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `tokenArrayEnsureCapacity` | 15 | private | `[inference: 2x growth, sand alloc for Token, min 64]` | Grows token array. Bumps to `max(new_cap, cap*2, 64)`. Copies old items to new allocation. |
| `tokenArrayAppend` | 27 | private | `[inference: ensure capacity + store + increment]` | Appends Token to dynamic array. Delegates capacity check to `tokenArrayEnsureCapacity`. |
| `moduleRegistryParseModule` | 33 | private | `[inference: lex full token stream, parse module root, ECB/ECD debugging]` | Full lex→parse pipeline for one module. Lexes content to token array, creates parser, parses `module_root`. **Debug:** snapshots `extra_children[0..5]` before/after parse (`ECB0:`/`ECD0:`) and writes `ECBED` if they changed (indicates store corruption). Returns `ast_root` or null on parse failure. |
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
         └──────│  failed  │ ←── readFile fail OR parse error OR circular dep
                └──────────┘
```

**Key:** `failed` is a sink state. `resolved` is only reached via Kahn's algorithm, not during the parsing loop. Modules in `failed` state are excluded from topological sort (in_degree set to 0 but `state == failed` check skips them).

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
    if content missing → state = failed, continue

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
moduleRegistrySortModules (Kahn's algorithm)
    │
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

---

## Debugging

### CLI Flags

| Flag | Effect |
|------|--------|
| `--dump-ast` | Dumps AST tree (phase-independent, but AST populated during import resolution) |

### Phase Entry/Exit Markers

| Marker | Function | Description |
|--------|----------|-------------|
| `I` | phase_ImportResolution (main.zig:250) | Phase entry — start of import resolution |
| `Z` | phase_ImportResolution (main.zig:256) | Phase exit — queue drained, all modules parsed |
| `M` | post-importResolve (main.zig:535) | Module dump — iterates modules, writes `M<id>:<ast_root>:R<decl_count>` |

### Import Resolution Parse Markers (import_resolver.zig)

| Marker | Location | Description |
|--------|----------|-------------|
| `ECB0:<val>` | 58 | Extra children count before parse (index 0) |
| `ECD0:<val>` | 69 | Extra children count after parse (index 0) |
| `ECBED` | 73 | Marker written if extra children changed during parse (should not happen — indicates store corruption) |
| `IRP:m<mod_id>` | 112 | Module being parsed (module ID) |
| `IRP:n<node>` | 113 | AST root node index |
| `IRP:p<payload>` | 114 | Module root payload (extra children index) |
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

### Diagnostic Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| `ERR_3005` | `CIRCULAR_TYPE_DEPENDENCY` | Circular import detected during topological sort |
| `ERR_4000` | `INVALID_CONTROL_FLOW` | Topological sort violation — import not resolved |

### Known Issues

1. **Fixed-size arrays** (module_registry.zig:329,341): `in_degree` and `worklist` are `[256]u32` — hard limit of 256 modules. Exceeding this causes silent out-of-bounds writes.
2. **Import dedup O(n)** (module_registry.zig:316-319): `importQueueEnqueue` does linear scan of pending items. LIFO stack means worst-case O(n²) across all enqueues.
3. **No post-parse cycle detection**: The parsing loop does not detect cycles — they surface later in `moduleRegistrySortModules`. An import cycle can cause infinite parsing (module A imports B, B imports A → both stay pending, queue loops forever). The `state != pending` check at line 87 prevents re-parsing but the queue will never drain if every module eventually depends on a module that imports it.
4. **`source_man_stub`** (module_registry.zig:197): One-byte stub used as placeholder `SourceManager` until `moduleRegistrySetSourceMan` is called. If `moduleRegistryResolveImports` runs before `setSourceMan`, the pointer dereference will crash.
5. **No path normalization** (module_resolver.zig:109-119,144-161): `joinPath` and `moduleResolverResolve` do not resolve `..` or `.` — only simple concatenation.
