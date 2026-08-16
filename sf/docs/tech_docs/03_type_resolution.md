# 03 — Type Resolution [updated: 2026-08-14 — F-task root-cause fix: `resolveTypeExprFull` `ident_expr` arm reordered current-module-first before bare (primitive + module-0 named-type fallback), const_alias_prepass Phase-2 seed scoped to alias declaring module; prior 2026-08-13 — Defect D FIXED (F5, layout dependency-graph ordering, operator ruling m0898 Option B: real `field_type -> container_tid` edges built after field-type resolution, `typeResolverBuildDependencyGraph`); prior — 2026-08-08 F7 line-ref re-verification (semantic_analyzer.zig:1290-1312 builtin_call, :1298-1301 @ptrToInt hoist, :529 resolveBitwise, :1727-1734 void-var error[3000]; lower.zig:2653-2657 @ptrToInt; type_resolver.zig:609-612 RTD/depth :610, evalConstU32Full :579-597); prior — F1 fix: @ptrToInt resolves to usize for single-arg calls; prior 2026-08-08 @ptrToInt-returns-argument-type (I1); 2026-08-06 va_list primitive (TYPE_VA_LIST=21) + variadic fn signatures; array-size mul/div/mod (F6)]

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `TypeId` sentinels | 21 | TYPE_VOID(1) through TYPE_TYPE(20), TYPE_VA_LIST(21) |
| `TypeKind` variants | 40 | none_sentinel(0) through anon_union(39) |
| `Type` fields | 10 | kind, state, flags, _pad, size, alignment, name_id, c_name_id, module_id, payload_idx |
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
| `TYPE_VA_LIST` | 21 | 4 | 4 |

Synthetic field indices: `SLICE_FIELD_PTR=0`, `SLICE_FIELD_LEN=1`, `TU_FIELD_TAG=0`, `TU_FIELD_PAYLOAD=1`.

`FIRST_USER_TYPE = 20` — **stale** (see below). `[updated: 2026-08-06]` Adding the
`va_list` primitive (`TypeKind.va_list_type`, registered at type_registry.zig:603,
primitive name `va_list` at :622) shifted every user type id by 1 — the F4
"va_list user-type-id shift" (AMENDMENT 4) re-baselined the mud/lisp/json MD5
gates for this (gol coincidentally unchanged). Since primitives now occupy 1-21, user types in practice start ≥22, but
the `FIRST_USER_TYPE` constant in type_registry.zig:39 still reads `20`
(pre-existing drift: TYPE_TYPE was already a primitive while FIRST_USER_TYPE was
never bumped). Docs-only task — source constant left unchanged.

---

## type_registry.zig (`sf/src/type_registry.zig`, 897 lines)

Central type store. Flat arrays of `Type` entries indexed by `TypeId` (u32). Per-kind payload arrays hold variable-length data.

### Types

| Type | Line | Description |
|------|------|-------------|
| `TypeId` | 9 | `u32` alias — index into `TypeRegistry.types_items` |
| `TypeKind` (enum u8) | 41 | 41 variants: none_sentinel(0), void/bool/noreturn/i8/i16/i32/i64/u8/u16/u32/u64/isize/usize/c_char/f32/f64, ptr/many_ptr/array/slice/optional/error_union/error_set/fn/struct/enum/union/tagged_union/tuple/unresolved_name/type_type/module_type/null_type/undefined_type/integer_literal_type/anon_struct_init/anon_array/anon_tuple/anon_union/va_list_type |
| `Type` (struct) | 58 | `kind(TypeKind, 1B)`, `state(u8, 0=unresolved, 2=resolved)`, `flags(u8)`, `_pad(u8)`, `size(u32)`, `alignment(u32)`, `name_id(u32)`, `c_name_id(u32)`, `module_id(u32)`, `payload_idx(u32)` — 28 bytes total |
| `PtrPayload` | 71 | `base: TypeId` — shared by ptr_type and many_ptr_type |
| `ArrayPayload` | 72 | `elem: TypeId`, `length: u32` |
| `SlicePayload` | 73 | `elem: TypeId` |
| `OptionalPayload` | 74 | `payload: TypeId` |
| `EUPayload` | 75 | `payload: TypeId`, `error_set: TypeId` |
| `ErrorSetPayload` | 76 | `tags_start: u16`, `tags_count: u16` |
| `FnPayload` | 77 | `name_id, module_id, return_type: TypeId`, `params_start/count: u16`, `is_extern: u8`, `flags_packed: u8` — `flags_packed` bit0 = `is_variadic` (2026-08-06) |
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
| `nameCacheGet` | 304 | pub | `[inference: u64ToU32MapGet on name_cache, return value or null; emit NGC:g1 marker for key_lo==1]` | Looks up a (module<<32)\|name_id key in name_cache. Used by resolveTypeExprFull and constAliasPrepass. Returns cached TypeId or null. |
| `nameCachePut` | 313 | pub | `[inference: u64ToU32MapPut on name_cache, emit NP:k<key_lo_16bits>v<value> marker]` | Stores a (module<<32)\|name_id→TypeId mapping in name_cache. Emits NP:k<key_lo>v<type_id> debug marker. |
| `typeRegistryAppend` | 153 | private | `[inference: ensure capacity, write Type at types_len, increment len, emit DC:k<n>t marker, emit X:id for struct_type]` | Core append to `types_items`. Returns the new `TypeId` (old `types_len`). Emits `DC:k<kind_enum>n<name_id>t<type_id>` debug marker. For struct_type, also emits `X:<id>`. |
| `registerPrimitive` | 246 | private | `[inference: call typeRegistryAppend with state=2, given kind/size/alignment, zero name_id/c_name_id/module_id/payload_idx]` | Appends a resolved (state=2) primitive type. |
| `typeRegistryRegisterPrimitives` | 579 | pub | `[inference: registerPrimitive for 21 primitives (1-21), then registerPrimitiveName for named ones]` | Populates sentinel TypeIds 1-21. Calls `registerPrimitiveName` for void, bool, i8-i64, u8-u64, isize, usize, c_char, f32, f64, null, undefined, type. |
| `registerPrimitiveName` | 621 | private | `[inference: interner.intern name, set Type.name_id, nameCachePut(key=name_id, value=tid)]` | Interns a primitive type name and registers it in `name_cache` (key=name_id only, module_id=0). |
| `typeRegistryRegisterNamedType` | 629 | pub | `[inference: compute key = module_id*2^32 + name_id, nameCacheGet check, typeRegistryAppend with kind+name_id+module_id, nameCachePut, emit RN:m<n>k<t> marker]` | Registers a user-defined named type (struct, enum, union, etc.). Key is `(module_id << 32) | name_id`. State=0 (unresolved). |
| `typeRegistryGetOrCreatePtr` | 326 | pub | `[inference: key = (base << 1) | is_const(0/1), ptr_cache check, ptrAppend, typeRegistryAppend(PtrPayload{base}), ptr_cache put, return tid]` | Creates or retrieves `*T` type. Size=4, align=4, flags=const. |
| `typeRegistryGetOrCreateManyPtr` | 342 | pub | `[inference: same as ptr but many_ptr_cache, kind=many_ptr_type]` | Creates or retrieves `[*]T` type. |
| `typeRegistryGetOrCreateSlice` | 358 | pub | `[inference: key = (elem << 1) | is_const, slice_cache check, emit U2H hit or U2N new marker, sliceAppend, typeRegistryAppend(size=8,align=4), cache put]` | Creates or retrieves `[]T` type. Size=8 (ptr+len), align=4. |
| `typeRegistryGetOrCreateOptional` | 388 | pub | `[inference: optional_cache check, if payload resolved compute size/align via alignUp(payload.size,4)+4 with pay_align, optAppend, typeRegistryAppend, cache put only if state=2]` | Creates `?T`. If payload resolved, `size = alignUp(alignUp(payload.size,4)+4, max(payload.align,4))`. |
| `typeRegistryGetOrCreateErrorUnion` | 412 | pub | `[inference: eu_key = (payload<<32) | error_set, eu_cache check, compute union_size=max(payload.size,4), total = alignUp(alignUp(union_size, union_align),4)+4, euAppend, typeRegistryAppend, cache put]` | Creates `E!T` error union type. |
| `typeRegistryGetOrCreateArray` | 441 | pub | `[inference: key = (elem<<32) | length, array_cache check, emit O0/O1 markers, arrayAppend, compute size=elem.size*length, typeRegistryAppend, cache put only if elem resolved, emit O2 marker]` | Creates `[N]T` array type. |
| `typeRegistryGetOrCreateTuple` | 486 | pub | `[inference: tupAppend(TuplePayload), typeRegistryAppend(state=2,size=0,align=1), no caching]` | Creates tuple type. Size computed later by layout resolver. |
| `typeRegistryGetOrCreateFn` | 497 | pub | `[inference: linear scan for matching fn_type+name_id+module_id, fnAppend(FnPayload), typeRegistryAppend(size=4,align=4, name_id=name_id), emit P2 marker]` | Creates or retrieves function type. Linear scan dedup by `kind==fn_type && name_id==name_id && module_id==module_id`. `is_variadic` param stored in `FnPayload.flags_packed` bit0 (2026-08-06). |
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
| `alignUp` | 261 | pub | `[inference: (v + a - 1) & ~(a - 1), round v up to multiple of a, a must be power of 2]` | Aligns value `v` up to alignment `a`. Used by optional/error_union size computation in typeRegistryGetOrCreateOptional/ErrorUnion. |

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

**[updated: 2026-08-14 — F-TYPEDB soft OOM]:** `arrayGrow` and `typeRegistryEnsureCapacity` no longer `catch unreachable` on a failed `sandAlloc` from the type_db growable arena — both route through the new `typeDbOom(used, new_bytes)` helper, which prints `OOM: type_db <used> -> <new>` to stderr (mirroring the `sandAlloc` OOM diagnostic style) and exits `pal.exit(1)` (soft OOM, visible to `--track-memory`, instead of a panic). The type_db arena is pool-backed via the unified growable pool (Task 3), so its OOM only fires on true pool exhaustion.

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

Implicit coercion rules (`typeRegistryIsAssignable`, `type_registry.zig:794-890`):

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

## type_resolver.zig (`sf/src/type_resolver.zig`, 1238 lines)

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
| `worklistEnsureCapacity` | 68 | private | `[inference: 2x growth (min 64), sandAlloc for worklist u32 array, copy old items, update pointers and cap]` | Grows the worklist array used by Kahn's algorithm. |
| `worklistPush` | 78 | private | `[inference: call worklistEnsureCapacity, write id at worklist_len, increment len]` | Pushes a TypeId onto the Kahn worklist. |
| `worklistPop` | 84 | private | `[inference: return null if empty, decrement len, return worklist_items[len]]` | Pops a TypeId from the Kahn worklist (LIFO). |
| `inDegreeEnsureCapacity` | 90 | private | `[inference: grow in_degree array to requested capacity (min 64), sandAlloc, update pointer and cap]` | Ensures the in_degree array is large enough for the given number of types. |
| `alignUp` | 99 | private | `[inference: (v + a - 1) & ~(a - 1), round v up to multiple of a, a must be power of 2]` | Aligns value `v` up to alignment `a`. Used by typeResolverResolveLayout for struct/union/tagged_union layout. |
| `typeResolverBuild` | 243 | pub | `[inference: copy dep edges, alloc in_degree array of size types_len, zero-init, count edges per target]` | Initializes in-degree array from dependency graph edges (symbol_registrator DUMMY `0->tid` edges PLUS the real `field_type -> container_tid` edges added by `typeResolverBuildDependencyGraph`). Allocates `sorted_items` array (same size as types). |
| `typeResolverResolve` | 268 | pub | `[inference: Kahn's algorithm — push zero-in-degree nodes, pop→resolveLayout→set state=2, decrement dependents' in-degree, push new zeros; detect circular deps]` | Topological sort + layout resolution. See [Kahn's Algorithm](#kahns-algorithm). |
| `layoutFieldNeedsEdge` | 346 | private | `[inference: true for struct/tagged_union/union/enum/array/tuple/optional/error_union, false otherwise]` | The F5 embeds-by-value edge rule: kinds whose layout must be completed before the container's layout is computed. Pointer/slice/fn/error_set/primitive/void fields are always-resolved fixed-size → no edge (avoids false self-reference cycles). |
| `layoutAddTypeEdge` | 358 | private | `[inference: if field_type < types_len and layoutFieldNeedsEdge(types_items[field_type].kind), typeResolverAddEdge(field_type, container_tid)]` | Adds one real `field_type -> container_tid` edge. Guards type_id bounds and skips non-embedding kinds. |
| `layoutAddFieldEdges` | 366 | private | `[inference: for each FieldEntry in fe_items[fstart..fstart+fcount], layoutAddTypeEdge(fe.type_id, container_tid)]` | Adds edges for every field of a struct/union/tagged_union container. |
| `typeResolverBuildDependencyGraph` | 373 | pub | `[inference: iterate all types; for struct/tagged_union/union containers call layoutAddFieldEdges over their fields, for array/tuple/optional/error_union add the elem/payload edge via layoutAddTypeEdge]` | **Defect D fix (F5, m0898 Option B).** Builds the REAL layout dependency graph from the now-resolved field type_ids, so the Kahn topological sort lays every field's type out BEFORE the container struct. Mirrors `fieldEmbedsByValue`(:324)/`requiresFullDef`(:335) semantics. Called from `phase_TypeResolution` (main.zig) AFTER `typeResolverResolveNames` (field types resolved by `resolveAggregateFieldTypesAll`) and BEFORE `typeResolverBuild`/`typeResolverResolve`. |
| `typeResolverResolveLayout` | 103 | private | `[inference: switch on kind, compute size/alignment, update Type in registry]` | Computes size/alignment for a single type. See [Layout Resolution](#layout-resolution). |
| `varDeclInitNeedsNameCache` | 937 | private | `[inference: return false for struct/union/enum/error_set/ident/import/fn decl, true otherwise]` | Filters var_decl init types that need name_cache registration. Used by resolveNamedTypeExpressions. |
| `typeResolverGetSorted` | 553 | pub | `[inference: return sorted_items[0..sorted_len]]` | Returns topological order slice. |
| `classifyTypeEmissionGroups` | 332 | pub | `[inference: compute PO (pointer-only) set via forward+backward propagation, return sorted ids]` | Classifies types as pointer-only vs value-emitted for C89 codegen. |
| `typeResolverResolveNames` | 1060 | pub | `[inference: create TypeResolveEnv, call resolveNamedTypeExpressions, resolveAggregateFieldTypesAll, resolveFnSignatures]` | **Phase entry point.** Resolves all type expressions across all modules. |

### Kahn's Algorithm

`typeResolverResolve` (`type_resolver.zig:269-322`):

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

`typeResolverResolveLayout` (`type_resolver.zig:104-224`):

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

### Defect D — layout dependency graph ordering (FIXED, F5, m0898 Option B)

**[updated: 2026-08-13] FIXED.** Root cause: the dependency graph driving the layout
topological sort carried only DUMMY edges — `symbol_registrator.zig:78`
(`addTypeDependencies`) adds `0 -> tid` for every field, never `field_type -> tid`, because at
symbol-registration time field `type_id`s are still `TYPE_VOID` placeholders. The real field
types get resolved LATER (`resolveAggregateFieldTypesAll`, type_resolver.zig:1179 / per-decl
`:927-989`). So the LIFO worklist popped a container struct BEFORE its union/enum field types
were sized → `typeResolverResolveLayout` (:104) read `size=0`/`align=0` for the field →
`alignUp(0,0)=0` → the `size==0 → 1/1` clamp (:130) → `@sizeOf`/`@alignOf` folded 1/1
(comptime_eval.zig:120/129) for any struct with a by-value union field (e.g. lisp `Value`,
json `JsonValue`).

Fix (general, ordering-only): **build the real graph after field types are resolved.** New
`typeResolverBuildDependencyGraph` (type_resolver.zig:373) adds a real `field_type ->
container_tid` edge for every field that **embeds by value** — the F5 edge rule
(`layoutFieldNeedsEdge` :346): struct/tagged_union/union/enum/array/tuple/optional/error_union.
Pointer/slice/fn/error_set/primitive/void fields are always-resolved fixed-size → no edge (a
pointer field would otherwise create a false self-reference cycle for `struct Node { next: *Node }`).
The Kahn pass (`typeResolverResolve` :269, cycle guard :307-321) then guarantees every field type is
laid out before its container. `phase_TypeResolution` (main.zig:313-314) calls it AFTER
`typeResolverResolveNames` (:312, which runs `resolveAggregateFieldTypesAll`) and BEFORE
`typeResolverBuild` (:314)/`typeResolverResolve` (:315).

Verified: `repro/mi_matrix/sizeof_struct_union_xmod` prints **`24`** (was `2`; zig0 oracle
`24`), `xmod_amp_arena_union_store` `@sizeOf(S)` emits **16** (was 1/1), struct-before-enum and
pointer/optional-of-pointer self-reference no-cycle cases correct, `self_embed_optional_cycle`
still correctly rejected (`error` circular-type-dep, no hang/ICE), F1/F2/F4 repros still green
(42/1/4243/78), 4 MD5 gates byte-identical, corpus OK=238/FAIL=3/GREEN=4 over 245 dirs (no new
FAIL). The readers (comptime_eval.zig:120/129), layout math (:104-224), and C emitter needed NO
change.

**Surfaced follow-up (NOT this fix):** a plain untagged `union` is emitted as a C `struct` with
all variants stacked (c89_emit `ZIG_UNION_` guard, `struct` body) while its layout uses the
max-member model — e.g. lisp_interpreter `ValueData` emits 32 bytes (Value C struct 36) but
`@sizeOf(Value)=16`. `lisp_interpreter` (pre-existing Defect-D family) consequently still
corrupts its arena once eval actually runs (`(+ 1 2)` SEGFAULT post-fix vs silent-fail pre-fix).
Tracked for the F3 closeout / union-emission task; `lisp_interpreter_curr` (tagged union) is
unaffected.

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
  [updated: 2026-08-01] F-S8 added **`enum_type` and `error_set_type`** — both emit as inline integer
  typedef aliases (`typedef <backing> <cname>;` / `typedef int <cname>;`), so a holder whose field is an
  enum/error_set embeds it by value and must NOT be classified pointer-only. A struct whose *only*
  by-value content is an enum/error_set (e.g. `struct { color: Color, next: *Node }`) moves CLS:p → CLS:v.
  **Note this is a classification-only fix**: `classifyTypeEmissionGroups` has NO `enum_type`/`error_set_type`
  branch, so the enum/error_set **itself** always stays CLS:p (`is_po = 1`, default). Enums are never seeded
  into `shared_set` by classification — their promotion happens via the `computeSharedSet` fixpoint
  (`c89_emit.zig:979`) when a shared member references them (F-S8 `c89NeedsEmitEdge` enum/error_set target
  support). Do not "fix" this by adding an enum CLS:v branch: it would push every enum into the shared
  header and break slice/optional-of-enum ordering (08 §1.17).
- `growWpEdges` (line 535): 2x growth for the backward edge adjacency list.

### Type Expression Resolution

#### `resolveTypeExprFull`

`type_resolver.zig:587-882` — `[inference: switch on AstKind (ident/struct/field_access/error_union/fn/ptr/many_ptr/slice/optional/array), resolve each child recursively, depth-limit 16, return tid or TYPE_UNDEFINED, emit RTD/NF/N2/UND markers]` recursive type expression resolver.

| AST Kind | Lines | Behavior |
|----------|-------|----------|
| `ident_expr` | 591-619 | Lookup, current-module-first (F-task 2026-08-14): name_cache((module_id<<32)\|canonical_id) when `module_id != MODULE_ID_NONE`, then bare name_cache(canonical_id) as the primitive + module-0 named-type fallback, then per-module name_cache scan, then symbolRegistryQualifiedLookup per module. Returns `s.type_id` or `TYPE_UNDEFINED`. Emits `NF`, `N2`, `OPTVOID:*` markers. |
| `struct_decl` | 620-671 | Generate synthetic `anon_<node_idx>` name. Register named type. If payload (extra children), resolve each `field_decl.child_0` recursively, `feAppend` fields, `stAppend` payload. |
| `field_access` | 672-715 | Resolve base expression. If base is `TYPE_UNDEFINED` and base is `ident_expr`, try module-qualified lookup (module symbol → field symbol). If base is `module_type`, lookup field in that module's symbol table. Emits `FAH:*` markers. |
| `error_union_type` | 716-728 | Resolve payload type (child_1) and optional error set (child_0). If no explicit error set, creates empty error set. Returns `typeRegistryGetOrCreateErrorUnion`. |
| `fn_type` | 729-788 | Resolve return type, resolve up to 16 param types. Builds unique name `"fnt_<ret>_<p0>_<p1>..."`. Registers fn type, marks as fn ptr, returns `typeRegistryGetOrCreatePtr(fn_tid, false)`. |
| `ptr_type` | 792-806 | Resolve child as base type. `is_const = (node.flags & 1) != 0`. Returns `typeRegistryGetOrCreatePtr(child, is_const)`. |
| `many_ptr_type` | 792-806 | Same as ptr but `typeRegistryGetOrCreateManyPtr`. |
| `slice_type` | 814-827 | `is_const = (node.flags & 1) != 0`. Returns `typeRegistryGetOrCreateSlice(child, is_const)`. |
| `optional_type` | 828-833 | Returns `typeRegistryGetOrCreateOptional(child)`. |
| `array_type` | 834-877 | Resolves element type (child_0). Evaluates length from child_1: supports `int_literal`, `add/sub`, `mul`/`div`/`mod_op` (F6, 2026-08-06), or `ident_expr` (via `evalConstU32Full`). Returns `typeRegistryGetOrCreateArray(elem, len)` or `TYPE_UNDEFINED` for zero-length. Emits `T0`, `T1`, `T2`, `T3` markers. |

**[updated: 2026-08-06] Array-size mul/div/mod (F6, commit `6dd614e7`):** the `array_type` arm's
size-node evaluation (type_resolver.zig:869-911) previously handled only `int_literal`,
`add`/`sub`, and `ident_expr`; a `mul`/`div`/`mod_op` size node (e.g. `[ROWS * COLS]u8`) fell
through all branches → `arr_len` stayed 0 → `if (arr_len != 0)` (line 899) was false →
`TYPE_UNDEFINED` (line 911). F6 adds the mul/div/mod arm (type_resolver.zig:888-896): it evaluates
both children via `evalConstU32Full`, and when neither is the `0xFFFFFFFF` unknown-sentinel AND
the divisor is non-zero, computes `lhs * rhs` / `lhs / rhs` / `lhs % rhs`. The arrays now resolve
(verified: `comptime_array_size_gap` emits `u8[4000]`/`u8[40]`/`u8[2]`).

#### `evalConstU32Full`

`type_resolver.zig:557-576` — `[inference: return int_literal int_values[node.payload], recurse into ident_expr decl.child_1, fallback 0xFFFFFFFF sentinel]` constant u32 expression evaluator:

1. **int_literal**: returns stored `int_values[node.payload]`
2. **ident_expr**: looks up symbol. If symbol `type_id == 0` and `flags & 0x01 == 0`, recursively evaluates `decl.child_1`
3. **Fallback**: returns `0xFFFFFFFF` (sentinel for "unknown")

Helper `symbolLookupAllModules` (line 578): linear scan of all symbol tables for a `name_id`.

#### `resolveDeclAggregateFieldTypes`

`type_resolver.zig:884-935` — `[inference: nameCacheGet lookup by (mod<<32)|name_id, walk field children, resolveTypeExprFull each field_decl.child_0, write result to fe_items[].type_id, emit B2/FSW/DFT/FTW/DTWR/TUI markers]` resolves field type annotations for struct/tagged_union declarations that have inline field type expressions.

#### `resolveNamedTypeExpressions`

`type_resolver.zig:949-971` — `[inference: iterate modules/decls, filter by varDeclInitNeedsNameCache, resolveTypeExprFull on init, nameCachePut under (mod<<32)|name_id]` iterates top-level `var_decl`s where init expression is a type expression (not an inline type decl, import, ident, or fn_decl).

#### `resolveAggregateFieldTypesAll`

`type_resolver.zig:973-991` — `[inference: iterate modules/decls, filter struct_decl/union_decl inits, call resolveDeclAggregateFieldTypes for each]` iterates all modules' top-level var_decls whose init is `struct_decl` or `union_decl`.

#### `resolveFnSignatures`

`type_resolver.zig:993-1058` — `[inference: iterate modules/decls, resolve fn return/param types via resolveTypeExprFull, create fn via typeRegistryGetOrCreateFn, resolve var_decl type annotations, update symbol.type_id and ResolvedTypeTable]` iterates all modules:
- **fn_decl**: resolves return type and param types via `resolveTypeExprFull`, creates fn type via `typeRegistryGetOrCreateFn`, records in `ResolvedTypeTable`, sets `symbol.type_id`. Reads `decl.flags & 0x01` → `is_variadic` and passes it through (2026-08-06); the fn-pointer path (`resolveTypeExprFull`, type_resolver.zig:816) always passes `is_variadic=0`.
- **var_decl with explicit type annotation** (child_0 != 0): resolves type expression, records in `ResolvedTypeTable`, sets `symbol.type_id`.

#### `typeResolverResolveNames` (entry point)

`type_resolver.zig:1060-1075` — orchestrates all name resolution:
1. `resolveNamedTypeExpressions` — var_decl type expressions
2. `resolveImportFieldAliases` — import re-export field aliases (`pub const Arena = @import(...).Arena`)
3. `resolveAggregateFieldTypesAll` — field type annotations
4. `resolveFnSignatures` — fn signatures + annotated var types

#### D2 defect — bare `ident_expr` type resolution — FIXED (F1) [updated: 2026-08-14]

`resolveTypeExprFull`'s `ident_expr` arm (type_resolver.zig:670-698) resolves a bare type name
(e.g. a fn return type `Arena`) in three tiers:

1. **global name_cache** (line 675): `nameCacheGet(typereg, canonical_id)` — the bare `name_id`
   key, populated only for primitive names by `registerPrimitiveName` (type_registry.zig:625-631).
2. **per-module name_cache scan** (lines 680-684): `while (mi < tables_len)` builds key
   `(mi << 32) | canonical_id` and returns the **first** matching module's TypeId — starting at
   module 0, not the *referencing* module.
3. **symbol scan** (lines 686-695): `symbolRegistryQualifiedLookup` over each module table, again
   lowest module_id first.

Tier 2 is the defect: it returns module **0**'s type for a same-named type that also exists in a
later module instance. So `create()` in module instance N resolves its return type `Arena` to
module 0's `Arena` TypeId (`module_id == 0`), not instance N's own `Arena` (`module_id == N`).
The `field_access` arm (lines 751-794) does NOT have this problem — `arena_mod.Arena` resolves the
base `module_type` then looks the field up in *that* module's table (line 780-789), so
`mod_a.makeA() arena_mod.Arena` correctly targets instance N's type while `create() Arena` (bare)
targets instance 0's.

Emission consequence (D2): the struct typedef is emitted from the type's *own* `module_id` (so the
instance-N `Arena` typedef mangles to `zT_..._Arena_N`, collision-suffixed in `nameManglerMangle`),
but the fn signature/return type references the *module-0* TypeId, so it emits the unsuffixed
`zT_..._Arena` — gcc rejects the emitted C as `return type is an incomplete type`. Reproduced by
`repro/mi_matrix/arena_multi_inst_xmod/` (two-path import `a/std_arena.zig` + `b/std_arena.zig`).
**Fix locus (F1):** thread the referencing `module_id` through `resolveTypeExprFull` / the
`TypeResolveEnv` and resolve bare `ident_expr` type names against the current module's symbol table
first, falling back to the all-modules scan only for primitives. Blast radius: only
`arena_multi_inst_xmod` hits instance-≥1 same-name types; mud_server/rogue_mud use their own
`sand.zig` allocator (no `std_arena`), and the 4 MD5 gates are single-instance → 0 gate impact.

**FIXED (F1, 2026-08-14).** `TypeResolveEnv` gained a `module_id: u32` field (type_resolver.zig:32),
with sentinel `MODULE_ID_NONE = 0xFFFFFFFF` (type_resolver.zig:24) meaning "no module context"
(global fallback). The `ident_expr` arm now resolves the current module's name_cache entry
(type_resolver.zig:682-686) and symbol-table entry (type_resolver.zig:694-701) **before** the
all-modules scan (preserved as the fallback for primitives/globals). Every `resolveTypeExprFull`
call site sets `module_id` explicitly: `resolveFnSignatures` / `resolveNamedTypeExpressions` /
`resolveDeclAggregateFieldTypes` thread `mods[mi].id`/`mod_id`; sema sites use `fs.module_id` /
`mfs.module_id` / `s.module_id` / `self.module_id`; lower sites use `self.module_id`; main.zig
threads `mods[mi].id` through `resolveStmtTypes`/`resolveTypeExpr`; the genuinely-global sites
(comptime `@sizeOf`/`@alignOf`/`@intCast` type args, enum backing type) use `MODULE_ID_NONE`. The
`field_access` arm is untouched. `arena_multi_inst_xmod` now emits self-consistent headers
(`Arena_1` typedef ↔ `create() → Arena_1`) and runs (prints `0`).

**[updated: 2026-08-14 — F-task root-cause fix]:** the bare name-cache key (`nid`, written by
`registerPrimitiveName`, type_registry.zig:630) collides with module-0's scoped key
(`(0<<32)|name_id == name_id`, written by `typeRegistryRegisterNamedType`). Any un-scoped
`nameCacheGet(nid)` therefore silently resolved module-0-first. The F1 reorder was still vulnerable
because its STEP-1 bare `nameCacheGet(canonical_id)` ran before the current-module lookup. The
F-task fix reorders the `ident_expr` arm so the current-module scoped lookup
(`(module_id<<32)|canonical_id`) runs FIRST, the bare lookup runs SECOND (now the primitive +
module-0 named-type fallback, since primitives *and* module-0 named types are stored under the bare
key — that shared key IS the collision), and the all-modules scan runs THIRD. The `field_access` arm and the symbol-lookup tiers (`:694-711`) are unchanged. For module 0
the scoped key equals the bare key, so the reorder is a no-op (control behavior preserved).

---

## const_alias_prepass.zig (`sf/src/const_alias_prepass.zig`, 224 lines)

Resolves `const Alias = TypeName` patterns where the RHS is a simple identifier referring to another type.

### Functions

| Function | Line | Scope | `[inference]` | Description |
|----------|------|-------|---------------|-------------|
| `resolveWellKnownTypeName` | 15 | private | `[inference: switch on string length (2-5), byte-compare for built-in type names, return sentinel or TYPE_UNDEFINED]` | Matches string names to TypeId sentinels: void(4), bool(4), i32/u32(3), u64/i64(3), f32/f64(3), i8/u8(2), usize/isize(5). Returns `TYPE_UNDEFINED` for non-well-known. |
| `growDep` | 41 | private | `[inference: 2x growth (min 16), sandAlloc for to/next arrays, copy old elements, update pointers and cap]` | Grows the dependency tracking arrays (`to_ptr`, `next_ptr`) used during constAliasPrepass catalog phase. |
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
      (1) name_cache(name_id only)  → global/primitive name
      (2) name_cache((alias mod_id)<<32 | name_id)  → alias's declaring-module name  [F-task 2026-08-14]
      (3) name_cache(module<<32 | name_id) scan  → per-module fallback
      (4) resolveWellKnownTypeName → "void", "i32", etc.
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
    ├─ typeResolverInit (type_resolver.zig:226)
    │   └─ zero init
    │
    ├─ typeResolverBuildDependencyGraph (type_resolver.zig:373)   [Defect D fix, F5]
    │   ├─ iterate all types
    │   ├─ struct/tagged_union/union → layoutAddFieldEdges (real field_type -> container)
    │   ├─ array/tuple → elem edge; optional/error_union → payload edge
    │   └─ skips pointer/slice/fn/error_set/primitive/void fields (embeds-by-value rule)
    │
    ├─ typeResolverBuild (type_resolver.zig:244)
    │   ├─ copy DepGraph edges from symbol_registrator (dummy 0->tid) + real F5 edges
    │   ├─ alloc sorted_items[0..types_len]
    │   ├─ alloc in_degree_items[0..types_len]
    │   └─ count edges per target type
    │
    ├─ typeResolverResolve (type_resolver.zig:269)
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
    └─ All Type entries with state=2 (resolved). Size/alignment are populated for the 8
        layout kinds; NOT for named error_set types (no error_set branch in
        typeResolverResolveLayout) and NOT for zero-size sentinels (void/noreturn/null/type).

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

Type ID values are dense monotonically increasing u32s starting at 0. Sentinels occupy 0-21 (index 0 is `none_sentinel` sentinel at type_id=0, though TYPE_VOID=1 is the first meaningful type; TYPE_VA_LIST=21 added 2026-08-06). The stale `FIRST_USER_TYPE = 20` constant means user types in practice start at TypeId ≥ 22.

To trace a specific TypeId through the pipeline:
- Search `DC:k*` for creation
- Search `RN:t<id>` for named type registration
- Search `NP:v<id>` for cache population
- In type_resolver.zig: `RTD:n<node>k<kind>` traces every `resolveTypeExprFull` entry
  (type_resolver.zig:609-612)

### Known Issues

1. **Linear dedup for fn_type** (type_registry.zig:501-507): `typeRegistryGetOrCreateFn` does a full scan of `types_items` on every call. No hash cache.

2. **typeRegistryGetOrCreateModule** (type_registry.zig:561-566): Linear scan of all types for matching `module_type+module_id`. No hash cache.

3. **No hash cache for optional when unresolved** (type_registry.zig:408): `optional_cache` only gets populated if `opt_state == 2` (payload resolved). Unresolved optionals will miss cache on subsequent lookups.

4. **Depth limit in resolveTypeExprFull** (type_resolver.zig:610): Hardcoded max depth of 16. Deeply nested type expressions will silently return `TYPE_UNDEFINED`.

5. **evalConstU32Full fallback ambiguity** (type_resolver.zig:579-597): `0xFFFFFFFF` return value is both a valid u32 and the sentinel for uncomputable. Cannot distinguish "zero-sized array length 0xFFFFFFFF" from "failed to evaluate".

7. **SURFACED (2026-08-13, F5): plain untagged `union` layout vs C emission mismatch.** A bare `union` layout uses the max-member model (`typeResolverResolveLayout` union branch, `size = alignUp(max_sz, max_align)`), but c89_emit emits a plain union as a C `struct` with ALL variants stacked (e.g. lisp_interpreter `ValueData` → 32-byte C struct) — so a union-holding struct's `@sizeOf` can under-size the emitted C struct, overflowing arena bump-alloc slots. Pre-fix masked by the Defect D 1/1 clamp; post-F5 `lisp_interpreter` `(+ 1 2)` SEGFAULTs (was silent fail) because eval now runs against the still-mismatched Value size. Tagged unions are unaffected (emitted correctly). Tracked for the F3 closeout / union-emission task.

6. **FIXED (2026-08-08, F1): `@ptrToInt` now resolves to `usize` for single-arg calls.** The `builtin_call` resolver (semantic_analyzer.zig:1290-1312) had the `@ptrToInt → TYPE_USIZE` branch nested *inside* the `ec.len >= 2` guard, making it dead code for the single-arg `@ptrToInt(x)` form — the call fell through to the `ec.len >= 1` branch and returned the *argument's* type (a pointer). An untyped `const current_pos = @ptrToInt(ptr);` was typed as the pointer, and a following `(current_pos + mask) & ~mask` chain failed `semanticAnalyzerResolveBitwise` (both operands must be equal integer types; semantic_analyzer.zig:529) → const init resolved to `TYPE_VOID` → `error[3000]` (semantic_analyzer.zig:1727-1734, the void-var rejection emits at :1734). Fix: the `ptrtoint_name_id` check is now hoisted above the `ec.len` dispatch (semantic_analyzer.zig:1298-1301), mirroring the lowerer's already-correct handling (lower.zig:2653-2657):
   - `if (node.child_0 == self.ptrtoint_name_id) { if (ec.len >= 1) _ = semanticAnalyzerResolveExpr(self, ec[0]); result = type_mod.TYPE_USIZE; }`
   - Result: `@ptrToInt` resolves to `TYPE_USIZE` regardless of arg count; multi-arg path semantics unchanged. Verified: `repro/mi_matrix/ptr_to_int_void_xmod` dump rc=0/gcc rc=0/run prints 1; `examples/z98/lisp_interpreter` + `lisp_interpreter_curr` dump rc=0; mud/gol/json MD5 gates byte-identical; lisp_interpreter_curr MD5 re-baselined `fad41183…` → `a12f2fcebc30f2d8c2a148facb9d1174` with byte-identical runtime output.

---

## Evidence: 4 Working Examples (Deep-Dive P3)

Traces: `/tmp/dd/*.mrk` (P0, `zig1 --markers --dump-c89`). The TypeResolution phase window is
bounded by `T` (main.zig:290) and `CE` (main.zig:327); extraction via
`awk '/^T$/{f=1}f{print}/^CE$/{exit}'`. Registry/layout/order data obtained by GDB on a debug
bootstrap build of the same source (`zig0 --header-priority-include`, `gcc -m32 -g -O0`), breaking
at `classifyTypeEmissionGroups` entry (after `typeResolverResolve`, so all types are resolved) and
dumping `self->registry` (`[gdb]`). The debug build reproduces the P0 marker stream, so both
evidence sets describe the same compiler.

Final `types_len` per example (== `sorted_len`): mud_server 61, game_of_life 41, json_parser 76,
lisp_interpreter_curr 105. All types reach `state=2`; zero `ERR_3005` cycle reports.

### Q1. TypeId assignments: sentinels vs user types

Sentinels are TypeIds 0-20 (0 = `none_sentinel`; 1-20 = TYPE_VOID..TYPE_TYPE, state=2 from
`typeRegistryRegisterPrimitives`, type_registry.zig:579-619). The first user type is 21. Named
user types are registered in pass 1 (`RN:` markers, type_registry.zig:645-661; `DC:k<kind>...`
type_registry.zig:158-170) in module-ID + declaration order:

| Example | TypeId | Kind | Name | Module |
|---------|:------:|------|------|:------:|
| mud_server | 21, 22, 27 | module | std, util, std_debug | m1, m2, m3 |
| mud_server | 23 | struct | plat_fd_set | m0 |
| mud_server | 24 | struct | Player | m0 |
| mud_server | 25 | struct | Room | m0 |
| mud_server | 26 | tagged_union | Command | m0 |
| game_of_life | 21, 24 | module | std, std_debug | m1, m2 |
| game_of_life | 22 | tagged_union | Cell | m0 |
| game_of_life | 23 | struct | Point | m0 |
| json_parser | 21, 22 | module | file, json | m1, m2 |
| json_parser | 23 | error_set | FileError (4 tags) | m1 |
| json_parser | 24 | struct | JsonItem | m2 |
| json_parser | 25 | tagged_union | JsonValue | m2 |
| json_parser | 26 | error_set | ParseError (7 tags) | m2 |
| json_parser | 27 | struct | Parser | m2 |
| lisp | 21-29 | module | sand, value, token, parser, env, eval, builtins, util, deep_copy | m1-m9 |
| lisp | 30 | struct | Sand | m1 |
| lisp | 31 | tagged_union | Value | m2 |
| lisp | 32 | tagged_union | Token | m3 |
| lisp | 33 | struct | Tokenizer | m3 |
| lisp | 34 | struct | EnvNode | m5 |
| lisp | 35 | error_set | LispError (22 tags) | m8 |
| lisp | 38 | struct | anon_3546 (inline `Cons: struct {car,cdr}` in value.zig) | m0 |

Evidence: `RN:`/`DC:` markers `[markers]`; `TID <id> kind ... name_id ... mod ...` GDB lines
`[gdb]`; name_id→string mapping via GDB on `TypeRegistry.interner` `[gdb]` (e.g. mud name 43 =
"plat_fd_set", 59 = "Player", 65 = "Room", 76 = "Command"; lisp 55 = "Value", 293 = "anon_3546").
`X:<id>` markers (struct appends, type_registry.zig:171-173) match the struct TypeIds exactly.

Synthetic types created during pass-2 type resolution (not registered, so no `RN:`) continue the
same dense sequence: mud 28 (array), 29 (array), 30 (slice) ... 60 (fn); json 28 (slice) ... 75
(fn); lisp 36 (many_ptr) ... 104 (fn). Module types `module_id` matches the module registry
(GDB); note they are created with `state=0` but the resolve pass flips them to `state=2`
(no-op layout), so all final states are 2.

### Q2. Layout sizes for key structs (GDB `[gdb]`)

`typeResolverResolveLayout` (type_resolver.zig:104-224) computes size/alignment; field offsets are
written back into `fe_items[].offset`. Final values:

| Example | Type | TID | size | align | fields (offset: type) |
|---------|------|:---:|:----:|:-----:|-----------------------|
| mud | plat_fd_set | 23 | 512 | 4 | data [128]u32 (0) |
| mud | Player | 24 | 272 | 4 | socket i32(0), room_id u8(4), buffer [256]u8(5), pos usize(264), is_active bool(268) |
| mud | Room | 25 | 12 | 4 | desc []const u8(0), north u8(8), south u8(9), east u8(10), west u8(11) |
| mud | Command | 26 | 8 | 4 | tag u32 + payload: Go u8 (Look/Quit/Unknown are void fields) |
| mud | !void (main ret) | 51 | 8 | 4 | empty error set (TID 50, size 4) + void payload |
| gol | Cell | 22 | 4 | 4 | tag u32 only (Dead/Alive are void variants) |
| gol | Point | 23 | 8 | 4 | x usize(0), y usize(4) |
| json | FileError | 23 | 0 | 0 | error_set, 4 tags (no layout branch) |
| json | JsonItem | 24 | 16 | 4 | key []const u8(0), value ?*JsonValue(8) |
| json | JsonValue | 25 | 16 | 8 | tag u32 + max payload 8 (f64 / []const u8 / []JsonValue / []JsonItem) |
| json | ParseError | 26 | 0 | 0 | error_set, 7 tags (no layout branch) |
| json | Parser | 27 | 16 | 4 | input []const u8(0), pos usize(8), arena *void(12) |
| json | ParseError!JsonValue | 65 | 8 | 4 | eu: payload(4) + err(4) |
| lisp | Sand | 30 | 12 | 4 | start [*]u8(0), pos usize(4), end usize(8) |
| lisp | Value | 31 | 16 | 8 | tag u32 + max payload 8 (i64 forces align 8; Cons anon struct also 8) |
| lisp | Token | 32 | 16 | 8 | tag u32 + max payload 8 (i64) |
| lisp | Tokenizer | 33 | 12 | 4 | input []const u8(0), pos usize(8) |
| lisp | EnvNode | 34 | 20 | 4 | symbol []const u8(0), value *Value(8), next ?*EnvNode(12) |
| lisp | LispError | 35 | 0 | 0 | error_set, 22 tags (no layout branch) |
| lisp | anon Cons | 38 | 8 | 4 | car *Value(0), cdr *Value(4) |

Field-offset evidence is the GDB `FE <i> name <nid> type <tid> off <off>` dump; sizes/aligns are the
`TID <id> ... size <s> align <a>` dump. Spot-checks against the doc's Layout Resolution rules:
tagged_union `total = tag(4) → alignUp(4,max_pa) + alignUp(max_ps,max_pa)`, optional
`alignUp(alignUp(size,4)+4, pay_align)`, all confirmed by these values.

**Named error_set types end at size=0, alignment=0**: `typeResolverResolveLayout` has no
`error_set_type` branch (the 8 handled kinds are struct/enum/union/tagged_union/optional/
error_union/array/tuple), so FileError/ParseError/LispError keep their initial size/align of 0.
The empty/unnamed error sets created via `typeRegistryGetOrCreateErrorSet`
(type_registry.zig:524-541) are created directly with size=4 align=4 (mud TID 50, gol TID 31).

### Q3. Pointer-only classification (`CLS:` markers `[markers]`)

`classifyTypeEmissionGroups` (type_resolver.zig:332-533) emits `CLS:c<n>` (pointer-only count),
then per type `CLS:p<tid>k<kind>` (pointer-only) or `CLS:v<tid>k<kind>` (value-emitted). Value-
emitted types (everything else is pointer-only):

| Example | value-emitted (CLS:v) | reason |
|---------|----------------------|--------|
| mud_server | 23 plat_fd_set, 24 Player, 47 `[2]Room` | struct with an array field; struct with array field; array of struct |
| game_of_life | (none) | no aggregate value-embeds another |
| json_parser | 65 ParseError!JsonValue | eu whose payload JsonValue is a tagged_union |
| lisp | 31 Value, 71 LispError!Token | Value embeds inline anon struct `Cons`; eu whose payload Token is a tagged_union |

Counts: mud `CLS:c58` (58 pointer-only), gol 41, json 75, lisp 103. Note gol has **zero**
value-emitted types even though Cell/Point are used as values in the program — the classification
is purely structural (field/element embedding), not usage-based. The doc's rule "field of kind
struct/tagged_union/union/array/tuple → NOT pointer-only" (type_resolver.zig:324-330, 371-483)
exactly predicts these sets. The optional/error_union backward-edge path
(type_resolver.zig:379-385) is exercised by json's `?*JsonValue` (JsonItem field) but its payload
is a pointer, so it never flips a parent.

### Q4. const_alias_prepass (`CAP:`/`GATE:`/`CAT:` markers `[markers]`)

`constAliasPrepass` (const_alias_prepass.zig:58-224) only catalogs `SymbolKind.global` symbols
whose `var_decl` init is a bare `ident_expr` (AstKind 24). In all 4 examples the catalog
terminates with `CAP:ac0` (alias_count == 0, early exit at const_alias_prepass.zig:149) and
`KAHN:start`/`KAHN:end` never fire:

| Example | CAP:tlm (total syms) | candidates (GATE/CAT) | result |
|---------|:--------------------:|-----------------------|--------|
| mud_server | 31 | 4 globals, inits kind 10 (int_literal) ×3, kind 16 (undefined_literal) ×1 | CAP:ac0 |
| game_of_life | 17 | 2 globals, inits kind 10 ×2 | CAP:ac0 |
| json_parser | 44 | 3 globals: 1 with no init (GATE:g3), 2 with int_literal inits | CAP:ac0 |
| lisp | 87 | 2 globals, inits kind 16 ×2 | CAP:ac0 |

So no `const X = Y` type aliases exist in these programs (type declarations are inline
`struct/union/enum/error{...}` or `@import`), the 3-phase Kahn propagation is **unexercised**, and
no transitive alias chain can be observed. `json`'s `const File = void` is a `type_alias` symbol
(SymbolKind 4), which the `global`-only gate skips. The doc's description of the prepass
(const_alias_prepass.zig:58-224, §Phases 1-3) matches the source mechanically; it simply never
runs to Phase 2/3 in these examples.

### Q5. Cache hits

Observable via markers `[markers]` (slice_cache `U2H`/`U2N` type_registry.zig:361-384; array_cache
`O1H`/`O2N` type_registry.zig:453-482; fn-type linear scan `P2:n...H` type_registry.zig:504-505;
ptr/many_ptr `PTR:i...c<child>` + inline `P<tid>`/`M<tid>` on hit vs `DC:` on miss
type_resolver.zig:813-832), and via GDB distinct-type counts `[gdb]`:

| Example | ptr_cache (hit/miss) | slice_cache (U2H/U2N) | array_cache (O1H/O2N) | fn linear scan hits | optional resolutions (distinct) |
|---------|:--------------------:|:---------------------:|:---------------------:|:-------------------:|:-------------------------------:|
| mud_server | 6 / 5 | 5 / 2 | 0 / 3 | 0 | 3 (1) |
| game_of_life | 2 / 1 | 3 / 2 | 0 / 0 | 0 | 0 |
| json_parser | 28 / 5 | 6 / 4 | 0 / 0 | 0 | 3 (3) |
| lisp | 97 / 9 | 24 / 3 | 1 / 1 | 0 | 9 (1) |

- **ptr_cache / many_ptr_cache**: heavily hit (lisp 97 of 106 resolutions dedup to 9 distinct ptr
  types). Hit markers are inline (`PTR:i18k84c1P33`), misses interleave a `DC:k17`/`DC:k18`.
- **slice_cache**: hits everywhere (lisp 24 hits, 3 distinct slice types).
- **array_cache**: only lisp has arrays — `[131072]u64` created once, hit once
  (`perm_buf_u64` / `temp_buf_u64`). mud creates 3 arrays ([128]u32, [256]u8, [2]Room), no hits.
- **fn_type linear scan** (type_registry.zig:501-507): **zero hits** in all 4 examples — every fn
  type is unique (fn-type counts equal the per-module fn symbol totals: mud 20, gol 11, json 32,
  lisp 48). Known Issue 1 (linear dedup) is therefore not just slow but never actually dedups here.
- **optional_cache / eu_cache / es_cache**: silent (no markers). Distinct types from GDB:
  optional mud 1 / json 3 / lisp 1 / gol 0; error-union mud 1 / gol 1 / json 4 / lisp 6; error-set
  (es_len) mud 1 (empty) / gol 1 (empty) / json 2 / lisp 2 — [FIXED 2026-07-31: pass-2 no longer doubles ES payload, see Known Issue 6 below].
  lisp's 9 optional resolutions producing 1 distinct type implies 8 optional_cache hits; mud's 3
  resolutions producing 1 distinct implies 2 hits.

### Q6. Kahn algorithm vs actual "topological" order (GDB `[gdb]`)

The doc's Kahn pseudocode (type_resolver.zig:269-322, seed / pop→layout→state=2→decrement→push /
cycle-check) is **mechanically exact** vs source. What it does not say: the DepGraph edge set is
degenerate — every edge is `(from=0, to=<owner type>)` from `addTypeDependencies`
(symbol_registrator.zig:78), so `in_degree` counts only *field counts per aggregate*, and no
type→type dependency edge ever exists. Consequently the resolved order is dominated by TypeId
order, not by field-type dependencies:

| Example | seed (in_degree 0) | pop order (worklist LIFO) | aggregate tail (pushed when tid 0 pops) |
|---------|--------------------|---------------------------|----------------------------------------|
| mud | 0-22, 27-60 | 60,59,...,28,27,22,...,1,0 | 26,25,24,23 (reverse registration) |
| gol | 0-21, 24-40 | 40,...,24,21,...,1,0 | 23,22 (reverse) |
| json | 0-23, 26, 28-75 | 75,...,28,26,23,22,...,1,0 | 27,25,24 (reverse) |
| lisp | 0-29, 35, 36-104 (all but field-owning 30-34; LispError contributes 0 edges) | 104,...,36,35,29,...,1,0 | 34,33,32,31,30 (reverse) |

For mud the full GDB `SORTED` list is `60,59,...,28,27,22,21,20,...,1,0,26,25,24,23`; gol
`40,...,24,21,...,1,0,23,22`; json `75,...,28,26,23,22,...,1,0,27,25,24`. The final push order
(while scanning tid 0's outgoing edges) is registration order, and the LIFO worklist then pops it
in reverse. So the aggregates resolve **last**, in reverse registration order, after sentinel 0.
The order is a *valid* topological order of the actual edge set (0 precedes every aggregate), but
it carries no field-dependency information: e.g. Player's `buffer: [256]u8` type is resolved
before Player even though the array references no aggregate, and a struct referencing a later
struct by value would still be ordered by TypeId. `sorted_len == types_len` in all 4 examples —
no type is left unresolved, no `ERR_3005`.

### Known Issue 6 (cross-doc): [FIXED 2026-07-31] pass-2 payload back-patch clobbers `types_len-1`

`populateTypePayload` (symbol_registrator.zig:84-211) back-patches `types_items[types_len-1]
.payload_idx` after each `stAppend`/`tuAppend`/`enAppend`/`esAppend`. Prior to the F3 fix, pass 2
(`registerModuleSymbols` re-run inside `phase_TypeResolution`, main.zig:296) called
`populateTypePayload` again, and since named types dedup via `nameCacheGet` (type_registry.zig:631)
and append nothing, every back-patch landed on the last type in the registry. F3 fix: pass-2 calls
`registerModuleSymbols` with `populate=false` (symbol_registrator.zig:399), guarding all three
`populateTypePayload` call sites (:255, :343, :360) while still running `addTypeDependencies` for
the DepGraph rebuild. Payload arrays are no longer doubled; `payload_idx` values are stable.
Regression test: `testPayloadStabilityAfterDoublePass` in `test_sym_reg_bin.zig`.

### Doc inaccuracies found (Deep-Dive P3)

| Doc location (pre-edit) | Claim | Reality |
|--------------------------|-------|---------|
| Summary Table (was :8) | TypeKind has 36 variants (0..anon_union=35) | 40 variants, 0..anon_union=39 (type_registry.zig:40-56) |
| Summary Table (was :9) | Type has 9 fields | 10 fields listed (kind,state,flags,_pad,size,alignment,name_id,c_name_id,module_id,payload_idx), 28 bytes total |
| Data Structures (was :496) | "All Type entries with size≠0, alignment≠0, state=2" | named error_set types end at size=0/align=0 (no layout branch); zero-size sentinels too |
| How to Inspect (was :611) | "GR, TR, Ti markers trace resolve entry" | no such markers exist in type_resolver.zig or any trace; the entry marker is `RTD:n<node>k<kind>` (type_resolver.zig:590) |
