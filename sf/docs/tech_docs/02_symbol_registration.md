# 02 — Symbol Registration

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `SymbolKind` variants | 7 | `local(0)`, `param(1)`, `global(2)`, `function(3)`, `type_alias(4)`, `module(5)`, `test_sym(6)` |
| `Symbol` fields | 7 | name_id, type_id, kind, flags, decl_node, module_id, scope_level |
| Decl kinds registered | 7 | var_decl, fn_decl, test_decl, struct_decl, enum_decl, union_decl, error_set_decl |
| `DepGraph` edge items | dynamic | Flat array of `DepEdge`, 2x growth, min 8 |
| `SymbolTable` per module | lazy | Created on first `symbolRegistryGetTable(mod_id)` access |
| Type stubs populated | 4 | StructPayload, UnionPayload/TaggedUnionPayload, EnumPayload, ErrorSetPayload |
| Debug markers | ~15+ | `S`, `S0`, `Ra`, `Rs`, `Rf`, `RCA`, `VR`, `VD`, `Vi`, `M5`, `FIX1`, `IMR` |

---

## symbol_table.zig (`sf/src/symbol_table.zig`, 122 lines)

Per-module symbol table and global registry of tables.

### Types

| Type | Line | Description |
|------|------|-------------|
| `Symbol` (struct) | 4 | Symbol entry: `name_id(u32, interned)`, `type_id(u32)`, `kind(SymbolKind)`, `flags(u16)`, `decl_node(u32)`, `module_id(u32)`, `scope_level(u32)` |
| `SymbolKind` (enum u8) | 14 | `local`(0, reserved for semantic analysis), `param`(1, reserved), `global`(2, top-level var), `function`(3), `type_alias`(4, type name), `module`(5, import), `test_sym`(6, test decl) |
| `SymbolTable` (struct) | 24 | Flat symbol array: `items([*]Symbol)`, `len(usize)`, `capacity(usize)`, `allocator(*Sand)` |
| `SymbolRegistry` (struct) | 73 | Array of per-module `SymbolTable`: `tables_items([*]SymbolTable)`, `tables_len/cap`, `tables_alloc(*Sand)` |

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `symbolTableInit` | 31 | pub | `[inference: zero-init SymbolTable with undefined items]` | Creates empty `SymbolTable`. `items` left undefined — allocated on first insert. |
| `symbolTableEnsureCapacity` | 40 | private | `[inference: 2x growth, sand alloc for Symbol, min 8]` | Grows symbol array. `new_cap = max(requested, cap*2, 8)`. |
| `symbolTableInsert` | 52 | pub | `[inference: linear dedup scan by name_id, ensure capacity, append]` | Inserts `Symbol`. **Dedup:** linear scan — if `name_id` exists, returns `false` without inserting. |
| `symbolTableLookup` | 64 | pub | `[inference: linear scan by name_id, return pointer or null]` | Looks up symbol by `name_id`. Returns `?*Symbol`. |
| `symbolRegistryInit` | 92 | pub | `[inference: zero-init SymbolRegistry with undefined tables]` | Creates empty `SymbolRegistry`. |
| `symbolRegistryEnsureCapacity` | 80 | private | `[inference: 2x growth, sand alloc for SymbolTable, min 8]` | Grows `tables_items` array. |
| `symbolRegistryGetTable` | 101 | pub | `[inference: grow tables_items to module_id, init missing with symbolTableInit]` | Gets or creates `SymbolTable` for given `module_id`. Missing indices are filled with empty tables. |
| `symbolIsPublic` | 115 | pub | `[inference: (flags & 2) != 0]` | Returns `true` if symbol has public visibility flag set. |
| `symbolRegistryQualifiedLookup` | 119 | pub | `[inference: get table by mod_id, lookup by name_id]` | Qualified symbol lookup: module-scoped `name_id` → `?*Symbol`. |

---

## symbol_registrator.zig (`sf/src/symbol_registrator.zig`, 434 lines)

Walks the AST root of each resolved module, registers declarations as symbols per module, builds type dependency graph, and creates type stubs.

### Types

| Type | Line | Description |
|------|------|-------------|
| `DepEdge` (struct) | 16 | Dependency edge: `from(u32)`, `to(u32)` |
| `DepGraph` (struct) | 18 | Dependency graph: `items([*]DepEdge)`, `len/cap`, `alloc(*Sand)`, `in_degree_items([*]u32)`, `in_degree_cap(usize)` |

### Functions

#### DepGraph

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `depGraphInit` | 27 | pub | `[inference: zero-init DepGraph with undefined arrays]` | Creates empty `DepGraph`. Arrays allocated on first `depGraphAddEdge`. |
| `depGraphEnsureCapacity` | 38 | private | `[inference: 2x growth, sand alloc for DepEdge, min 8]` | Grows edge array. |
| `depGraphAddEdge` | 48 | pub | `[inference: ensure capacity, store DepEdge{from, to}, increment len]` | Appends `DepEdge` to graph. Used to record type dependencies (field → type). |
| `depGraphFinalize` | 54 | pub | `[inference: alloc in_degree array of size max_type_id+1, zero-init, count edges per target]` | Computes in-degree for each type ID. Allocates `in_degree_items[0..max_type_id]`, counts edges where `edge.to == tid`. |

#### Internal Helpers

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `addTypeDependencies` | 70 | private | `[inference: iterate children of decl_node, add dep edge for each field_decl → tid]` | Records type dependencies. For each `field_decl` child, adds `depGraphAddEdge(g, 0, tid)` — node 0 is a sentinel root. |
| `populateTypePayload` | 84 | private | `[inference: switch on decl_kind, iterate children, append payload structs to TypeRegistry]` | Creates type stubs in `TypeRegistry`. See [Type Stub Population](#type-stub-population) below. |
| `registerDecl` | 213 | private | `[inference: switch on node.kind, create Symbol, insert into SymbolTable]` | Registers a single declaration. See [Decl Registration Walkthrough](#decl-registration-walkthrough) below. |

#### Entry Point

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `registerModuleSymbols` | 399 | pub | `[inference: iterate resolved modules, walk module_root children, call registerDecl per decl]` | **Phase entry point.** Iterates all modules in `ModuleRegistry`. For each `parsed`/`resolved` module with an `ast_root`, walks the `module_root` node's `extra_children` (top-level decls) and calls `registerDecl` for each. Module 0 dumps `RS` debug marker with decl node indices and AstKind values. |

---

## Decl Registration Walkthrough

`registerDecl` (symbol_registrator.zig:213) switches on `node.kind`:

### `var_decl` (line 216)

Two sub-cases based on `child_1` (the init expression):

1. **Init is `import_expr`** (line 227): Resolves target module via `path_to_id` hash map. If found, creates `SymbolKind.module` with `type_id = typeRegistryGetOrCreateModule(mtid)`. Writes `M5:p<path_id>`, `Rs`, `FIX1:mid=<mod_id>t=<target_mtid>n=<mod_id>` markers. If not found, writes `Rf` (resolve failed) marker.

2. **Init is inline type decl** (struct_decl/enum_decl/union_decl/error_set_decl, line 246): Registers type via `typeRegistryRegisterNamedType`, calls `populateTypePayload` to create type stubs, calls `addTypeDependencies` to record field→type edges. Creates `SymbolKind.type_alias`.

3. **Init is `ident_expr`** (line 259): Looks up type via `nameCacheGet`. If cached, creates `SymbolKind.type_alias` with the cached type ID and writes `RCA:p<ident_payload>`, `RCA:i<interned_name>`, `RCA:H<cached_type>` markers.

Default case (no special init): creates `SymbolKind.global`.

All var_decl symbols emit `Ra` (register alias), `D12:n<name_id>` (debug name dump), then `VR`/`VD:<name_id>:<kind_enum>`/`Vi` (variable register/dump/info).

### `fn_decl` (line 305)

Creates `SymbolKind.function` using `proto.name_id` from the function prototype (`store.fn_protos[node.payload]`).

### `test_decl` (line 319)

Creates `SymbolKind.test_sym` if `node.payload != 0` (named test). Anonymous tests (`test {}`) are skipped.

### `struct_decl`, `enum_decl`, `union_decl` (line 334)

Registers type via `typeRegistryRegisterNamedType`, calls `populateTypePayload` for field/member stubs, calls `addTypeDependencies`, creates `SymbolKind.type_alias`. Union flag bit 0 distinguishes `union` vs `tagged_union`.

### `error_set_decl` (line 357)

Registers error set type via `typeRegistryRegisterNamedType` with `TypeKind.error_set_type`, calls `populateTypePayload`, creates `SymbolKind.type_alias`.

### `import_expr` (line 373)

Resolves target module via `path_to_id` hash map. If found, creates `SymbolKind.module` with `type_id = typeRegistryGetOrCreateModule(tid)`. Emits `IMR:n<path_id>m<mod_id>` marker.

---

## Type Stub Population

`populateTypePayload` (symbol_registrator.zig:84) creates skeleton type payloads in `TypeRegistry`. All types iterate `astStoreGetExtraChildren(store, node.payload)` to find `field_decl` children:

### struct_decl (line 90)

Iterates children, calls `feAppend` for each `field_decl` (with `name_id = fd.payload`, `type_id = TYPE_VOID`, `offset = 0`), then calls `stAppend` with `StructPayload{fields_start, fields_count}`. Back-patches `payload_idx` on the last registered type.

### union_decl (line 118)

Same field iteration as struct. If `node.flags & 1 != 0` (tagged union): calls `tuAppend` with `TaggedUnionPayload{tag_type = TYPE_U32, fields_start, fields_count}`. Else: calls `unAppend` with `UnionPayload{fields_start, fields_count, tag_type = TYPE_VOID}`. Back-patches `payload_idx`.

### enum_decl (line 158)

Creates `TypeResolveEnv` for backing type resolution. If `node.child_0 != 0`, resolves the backing integer type via `resolveTypeExprFull`. Iterates children: for each `field_decl`, auto-increments value (starting at 0) unless `mnode.child_1` provides an explicit value via `evalConstU32Full`. Calls `emAppend` with `EnumMember{name_id, value}`, then `enAppend` with `EnumPayload{members_start, members_count, backing_type}`. Back-patches `payload_idx`.

### error_set_decl (line 195)

Iterates children, calls `xnAppend` for each child node index (tags are node indices into AST, not interned names). Calls `esAppend` with `ErrorSetPayload{tags_start, tags_count}`.

---

## Data Flow

```
phase_SymbolRegistration (main.zig:259)
    │
    │  marker: "S\n"
    │  scratch arena reset
    │
    ├─ depGraphInit(&scratch)
    │
    ├─ LOOP over all modules (by ascending ID):
    │   │
    │   ▼
    │   registerModuleSymbols (symbol_registrator.zig:399)
    │       │
    │       ├─ skip if state != parsed/resolved or ast_root == 0
    │       │
    │       ├─ read module_root node → extra_children (top-level decls)
    │       │
    │       ├─ module_id == 0: dump "RS" marker
    │       │   └─ write decl node indices and AstKind enum values
    │       │
    │       └─ LOOP over decls:
    │           │
    │           ▼
    │           registerDecl (symbol_registrator.zig:213)
    │               │
    │               ├─ switch on node.kind:
    │               │   ├─ var_decl → SymbolKind.{global|module|type_alias}
    │               │   │   └─ init type decl? → populateTypePayload + addTypeDependencies
    │               │   │   └─ init import_expr? → SymbolKind.module via path_to_id
    │               │   │   └─ init ident_expr? → nameCacheGet → SymbolKind.type_alias
    │               │   ├─ fn_decl → SymbolKind.function (proto.name_id)
    │               │   ├─ test_decl → SymbolKind.test_sym (if named)
    │               │   ├─ struct_decl/enum_decl/union_decl → typeRegistryRegisterNamedType
    │               │   │   └─ populateTypePayload + addTypeDependencies
    │               │   │   └─ SymbolKind.type_alias
    │               │   ├─ error_set_decl → typeRegistryRegisterNamedType
    │               │   │   └─ populateTypePayload + SymbolKind.type_alias
    │               │   └─ import_expr → SymbolKind.module (path_to_id lookup)
    │               │
    │               └─ symbolRegistryGetTable(mod_id) → SymbolTable
    │                   └─ symbolTableInsert(sym) → bool (false = duplicate)
    │
    ├─ "S0" marker dump (root module 0 decl kinds)
    │
    └─ DepGraph available for phase 3 (type resolution)
```

### Data Structures After Symbol Registration

```
SymbolRegistry (permanent arena)
    │
    ├─ tables_items[0..n]
    │   ├─ SymbolTable[0] → [Symbol{var_x, fn_main, StructA, ...}]
    │   ├─ SymbolTable[1] → [Symbol{imported_fn, ...}]
    │   └─ ...
    │
    └─ Each SymbolTable:
        └─ Flat array of Symbol — dedup by name_id

DepGraph (scratch arena, consumed by phase 3)
    │
    ├─ items[0..len]: DepEdge{from, to}
    └─ in_degree_items[0..max_type_id]: u32 in-degree counts

TypeRegistry (permanent arena, updated with stubs)
    │
    ├─ Type entries with payload_idx → StructPayload / UnionPayload / etc.
    ├─ FieldEntry array (fe)
    ├─ EnumMember array (em)
    └─ Error tag indices (xn)
```

---

## Debugging

### Phase Entry/Exit Markers

| Marker | Location | Description |
|--------|----------|-------------|
| `S` | main.zig:260 | Phase entry — start of symbol registration |
| `S0` | main.zig:274 | Root module (0) decl kind listing — writes AstKind enum values |

### Declaration Registration Markers (symbol_registrator.zig)

| Marker | Location | Description |
|--------|----------|-------------|
| `Ra` | 217 | Register alias — var_decl registration start |
| `Rs` | 232 | Register symbol — import_expr target resolved |
| `Rf` | 243 | Register failed — import_expr target not in path_to_id |
| `RCA:p<payload>` | 260 | Register const alias — init.ident payload |
| `RCA:i<name_id>` | 261 | Register const alias — resolved ident name_id |
| `RCA:H<type_id>` | 265 | Register const alias — cache hit type ID |
| `M5:p<path_id>` | 229 | Module import — path ID of import_expr payload |
| `FIX1:mid=<mod_id>t=<target>n=<mod_id>` | 235-240 | Fixup debug — module id, target mod id, current mod id |
| `D12:n<name_id>` | 219-221 | Debug name dump — var_decl name_id |
| `VR` | 287 | Variable register — duplicate insert (symbolTableInsert returned false) |
| `VD:<name_id>:<kind_enum>` | 291-302 | Variable dump — name_id and SymbolKind numeric value |
| `Vi` | 303 | Variable info — end of var_decl registration |
| `IMR:n<path_id>m<mod_id>` | 388-392 | Import module registered — path_id and resolved module ID |

### Diagnostic Error Codes

(None emitted during symbol registration — type errors surface in phase 3.)

### Known Issues

1. **Linear dedup O(n)** (symbol_table.zig:53-56): `symbolTableInsert` does a full linear scan of the table for every insert. Per-module tables grow unbounded; worst-case O(n²) across all inserts in a module.

2. **No local/param symbol registration during phase 2** (symbol_table.zig:14-16): `SymbolKind.local` and `SymbolKind.param` are defined but never used in this phase — they are reserved for semantic analysis (phase 5).

3. **Duplicate `VR` marker on re-insert** (symbol_registrator.zig:286-289): If `symbolTableInsert` returns `false` (duplicate name), only a debug marker is written — no error diagnostic is emitted. Duplicates silently shadow rather than producing a compile error.

4. **Sentinel root node (from=0) in DepGraph** (symbol_registrator.zig:78): `addTypeDependencies` always uses `from=0` as a sentinel. Type resolution must handle this convention — `tid=0` is not a valid type ID, it means "root/dummy".

5. **Scratch arena dependency** (phase_SymbolRegistration, main.zig:261): `DepGraph` is allocated in scratch arena and invalidated on next phase's `sandReset`. If type resolution (phase 3) needs to reference the graph later, it must snapshot or consume it before reset.
