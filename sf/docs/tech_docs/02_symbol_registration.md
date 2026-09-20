# 02 — Symbol Registration [updated: 2026-09-20 — refreshed against current source: arbitrary-width/packed/pointer-and-fn type-alias registration, the `phase_FrontResolution` back-fill, and current markers; line references and dated evidence removed]

> Covers: `symbol_registrator.zig`, `symbol_table.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `SymbolKind` variants | 7 | `local(0)`, `param(1)`, `global(2)`, `function(3)`, `type_alias(4)`, `module(5)`, `test_sym(6)` |
| `Symbol` fields | 7 | name_id, type_id, kind, flags, decl_node, module_id, scope_level |
| Decl kinds creating symbols | 8 | var_decl, fn_decl, test_decl, struct_decl, enum_decl, union_decl, error_set_decl, import_expr |
| `DepGraph` edge items | dynamic | Flat array of `DepEdge`, 2x growth, min 8 |
| `SymbolTable` per module | lazy | Created on first `symbolRegistryGetTable(mod_id)` access |
| Type-stub back-patch paths | 4 | StructPayload; UnionPayload/TaggedUnionPayload; EnumPayload; ErrorSetPayload — packed struct/union additionally seed the `pk_struct`/`pk_un` side tables |
| Debug markers | ~16+ | Phase: `S`, `S0`, `T`, `T0`; registration: `RS`, `Ra`, `D12`, `M5`, `Rs`, `FIX1`, `Rf`, `RCA`, `AT`, `VR`, `VD`, `Vi`, `IMR`; type-registry (from type_registry.zig): `MC`, `DC`, `X`, `NP`, `NGC`, `RN` |

---

## symbol_table.zig (`sf/src/symbol_table.zig`)

Per-module symbol table and global registry of tables.

### Types

| Type | Description |
|------|-------------|
| `Symbol` (struct) | Symbol entry: `name_id(u32, interned)`, `type_id(u32)`, `kind(SymbolKind)`, `flags(u16)`, `decl_node(u32)`, `module_id(u32)`, `scope_level(u32)` |
| `SymbolKind` (enum u8) | `local`(0, reserved for semantic analysis), `param`(1, reserved), `global`(2, top-level var), `function`(3), `type_alias`(4, type name), `module`(5, import), `test_sym`(6, test decl) |
| `SymbolTable` (struct) | Flat symbol array: `items([*]Symbol)`, `len(usize)`, `capacity(usize)`, `allocator(*Sand)` |
| `SymbolRegistry` (struct) | Array of per-module `SymbolTable`: `tables_items([*]SymbolTable)`, `tables_len/cap`, `tables_alloc(*Sand)` |

### Functions

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `symbolTableInit` | pub | `[inference: zero-init SymbolTable with undefined items]` | Creates empty `SymbolTable`. `items` left undefined — allocated on first insert. |
| `symbolTableEnsureCapacity` | private | `[inference: 2x growth, sand realloc-in-place with sandAlloc fallback, min 8]` | Grows symbol array. `new_cap = max(requested, cap*2, 8)`. |
| `symbolTableInsert` | pub | `[inference: linear dedup scan by name_id, ensure capacity, append]` | Inserts `Symbol`. **Dedup:** linear scan — if `name_id` exists, returns `false` without inserting. |
| `symbolTableLookup` | pub | `[inference: linear scan by name_id, return pointer or null]` | Looks up symbol by `name_id`. Returns `?*Symbol`. |
| `symbolRegistryInit` | pub | `[inference: zero-init SymbolRegistry with undefined tables]` | Creates empty `SymbolRegistry`. |
| `symbolRegistryEnsureCapacity` | private | `[inference: 2x growth, sand realloc-in-place with sandAlloc fallback, min 8]` | Grows `tables_items` array. |
| `symbolRegistryGetTable` | pub | `[inference: grow tables_items to module_id, init missing with symbolTableInit]` | Gets or creates `SymbolTable` for given `module_id`. Missing indices are filled with empty tables. |
| `symbolIsPublic` | pub | `[inference: (flags & 2) != 0]` | Returns `true` if symbol has public visibility flag set. |
| `symbolRegistryQualifiedLookup` | pub | `[inference: get table by mod_id, lookup by name_id]` | Qualified symbol lookup: module-scoped `name_id` → `?*Symbol`. |

---

## symbol_registrator.zig (`sf/src/symbol_registrator.zig`)

Walks the AST root of each resolved module, registers declarations as symbols per module, builds a type dependency graph, and creates type stubs.

### Types

| Type | Description |
|------|-------------|
| `DepEdge` (struct) | Dependency edge: `from(u32)`, `to(u32)` |
| `DepGraph` (struct) | Dependency graph: `items([*]DepEdge)`, `len/cap`, `alloc(*Sand)`, `in_degree_items([*]u32)`, `in_degree_cap(usize)` |

### Functions

#### DepGraph

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `depGraphInit` | pub | `[inference: zero-init DepGraph with undefined arrays]` | Creates empty `DepGraph`. Arrays allocated on first `depGraphAddEdge`. |
| `depGraphEnsureCapacity` | private | `[inference: 2x growth, sand alloc for DepEdge, min 8]` | Grows edge array. |
| `depGraphAddEdge` | pub | `[inference: ensure capacity, store DepEdge{from, to}, increment len]` | Appends `DepEdge` to graph. Used to record type dependencies (field → type). |
| `depGraphFinalize` | pub | `[inference: alloc in_degree array of size max_type_id+1, zero-init, count edges per target]` | Computes in-degree for each type ID. Allocates `in_degree_items[0..max_type_id]`, counts edges where `edge.to == tid`. Called by tests, not by the main pipeline. |

#### Internal Helpers

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `addTypeDependencies` | private | `[inference: iterate extra children of decl_idx, add dep edge for each field_decl → tid]` | Records type dependencies. For each `field_decl` extra child, adds `depGraphAddEdge(g, 0, tid)` — node 0 is a sentinel root. Returns early if the decl has no payload. |
| `populateTypePayload` | private | `[inference: switch on decl_kind, iterate extra children, append payload structs to TypeRegistry]` | Creates type stubs in `TypeRegistry`. See [Type Stub Population](#type-stub-population) below. |
| `registerDecl` | private | `[inference: switch on node.kind, create Symbol, insert into SymbolTable; populate guards stub creation]` | Registers a single declaration. See [Decl Registration Walkthrough](#decl-registration-walkthrough) below. |

#### Entry Point

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `registerModuleSymbols` | pub | `[inference: iterate resolved modules, walk module_root extra children, call registerDecl per decl; populate forwarded]` | **Phase entry point.** Iterates all modules in `ModuleRegistry`. For each `parsed`/`resolved` module with an `ast_root`, walks the `module_root` node's `extra_children` (top-level decls) and calls `registerDecl` for each, forwarding the `populate` flag. Module 0 dumps the `RS` debug marker with decl node indices and AstKind values. |

---

## Decl Registration Walkthrough

`registerDecl` (`symbol_registrator.zig`) switches on `node.kind`:

### `var_decl`

Sub-cases based on `child_1` (the init expression):

1. **Init is `import_expr`**: Resolves the target module via the `path_to_id` hash map. If found, creates `SymbolKind.module` with `type_id = typeRegistryGetOrCreateModule(mtid)`. Writes `M5:p<path_id>`, `Rs`, `FIX1:mid=<target_mtid>t=<target_mtid>n=<mod_id>` markers. If not found, writes the `Rf` (resolve failed) marker.

2. **Init is an inline type decl** (`struct_decl`/`enum_decl`/`union_decl`/`error_set_decl`): Registers the type via `typeRegistryRegisterNamedType`, calls `populateTypePayload` (when `populate=true`) to create type stubs, calls `addTypeDependencies` to record field→type edges. Packed struct/union (flag `0x10`) calls `typeRegistrySetPacked` (a packed union selects `TypeKind.packed_union_type`; a packed struct stays `struct_type`). Creates `SymbolKind.type_alias`.

3. **Init is `ident_expr`**: Looks up the type via `nameCacheGet`. If cached, creates `SymbolKind.type_alias` with the cached type ID and writes `RCA:p<ident_payload>`, `RCA:i<interned_name>`, `RCA:H<cached_type>` markers. On a cache miss, the identifier text is tested with `parseArbIntWidth`; if it names an arbitrary-width integer (`u1..u64` / `i1..i63`), `typeRegistryGetOrCreateArbInt` builds the TypeId, caches it, and the symbol registers as `SymbolKind.type_alias`.

   [updated: 2026-08-14] **Site-2 fix (fallback demotion, F-task):** the `ident_expr` alias branch now scopes its RHS type lookup to the **declaring module first** — `nameCacheGet(type_reg, (mod_id<<32)|ident_name_id)` — before falling back to the bare `nameCacheGet(type_reg, ident_name_id)` key (which holds primitives *and* module-0 named types). This mirrors `resolveTypeExprFull`'s current-module-first reorder (see 03_type_resolution.md); `pub const Bar = Foo` in module B now resolves B's own `Foo`, not module-0's.

4. **Init is an aggregate/pointer/fn type node** (`array_type`, `slice_type`, `many_ptr_type`, `ptr_type`, `optional_type`, `error_union_type`, `fn_type`): Writes `AT:p<name_id>`; looks the name up via `nameCacheGet` (module-qualified, then bare). If cached, stores the cached type ID; the symbol is always created as `SymbolKind.type_alias` (with `type_id = 0` when not cached, later back-filled by `phase_FrontResolution`). `ptr_type` nodes carry `const`/`volatile` qualifier bits in their flags; `fn_type` nodes carry the calling-convention bit (`stdcall`). Registration does not inspect these qualifier bits.

Default case (no special init): creates `SymbolKind.global`.

[updated: 2026-08-07] **`pub const` literal-init globals have NO storage slot (F3, commit 317f3a82):**
a top-level `pub const X: T = <literal>;` registers as `SymbolKind.global` (bit0 flag = mutable;
const has bit0 clear) but the storage-global collection (`main.zig`) only promotes a global to
a `ModuleGlobalDecl` (F-7 storage slot, `load_global`/`store_global` emission) when `decl.flags`
bit0 is set OR the init is NOT an `int_literal`/`float_literal`/`char_literal`. A literal-init const
gets NO storage slot — it is a compile-time value, not a runtime object. Cross-module refs to it are
folded at the ref site; same-module refs fold too (`lower.zig`). The
`ts.flags & 0x01` bit0 is checked in the cross-module field-access branch to distinguish const
(bit0 clear → fold) from mutable `pub var` (bit0 set → storage slot, `load_global`). Extern
declarations (`flags & 0x04`) are skipped by the storage-global collector entirely.

All var_decl symbols emit `Ra` (register alias), `D12:n<name_id>` (debug name dump), then `VD:<name_id>:<kind_enum>` and `Vi`; `VR` is written additionally only when the insert is rejected as a duplicate (`symbolTableInsert` returned `false` — happens on the pass-2 re-registration).

### `fn_decl`

Creates `SymbolKind.function` using `proto.name_id` from the function prototype (`store.fn_protos[node.payload]`). `FnProto` also carries `call_conv`, but registration does not use it.

### `test_decl`

Creates `SymbolKind.test_sym` if `node.payload != 0` (named test). Anonymous tests (`test {}`) are skipped.

### `struct_decl`, `enum_decl`, `union_decl`

Registers the type via `typeRegistryRegisterNamedType` (the `TypeKind` derives from the decl kind: `struct_type`/`enum_type`/`union_type`/`tagged_union_type`/`packed_union_type`; flag `0x10` selects packed and calls `typeRegistrySetPacked`), calls `populateTypePayload` for field/member stubs, calls `addTypeDependencies`, creates `SymbolKind.type_alias`. Union flag bit 0 distinguishes `union` vs `tagged_union`.

### `error_set_decl`

Registers error set type via `typeRegistryRegisterNamedType` with `TypeKind.error_set_type`, calls `populateTypePayload`, creates `SymbolKind.type_alias`.

### `import_expr`

Resolves target module via `path_to_id` hash map. If found, creates `SymbolKind.module` with `type_id = typeRegistryGetOrCreateModule(tid)`. Emits `IMR:n<path_id>m<mod_id>` marker.

### `else` default

No symbol is created. This is how `@cInclude` decls (`AstKind.c_include`) pass through registration silently.

---

## Type Stub Population

`populateTypePayload` (`symbol_registrator.zig`) creates skeleton type payloads in `TypeRegistry`. It returns early when the decl node has no payload or no extra children. The aggregate branches iterate the decl node's extra children to find `field_decl` nodes.

### struct_decl

Iterates children, calls `feAppend` for each `field_decl` (with `name_id = fd.payload`, `type_id = TYPE_VOID`, `offset = 0`), then, when at least one field was found, calls `stAppend` with `StructPayload{fields_start, fields_count}`. Back-patches `payload_idx` on the just-registered type. `stAppend` also appends an empty `PackedStructInfo` to the `pk_struct` side table (packed layout is computed later in `type_registry.zig`).

### union_decl

Same field iteration as struct. If `node.flags & 1 != 0` (tagged union): calls `tuAppend` with `TaggedUnionPayload{tag_type = TYPE_U32, fields_start, fields_count}`. Else: calls `unAppend` with `UnionPayload{fields_start, fields_count, tag_type = TYPE_VOID}`; `unAppend` also appends an empty `PackedStructInfo` to the `pk_un` side table. Back-patches `payload_idx`.

### enum_decl

Creates a `TypeResolveEnv` for backing-type resolution. If `node.child_0 != 0`, resolves the backing integer type via `resolveTypeExprFull` and records `explicit_backing = 1`; otherwise the backing defaults to `TYPE_U32`. Iterates children: for each `field_decl`, auto-increments the value (starting at 0, i64) unless `mnode.child_1` provides an explicit value via `evalConstI64Full`. Calls `emAppend` with `EnumMember{name_id, value}`, then `enAppend` with `EnumPayload{members_start, members_count, backing_type, explicit_backing}`. Back-patches `payload_idx`.

### error_set_decl

Iterates children, calls `xnAppend` for each child node index (tags are node indices into AST, not interned names). Calls `esAppend` with `ErrorSetPayload{tags_start, tags_count}` (`tags_count` = child count). Back-patches `payload_idx`.

---

## Data Flow

```
phase_SymbolRegistration (main.zig)
    │
    │  marker: "S\n"
    │  scratch arena reset
    │
    ├─ depGraphInit(&scratch)   [scratch-local; discarded at phase end]
    │
    ├─ LOOP over all modules (by ascending ID):
    │   │
    │   ▼
    │   registerModuleSymbols (symbol_registrator.zig, populate=true)
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
    │           registerDecl (symbol_registrator.zig)
    │               │
    │               ├─ switch on node.kind:
    │               │   ├─ var_decl → SymbolKind.{global|module|type_alias}
    │               │   │   └─ init type decl? → populateTypePayload + addTypeDependencies
    │               │   │   └─ init import_expr? → SymbolKind.module via path_to_id
    │               │   │   └─ init ident_expr? → nameCacheGet (module-first) → SymbolKind.type_alias
    │               │   │   │   └─ miss + arbitrary-width name (uN/iN)? → typeRegistryGetOrCreateArbInt
    │               │   │   └─ init ptr/array/slice/optional/error-union/fn type? → nameCacheGet → SymbolKind.type_alias
    │               │   ├─ fn_decl → SymbolKind.function (proto.name_id)
    │               │   ├─ test_decl → SymbolKind.test_sym (if named)
    │               │   ├─ struct_decl/enum_decl/union_decl → typeRegistryRegisterNamedType
    │               │   │   └─ populateTypePayload + addTypeDependencies
    │               │   │   └─ SymbolKind.type_alias (+ typeRegistrySetPacked when packed)
    │               │   ├─ error_set_decl → typeRegistryRegisterNamedType
    │               │   │   └─ populateTypePayload + SymbolKind.type_alias
    │               │   └─ import_expr → SymbolKind.module (path_to_id lookup)
    │               │
    │               └─ symbolRegistryGetTable(mod_id) → SymbolTable
    │                   └─ symbolTableInsert(sym) → bool (false = duplicate)
    │
    └─ "S0" marker dump (root module 0 decl kinds)
```

**Double registration:** `phase_TypeResolution` (`main.zig`) re-runs the whole loop — marker
`"T\n"`, then `registerModuleSymbols` for every module into a fresh
`depGraphInit`. This is the "re-register" pass: `registerModuleSymbols` is called with
`populate=false` (2026-07-31 F3 fix), which skips `populateTypePayload` but still runs
`addTypeDependencies` to rebuild the DepGraph. Symbol inserts are all rejected as duplicates (`VR`),
named-type / module-type registration dedups (no new `DC`/`MC`). The pass-2 graph is consumed
within `phase_TypeResolution` by `typeResolverBuild`/`typeResolverResolve` — it is not handed off
from phase 2 (phase 2's graph is scratch-local and discarded).

**`phase_FrontResolution` interaction:** after `phase_TypeResolution`, `phase_FrontResolution`
(`main.zig`) calls `frontResolveModuleInits` (`front_resolution.zig`). It resolves module-level
`var_decl` type annotations and init expressions, then back-fills the `type_id` of
`SymbolKind.global` / `SymbolKind.type_alias` symbols that registration left at 0 (registration
cannot always resolve a type: `fn_decl` always stores 0, and the `ident_expr`/aggregate-type
branches store 0 on a cache miss). It also promotes a var symbol to `SymbolKind.type_alias` when
its `ident_expr` initializer resolves to an existing type alias, and seeds `nameCache` entries. The
fixed-point loop is bounded by `countUntypedGlobals` (symbols with `type_id == 0`).

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

DepGraph (scratch arena, scratch-local per phase)
    │
    ├─ items[0..len]: DepEdge{from, to}
    └─ in_degree_items[0..max_type_id]: u32 in-degree counts (via depGraphFinalize)

TypeRegistry (permanent arena, updated with stubs)
    │
    ├─ Type entries with payload_idx → StructPayload / UnionPayload / TaggedUnionPayload / EnumPayload / ErrorSetPayload
    ├─ FieldEntry array (fe)
    ├─ EnumMember array (em)
    ├─ Error tag indices (xn)
    └─ Packed-layout side tables (pk / pk_struct / pk_un), seeded empty by stAppend/unAppend
```

---

## Debugging

### Phase Entry/Exit Markers

| Marker | Location | Description |
|--------|----------|-------------|
| `S` | `phase_SymbolRegistration` (`main.zig`) | Phase entry — start of symbol registration |
| `S0` | `phase_SymbolRegistration` (`main.zig`) | Root module (0) decl kind listing — writes AstKind enum values |
| `T` | `phase_TypeResolution` (`main.zig`) | Phase entry — re-registration pass |
| `T0` | `phase_TypeResolution` (`main.zig`) | Root module (0) decl kind listing |

### Declaration Registration Markers (symbol_registrator.zig)

| Marker | Description |
|--------|-------------|
| `RS` | Module-0 top-level decl dump — node-index `=` AstKind value pairs, written by `registerModuleSymbols` |
| `Ra` | Register alias — var_decl registration start |
| `D12:n<name_id>` | Debug name dump — var_decl name_id |
| `M5:p<path_id>` | Module import — path ID of import_expr payload |
| `Rs` | Register symbol — import_expr target resolved |
| `FIX1:mid=<target>t=<target>n=<mod_id>` | Fixup debug — resolved target module id (`mid` and `t`) and declaring module id (`n`) |
| `Rf` | Register failed — import_expr target not in `path_to_id` |
| `RCA:p<payload>` | Register const alias — init.ident payload |
| `RCA:i<name_id>` | Register const alias — resolved ident name_id |
| `RCA:H<type_id>` | Register const alias — cache hit type ID |
| `AT:p<name_id>` | Aggregate/pointer/fn type alias — var_decl with an inline `ptr_type`/`many_ptr_type`/`array_type`/`slice_type`/`optional_type`/`error_union_type`/`fn_type` init |
| `VR` | Variable register — duplicate insert (`symbolTableInsert` returned false) |
| `VD:<name_id>:<kind_enum>` | Variable dump — name_id and `SymbolKind` numeric value |
| `Vi` | Variable info — end of var_decl registration |
| `IMR:n<path_id>m<mod_id>` | Import module registered — path_id and resolved module ID |

Type-registry markers emitted while registering named types / modules: `RN:m<mod_id>n<name_id>k<kind>t<tid>` (`typeRegistryRegisterNamedType`), `DC:k<kind>n<name_id>t<id>` (`typeRegistryAppend`), `X:<id>` (struct append), `MC` (`typeRegistryGetOrCreateModule`), `NP:k<key>v<value>` (`nameCachePut`), and `NGC:g1<val>` (`nameCacheGet`).

### Diagnostic Error Codes

(None emitted during symbol registration — type errors surface in phase 3.)

### Known Issues

1. **Linear dedup O(n)** (`symbol_table.zig`): `symbolTableInsert` does a full linear scan of the table for every insert. Per-module tables grow unbounded; worst-case O(n²) across all inserts in a module.

2. **No local/param symbol registration during phase 2** (`symbol_table.zig`): `SymbolKind.local` and `SymbolKind.param` are defined but never used in this phase — they are reserved for semantic analysis (phase 5).

3. **Duplicate `VR` marker on re-insert** (`symbol_registrator.zig`): If `symbolTableInsert` returns `false` (duplicate name), only a debug marker is written — no error diagnostic is emitted. Duplicates silently shadow rather than producing a compile error.

4. **Sentinel root node (from=0) in DepGraph** (`symbol_registrator.zig`): `addTypeDependencies` always uses `from=0` as a sentinel. Type resolution must handle this convention — `tid=0` is not a valid type ID, it means "root/dummy".

5. **Scratch arena dependency** (`phase_SymbolRegistration`, `main.zig`): `DepGraph` is allocated in the scratch arena and invalidated on the next phase's `sandReset`. In practice moot: `phase_TypeResolution` resets scratch itself and re-runs the identical `registerModuleSymbols` loop (`populate=false`), rebuilding an equivalent graph within the same phase, so no phase-2 snapshot is relied upon.

6. **[FIXED 2026-07-31]** **Pass-2 payload duplication on re-registration** (`symbol_registrator.zig`, fixed by F3): `registerModuleSymbols` runs twice — once in `phase_SymbolRegistration` with `populate=true` and again inside `phase_TypeResolution` with `populate=false`. The second pass skips `populateTypePayload` (guarded by the `populate` flag at each `registerDecl` call site), so payload arrays are NOT doubled and the back-patch clobber of `types_items[types_len-1].payload_idx` no longer occurs. `addTypeDependencies` still runs in both passes to rebuild the DepGraph for phase 3. Regression test: `testPayloadStabilityAfterDoublePass` in `sf/src/tests/test_sym_reg_bin.zig` asserts `st_len`/`tu_len`/`es_len`/`fe_len`/`xn_len` and `payload_idx` stability across the double pass.

7. **`symbolRegistryQualifiedLookup` mutates the registry** (`symbol_table.zig`): the lookup routes through `symbolRegistryGetTable`, which creates (and grows) a `SymbolTable` for any module id it has not seen. A pure read therefore has a side effect; callers that query an unregistered module id silently materialize an empty table.

8. **Symbols may register with `type_id = 0`** (`symbol_registrator.zig`): the aggregate/pointer/fn-type (`AT`) branch always creates a `SymbolKind.type_alias` but leaves `type_id = 0` when the type is not yet in the name cache; the `ident_expr` branch likewise leaves `type_id = 0` on a non-arbitrary-width cache miss (the symbol stays `SymbolKind.global`). `phase_FrontResolution` (`front_resolution.zig`) back-fills the type ID and promotes the symbol to `type_alias` when its initializer resolves to one — see the interaction note under Data Flow.
