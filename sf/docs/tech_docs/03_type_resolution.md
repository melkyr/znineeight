# 03 — Type Resolution

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `TypeId` sentinels | 20 | TYPE_VOID(1) through TYPE_TYPE(20) |
| `TypeKind` variants | 36 | none_sentinel(0) through anon_union(35) |
| `Type` fields | 9 | kind, state, flags, _pad, size, alignment, name_id, c_name_id, module_id, payload_idx |
| Payload structs | 13 | PtrPayload, ArrayPayload, SlicePayload, OptionalPayload, EUPayload, ErrorSetPayload, FnPayload, StructPayload, EnumPayload, UnionPayload, TaggedUnionPayload, TuplePayload, UnresolvedPayload |
| Per-kind payload arrays | 13 | ptr/array/slice/opt/eu/es/fn/st/en/un/tu/tup/unr |
| Auxiliary arrays | 4 | fe(FieldEntry), em(EnumMember), xt(TypeId list), xn(u32 list) |
| Type caches | 8 | ptr_cache, many_ptr_cache, slice_cache, optional_cache, array_cache, eu_cache, es_cache, name_cache |
| TypeResolver fields | 9 | registry, depend_items/len/cap, in_degree_items/cap, sorted_items/len, worklist_items/len/cap, diag, alloc |
| Layout kinds resolved | 8 | struct, enum, union, tagged_union, optional, error_union, array, tuple |
| Debug markers | ~25+ | `DC`, `NP`, `U2H`, `U2N`, `O0`, `O1`, `O2`, `P2`, `RN`, `PTR`, `SL`, `T0`-`T3`, `A`, `CAP`, `CAT`, `GATE`, `KAHN`, `CLS`, `RTD`, `FAH`, `FER`, `FSW`, `DFT`, `FTW`, `B2` |

---

## TypeId Sentinel Values

All `type_registry.zig:11-37`:

| Sentinel | Value | Size (bytes) | Alignment (bytes) |
|----------|-------|-------------|-------------------|
| `TYPE_VOID` | 1 | 0 | 0 |
| `TYPE_BOOL` | 2 | 4 | 4 |
| `TYPE_NORETURN` | 3 | 0 | 0 |
| `TYPE_I8` | 4 | 1 | 1 |
| `TYPE_I16` | 5 | 2 | 2 |
| `TYPE_I32` | 6 | 4 | 4 |
| `TYPE_I64` | 7 | 8 | 8 |
| `TYPE_U8` | 8 | 1 | 1 |
| `TYPE_U16` | 9 | 2 | 2 |
| `TYPE_U32` | 10 | 4 | 4 |
| `TYPE_U64` | 11 | 8 | 8 |
| `TYPE_ISIZE` | 12 | 4 | 4 |
| `TYPE_USIZE` | 13 | 4 | 4 |
| `TYPE_C_CHAR` | 14 | 1 | 1 |
| `TYPE_F32` | 15 | 4 | 4 |
| `TYPE_F64` | 16 | 8 | 8 |
| `TYPE_NULL` | 17 | 0 | 0 |
| `TYPE_UNDEFINED` | 18 | 0 | 0 |
| `TYPE_INT_LIT` | 19 | 0 | 0 |
| `TYPE_TYPE` | 20 | 0 | 0 |

Synthetic field indices: `SLICE_FIELD_PTR=0`, `SLICE_FIELD_LEN=1`, `TU_FIELD_TAG=0`, `TU_FIELD_PAYLOAD=1`.

`FIRST_USER_TYPE = 20` — first non-sentinel TypeId allocated by the compiler.

---

## type_registry.zig (`sf/src/type_registry.zig`, 897 lines)

Central type store. Flat arrays of `Type` entries indexed by `TypeId` (u32). Per-kind payload arrays hold variable-length data.

### Types

| Type | Line | Description |
|------|------|-------------|
| `TypeId` | 9 | `u32` alias — index into `TypeRegistry.types_items` |
| `TypeKind` (enum u8) | 40 | 36 variants: none_sentinel(0), void/bool/noreturn/i8/i16/i32/i64/u8/u16/u32/u64/isize/usize/c_char/f32/f64, ptr/many_ptr/array/slice/optional/error_union/error_set/fn/struct/enum/union/tagged_union/tuple/unresolved_name/type_type/module_type/null_type/undefined_type/integer_literal_type/anon_struct_init/anon_array/anon_tuple/anon_union |
| `Type` (struct) | 58 | `kind(TypeKind, 1B)`, `state(u8, 0=unresolved, 2=resolved)`, `flags(u8)`, `_pad(u8)`, `size(u32)`, `alignment(u32)`, `name_id(u32)`, `c_name_id(u32)`, `module_id(u32)`, `payload_idx(u32)` — 28 bytes total |
| `PtrPayload` | 71 | `base: TypeId` — shared by ptr_type and many_ptr_type |
| `ArrayPayload` | 72 | `elem: TypeId`, `length: u32` |
| `SlicePayload` | 73 | `elem: TypeId` |
| `OptionalPayload` | 74 | `payload: TypeId` |
| `EUPayload` | 75 | `payload: TypeId`, `error_set: TypeId` |
| `ErrorSetPayload` | 76 | `tags_start: u16`, `tags_count: u16` |
| `FnPayload` | 77 | `name_id, module_id, return_type: TypeId`, `params_start/count: u16`, `is_extern: u8`, `flags_packed: u8` |
| `StructPayload` | 78 | `fields_start: u16`, `fields_count: u16` |
| `EnumPayload` | 79 | `members_start/count: u16`, `backing_type: TypeId` |
| `UnionPayload` | 80 | `fields_start/count: u16`, `tag_type: TypeId` |
| `TaggedUnionPayload` | 81 | `tag_type: TypeId`, `fields_start/count: u16` |
| `TuplePayload` | 82 | `elems_start: u16`, `elems_count: u16` |
| `UnresolvedPayload` | 83 | `name_id, module_id: u32` |
| `FieldEntry` | 84 | `name_id, type_id: u32`, `offset: u32` |
| `EnumMember` | 85 | `name_id: u32`, `value: i64` |
| `FnParam` | 86 | `name_id: u32`, `type_id: u32` |

### TypeRegistry struct

`type_registry.zig:88-123`:

- **types**: `items([*]Type)`, `len`, `cap`, `alloc(*Sand)` — the master type array; TypeId is the index
- **Per-kind payload arrays**: `ptr/array/slice/opt/eu/es/fn/st/en/un/tu/tup/unr` — each with `_items([*]PayloadType)`, `_len(usize)`, `_cap(usize)`
- **Auxiliary arrays**: `fe(FieldEntry)`, `em(EnumMember)`, `xt(TypeId)`, `xn(u32)`
- **Caches**: 8 hash maps — `ptr_cache(U64ToU32Map)`, `many_ptr_cache(U64ToU32Map)`, `slice_cache(U64ToU32Map)`, `optional_cache(U32ToU32Map)`, `array_cache(U64ToU32Map)`, `eu_cache(U64ToU32Map)`, `es_cache(U64ToU32Map)`, `name_cache(U64ToU32Map)`

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `typeRegistryInit` | 271 | pub | `[inference: zero-init all arrays, init 8 caches via u64ToU32MapInit/u32ToU32MapInit, return TypeRegistry]` | Creates empty registry. Arrays start with undefined/null items, len=cap=0. All 8 hash maps initialized. |
| `typeRegistryAppend` | 153 | private | `[inference: ensure capacity, write Type at types_len, increment len, emit DC:k<n>t marker, emit X:id for struct_type]` | Core append to `types_items`. Returns the new `TypeId` (old `types_len`). Emits `DC:k<kind_enum>n<name_id>t<type_id>` debug marker. For struct_type, also emits `X:<id>`. |
| `registerPrimitive` | 246 | private | `[inference: call typeRegistryAppend with state=2, given kind/size/alignment, zero name_id/c_name_id/module_id/payload_idx]` | Appends a resolved (state=2) primitive type. |
| `typeRegistryRegisterPrimitives` | 579 | pub | `[inference: registerPrimitive for 20 primitives (1-20), then registerPrimitiveName for named ones]` | Populates sentinel TypeIds 1-20. Calls `registerPrimitiveName` for void, bool, i8-i64, u8-u64, isize, usize, c_char, f32, f64, null, undefined, type. |
| `registerPrimitiveName` | 621 | private | `[inference: interner.intern name, set Type.name_id, nameCachePut(key=name_id, value=tid)]` | Interns a primitive type name and registers it in `name_cache` (key=name_id only, module_id=0). |
| `typeRegistryRegisterNamedType` | 629 | pub | `[inference: compute key = module_id*2^32 + name_id, nameCacheGet check, typeRegistryAppend with kind+name_id+module_id, nameCachePut, emit RN:m<n>k<t> marker]` | Registers a user-defined named type (struct, enum, union, etc.). Key is `(module_id << 32) | name_id`. State=0 (unresolved). |
| `typeRegistryGetOrCreatePtr` | 326 | pub | `[inference: key = (base << 1) | is_const(0/1), ptr_cache check, ptrAppend, typeRegistryAppend(PtrPayload{base}), ptr_cache put, return tid]` | Creates or retrieves `*T` type. Size=4, align=4, flags=const. |
| `typeRegistryGetOrCreateManyPtr` | 342 | pub | `[inference: same as ptr but many_ptr_cache, kind=many_ptr_type]` | Creates or retrieves `[*]T` type. |
| `typeRegistryGetOrCreateSlice` | 358 | pub | `[inference: key = (elem << 1) | is_const, slice_cache check, emit U2H hit or U2N new marker, sliceAppend, typeRegistryAppend(size=8,align=4), cache put]` | Creates or retrieves `[]T` type. Size=8 (ptr+len), align=4. |
| `typeRegistryGetOrCreateOptional` | 388 | pub | `[inference: optional_cache check, if payload resolved compute size/align via alignUp(payload.size,4)+4 with pay_align, optAppend, typeRegistryAppend, cache put only if state=2]` | Creates `?T`. If payload resolved, `size = alignUp(alignUp(payload.size,4)+4, max(payload.align,4))`. |
| `typeRegistryGetOrCreateErrorUnion` | 412 | pub | `[inference: eu_key = (payload<<32) | error_set, eu_cache check, compute union_size=max(payload.size,4), total = alignUp(alignUp(union_size, union_align),4)+4, euAppend, typeRegistryAppend, cache put]` | Creates `E!T` error union type. |
| `typeRegistryGetOrCreateArray` | 441 | pub | `[inference: key = (elem<<32) | length, array_cache check, emit O0/O1 markers, arrayAppend, compute size=elem.size*length, typeRegistryAppend, cache put only if elem resolved, emit O2 marker]` | Creates `[N]T` array type. |
| `typeRegistryGetOrCreateTuple` | 486 | pub | `[inference: tupAppend(TuplePayload), typeRegistryAppend(state=2,size=0,align=1), no caching]` | Creates tuple type. Size computed later by layout resolver. |
| `typeRegistryGetOrCreateFn` | 497 | pub | `[inference: linear scan for matching fn_type+name_id+module_id, fnAppend(FnPayload), typeRegistryAppend(size=4,align=4, name_id=name_id), emit P2 marker]` | Creates or retrieves function type. Linear scan dedup by `kind==fn_type && name_id==name_id && module_id==module_id`. |
| `typeRegistryMarkFnPtrUsed` | 520 | pub | `[inference: types_items[tid].flags |= 1]` | Sets bit 0 of flags — marks that this fn type is referenced as a pointer (enables C89 fn ptr emission). |
| `typeRegistryGetOrCreateErrorSet` | 524 | pub | `[inference: hash key = fold(^) of tag names with FNV offset, es_cache check, esAppend, typeRegistryAppend(size=4,align=4), cache put]` | Creates error set type. Tags are `xn_items[tags_start..tags_start+tags_count]`. Hash = XOR-fold of all tag name_ids with FNV prime multiplier. |
| `typeRegistryErrorSetMemberIndex` | 543 | pub | `[inference: bounds check, linear scan of xn_items for matching name_id]` | Returns member index within an error set, or `0xFFFFFFFF` if not found. |
| `typeRegistryGetOrCreateModule` | 559 | pub | `[inference: linear scan for matching module_type+module_id, typeRegistryAppend(state=0), emit MC marker]` | Creates module type reference. |
| `isValueDependency` | 665 | pub | `[inference: return true for struct/union/tagged_union/array/optional/error_union/tuple/unresolved_name]` | Returns `true` if this type kind participates in value dependency (used by dep graph builder). |
| `typeRegistryGetTypeState` | 678 | pub | `[inference: read types_items[tid].state]` | Returns type resolution state (0=unresolved, 2=resolved). |
| `typeRegistryIsNumeric` | 682 | pub | `[inference: kind ranges i8-usize + f32/f64 + integer_literal]` | i8-u64, isize, usize, f32, f64, integer_literal_type. |
| `typeRegistryIsInteger` | 700 | pub | `[inference: same as IsNumeric minus f32/f64]` | Integer types only (no float). |
| `typeRegistryIsUnsigned` | 716 | pub | `[inference: u8/u16/u32/u64/usize]` | Unsigned integer types only. |
| `typeRegistryIsPointer` | 726 | pub | `[inference: kind == ptr_type or many_ptr_type]` | Regular or many-item pointer. |
| `typeRegistryIsSlice` | 731 | pub | `[inference: kind == slice_type]` | Slice type. |
| `typeRegistryGetPointeeType` | 735 | pub | `[inference: if ptr/many_ptr, return ptr_items[payload_idx].base; else null]` | Returns the base type of a pointer. |
| `typeRegistryGetSliceElem` | 741 | pub | `[inference: if slice_type, return slice_items[payload_idx].elem; else null]` | Returns element type of a slice. |
| `typeRegistryIndexedElemType` | 751 | pub | `[inference: array→array.elem, slice→slice.elem, ptr→pointee (deref array), else TYPE_UNDEFINED]` | Element type for indexing `base_tid[i]`. Handles `*[N]T` → `T`. |
| `typeRegistryIsOptional` | 770 | pub | `[inference: kind == optional_type]` | Is this an optional type? |
| `typeRegistryIsErrorSet` | 774 | pub | `[inference: kind == error_set_type]` | Is this an error set type? |
| `typeRegistryGetStructFields` | 778 | pub | `[inference: resolve StructPayload, return slice of fe_items]` | Returns struct field entries (includes computed offsets). |
| `typeRegistryIsAssignable` | 786 | pub | `[inference: ~30 rule branches for implicit coercion]` | Type assignability check. See [typeRegistryIsAssignable Rules](#typeregistryisassignable-rules). |
| `canLiteralFitInType` | 884 | pub | `[inference: range check per integer type, true for f32/f64]` | Whether an `i64` value fits in the given integer type. |

### *Append Helpers

All follow same pattern: `payloadEnsure` → write at `len` → `len += 1`.

| Helper | Line | Scope | Payload Type |
|--------|------|-------|-------------|
| `ptrAppend` | 177 | private | `PtrPayload` |
| `arrayAppend` | 181 | private | `ArrayPayload` |
| `sliceAppend` | 185 | private | `SlicePayload` |
| `optAppend` | 189 | private | `OptionalPayload` |
| `euAppend` | 193 | private | `EUPayload` |
| `esAppend` | 197 | pub | `ErrorSetPayload` |
| `fnAppend` | 201 | private | `FnPayload` |
| `stAppend` | 205 | pub | `StructPayload` |
| `enAppend` | 209 | pub | `EnumPayload` |
| `unAppend` | 213 | pub | `UnionPayload` |
| `tuAppend` | 217 | pub | `TaggedUnionPayload` |
| `tupAppend` | 221 | pub | `TuplePayload` |
| `unrAppend` | 225 | private | `UnresolvedPayload` |
| `feAppend` | 229 | pub | `FieldEntry` |
| `emAppend` | 233 | pub | `EnumMember` |
| `xtAppend` | 237 | pub | `TypeId` |
| `xnAppend` | 241 | pub | `u32` |

Note: `xtAppend` and `xnAppend` use `elem_size=4` (u32), unlike the struct-payload `*Append` helpers which use `@sizeOf(PayloadStruct)`.

### Type Caches

| Cache | Key Type | Key Construction | Used By |
|-------|----------|-----------------|---------|
| `ptr_cache` | u64 | `(base << 1) \| is_const` | `typeRegistryGetOrCreatePtr` |
| `many_ptr_cache` | u64 | `(base << 1) \| is_const` | `typeRegistryGetOrCreateManyPtr` |
| `slice_cache` | u64 | `(elem << 1) \| is_const` | `typeRegistryGetOrCreateSlice` |
| `optional_cache` | u32 | `payload TypeId` | `typeRegistryGetOrCreateOptional` |
| `array_cache` | u64 | `(elem << 32) \| length` | `typeRegistryGetOrCreateArray` |
| `eu_cache` | u64 | `(payload << 32) \| error_set` | `typeRegistryGetOrCreateErrorUnion` |
| `es_cache` | u64 | XOR-fold FNV hash of tag name_ids | `typeRegistryGetOrCreateErrorSet` |
| `name_cache` | u64 | `(module_id << 32) \| name_id` | `typeRegistryRegisterNamedType`, `resolveTypeExprFull`, `constAliasPrepass` |

### typeRegistryIsAssignable Rules

Implicit coercion rules (`typeRegistryIsAssignable`, `type_registry.zig:786-882`):

1. **Identity**: `source == target` → true
2. **Integer literal → numeric**: `integer_literal_type → any numeric type` → true
3. **Integer widening (same sign)**: same signedness, `source.size < target.size` → true
4. **Float widening**: `f32 → f64` → true
5. **null → pointer/optional/fn**: `null_type → *T, ?T, fn` → true
6. **Optional wrapping**: `source → ?T` if `source → T` → true
7. **Error union (same error set)**: `E!A → E!B` where `E==E`, `A → B`
8. **Error union wrapping**: `source → E!T` if `source → T`
9. **Error set → error union**: `error_set → E!T`
10. **ptr → ptr**: `*void → *T`, `*T → *void`, `*const T ← *T`
11. **slice → const slice**: `[]T → []const T`
12. **ptr → slice**: `*[N]T → []T`, `*T → []T`, `*c_char ↔ *u8`
13. **many ptr → const many ptr**: `[*]T → [*]const T`
14. **ptr → optional pointer**: `*T → ?*T`
15. **u8 ↔ c_char** (bidirectional)
16. **array → slice**: `[N]T → []T`
17. **array → many ptr**: `[N]T → [*]T`
18. **slice → many ptr**: `[]T → [*]T`

---

## type_resolver.zig (`sf/src/type_resolver.zig`, 1075 lines)

Depends-on-graph topological sort and layout computation for all compound types. Also handles type expression resolution from AST nodes.

### Types

| Type | Line | Description |
|------|------|-------------|
| `TypeResolveEnv` | 23 | Bundle: `store(*AstStore)`, `typereg(*TypeRegistry)`, `symbol_reg(*SymbolRegistry)`, `interner(*StringInterner)` |
| `ClassificationResult` | 31 | Result of `classifyTypeEmissionGroups`: `ids([*]u32)`, `len(u32)` |
| `TypeResolver` | 36 | Kahn topological sorter: `registry(*TypeRegistry)`, `depend_items/len/cap([*]DepEdge)`, `in_degree_items/cap([*]u32)`, `sorted_items/len([*]u32)`, `worklist_items/len/cap([*]u32)`, `diag(*DiagnosticCollector)`, `alloc(*Sand)` |

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `typeResolverInit` | 225 | pub | `[inference: zero-init TypeResolver with undefined items, len/cap=0]` | Creates empty resolver. |
| `typeResolverAddEdge` | 62 | pub | `[inference: dependEnsureCapacity (2x growth, min 8), store DepEdge{from,to}, increment depend_len]` | Appends a dependency edge. |
| `dependEnsureCapacity` | 52 | private | `[inference: 2x growth, min 8, sand alloc 8-byte edges]` | Grows the dependency edge array. |
| `typeResolverBuild` | 243 | pub | `[inference: copy dep edges, alloc in_degree array of size types_len, zero-init, count edges per target]` | Initializes in-degree array from dependency graph edges. Allocates `sorted_items` array (same size as types). |
| `typeResolverResolve` | 268 | pub | `[inference: Kahn's algorithm — push zero-in-degree nodes, pop→resolveLayout→set state=2, decrement dependents' in-degree, push new zeros; detect circular deps]` | Topological sort + layout resolution. See [Kahn's Algorithm](#kahns-algorithm). |
| `typeResolverResolveLayout` | 103 | private | `[inference: switch on kind, compute size/alignment, update Type in registry]` | Computes size/alignment for a single type. See [Layout Resolution](#layout-resolution). |
| `typeResolverGetSorted` | 553 | pub | `[inference: return sorted_items[0..sorted_len]]` | Returns topological order slice. |
| `classifyTypeEmissionGroups` | 332 | pub | `[inference: compute PO (pointer-only) set via forward+backward propagation, return sorted ids]` | Classifies types as pointer-only vs value-emitted for C89 codegen. |
| `typeResolverResolveNames` | 1060 | pub | `[inference: create TypeResolveEnv, call resolveNamedTypeExpressions, resolveAggregateFieldTypesAll, resolveFnSignatures]` | **Phase entry point.** Resolves all type expressions across all modules. |

### Kahn's Algorithm

`typeResolverResolve` (`type_resolver.zig:268-321`):

```
in_degree[0..type_count] = count of unsatisfied dependencies per type

Phase 1 — Seed:
  for each type_id where in_degree[tid] == 0:
    worklistPush(tid)

Phase 2 — Process:
  while worklist not empty:
    tid = worklistPop()
    sorted_items.append(tid)
    typeResolverResolveLayout(tid)          # compute size/alignment
    registry.types_items[tid].state = 2     # mark resolved
    for each edge where edge.from == tid:
      dep = edge.to
      in_degree[dep] -= 1
      if in_degree[dep] == 0:
        worklistPush(dep)

Phase 3 — Cycle detection:
  for each type where state != 2 and in_degree > 0:
    emit ERR_3005_CIRCULAR_TYPE_DEPENDENCY
    set kind = void_type, size = 0, align = 1, state = 2 (safety-valve)
```

### Layout Resolution

`typeResolverResolveLayout` (`type_resolver.zig:103-223`):

| Kind | Logic |
|------|-------|
| **struct_type** | Iterate fields. For each: `alignUp(offset, ft.alignment)`, set `fe.offset`, `offset += ft.size`, track `max_align`. Final `size = alignUp(offset, max_align)` (min 1). Voids are laid at current offset without advancing. |
| **enum_type** | `size = backing_type.size`, `alignment = backing_type.alignment` |
| **union_type** | Iterate fields. `max_sz = max(field.size)`, `max_align = max(field.alignment)`. `size = alignUp(max_sz, max_align)` (min 1). |
| **tagged_union_type** | Tag first: `total = tag_type.size`, `total = alignUp(total, max_pa)`, then `total += alignUp(max_payload_size, max_pa)`. `size = alignUp(total, overall_align)` where `overall_align = max(tag_type.alignment, max_pa)`. |
| **optional_type** | `pay_align = max(pt.alignment, 4)`. `size = alignUp(alignUp(pt.size, 4) + 4, pay_align)`. |
| **error_union_type** | `union_sz = max(pt.size, 4)`, `union_align = max(pt.alignment, 4)`. `total = alignUp(alignUp(union_sz, union_align), 4) + 4`. `size = alignUp(total, union_align)`. |
| **array_type** | `size = elem.size * length`, `alignment = elem.alignment`. |
| **tuple_type** | Same as struct: sequential layout. `size = alignUp(offset, max_align)` (min 1). |

### classifyTypeEmissionGroups

`type_resolver.zig:332-533`:

Computes which types can be emitted as pointer-only forward declarations (C89 requirement) vs must have full value layout.

1. **Forward pass** (per type kind):
   - Check every field (or element for array/error_union) of a value-embedding kind:
     - If field is `struct_type`/`tagged_union_type`/`union_type`/`array_type`/`tuple_type` → type is NOT pointer-only (requires full definition)
     - If field is `optional_type` or `error_union_type` → add backward edge from parent to optional's/error_union's *payload* (the payload type's resolution status may propagate)
   - If none of these conditions trigger → type marked pointer-only (1)
2. **Backward propagation** (worklist):
   - Types that are NOT pointer-only (0) propagate: any parent that depends on them (via optional/error_union edge) also becomes NOT pointer-only
3. **Result**: returns `ClassificationResult{ids, len}` — sorted list of pointer-only TypeIds

Internal helpers:
- `fieldEmbedsByValue` (line 323): returns true for `struct/tagged_union/union/array/tuple` — these kinds require the full type definition when used as fields.
- `growWpEdges` (line 535): 2x growth for the backward edge adjacency list.

### Type Expression Resolution

#### `resolveTypeExprFull`

`type_resolver.zig:587-882` — recursive type expression resolver. Depth-limited to 16. Emits `RTD:n<node>k<kind>` markers.

| AST Kind | Lines | Behavior |
|----------|-------|----------|
| `ident_expr` | 591-619 | Lookup: name_cache(canonical_id), then per-module name_cache, then symbolRegistryQualifiedLookup per module. Returns `s.type_id` or `TYPE_UNDEFINED`. Emits `NF`, `N2`, `OPTVOID:*` markers. |
| `struct_decl` | 620-671 | Generate synthetic `anon_<node_idx>` name. Register named type. If payload (extra children), resolve each `field_decl.child_0` recursively, `feAppend` fields, `stAppend` payload. |
| `field_access` | 672-715 | Resolve base expression. If base is `TYPE_UNDEFINED` and base is `ident_expr`, try module-qualified lookup (module symbol → field symbol). If base is `module_type`, lookup field in that module's symbol table. Emits `FAH:*` markers. |
| `error_union_type` | 716-728 | Resolve payload type (child_1) and optional error set (child_0). If no explicit error set, creates empty error set. Returns `typeRegistryGetOrCreateErrorUnion`. |
| `fn_type` | 729-788 | Resolve return type, resolve up to 16 param types. Builds unique name `"fnt_<ret>_<p0>_<p1>..."`. Registers fn type, marks as fn ptr, returns `typeRegistryGetOrCreatePtr(fn_tid, false)`. |
| `ptr_type` | 792-806 | Resolve child as base type. `is_const = (node.flags & 1) != 0`. Returns `typeRegistryGetOrCreatePtr(child, is_const)`. |
| `many_ptr_type` | 792-806 | Same as ptr but `typeRegistryGetOrCreateManyPtr`. |
| `slice_type` | 814-827 | `is_const = (node.flags & 1) != 0`. Returns `typeRegistryGetOrCreateSlice(child, is_const)`. |
| `optional_type` | 828-833 | Returns `typeRegistryGetOrCreateOptional(child)`. |
| `array_type` | 834-877 | Resolves element type (child_0). Evaluates length from child_1: supports `int_literal`, `add/sub` (via `evalConstU32Full`), or `ident_expr` (via `evalConstU32Full`). Returns `typeRegistryGetOrCreateArray(elem, len)` or `TYPE_UNDEFINED` for zero-length. Emits `T0`, `T1`, `T2`, `T3` markers. |

#### `evalConstU32Full`

`type_resolver.zig:557-576` — constant u32 expression evaluator:

1. **int_literal**: returns stored `int_values[node.payload]`
2. **ident_expr**: looks up symbol. If symbol `type_id == 0` and `flags & 0x01 == 0`, recursively evaluates `decl.child_1`
3. **Fallback**: returns `0xFFFFFFFF` (sentinel for "unknown")

Helper `symbolLookupAllModules` (line 578): linear scan of all symbol tables for a `name_id`.

#### `resolveDeclAggregateFieldTypes`

`type_resolver.zig:884-935` — resolves field type annotations for struct/tagged_union declarations that have inline field type expressions. Walks `init.payload` (extra children of the init expression), resolves each `field_decl.child_0`, and writes the result back to `fe_items[].type_id`. Emits `B2`, `FSW`, `DFT`, `FTW`, `DTWR`, `TUI` markers.

#### `resolveNamedTypeExpressions`

`type_resolver.zig:949-971` — iterates top-level `var_decl`s where init expression is a type expression (not an inline type decl, import, ident, or fn_decl). Resolves via `resolveTypeExprFull`, stores result in `nameCachePut` under `(module_id << 32) | name_id`.

#### `resolveAggregateFieldTypesAll`

`type_resolver.zig:973-991` — iterates all modules' top-level var_decls whose init is `struct_decl` or `union_decl`. Calls `resolveDeclAggregateFieldTypes` for each.

#### `resolveFnSignatures`

`type_resolver.zig:993-1058` — iterates all modules:
- **fn_decl**: resolves return type and param types via `resolveTypeExprFull`, creates fn type via `typeRegistryGetOrCreateFn`, records in `ResolvedTypeTable`, sets `symbol.type_id`.
- **var_decl with explicit type annotation** (child_0 != 0): resolves type expression, records in `ResolvedTypeTable`, sets `symbol.type_id`.

#### `typeResolverResolveNames` (entry point)

`type_resolver.zig:1060-1075` — orchestrates all name resolution:
1. `resolveNamedTypeExpressions` — var_decl type expressions
2. `resolveAggregateFieldTypesAll` — field type annotations
3. `resolveFnSignatures` — fn signatures + annotated var types

---

## const_alias_prepass.zig (`sf/src/const_alias_prepass.zig`, 224 lines)

Resolves `const Alias = TypeName` patterns where the RHS is a simple identifier referring to another type.

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `resolveWellKnownTypeName` | 15 | private | `[inference: switch on string length (2-5), byte-compare for built-in type names, return sentinel or TYPE_UNDEFINED]` | Matches string names to TypeId sentinels: void(4), bool(4), i32/u32(3), u64/i64(3), f32/f64(3), i8/u8(2), usize/isize(5). Returns `TYPE_UNDEFINED` for non-well-known. |
| `constAliasPrepass` | 58 | pub | `[inference: 3-phase Kahn worklist: catalog global const aliases, seed resolvable ones, propagate resolved types through dep chain]` | Resolves `const X = Y` type aliases before full type resolution. |

### constAliasPrepass — Three Phases

```
Phase 1 — Catalog (line 100):
  for each module's symbol table:
    for each global symbol with type_id == 0 and decl is const (kind == 1):
      if init is ident_expr (kind == 24):
        record alias: alias_name[count] = canonicalized dep_name
        record dep edge: dep_head[dep_name] → alias_count (linked list)
        alias_count += 1
    Emits: CAT:ik, CAT:dn markers

Phase 2 — Seed (line 152):
  for each alias:
    lookup dep_name in:
      (1) name_cache(name_id only)  → global name
      (2) name_cache(module<<32 | name_id)  → per-module name
      (3) resolveWellKnownTypeName → "void", "i32", etc.
    if resolved:
      sym.type_id = resolved
      nameCachePut((mod_id<<32) | dep_name, resolved)
      worklist.push(alias_idx)

Phase 3 — Kahn propagation (line 190):
  while worklist not empty:
    resolved_idx = worklist.pop()
    resolved_sym.type_id = rt  (the resolved TypeId)
    alias_own_name = resolved_sym's declared name
    for each dependent alias (linked list via dep_head[alias_own_name]):
      if dep_sym.type_id == 0:
        dep_sym.type_id = rt
        nameCachePut((dep_mod<<32) | dep_name, rt)
        worklist.push(dep_alias_idx)
    Emits: KAHN:start, KAHN:end markers
```

---

## Data Flow

```
phase_TypeResolution (main.zig)
    │
    │  scratch arena reset
    │
    ├─ constAliasPrepass (const_alias_prepass.zig:58)
    │   │  marker: "CAP:ent"
    │   │
    │   ├─ Phase 1 — Catalog: find all "const X = Y" aliases
    │   │   └─ dep_head linked list per name_id
    │   │
    │   ├─ Phase 2 — Seed: resolve directly-known names
    │   │   └─ nameCache, well-known types
    │   │
    │   └─ Phase 3 — Kahn: propagate through alias chain
    │       └─ emit KAHN:start / KAHN:end
    │
    ├─ typeResolverResolveNames (type_resolver.zig:1060)
    │   │
    │   ├─ resolveNamedTypeExpressions
    │   │   └─ var_decl type expressions → nameCachePut
    │   │
    │   ├─ resolveAggregateFieldTypesAll
    │   │   └─ resolveDeclAggregateFieldTypes (per struct/union)
    │   │       ├─ resolveTypeExprFull for each field_decl.child_0
    │   │       └─ fe_items[].type_id = resolved type
    │   │
    │   └─ resolveFnSignatures
    │       ├─ fn_decl return type + param types → resolveTypeExprFull
    │       ├─ var_decl with type annotation → resolveTypeExprFull
    │       ├─ → typeRegistryGetOrCreateFn
    │       ├─ → ResolvedTypeTable.set
    │       └─ → symbol.type_id = resolved
    │
    ├─ typeResolverInit (type_resolver.zig:225)
    │   └─ zero init
    │
    ├─ typeResolverBuild (type_resolver.zig:243)
    │   ├─ copy DepGraph edges from symbol_registrator
    │   ├─ alloc sorted_items[0..types_len]
    │   ├─ alloc in_degree_items[0..types_len]
    │   └─ count edges per target type
    │
    ├─ typeResolverResolve (type_resolver.zig:268)
    │   │  Kahn's algorithm:
    │   │
    │   ├─ Seed: push zero-in-degree types to worklist
    │   │
    │   ├─ Loop: pop → typeResolverResolveLayout → state=2
    │   │   ├─ struct_type  → sequential offset+size per field
    │   │   ├─ enum_type    → backing_type.size/align
    │   │   ├─ union_type   → max field size/align
    │   │   ├─ tagged_union → tag + max payload, aligned
    │   │   ├─ optional     → payload + 4-byte tag
    │   │   ├─ error_union  → union + 4-byte error code
    │   │   ├─ array_type   → elem.size * length
    │   │   └─ tuple_type   → sequential layout
    │   │   │
    │   │   └─ decrement dependents' in_degree
    │   │       └─ push newly-zero types
    │   │
    │   └─ Cycle detection: unresolved → ERR_3005 → void_type fallback
    │
    ├─ typeResolverGetSorted → topological order
    │
    └─ classifyTypeEmissionGroups (type_resolver.zig:332)
        └─ pointer-only classification for C89 forward decls

State transitions in types_items[*].state:
  0 (initial) → 2 (resolved) — set by typeResolverResolveLayout
```

### Data Structures After Type Resolution

```
TypeRegistry (permanent arena)
    │
    ├─ types_items[0..n] — all types, state=2 for resolved
    │   ├─ [1-20] primitives (state=2 from registration)
    │   ├─ [21..] user types (state updated during resolve)
    │   └─ size, alignment, payload_idx fully populated
    │
    ├─ Per-kind payload arrays
    │   ├─ st_items[*] → StructPayload{fields_start, fields_count}
    │   ├─ fe_items[*] → FieldEntry{name_id, type_id, offset}
    │   ├─ en_items[*] → EnumPayload{members_start, count, backing}
    │   ├─ em_items[*] → EnumMember{name_id, value}
    │   └─ ... (all payload types populated)
    │
    ├─ Caches (hash maps)
    │   ├─ ptr_cache: (base<<1)|const → TypeId
    │   ├─ slice_cache: (elem<<1)|const → TypeId
    │   ├─ array_cache: (elem<<32)|len → TypeId
    │   ├─ optional_cache: payload → TypeId
    │   ├─ eu_cache: (payload<<32)|es → TypeId
    │   ├─ es_cache: hash(tags) → TypeId
    │   └─ name_cache: (mod<<32)|name → TypeId
    │
    └─ All Type entries with size≠0, alignment≠0, state=2

TypeResolver (scratch arena, consumed by next phase)
    │
    ├─ sorted_items[0..sorted_len] — topological order
    └─ in_degree_items — consumed, used for cycle detection
```

---

## Debugging

### Phase Entry/Exit Markers

| Marker | Location | Description |
|--------|----------|-------------|
| `CAP:ent` | const_alias_prepass.zig:59 | constAliasPrepass entry |
| `CAP:ac<count>` | const_alias_prepass.zig:148 | Alias count after catalog |
| `CAP:ac0` | const_alias_prepass.zig:149 | No aliases found, early exit |
| `KAHN:start` | const_alias_prepass.zig:188 | Kahn propagation loop start |
| `KAHN:end` | const_alias_prepass.zig:223 | Kahn propagation loop end |
| `CLS:c<count>` | type_resolver.zig:506 | classifyTypeEmissionGroups result count |

### Type Creation Markers (type_registry.zig)

| Marker | Location | Description |
|--------|----------|-------------|
| `DC:k<kind>n<name_id>t<type_id>` | 158-170 | Type created — kind enum, name_id, assigned TypeId |
| `X:<id>` | 172 | Struct type created (TypeId) |
| `MC<id>` | 574 | Module type created (TypeId) |
| `NP:k<key_lo>v<type_id>` | 315-323 | nameCachePut — name_id key (low 16 bits) + cached type_id |
| `RN:m<mod>n<name>k<kind>t<tid>` | 646-661 | Register named type — module_id, name_id, kind enum, assigned tid |
| `U2H:e<elem>r<existing>c<const>` | 362-367 | Slice cache hit (U2H="use-to-hit") |
| `U2N:e<elem>r<new_tid>c<const>` | 379-384 | Slice cache miss, created new (U2N="use-to-new") |
| `O0:e<elem>L<len>` | 442-451 | Array type creation start |
| `O1H<existing>` | 454-459 | Array cache hit |
| `O2N<new_tid>` | 477-482 | Array cache miss, new type ID |
| `P2:n<name_id>H<existing_tid>` | 498-507 | Fn type hit (linear scan) |
| `P2:n<name_id><tid>\n` | 498-518 | Fn type created |

### Type Expression Resolution Markers (type_resolver.zig)

| Marker | Location | Description |
|--------|----------|-------------|
| `RTD:n<node>k<kind>` | 590 | ResolveTypeExprDepth — node index and AstKind |
| `T0` | 835 | Array type resolution start |
| `T1e<elem>` | 836-840 | Array element type ID |
| `T2L<len>` | 859-863 | Array length |
| `T3a<tid>` | 866-870 | Array type created (TypeId) |
| `A` / `a` | 871-872 | Array success (A) or TYPE_UNDEFINED (a) |
| `FAH:r<resolved>` | 689, 707 | Field access hit — resolved type ID |
| `FAH:m<child_0>` | 697 | Field access miss — base node index |
| `FAH:N<node>` | 713 | Field access no match |
| `PTR:i<node>k<kind>c<child>` | 793-798 | Pointer type resolution |
| `P<tid>` / `M<tid>` | 802/808 | Pointer (P) or many-pointer (M) created |
| `SL:e<elem>s<tid>` | 820-826 | Slice type created |
| `OPTVOID:*` | 593-618, 735-786, 829-832 | Optional/void type resolution markers |
| `FER:n<idx>t<type_id>` | 166-167 | Field entry read during tagged_union layout |
| `FSW:n<fe_idx>t<type_id>` | 904-905 | Field slot write during type resolution |
| `DFT:n<fi>t<tid>` | 917-918 | Decl field type tag |
| `FTW:n<fe_idx>t<tid>` | 926-927 | Field type write |
| `B2:p<payload>t<tid>` | 899-901 | Field decl payload and resolved type |
| `DTWR` | 923 | Field type written |
| `DTSK` | 929 | Field type skipped (TYPE_UNDEFINED) |
| `TUI:fs<start>fc<count>` | 911-912 | Tagged union field range |
| `NGC:g1<result>` | 308 | nameCacheGet for key_lo==1 (debug only) |
| `NF` | 599 | Name not found in global name_cache |
| `N2` | 606 | Name not found in per-module caches |
| `UND:n<node>k<kind>` | 879-880 | resolveTypeExprFull returning TYPE_UNDEFINED |

### constAliasPrepass Markers

| Marker | Location | Description |
|--------|----------|-------------|
| `CAP:tlm<total>` | 66 | Total symbols across all modules |
| `CAP:tl0` | 67 | No symbols, early return |
| `GATE:g0<type_id>` | 108 | Global alias type check (must be 0 to continue) |
| `GATE:g1` | 110 | Gate passed: type_id == 0 |
| `GATE:g2<kind>` | 112-115 | Gate failed: not const (kind != 1) |
| `GATE:g3` | 116-118 | Gate failed: no child_1 (no init expr) |
| `CAT:ik<init_kind>` | 122-123 | Catalog: init expression AstKind |
| `CAT:dn<name_id>` | 127-129 | Catalog: dependency name_id |

### classifyTypeEmissionGroups Markers

| Marker | Location | Description |
|--------|----------|-------------|
| `CLS:c<count>` | 506-510 | Total pointer-only type count |
| `CLS:p<tid>k<kind>` | 514-515 | Per pointer-only type |
| `CLS:v<tid>k<kind>` | 516-517 | Per value-emitted type |

### Diagnostic Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 3005 | `ERR_3005_CIRCULAR_TYPE_DEPENDENCY` | Type refers to itself (directly or transitively). Emitted during `typeResolverResolve` cycle detection. The offending type is set to `void_type` as fallback. |

### How to Inspect TypeId Values

Use the marker system (`pal_mod.markerWrite`):

```
Marker format: "<prefix><key><value>\n"
Examples:
  "DC:k17n493t25\n"   → created type kind=17 name_id=493 TypeId=25
  "RN:m1n200k12t30\n" → registered named type mod=1 name=200 kind=12 TypeId=30
  "NP:k3a5v22\n"      → name_cache put key_low=0x3a5→type_id=22
```

Type ID values are dense monotonically increasing u32s starting at 0. Sentinels occupy 0-20 (index 0 is `none_sentinel` sentinel at type_id=0, though TYPE_VOID=1 is the first meaningful type). `FIRST_USER_TYPE = 20` means user types start at TypeId ≥ 21.

To trace a specific TypeId through the pipeline:
- Search `DC:k*` for creation
- Search `RN:t<id>` for named type registration
- Search `NP:v<id>` for cache population
- In type_resolver.zig: `GR`, `TR`, `Ti` markers trace resolve entry

### Known Issues

1. **Linear dedup for fn_type** (type_registry.zig:501-507): `typeRegistryGetOrCreateFn` does a full scan of `types_items` on every call. No hash cache.

2. **typeRegistryGetOrCreateModule** (type_registry.zig:561-566): Linear scan of all types for matching `module_type+module_id`. No hash cache.

3. **No hash cache for optional when unresolved** (type_registry.zig:408): `optional_cache` only gets populated if `opt_state == 2` (payload resolved). Unresolved optionals will miss cache on subsequent lookups.

4. **Depth limit in resolveTypeExprFull** (type_resolver.zig:588): Hardcoded max depth of 16. Deeply nested type expressions will silently return `TYPE_UNDEFINED`.

5. **evalConstU32Full fallback ambiguity** (type_resolver.zig:575): `0xFFFFFFFF` return value is both a valid u32 and the sentinel for uncomputable. Cannot distinguish "zero-sized array length 0xFFFFFFFF" from "failed to evaluate".
