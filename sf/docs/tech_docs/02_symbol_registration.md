# 02 — Symbol Registration

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `SymbolKind` variants | 7 | `local(0)`, `param(1)`, `global(2)`, `function(3)`, `type_alias(4)`, `module(5)`, `test_sym(6)` |
| `Symbol` fields | 7 | name_id, type_id, kind, flags, decl_node, module_id, scope_level |
| Decl kinds registered | 7 | var_decl, fn_decl, test_decl, struct_decl, enum_decl, union_decl, error_set_decl |
| `DepGraph` edge items | dynamic | Flat array of `DepEdge`, 2x growth, min 8 |
| `SymbolTable` per module | lazy | Created on first `symbolRegistryGetTable(mod_id)` access |
| Type stubs populated | 4 kinds | All 4 back-patch paths exist (StructPayload, UnionPayload/TaggedUnionPayload, EnumPayload, ErrorSetPayload); the 4 examples populate only StructPayload + TaggedUnionPayload + ErrorSetPayload (see Evidence) |
| Debug markers | ~15+ | Phase: `S`, `S0`, `T`, `T0`; registration: `RS`, `Ra`, `D12`, `M5`, `Rs`, `Rf`, `FIX1`, `RCA`, `VR`, `VD`, `Vi`, `IMR`; type-registry (from type_registry.zig): `MC`, `DC`, `X`, `NP`, `RN`, `NGC` |

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

All var_decl symbols emit `Ra` (register alias), `D12:n<name_id>` (debug name dump), then `VD:<name_id>:<kind_enum>` and `Vi`; `VR` is written additionally only when the insert is rejected as a duplicate (`symbolTableInsert` returned `false` — happens on the pass-2 re-registration, see Evidence).

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

### `else` default (line 395)

No symbol is created. This is how `@cInclude` decls (`AstKind.c_include`, all 4 examples have 2-3
top-level) pass through registration silently. Of the 7 switch cases, only `var_decl`, `fn_decl`
and `else` are exercised by the 4 examples — `test_decl`, standalone `struct_decl`/`enum_decl`/
`union_decl`, standalone `error_set_decl` and standalone `import_expr` fire nowhere (see Known
Issue 7).

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

**Double registration:** `phase_TypeResolution` (main.zig:289) re-runs the whole loop — marker
`"T\n"` (main.zig:290), then `registerModuleSymbols` for every module (main.zig:296) into a fresh
`depGraphInit`. This is the "re-register" pass: symbol inserts are all rejected as duplicates
(`VR`), named-type / module-type registration dedups (no new `DC`/`MC`), and `populateTypePayload`
re-appends duplicate payload entries (see Known Issue 6). Phase 3's type resolution consumes the
pass-2-built graph (edge counts identical in both passes, verified in Evidence).

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

6. **Pass-2 payload duplication on re-registration** (symbol_registrator.zig:84, verified `[fprintf]`): `registerModuleSymbols` runs twice — once in `phase_SymbolRegistration` (main.zig:266) and again inside `phase_TypeResolution` (main.zig:296). The second run re-executes `populateTypePayload`, so every payload array (`fe`, `em`, `xn`, `st`, `tu`, `un`, `en`, `es`) is appended to AGAIN with identical entries, and the back-patch `types_items[types_len-1].payload_idx = <new idx>` (symbol_registrator.zig:112-116, :140-155, :189-193, :205-209) targets the *last type in the registry* — which in pass 2 is NOT the type being re-registered (named-type dedup at type_registry.zig:631 returns the existing id without appending). Observed: json_parser `fe` grows 11→22 and `xn` 11→22 across the two passes; the last registered type (json `Parser`) ends with `payload_idx` pointing at pass-2 duplicates. The duplicated entries are identical (`FieldEntry{name_id, TYPE_VOID, 0}` placeholders) and phase 3 re-resolves fields from the AST by name, so the 4 examples still compile/run correctly — but the payload arrays ~double in size and the final type's `payload_idx` is re-pointed. Latent corruption, not yet observable as a miscompile.

7. **Standalone struct/enum/union/error_set/test/import_expr cases not exercised by the 4 examples** (verified `[markers]` + `[fprintf]`): every top-level decl in all 4 examples is `var_decl`, `fn_decl`, or `c_include` (AstKind 1/2/96 in the `RS`/`S0` dumps); all type declarations are `const X = struct/enum/union(enum)/error{...}` — i.e. a var_decl with an inline-type init. The `test_decl` (symbol_registrator.zig:319), standalone `struct_decl`/`enum_decl`/`union_decl` (:334), standalone `error_set_decl` (:357) and standalone `import_expr` (:373) cases exist in the switch but fire nowhere in these examples.

---

## Evidence: 4 Working Examples (Deep-Dive P2)

Traces: `/tmp/dd/*.mrk` (P0, `zig1 --markers --dump-c89`). Per-module symbol counts/names and
payload counts obtained by fprintf-instrumenting a bootstrap rebuild of the same
`sf/src/main.zig` into `/tmp/z1` (scratch only, `[fprintf]`) and running it with `--markers`.
`RS`/`S0`/`T0` dump lines are `[markers]`.

### Per-module symbol tables (fprintf `[fprintf]`)

`registerModuleSymbols` was instrumented to print each module's `SymbolTable` after registration
(`MODREG mod=<id> len=<n> g=<globals> f=<functions> ta=<type_aliases> m=<modules>`). `decls(m0)`
= root module top-level decl-kind counts from the `RS` marker (module 0 only). `var_decl`
registers into `global`+`type_alias`+`module` combined; `fn_decl` → `function`.

| Example | mod | file | total | function | global | type_alias | module | decls(m0) |
|---------|:---:|------|:-----:|:--------:|:------:|:----------:|:------:|-----------|
| mud_server | 0 | main.zig | 26 | 16 | 4 | 4 | 2 | 10 var / 16 fn / 2 c_include |
| mud_server | 1 | std.zig | 1 | 0 | 0 | 0 | 1 | - |
| mud_server | 2 | util.zig | 2 | 2 | 0 | 0 | 0 | - |
| mud_server | 3 | std_debug.zig | 2 | 2 | 0 | 0 | 0 | - |
| game_of_life | 0 | main.zig | 12 | 7 | 2 | 2 | 1 | 5 var / 7 fn / 2 c_include |
| game_of_life | 1 | std.zig | 1 | 0 | 0 | 0 | 1 | - |
| game_of_life | 2 | std_debug.zig | 4 | 4 | 0 | 0 | 0 | - |
| json_parser | 0 | main.zig | 10 | 7 | 1 | 0 | 2 | 3 var / 7 fn / 3 c_include |
| json_parser | 1 | file.zig | 14 | 10 | 2 | 2 | 0 | - |
| json_parser | 2 | json.zig | 20 | 15 | 0 | 4 | 1 | - |
| lisp_interpreter_curr | 0 | main.zig | 19 | 8 | 2 | 0 | 9 | 11 var / 8 fn / 2 c_include |
| lisp_interpreter_curr | 1 | sand.zig | 5 | 3 | 0 | 1 | 1 | - |
| lisp_interpreter_curr | 2 | value.zig | 10 | 7 | 0 | 1 | 2 | - |
| lisp_interpreter_curr | 3 | token.zig | 9 | 6 | 0 | 2 | 1 | - |
| lisp_interpreter_curr | 4 | parser.zig | 6 | 2 | 0 | 0 | 4 | - |
| lisp_interpreter_curr | 5 | env.zig | 7 | 3 | 0 | 1 | 3 | - |
| lisp_interpreter_curr | 6 | eval.zig | 9 | 4 | 0 | 0 | 5 | - |
| lisp_interpreter_curr | 7 | builtins.zig | 14 | 11 | 0 | 0 | 3 | - |
| lisp_interpreter_curr | 8 | util.zig | 4 | 3 | 0 | 1 | 0 | - |
| lisp_interpreter_curr | 9 | deep_copy.zig | 4 | 1 | 0 | 0 | 3 | - |

Totals: mud_server 31 symbols / 4 modules, game_of_life 17 / 3, json_parser 44 / 3,
lisp_interpreter_curr 87 / 10. Every symbol is inserted once in pass 1 (dedup accepts) and
rejected in pass 2 (`VR`); the tables are byte-identical after both passes.

Representative excerpt (`[fprintf]`, json_parser pass 1):

```
MODREG mod=2 len=20 g=0 f=15 ta=4 m=1
SYM mod=2 name=file kind=5 type=21 decl=294
SYM mod=2 name=JsonItem kind=4 type=24 decl=303
SYM mod=2 name=JsonValue kind=4 type=25 decl=319
SYM mod=2 name=ParseError kind=4 type=26 decl=321
SYM mod=2 name=Parser kind=4 type=27 decl=331
...
```

### DepGraph evidence

Edges are added only by `addTypeDependencies` (symbol_registrator.zig:70-82), one per `field_decl`
child, always with `from=0` (sentinel) and `to=<type_id>`. Edge counts therefore equal the total
field counts of the aggregate types. fprintf `DEPGRAPH phaseS edges=N` and `DEPGRAPH phaseT
edges=N`:

| Example | edges (pass 1 == pass 2) | Sources (fields / variants / tags) |
|---------|:------------------------:|------------------------------------|
| mud_server | 15 | plat_fd_set(1) + Player(5) + Room(5) + Command(4) |
| game_of_life | 4 | Cell(2) + Point(2) |
| json_parser | 11 | JsonItem(2) + JsonValue(6) + Parser(3) — error sets contribute 0 |
| lisp_interpreter_curr | 19 | Sand(3) + Value(6) + Token(5) + Tokenizer(2) + EnvNode(3) — LispError contributes 0 |

Cycles: **none**. Because every edge has `from=0`, no type→type edge exists in the graph, so a
cycle is structurally impossible. `typeResolverResolve` reports
`ERR_3005_CIRCULAR_TYPE_DEPENDENCY` (type_resolver.zig:306-320) only if an in-degree > 0 survives
the worklist drain; grep for `circular type dependency` in all four traces = 0 hits. `[fprintf]` +
`[markers]`

### Type stubs populated (`S0`/`RS`/`DC:k<TypeKind>` markers)

`DC:k<kind>n<name>t<id>` fires per `typeRegistryAppend` (type_registry.zig:158-170); `X:<id>` per
struct append (:171-172); `RN:` per named-type registration (:645-654). Payload contents confirmed
with `PAY <kind> decl=<n> ...` `[fprintf]`. Per example, only the types actually declared get a
payload:

| Example | StructPayload (fields) | TaggedUnionPayload (variants) | ErrorSetPayload (tags) |
|---------|:----------------------:|:-----------------------------:|:----------------------:|
| mud_server | plat_fd_set(1), Player(5), Room(5) | Command(4) | - |
| game_of_life | Point(2) | Cell(2) | - |
| json_parser | JsonItem(2), Parser(3) | JsonValue(6) | FileError(4), ParseError(7) |
| lisp_interpreter_curr | Sand(3), Tokenizer(2), EnvNode(3) | Value(6), Token(5) | LispError(22) |

`fe` (FieldEntry) totals per pass: mud 15, gol 4, json 11, lisp 19 (49 across examples). `xn`
(error-tag indices) per pass: json 11, lisp 22 (33). **No example declares an `enum` or a plain
`union`**, so EnumPayload and UnionPayload back-patch paths (symbol_registrator.zig:118-157,
:158-194) are never populated here. `RS` module-0 decl-kind dump (mud_server pass 1, quoted):
`RS18939932:2=1 4=1 5=96 6=96 ... 842=2` (one per pass).

### Double registration: pass 1 vs pass 2

`registerModuleSymbols` runs in BOTH `phase_SymbolRegistration` (main.zig:266) and
`phase_TypeResolution` (main.zig:296). The marker streams differ:

| Marker | Pass 1 (S..S0) | Pass 2 (T..) | Cause |
|--------|:--------------:|:------------:|-------|
| `S\n` / `T\n` (phase entry) | `S` | `T` | main.zig:260 / :290 |
| `VR` (duplicate insert) | none | every var_decl | `symbolTableInsert` rejects (symbol_table.zig:55) |
| `DC:k...`, `X:`, `RN:`, `NP:`, `MC`/`MCDC` (new type) | present | absent | named-type / module-type dedup (type_registry.zig:631, :559-565) |
| `RCA:p/i/H` (ident alias) | present | present again | `nameCacheGet` re-runs (symbol_registrator.zig:259-271) |
| `RS` (module-0 dump) | present | present | symbol_registrator.zig:406 |

Symbol tables after both passes are identical (dedup keeps pass-1 entries). Payload arrays are NOT
idempotent — see Known Issue 6.

### Q5: lisp `LispError` error-set registration

`util.zig:1-24` declares `pub const LispError = error { ...22 members... }`. In the AST this is
`var_decl` (node 910) whose `child_1` is `error_set_decl` (node 909), so registration flows through
the **var_decl inline-type path** (symbol_registrator.zig:246-258), not the standalone
`error_set_decl` case (:357):

1. `typeRegistryRegisterNamedType(m8, name_id=156, TypeKind.error_set_type)` → `t35` (marker
   `DC:k23n156t35`).
2. `populateTypePayload(error_set_decl, 909)` — every child (error-tag literal node) is appended to
   `xn[]` (`xnAppend`, symbol_registrator.zig:198-200); `esAppend` records
   `ErrorSetPayload{tags_start=0, tags_count=22}`. `[fprintf]`:
   `PAY error_set decl=909 tags_start=0 tags_count=22`. Members ARE populated at this stage — as
   AST **node indices**, not interned names (see doc :140-142).
3. `addTypeDependencies` adds no edge (error-tag children are not `field_decl`).
4. Symbol inserted: `SymbolKind.type_alias`, `type_id=t35` (`[fprintf]`:
   `SYM mod=8 name=LispError kind=4 type=35 decl=910`; marker `VD156:4`).

### Questionnaire answers (all with evidence)

1. Per-module symbol counts + decl-kind distribution — tables above. `[fprintf]` + `[markers]`
2. DepGraph edges: mud 15, gol 4, json 11, lisp 19 (identical in both passes). No cycles possible
   (all edges `from=0`); 0 `ERR_3005` diagnostics. `[fprintf]` + `[markers]`
3. Type stubs: 9 StructPayload + 5 TaggedUnionPayload + 3 ErrorSetPayload populated across the 4
   examples per pass; no EnumPayload or plain UnionPayload. `[markers]` + `[fprintf]`
4. Double registration IS observable and the markers differ: `VR` appears only in pass 2; new-type
   markers (`DC`/`X`/`MC`/`RN`/`NP`) only in pass 1; `RCA` re-fires; phase-entry `S` vs `T`.
   `[markers]`
5. LispError: var_decl inline error_set path; 22 members populated as node indices in `xn[]`
   (`ErrorSetPayload{0, 22}`) at registration time. `[markers]` + `[fprintf]`
6. Tech doc 7 AstKind cases: all documented cases match source line numbers (see inaccuracies
   table); the `else => {}` default (symbol_registrator.zig:395, which silently skips `c_include`)
   is undocumented, and only `var_decl`, `fn_decl` and `else` are exercised by the 4 examples
   (Known Issue 7). `[markers]` + `[fprintf]`

### Doc inaccuracies found (item 6)

| Doc location | Claim | Reality |
|--------------|-------|---------|
| this doc :12 | "Type stubs populated | 4 | StructPayload, UnionPayload/TaggedUnionPayload, EnumPayload, ErrorSetPayload" | Only StructPayload, TaggedUnionPayload and ErrorSetPayload are populated by the 4 examples (no enum / plain union declared). All 4 back-patch code paths exist. |
| this doc :13 | Debug-markers list omits `RS`, `D12`, `MC`, `DC`, `X`, `NP`, `RN`, `NGC` | All fire during registration: type_registry.zig:161 (DC), :172 (X), :308 (NGC), :318 (NP), :574-575 (MC/MCDC), :648 (RN); symbol_registrator.zig:219 (D12), :406 (RS). |
| this doc :100 | "then `VR`/`VD`/`Vi`" (implies `VR` on every var_decl) | `VR` fires only on duplicate reject (symbol_registrator.zig:286-289); pass 1 has zero `VR`, pass 2 has one per var_decl. |
| this doc Data Flow (:156-192) | Phase 3 "consumes" the phase-2 DepGraph | Phase 3 re-runs `registerModuleSymbols` and rebuilds the graph itself (main.zig:296); both graphs are identical (same edge counts, verified `[fprintf]`). |
