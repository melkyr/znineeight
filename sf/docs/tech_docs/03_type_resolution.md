# 03 — Type Resolution [updated: 2026-09-21 — Task B5: `typeRegistryIsAssignable`'s error-union→error-union branch now requires exact payload TypeId equality (`eu_src.payload == eu_tgt.payload`) instead of general payload assignability, so a runtime payload-differing EU→EU coercion (return / assignment / declaration / call argument) clean-rejects with `error[3000]`, matching official Zig's in-memory-payload rule; the same-payload subset path (`F!i32 → E!i32`) is unchanged and byte-identical] [updated: 2026-09-21 — Task B3 item 2: `intValueFitsType` no longer blanket-accepts a `wb >= 64` target; it classifies the cast operand syntactically via the new `evalConstSignClass` (a tri-state mirror of `comptime_eval.comptimeEvalSignClass`) so `@as(u64,-1)`/`@intCast(u64,-1)` in an enum initializer reject (`error[3055]`) while a large non-negative literal/unsigned source stays accepted] [updated: 2026-09-21 — Task B2 fix round 1: `registerContainerType`'s union branch captures `UnionPayload.fields_start` AFTER the field-type resolve loop (a nested aggregate field appends its own `fe` entries, so the old pre-loop capture pointed the union into the nested type's fields); the new `validateLocalEnum` runs the shared strict member walk for inline enums (via `registerContainerType`) as well as the sema binding/expression forms, so `var e: enum(u8){A=1,B=1}` clean-rejects `ERR_3055`] [updated: 2026-09-21 — Task B2: function-local / inline named container types register through ONE helper `registerContainerType` (synthesized `anon_<node_idx>` name + direct struct/union field resolution + shared `populateTypePayload` for enum/error-set); `resolveTypeExprFull`'s `struct_decl` arm delegates and gains `enum_decl`/`union_decl` arms; `TypeResolveEnv` gains a function-local type scope (`LocalTypeScope`) consulted first in the `ident_expr` arm; `layoutEnsure` is now `pub` so sema can lay out a type registered after the layout pass] [updated: 2026-09-21 — Task 11S (a): `evalConstU32Full`'s array-size `@intCast` arm now resolves the target type, folds the operand with the U32 evaluator, and requires `intValueFitsType`, emitting `error[3000]` for an out-of-range/non-integer target (previously the target was ignored — the Task 11F regression)] [updated: 2026-09-21 — Task 11J fix round 1 (AMENDMENT 13): `evalConstI64Full`'s `@as`/`@intCast` arm now requires an integer target and range-checks the folded value against the target width/signedness via the new `intValueFitsType` helper (non-integer target / out-of-range → `null` → `ERR_3055`); `enumMembersResolve` gains a `check_only` mode used by the semantic analyzer for function-local enums] [updated: 2026-09-21 — Task 11J: enum member initializers fold as comptime integer expressions via a post-layout re-evaluation pass (`enumReevaluateAll`) and the shared `enumMembersResolve` walk; `evalConstI64Full` gains a depth cap (16) plus the integer-expression and integer-valued-builtin arms; an unfoldable initializer or a duplicate tag rejects with ERR_3055] [updated: 2026-09-21 — Task 11H: the layout math is factored into `layoutCompute` and reached through one shared, order-independent `layoutEnsure(registry, tid, depth)` used by BOTH the normal topological pass and the array-size fold; `evalConstU32Full` now completes a struct on demand and folds struct `@sizeOf`/`@alignOf`/`@bitSizeOf` in array-size positions (only from `state == 2`)] [updated: 2026-09-21 — Task 11F: `evalConstU32Full` folds the integer-valued builtins (`@intCast`/`@sizeOf`/`@alignOf`/`@bitSizeOf`) in array-size positions; `evalConstScalarKind` restricts the `@sizeOf`/`@alignOf`/`@bitSizeOf` fold to complete primitive/alias types] [updated: 2026-09-20 — refreshed against current source: `front_resolution.zig` front pass, arbitrary-width int/`enum(uN)` layer, packed struct/union kinds, `volatile`/calling-convention type layer, `TYPE_VA_LIST`; line references and dated evidence removed]

> Covers: `type_resolver.zig`, `type_registry.zig`, `const_alias_prepass.zig`, `front_resolution.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `TypeId` sentinels | 21 | TYPE_VOID(1) through TYPE_TYPE(20), TYPE_VA_LIST(21) |
| `TypeKind` variants | 44 | none_sentinel(0) through packed_union_type(43) |
| `Type` fields | 11 | kind, state, flags, is_signed, width_bits, size, alignment, name_id, c_name_id, module_id, payload_idx (32 bytes) |
| Payload structs | 15 | PtrPayload, ArrayPayload, SlicePayload, OptionalPayload, EUPayload, ErrorSetPayload, FnPayload, StructPayload, EnumPayload, UnionPayload, TaggedUnionPayload, TuplePayload, UnresolvedPayload, PackedBitField, PackedStructInfo |
| Per-kind payload arrays | 13 | ptr/array/slice/opt/eu/es/fn/st/en/un/tu/tup/unr |
| Auxiliary arrays | 7 | fe(FieldEntry), em(EnumMember), xt(TypeId list), xn(u32 list), pk(PackedBitField), pk_struct(PackedStructInfo), pk_un(PackedStructInfo) |
| Type caches | 8 | ptr_cache, many_ptr_cache, slice_cache, optional_cache, array_cache, eu_cache, es_cache, name_cache |
| TypeResolver fields | 13 | registry, depend_items/len/cap, in_degree_items/cap, sorted_items/len, worklist_items/len/cap, diag, alloc |
| Layout kinds resolved | 9 | struct (incl. packed), enum, union, packed_union, tagged_union, optional, error_union, array, tuple |
| Debug markers | ~40+ | `DC`, `NP`, `U2H`, `U2N`, `O0`, `O1H`, `O2N`, `P2`, `NGC`, `RN`, `X`, `MC`, `RTD`, `NF`, `N2`, `OPTVOID`, `FAH`, `PTR`, `P`, `M`, `SL`, `T0`-`T3`, `A`, `CAP`, `CAT`, `GATE`, `KAHN`, `CLS`, `FER`, `FSW`, `DFT`, `FTW`, `B2`, `DTWR`, `DTSK`, `TUI`, `UND` |

---

## TypeId Sentinel Values

Defined in `type_registry.zig`:

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

`FIRST_USER_TYPE = 20` — **stale** (see below). Adding the
`va_list` primitive (`TypeKind.va_list_type`, registered by `typeRegistryRegisterPrimitives`,
primitive name `va_list` via `registerPrimitiveName`) shifted every user type id by 1 — the F4
"va_list user-type-id shift" re-baselined the mud/lisp/json MD5 gates for this (gol coincidentally
unchanged). Since primitives now occupy 1-21, user types in practice start ≥22, but the
`FIRST_USER_TYPE` constant in `type_registry.zig` still reads `20` (pre-existing drift:
`TYPE_TYPE` was already a primitive while `FIRST_USER_TYPE` was never bumped). Docs-only task —
the source constant is left unchanged.

---

## type_registry.zig (`sf/src/type_registry.zig`)

Central type store. Flat arrays of `Type` entries indexed by `TypeId` (u32). Per-kind payload arrays hold variable-length data.

### Types

| Type | Description |
|------|-------------|
| `TypeId` | `u32` alias — index into `TypeRegistry.types_items` |
| `TypeKind` (enum u8) | 44 variants: none_sentinel(0), void/bool/noreturn/i8/i16/i32/i64/u8/u16/u32/u64/isize/usize/c_char/f32/f64, ptr/many_ptr/array/slice/optional/error_union/error_set/fn/struct/enum/union/tagged_union/tuple/unresolved_name/type_type/module_type/null_type/undefined_type/integer_literal_type/anon_struct_init/anon_array/anon_tuple/anon_union/va_list_type, arb_uint_type, arb_int_type, packed_union_type |
| `Type` (struct) | `kind(TypeKind, 1B)`, `state(u8, 0=unresolved, 2=resolved)`, `flags(u8)`, `is_signed(u8)`, `width_bits(u8)`, `size(u32)`, `alignment(u32)`, `name_id(u32)`, `c_name_id(u32)`, `module_id(u32)`, `payload_idx(u32)` — 32 bytes total |
| `VOLATILE_FLAG` / `FN_FLAG_VARIADIC` / `FN_FLAG_STDCALL` | flag-bit constants: `VOLATILE_FLAG=2`, `FN_FLAG_VARIADIC=1`, `FN_FLAG_STDCALL=2` |
| `PtrPayload` | `base: TypeId` — shared by ptr_type and many_ptr_type |
| `ArrayPayload` | `elem: TypeId`, `length: u32` |
| `SlicePayload` | `elem: TypeId` |
| `OptionalPayload` | `payload: TypeId` |
| `EUPayload` | `payload: TypeId`, `error_set: TypeId` |
| `ErrorSetPayload` | `tags_start: u32`, `tags_count: u16` |
| `FnPayload` | `name_id, module_id: u32`, `params_start: u32`, `params_count: u16`, `return_type: TypeId`, `is_extern: u8`, `flags_packed: u8` — bit0 `is_variadic`, bit1 `stdcall` |
| `StructPayload` | `fields_start: u32`, `fields_count: u16` |
| `EnumPayload` | `members_start: u32`, `members_count: u16`, `backing_type: TypeId`, `explicit_backing: u8` |
| `UnionPayload` | `fields_start: u32`, `fields_count: u16`, `tag_type: TypeId` |
| `TaggedUnionPayload` | `tag_type: TypeId`, `fields_start: u32`, `fields_count: u16` |
| `TuplePayload` | `elems_start: u32`, `elems_count: u16` |
| `UnresolvedPayload` | `name_id, module_id: u32` |
| `FieldEntry` | `name_id: u32`, `type_id: TypeId`, `offset: u32` |
| `PackedBitField` | `bit_offset: u32`, `bit_width: u16` |
| `PackedStructInfo` | `pk_start: u32`, `pk_count: u16`, `total_bits: u32` |
| `EnumMember` | `name_id: u32`, `value: i64` |
| `FnParam` | `name_id: u32`, `type_id: TypeId` |

### TypeRegistry struct

Defined in `type_registry.zig`:

- **types**: `types_items([*]Type)`, `types_len`, `types_cap`, `types_alloc(*Sand)` — the master type array; TypeId is the index. Also holds `interner(*StringInterner)`.
- **Per-kind payload arrays**: `ptr/array/slice/opt/eu/es/fn/st/en/un/tu/tup/unr` — each with `_items([*]PayloadType)`, `_len(usize)`, `_cap(usize)`
- **Auxiliary arrays**: `fe(FieldEntry)`, `em(EnumMember)`, `xt(TypeId)`, `xn(u32)`, `pk(PackedBitField)`, `pk_struct(PackedStructInfo)`, `pk_un(PackedStructInfo)`
- **Caches**: 8 hash maps — `ptr_cache(U64ToU32Map)`, `many_ptr_cache(U64ToU32Map)`, `slice_cache(U64ToU32Map)`, `optional_cache(U32ToU32Map)`, `array_cache(U64ToU32Map)`, `eu_cache(U64ToU32Map)`, `es_cache(U64ToU32Map)`, `name_cache(U64ToU32Map)`

### Functions

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `typeRegistryInit` | pub | `[inference: zero-init all arrays, init 8 caches via u64ToU32MapInit/u32ToU32MapInit, return TypeRegistry]` | Creates an empty registry. Arrays start undefined, len=cap=0; all 8 hash maps initialized. |
| `typeDbOom` | private | `[inference: print "OOM: type_db <used> -> <new>" to stderr, pal.exit(1)]` | Soft-OOM handler for the type_db arena (see note below). |
| `arrayGrow` | private | `[inference: 2x growth (min 8), sandAlloc, byte-copy old elements, update cap]` | Grows a per-kind payload array. |
| `payloadEnsure` | private | `[inference: no-op if new_cap <= cap, else arrayGrow]` | Capacity guard used by the `*Append` helpers. |
| `typeRegistryEnsureCapacity` | private | `[inference: grow types array (2x, min 32), sandAlloc, copy Type entries]` | Grows `types_items`. |
| `typeRegistryAppend` | private | `[inference: ensure capacity, write Type at types_len, increment len, emit DC:k<n>t marker, emit X:id for struct_type]` | Core append to `types_items`. Returns the new `TypeId` (old `types_len`). |
| `typeWidthBitsForKind` | private | `[inference: map fixed kinds to 8/16/32/64, else 0]` | Bit width for the fixed primitive kinds. |
| `registerPrimitive` | private | `[inference: typeRegistryAppend with state=2, set is_signed/width_bits from kind]` | Appends a resolved (state=2) primitive type. |
| `alignUp` | pub | `[inference: (v + a - 1) & ~(a - 1), round v up to multiple of a, a must be power of 2]` | Aligns `v` up to alignment `a`; used by optional/error-union size computation. |
| `initArray` | private | `[inference: items=undefined, len=cap=0]` | Zero-inits an array slot. |
| `nameCacheGet` | pub | `[inference: u64ToU32MapGet on name_cache, return value or null; emit NGC:g1 marker for key_lo==1]` | Looks up a `(module<<32)\|name_id` key in `name_cache` (also used for bare primitive keys). Returns a cached TypeId or null. |
| `nameCachePut` | pub | `[inference: u64ToU32MapPut on name_cache, emit NP:k<key_lo_16bits>v<value> marker]` | Stores a `(module<<32)\|name_id` → TypeId mapping. |
| `typeRegistryGetOrCreatePtr` | pub | `[inference: delegate to typeRegistryGetOrCreatePtrQ(is_volatile=false)]` | Creates/retrieves `*T`. |
| `typeRegistryGetOrCreatePtrQ` | pub | `[inference: key = (base<<2) \| (is_const \| is_volatile<<1), ptr_cache check, ptrAppend, append size=4 align=4 flags=q]` | Creates/retrieves `*T` with `const`/`volatile` qualifiers (`VOLATILE_FLAG` bit). |
| `typeRegistryGetOrCreateManyPtr` | pub | `[inference: delegate to typeRegistryGetOrCreateManyPtrQ(is_volatile=false)]` | Creates/retrieves `[*]T`. |
| `typeRegistryGetOrCreateManyPtrQ` | pub | `[inference: same as ptr but many_ptr_cache, kind=many_ptr_type]` | Creates/retrieves `[*]T` with qualifiers. |
| `typeRegistryGetOrCreateSlice` | pub | `[inference: key = (elem<<1) \| is_const, slice_cache check, emit U2H hit or U2N new marker, sliceAppend, append size=8 align=4]` | Creates/retrieves `[]T`. Size=8 (ptr+len), align=4. |
| `typeRegistryGetOrCreateOptional` | pub | `[inference: optional_cache check, if payload resolved compute size/align, optAppend, append, cache put only if state=2]` | Creates `?T`. If payload resolved, `size = alignUp(alignUp(payload.size,4)+4, max(payload.align,4))`. |
| `typeRegistryGetOrCreateErrorUnion` | pub | `[inference: eu_key = (payload<<32) \| error_set, eu_cache check, compute union_size=max(payload.size,4), total=alignUp(alignUp(union_size,union_align),4)+4, size=alignUp(total,union_align)]` | Creates `E!T` error-union type. |
| `typeRegistryGetOrCreateArray` | pub | `[inference: key = (elem<<32) \| length, array_cache check, emit O0/O1 markers, arrayAppend, size=elem.size*length, cache put only if elem resolved, emit O2 marker]` | Creates `[N]T`. |
| `typeRegistryGetOrCreateTuple` | pub | `[inference: tupAppend(TuplePayload), append(state=2,size=0,align=1), no caching]` | Creates a tuple type; size computed later by the layout resolver. |
| `typeRegistryGetOrCreateFn` | pub | `[inference: linear scan for matching fn_type+name_id+module_id+stdcall bit, fnAppend(FnPayload), append(size=4,align=4,name_id), emit P2 marker]` | Creates/retrieves a function type. `is_variadic` is `flags_packed` bit0 (`FN_FLAG_VARIADIC`), `call_conv==1` sets bit1 (`FN_FLAG_STDCALL`). |
| `typeRegistryMarkFnPtrUsed` | pub | `[inference: types_items[tid].flags \|= 1]` | Marks that this fn type is referenced as a pointer (enables C89 fn-ptr emission). |
| `typeRegistryGetOrCreateErrorSet` | pub | `[inference: key = FNV-fold of tag names, es_cache check, esAppend, append(size=4,align=4), cache put]` | Creates an error-set type. Tags are `xn_items[tags_start..tags_start+tags_count]`. |
| `typeRegistryErrorSetMemberIndex` | pub | `[inference: bounds check, linear scan of xn_items for matching name_id]` | Returns the member index within an error set, or `0xFFFFFFFF` if not found. |
| `typeRegistryGetOrCreateModule` | pub | `[inference: linear scan for matching module_type+module_id, append(state=0), emit MC marker]` | Creates/retrieves a module type reference. |
| `typeRegistryRegisterPrimitives` | pub | `[inference: registerPrimitive for kinds 0-21, then registerPrimitiveName for the named ones]` | Populates sentinel TypeIds 0-21 (none_sentinel + 21 named primitives: void, bool, i8-i64, u8-u64, isize, usize, c_char, f32, f64, null, undefined, type, va_list). |
| `registerPrimitiveName` | private | `[inference: interner.intern name, set Type.name_id, nameCachePut(key=name_id, value=tid)]` | Interns a primitive name and registers it in `name_cache` under the bare `name_id` key. |
| `parseArbIntWidth` | pub | `[inference: parse uN/iN name; u1..u64, i1..i63; 0 on invalid]` | Parses an arbitrary-width integer type name. |
| `typeRegistryGetOrCreateArbInt` | pub | `[inference: parseArbIntWidth, name_cache check, carrier = 1/2/4/8 by width, append arb_uint_type/arb_int_type with width_bits/is_signed, registerPrimitiveName]` | Creates an arbitrary-width int type (`uN`/`iN`); the carrier is 1 byte for width ≤8, 2 for ≤16, 4 for ≤32, 8 for ≤64. |
| `typeRegistryEnumBackingType` | pub | `[inference: enum_type → en_items[payload].backing_type, else TYPE_U32]` | Returns an enum's backing TypeId. |
| `typeRegistryEnumHasExplicitBacking` | pub | `[inference: enum_type → en_items[payload].explicit_backing != 0]` | Whether the enum declared an explicit `(uN)`/int backing. |
| `typeRegistryIntWidthBits` | pub | `[inference: enum → backing width; arb → width_bits; else typeWidthBitsForKind]` | Bit width of an integer / enum-backed / arbitrary-width type (0 otherwise). |
| `typeRegistryIntIsSigned` | pub | `[inference: enum → backing signedness; arb_int → true; arb_uint → false; fixed kinds by kind]` | Signedness of an integer / enum-backed / arbitrary-width type. |
| `typeRegistryRegisterNamedType` | pub | `[inference: key = module_id*2^32 + name_id, nameCacheGet check, append kind+name_id+module_id, nameCachePut, emit RN marker]` | Registers a user-defined named type (struct, enum, union, etc.). State=0 (unresolved). |
| `isValueDependency` | pub | `[inference: true for struct/union/tagged_union/array/optional/error_union/tuple/unresolved_name]` | Whether this kind participates in value dependency (used by the dep-graph builder). |
| `typeRegistryGetTypeState` | pub | `[inference: read types_items[tid].state]` | Returns the resolution state (0=unresolved, 2=resolved). |
| `typeRegistryIsNumeric` | pub | `[inference: fixed int kinds + arb types + f32/f64 + integer_literal]` | Numeric types. |
| `typeRegistryIsInteger` | pub | `[inference: same as IsNumeric minus f32/f64]` | Integer types only (fixed + arbitrary-width + integer_literal). |
| `typeRegistryIsUnsigned` | pub | `[inference: u8/u16/u32/u64/usize + arb_uint_type]` | Unsigned integer types only. |
| `typeRegistryIsPointer` | pub | `[inference: kind == ptr_type or many_ptr_type]` | Regular or many-item pointer. |
| `typeRegistryIsSlice` | pub | `[inference: kind == slice_type]` | Slice type. |
| `typeRegistryGetPointeeType` | pub | `[inference: if ptr/many_ptr, return ptr_items[payload_idx].base; else null]` | Returns the base type of a pointer. |
| `typeRegistryArrayByteSize` | pub | `[inference: if array_type and state==2, return size; else null]` | Byte length of a concrete array (used by the `-fsafe` `@asyncInit` buffer check). |
| `typeRegistryGetSliceElem` | pub | `[inference: if slice_type, return slice_items[payload_idx].elem; else null]` | Returns the element type of a slice. |
| `typeRegistryIndexedElemType` | pub | `[inference: array→array.elem, slice→slice.elem, ptr→pointee (deref array), else TYPE_UNDEFINED]` | Element type for indexing `base_tid[i]`; handles `*[N]T` → `T`. |
| `typeRegistryIsOptional` | pub | `[inference: kind == optional_type]` | Is this an optional type? |
| `typeRegistryIsErrorSet` | pub | `[inference: kind == error_set_type]` | Is this an error-set type? |
| `typeRegistryGetStructFields` | pub | `[inference: resolve StructPayload, return slice of fe_items]` | Returns struct field entries (with computed offsets). |
| `typeRegistryIsPacked` | pub | `[inference: struct_type with flags & 0x10]` | Whether a struct is packed. |
| `typeRegistryComputePackedLayout` | pub | `[inference: per-field bit widths (bool=1, nested packed struct=its total_bits, else int width), accumulate total_bits, size=ceil(bits/8) min 1, align=1]` | Computes a packed struct's bit layout and writes `pk_struct_items[payload_idx]`. |
| `typeRegistryGetPackedBitFields` | pub | `[inference: packed struct → slice of pk_items, else false]` | Returns the packed bit-field entries. |
| `typeRegistryGetPackedTotalBits` | pub | `[inference: packed struct → total_bits, else 0]` | Total bit width of a packed struct. |
| `typeRegistrySetPacked` | pub | `[inference: flags \|= 0x10]` | Marks a struct type as packed. |
| `typeRegistryComputePackedUnionLayout` | pub | `[inference: max member bit width, size=ceil(max_bits/8) min 1, align=1]` | Computes a packed union's bit layout and writes `pk_un_items[payload_idx]`. |
| `typeRegistryGetPackedUnionBitFields` | pub | `[inference: packed_union_type → slice of pk_items, else false]` | Returns the packed-union bit-field entries. |
| `typeRegistryGetPackedUnionTotalBits` | pub | `[inference: packed_union_type → max bits, else 0]` | Max member bit width of a packed union. |
| `typeRegistryGetUnionFields` | pub | `[inference: resolve UnionPayload, return slice of fe_items]` | Returns union field entries. |
| `pointerQualifiersMonotone` | pub | `[inference: ((src_flags & mask) & ~(tgt_flags & mask)) == 0]` | Qualifier-monotonicity helper (no dropping `const`/`volatile`). |
| `typeRegistryIsAssignable` | pub | `[inference: ~30 rule branches for implicit coercion]` | Type assignability check. See [typeRegistryIsAssignable Rules](#typeregistryisassignable-rules). |
| `errorSetIsSubset` | pub | `[inference: every source tag name_id is a member of the target set]` | Error-set subset check used by error-union assignability. |
| `canLiteralFitInType` | pub | `[inference: range check per fixed integer type, true for f32/f64]` | Whether an `i64` value fits in the given fixed integer type (see Known Issues for arbitrary-width coverage). |

### *Append Helpers

All follow same pattern: `payloadEnsure` → write at `len` → `len += 1`.

| Helper | Scope | Payload Type |
|--------|-------|-------------|
| `ptrAppend` | private | `PtrPayload` |
| `arrayAppend` | private | `ArrayPayload` |
| `sliceAppend` | private | `SlicePayload` |
| `optAppend` | private | `OptionalPayload` |
| `euAppend` | private | `EUPayload` |
| `esAppend` | pub | `ErrorSetPayload` |
| `fnAppend` | private | `FnPayload` |
| `stAppend` | pub | `StructPayload` (also seeds `pk_struct_items`) |
| `pkFieldAppend` | pub | `PackedBitField` |
| `pkStructAppend` | private | `PackedStructInfo` |
| `pkSetFields` | pub | `PackedStructInfo` (overwrite by index) |
| `enAppend` | pub | `EnumPayload` |
| `unAppend` | pub | `UnionPayload` (also seeds `pk_un_items`) |
| `pkUnStructAppend` | private | `PackedStructInfo` |
| `pkUnSetFields` | pub | `PackedStructInfo` (overwrite by index) |
| `tuAppend` | pub | `TaggedUnionPayload` |
| `tupAppend` | pub | `TuplePayload` |
| `unrAppend` | private | `UnresolvedPayload` |
| `feAppend` | pub | `FieldEntry` |
| `emAppend` | pub | `EnumMember` |
| `xtAppend` | pub | `TypeId` |
| `xnAppend` | pub | `u32` |

Note: `stAppend`/`unAppend` also append a zeroed `PackedStructInfo` to the parallel `pk_struct`/`pk_un` side table; `pkSetFields`/`pkUnSetFields` overwrite it by index (no append). `xtAppend` and `xnAppend` use `elem_size=4` (u32), unlike the struct-payload `*Append` helpers which use `@sizeOf(PayloadStruct)`.

**[updated: 2026-08-14 — F-TYPEDB soft OOM]:** `arrayGrow` and `typeRegistryEnsureCapacity` no longer `catch unreachable` on a failed `sandAlloc` from the type_db growable arena — both route through the new `typeDbOom(used, new_bytes)` helper, which prints `OOM: type_db <used> -> <new>` to stderr (mirroring the `sandAlloc` OOM diagnostic style) and exits `pal.exit(1)` (soft OOM, visible to `--track-memory`, instead of a panic). The type_db arena is pool-backed via the unified growable pool (Task 3), so its OOM only fires on true pool exhaustion.

### Type Caches

| Cache | Key Type | Key Construction | Used By |
|-------|----------|-----------------|---------|
| `ptr_cache` | u64 | `(base << 2) \| (is_const \| is_volatile<<1)` | `typeRegistryGetOrCreatePtrQ` |
| `many_ptr_cache` | u64 | `(base << 2) \| (is_const \| is_volatile<<1)` | `typeRegistryGetOrCreateManyPtrQ` |
| `slice_cache` | u64 | `(elem << 1) \| is_const` | `typeRegistryGetOrCreateSlice` |
| `optional_cache` | u32 | `payload TypeId` | `typeRegistryGetOrCreateOptional` |
| `array_cache` | u64 | `(elem << 32) \| length` | `typeRegistryGetOrCreateArray` |
| `eu_cache` | u64 | `(payload << 32) \| error_set` | `typeRegistryGetOrCreateErrorUnion` |
| `es_cache` | u64 | XOR-fold FNV hash of tag name_ids | `typeRegistryGetOrCreateErrorSet` |
| `name_cache` | u64 | `(module_id << 32) \| name_id` (bare key for primitives) | `typeRegistryRegisterNamedType`, `registerPrimitiveName`, `typeRegistryGetOrCreateArbInt`, `resolveTypeExprFull`, `constAliasPrepass`, `front_resolution.zig` |

### typeRegistryIsAssignable Rules

Implicit coercion rules (`typeRegistryIsAssignable`, with helper `pointerQualifiersMonotone` for `const`/`volatile` and `errorSetIsSubset` for error sets):

1. **Identity**: `source == target` → true
2. **Undefined / noreturn source**: `undefined_type → any`, `noreturn_type → any` → true
3. **Integer literal → numeric / c_char**: `integer_literal_type → any numeric type or TYPE_C_CHAR` → true
4. **Integer widening (same sign, wider)**: both integer, `source != TYPE_INT_LIT`, same `typeRegistryIsUnsigned`, and `typeRegistryIntWidthBits(source) < typeRegistryIntWidthBits(target)` → true (covers arbitrary-width ints and `enum(uN)` backing)
5. **Float widening**: `f32 → f64` → true
6. **null → pointer/optional/fn**: `null_type → *T, ?T, fn` → true
7. **fn → fn pointer**: `fn_type → *fn` when return type, param count, variadic bit, stdcall bit, and every param TypeId match
8. **Optional wrapping**: `source → ?T` if `source → T`; also `null → ?T`
9. **Error union (equal/subset error set, in-memory payload)**: `E!A → E!B` where the error sets are equal or the source set is a subset of the target set, and the payloads are **in-memory identical** (`A == B`, exact TypeId equality). **Task B5 (2026-09-21):** the payload check was general assignability (`A → B`), which wrongly accepted integer-widening payloads — invalid Zig, because official Zig's EU→EU rule is in-memory payload compatibility and only comptime-known values may coerce. This one branch gates every EU→EU context (return, assignment, var-declaration, call argument), so all runtime payload-differing coercions now clean-reject with `error[3000]`. Declared stricter-than-Zig divergences (safe clean rejects): any in-memory qualifier difference in the payload is rejected — e.g. pointer-qualifier EU→EU (`F!*u8 → E!*const u8`) and slice-qualifier EU→EU (`F![]u8 → E![]const u8`) — and comptime-known payload-differing EU→EU is rejected, because exact payload TypeId equality is also what the payload-keyed C EU typedef can represent without a rewrap.
10. **Error union wrapping**: `source → E!T` if `source → T`
11. **Error set → error union**: `error_set → E!T`
12. **ptr → ptr**: `*void` ↔ `*T`; `*const T ← *T`; `*volatile T ← *T` (qualifier-monotone over `VOLATILE_FLAG`; const and volatile widening can combine)
13. **slice → slice**: `[]T → []const T`, `[]T → []volatile T` (qualifier-monotone)
14. **ptr → slice**: only `*[N]T → []T` (a bare `*T`/`*c_char` has no length and is not assignable)
15. **many ptr → many ptr**: `[*]T → [*]const T`, `[*]T → [*]volatile T` (qualifier-monotone)
16. **array → slice**: `[N]T → []T` (const/volatile monotone)
17. **array → many ptr**: `[N]T → [*]T`
18. **ptr → many ptr**: `*[N]T → [*]T`
19. **array → array**: same element TypeId and length
20. **slice → many ptr**: `[]T → [*]T`
21. **ptr → optional pointer**: `*T → ?*T`
22. **u8 ↔ c_char** (bidirectional)
23. **tuple → array**: same element count and every tuple element assignable to the array element

---

## type_resolver.zig (`sf/src/type_resolver.zig`)

Depends-on-graph topological sort and layout computation for all compound types. Also handles type expression resolution from AST nodes.

### Types

| Type | Description |
|------|-------------|
| `MODULE_ID_NONE` | `u32` sentinel `0xFFFFFFFF` — "no module context" for `TypeResolveEnv.module_id` (global fallback). |
| `MAX_FN_PARAMS` | `64` — maximum fn-type parameter count; exceeding it is a hard `@panic` in `resolveFnSignatures`, never a silent truncation. |
| `TypeResolveEnv` | Bundle: `store(*AstStore)`, `typereg(*TypeRegistry)`, `symbol_reg(*SymbolRegistry)`, `interner(*StringInterner)`, `module_id(u32)`, `source_file_id(u32)`, `diag(?*DiagnosticCollector)`, `local_consts(?*LocalConstScope)`, `local_types(?*LocalTypeScope)`. |
| `LocalConstScope` | Function-local `const` name → `var_decl` node scope: `names([*]u32)`, `nodes([*]u32)`, `count`, `cap`, `alloc(*Sand)`. |
| `LocalTypeScope` | **Task B2.** Function-local named-type name → `TypeId` scope: `names([*]u32)`, `types([*]u32)`, `count`, `cap`, `alloc(*Sand)`; `localTypeScopeInit`/`localTypeScopePush`/`localTypeScopeLookup` (newest-first). Consulted FIRST by `resolveTypeExprFull`'s `ident_expr` arm so a local type shadows module names inside the enclosing function (used for compound uses `E!T`, `*E`, `[N]E`, `?E`). |
| `ClassificationResult` | Result of `classifyTypeEmissionGroups`: `ids([*]u32)`, `len(u32)`. |
| `TypeResolver` | Kahn topological sorter: `registry(*TypeRegistry)`, `depend_items/len/cap([*]DepEdge)`, `in_degree_items/cap([*]u32)`, `sorted_items/len([*]u32)`, `worklist_items/len/cap([*]u32)`, `diag(*DiagnosticCollector)`, `alloc(*Sand)`. |

### Functions

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `typeResolverInit` | pub | `[inference: zero-init TypeResolver with undefined items, len/cap=0]` | Creates an empty resolver. |
| `typeResolverAddEdge` | pub | `[inference: dependEnsureCapacity, store DepEdge{from,to}, increment depend_len]` | Appends a dependency edge. |
| `dependEnsureCapacity` | private | `[inference: 2x growth, min 8, realloc-in-place then sand alloc 8-byte edges]` | Grows the dependency edge array. |
| `worklistEnsureCapacity` | private | `[inference: 2x growth (min 64), realloc-in-place then sandAlloc u32 array, copy old items]` | Grows the Kahn worklist array. |
| `worklistPush` | private | `[inference: worklistEnsureCapacity, write id at worklist_len, increment len]` | Pushes a TypeId onto the Kahn worklist. |
| `worklistPop` | private | `[inference: return null if empty, decrement len, return worklist_items[len]]` | Pops a TypeId from the Kahn worklist (LIFO). |
| `inDegreeEnsureCapacity` | private | `[inference: grow in_degree array to requested capacity (min 64), sandAlloc, update pointer and cap]` | Ensures the in_degree array is large enough. |
| `alignUp` | private | `[inference: (v + a - 1) & ~(a - 1), round v up to multiple of a, a must be power of 2]` | Aligns `v` up to alignment `a`; used by `layoutCompute`. |
| `layoutCompute` | private | `[inference: switch on kind, compute size/alignment, update Type in registry; does NOT touch state]` | The ONE layout math (the former `typeResolverResolveLayout` body, verbatim). Callable only when every direct dependency is complete. See [Layout Resolution](#layout-resolution). |
| `layoutDepOk` | private | `[inference: false for dep 0/TYPE_UNDEFINED/TYPE_VOID, else layoutEnsure(dep, depth)]` | One direct-dependency completeness check for the shared walk. |
| `layoutFieldDepsOk` | private | `[inference: for each FieldEntry type_id in fe_items[fstart..fstart+fcount], layoutDepOk]` | Field-list dependency completeness check. |
| `layoutEnsure` | **pub** | `[inference: true if state==2; false past depth cap 16; walk direct deps (fields/tag/enum backing/tuple elems/array elem/optional+EU payload), false if any incomplete; else layoutCompute + state=2]` | **Task 11H (Option B, AMENDMENT 10).** The ONE shared, order-independent layout entry point. Used by the normal topological pass AND the on-demand array-size fold, so there is exactly one layout implementation and one dependency walk. **Task B2:** now `pub` so the semantic analyzer can lay out a container type registered during `phase_SemanticAnalysis` (which misses the earlier layout pass). |
| `typeResolverResolveLayout` | private | `[inference: layoutEnsure(registry, tid, 0); on false fall back to layoutCompute]` | Normal-pass wrapper. The fallback preserves the historical behavior for a legitimate zero-size `void` field, a depth cap, or a kind with no layout math; the on-demand fold never takes it. |
| `typeResolverBuild` | pub | `[inference: copy dep edges, alloc in_degree array of size types_len, zero-init, count edges per target]` | Initializes the in-degree array from the dependency graph (symbol-registrator DUMMY `0->tid` edges PLUS the real `field_type -> container_tid` edges added by `typeResolverBuildDependencyGraph`). Allocates `sorted_items`. |
| `typeResolverResolve` | pub | `[inference: Kahn's algorithm — push zero-in-degree nodes, pop→resolveLayout→set state=2, decrement dependents' in-degree, push new zeros; detect circular deps]` | Topological sort + layout resolution. See [Kahn's Algorithm](#kahns-algorithm). |
| `fieldEmbedsByValue` | private | `[inference: true for struct/tagged_union/union/packed_union/array/tuple/enum/error_set]` | Classification helper: kinds that require the full type definition when used as a field. |
| `requiresFullDef` | private | `[inference: true for struct/tagged_union/union/packed_union/array/tuple/optional/error_union]` | Classification helper for optional payloads. |
| `layoutFieldNeedsEdge` | private | `[inference: true for struct/tagged_union/union/packed_union/enum/array/tuple/optional/error_union, false otherwise]` | The F5 embeds-by-value edge rule: kinds whose layout must be completed before the container's layout. Pointer/slice/fn/error_set/primitive/void fields are always-resolved fixed-size → no edge (avoids false self-reference cycles). |
| `layoutAddTypeEdge` | private | `[inference: if field_type < types_len and layoutFieldNeedsEdge(types_items[field_type].kind), typeResolverAddEdge(field_type, container_tid)]` | Adds one real `field_type -> container_tid` edge; guards bounds and skips non-embedding kinds. |
| `layoutAddFieldEdges` | private | `[inference: for each FieldEntry in fe_items[fstart..fstart+fcount], layoutAddTypeEdge(fe.type_id, container_tid)]` | Adds edges for every field of a struct/union/tagged_union/packed_union container. |
| `typeResolverBuildDependencyGraph` | pub | `[inference: iterate all types; for struct/tagged_union/union/packed_union containers call layoutAddFieldEdges, for array/tuple/optional/error_union add the elem/payload edge via layoutAddTypeEdge]` | **Defect D fix (F5, m0898 Option B).** Builds the REAL layout dependency graph from the now-resolved field type_ids, so the Kahn sort lays every field's type out BEFORE its container. Mirrors `fieldEmbedsByValue`/`requiresFullDef` semantics. Called from `phase_TypeResolution` AFTER `typeResolverResolveNames` and BEFORE `typeResolverBuild`/`typeResolverResolve`. |
| `classifyTypeEmissionGroups` | pub | `[inference: compute PO (pointer-only) set via forward+backward propagation, return sorted ids]` | Classifies types as pointer-only vs value-emitted for C89 codegen. |
| `growWpEdges` | private | `[inference: 2x growth for the backward edge adjacency list]` | Grows the classification backward-edge arrays. |
| `typeResolverGetSorted` | pub | `[inference: return sorted_items[0..sorted_len]]` | Returns the topological order slice. |
| `evalConstModuleOfExpr` | private | `[inference: resolve a field-access base to a module id, walking module aliases; 0 when not a module reference]` | Module-base resolver used by `evalConstU32Full`'s `field_access` arm. |
| `evalConstU32Full` | pub | `[inference: fold int_literal/arithmetic/negate/ident_expr/field_access/builtin_call, depth-limit 16, fallback 0xFFFFFFFF sentinel]` | Constant `u32` expression evaluator (array sizes). See [Type Expression Resolution](#type-expression-resolution). **Task 11S (a):** the `@intCast` arm resolves the target and gates the fold on `intValueFitsType`, emitting `error[3000]` for an out-of-range/non-integer target. |
| `evalConstI64Full` | pub | `[inference: int_literal/char_literal/negate/paren_expr/integer binops (arith/bitwise/shift)/ident_expr/field_access/builtin_call (@intCast,@as,@sizeOf,@alignOf,@bitSizeOf,@offsetOf,@bitOffsetOf), depth-limit 16, returns ?i64]` | Constant `i64` evaluator (enum backing values). **Task 11J** adds the depth cap (16) plus the integer-expression and integer-valued-builtin arms; `~`, enum-member references, bool/float builtins (`@isWindows`/`@intToFloat`/`@floatCast`), function calls, and any other unfoldable form return `null`, which the caller rejects (`ERR_3055`). **Fix round 1:** the `@as`/`@intCast` arm requires the target to be an integer type and the folded value to fit it (`intValueFitsType`). |
| `intValueFitsType` | private | `[inference: true when v fits the integer type tid (width + signedness); false for a non-integer target or out-of-range value]` | **Task 11J fix round 1** (AMENDMENT 13): the `@as`/`@intCast` target/value check. **Task 11S (a)** reuses it for the array-size `@intCast` fold (out-of-range → `error[3000]` + unfoldable sentinel). **Task B3 item 2:** a `wb >= 64` target is checked via `evalConstSignClass` (the operand node's syntactic sign class) instead of blanket-accepted. |
| `evalConstSignClass` | private | `[inference: tri-state (unknown/negative/non_negative) syntactic sign class of a cast operand node]` | **Task B3 item 2:** classifies int/char/bool literals as non-negative, `negate` as negative, an ident/`@as`/`@intCast` by its declared/target integer type (recursing into a const initializer when untyped), and everything else as unknown (never rejected). Mirrors `comptime_eval.comptimeEvalSignClass`; used only by the 64-bit branch of `intValueFitsType`. |
| `enumMembersResolve` | pub | `[inference: one shared enum-member walk — fresh auto_val cascade; append vs overwrite; check_only keeps values in a local buffer; strict mode folds each explicit initializer via evalConstI64Full and rejects an unfoldable one (out_fail_kind=1) or a duplicate tag (out_fail_kind=2)]` | **Task 11J** (AMENDMENT 10): the ONE walk used by symbol registration (`append=true, strict=false`), the post-layout re-evaluation pass (`append=false, strict=true`), and the semantic analyzer's function-local enum check (`check_only=true, strict=true`). |
| `enumReevaluateAll` | pub | `[inference: iterate modules/decls, detect enum decls mirroring the sema gate, nameCacheGet the enum tid, re-walk with strict=true and overwrite em_items[].value; on failure emit ERR_3055]` | **Task 11J** Option B (P1): post-layout enum re-evaluation, called at the end of `phase_TypeResolution` immediately after `typeResolverResolve`. |
| `symbolLookupAllModules` | private | `[inference: linear scan of all symbol tables for a name_id]` | Name → symbol lookup across modules. |
| `resolveTypeExprFull` | pub | `[inference: recursive AST type-expression resolver, depth-limit 16]` | See [Type Expression Resolution](#type-expression-resolution). **Task B2:** the `ident_expr` arm consults `env.local_types` first; the `struct_decl`/`enum_decl`/`union_decl` arms all delegate to `registerContainerType`. |
| `isContainerDeclKind` | pub | `[inference: kind in {struct_decl, enum_decl, union_decl, error_set_decl}]` | **Task B2.** Shared predicate for the four first-class container decls; used by the sema var-decl binding branch and the lower var-decl skip. |
| `containerAnonNameId` | private | `[inference: intern "anon_<node_idx>" into the string interner]` | **Task B2.** ONE synthesized-name scheme for anonymous / function-local container types (module 0), extracted from the former inline-struct arm so its emitted C stays byte-identical. |
| `registerContainerType` | pub | `[inference: enum -> validateLocalEnum; nameCacheGet("anon_<node>") short-circuit; typeRegistryRegisterNamedType(module 0, kind); setPacked for packed struct/union; resolve struct/union field types DIRECTLY (the module-only `resolveAggregateFieldTypesAll` never visits local/inline aggregates) then capture fields_start and append the payload; delegate enum/error-set payloads to the shared `populateTypePayload`]` | **Task B2.** Registers one struct/enum/union/error-set container type and populates its payload; idempotent across passes. **Fix round 1:** union `fields_start` captured after the resolve loop; inline enums validated. |
| `validateLocalEnum` | pub | `[inference: diagnosticCollectorMarkNodeOnce(env.diag, enum_node); enumMembersResolve(check_only=true, strict=true); on failure emit ERR_3055 with the failing member span (duplicate vs non-constant message)]` | **Task B2 fix round 1.** The ONE strict local/inline enum validation, shared by `registerContainerType` and the sema `semanticAnalyzerCheckLocalEnum`; a null `env.diag` pass is a no-op. |
| `localTypeScopeInit` / `localTypeScopePush` / `localTypeScopeLookup` | pub | `[inference: init/append/newest-first scan of the function-local type scope]` | **Task B2.** `LocalTypeScope` helpers used by the semantic analyzer (binding) and `resolveTypeExprFull`. |
| `resolveDeclAggregateFieldTypes` | pub | `[inference: nameCacheGet by (mod<<32)|name_id, walk field children, resolveTypeExprFull each field_decl.child_0, write fe_items[].type_id]` | Resolves inline field type annotations for struct/tagged_union/union/packed_union declarations. |
| `varDeclInitNeedsNameCache` | private | `[inference: return false for struct/union/enum/error_set/ident/import/fn decl, true otherwise]` | Filters var_decl init types that need name_cache registration. |
| `resolveNamedTypeExpressions` | private | `[inference: iterate modules/decls, filter by varDeclInitNeedsNameCache, resolveTypeExprFull on init, nameCachePut]` | Top-level var_decl type expressions. |
| `resolveImportFieldAlias` | private | `[inference: resolve @import(...).A field aliases, recursing through chained aliases, depth 8]` | Single import re-export alias. |
| `resolveImportFieldAliases` | private | `[inference: iterate modules/decls, resolve import_expr field_access aliases, set symbol.type_id + nameCachePut]` | All import re-export aliases. |
| `resolveAggregateFieldTypesAll` | private | `[inference: iterate modules/decls, filter struct_decl/union_decl inits, call resolveDeclAggregateFieldTypes]` | Field type annotations across modules. |
| `resolveFnSignatures` | private | `[inference: iterate modules/decls, resolve fn return/param types, create fn via typeRegistryGetOrCreateFn, resolve var_decl annotations, update symbol.type_id + ResolvedTypeTable]` | Function signatures + annotated var types. |
| `localConstScopeInit` / `localConstScopePush` / `localConstScopeLookup` | pub | `[inference: init/append/newest-first scan of the function-local const scope]` | `LocalConstScope` helpers used by `front_resolution.zig` and `evalConstU32Full`. |
| `typeResolverResolveNames` | pub | `[inference: create TypeResolveEnv, call resolveNamedTypeExpressions, resolveImportFieldAliases, resolveAggregateFieldTypesAll, resolveFnSignatures]` | **Phase entry point.** Resolves all type expressions across all modules. |

### Kahn's Algorithm

`typeResolverResolve`:

```
in_degree[0..type_count] = count of unsatisfied dependencies per type

Phase 1 — Seed:
  for each type_id where in_degree[tid] == 0:
    worklistPush(tid)

Phase 2 — Process:
  while worklist not empty:
    tid = worklistPop()
    sorted_items.append(tid)
    typeResolverResolveLayout(tid)          # layoutEnsure: compute size/alignment
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

`layoutCompute` (reached via `layoutEnsure` from `typeResolverResolveLayout`):

| Kind | Logic |
|------|-------|
| **struct_type** | If the packed flag (`flags & 0x10`) is set, delegate to `typeRegistryComputePackedLayout` (bit layout). Otherwise iterate fields: `alignUp(offset, ft.alignment)`, set `fe.offset`, `offset += ft.size`, track `max_align`; final `size = alignUp(offset, max_align)` (min 1). Voids are laid at the current offset without advancing. |
| **enum_type** | `size = backing_type.size`, `alignment = backing_type.alignment` |
| **union_type** | Iterate fields: `max_sz = max(field.size)`, `max_align = max(field.alignment)`; `size = alignUp(max_sz, max_align)` (min 1). |
| **packed_union_type** | Delegate to `typeRegistryComputePackedUnionLayout`: max member bit width, `size = ceil(max_bits/8)` (min 1), `alignment = 1`. |
| **tagged_union_type** | Tag first: `total = tag_type.size`, `total = alignUp(total, max_pa)`, then `total += alignUp(max_payload_size, max_pa)`; `size = alignUp(total, overall_align)` where `overall_align = max(tag_type.alignment, max_pa)`. |
| **optional_type** | `pay_align = max(pt.alignment, 4)`; `size = alignUp(alignUp(pt.size, 4) + 4, pay_align)`. |
| **error_union_type** | `union_sz = max(pt.size, 4)`, `union_align = max(pt.alignment, 4)`; `total = alignUp(alignUp(union_sz, union_align), 4) + 4`; `size = alignUp(total, union_align)`. |
| **array_type** | `size = elem.size * length`, `alignment = elem.alignment`. |
| **tuple_type** | Same as struct: sequential layout, `size = alignUp(offset, max_align)` (min 1). |

There is no `error_set_type` branch: named error-set types keep their registration `size=0`/`alignment=0`; the unnamed/empty sets created by `typeRegistryGetOrCreateErrorSet` are created directly with `size=4`/`alignment=4`.

### Defect D — layout dependency graph ordering (FIXED, F5, m0898 Option B)

**[updated: 2026-08-13] FIXED.** Root cause: the dependency graph driving the layout
topological sort carried only DUMMY edges — `addTypeDependencies` in `symbol_registrator.zig`
adds `0 -> tid` for every field, never `field_type -> tid`, because at symbol-registration time
field `type_id`s are still `TYPE_VOID` placeholders. The real field types are resolved LATER
(`resolveAggregateFieldTypesAll`). So the LIFO worklist popped a container struct BEFORE its
union/enum field types were sized → `typeResolverResolveLayout` read `size=0`/`align=0` for the
field → `alignUp(0,0)=0` → the `size==0 → 1/1` clamp → `@sizeOf`/`@alignOf` folded 1/1 in
`comptime_eval.zig` for any struct with a by-value union field (e.g. lisp `Value`, json
`JsonValue`).

Fix (general, ordering-only): **build the real graph after field types are resolved.**
`typeResolverBuildDependencyGraph` adds a real `field_type -> container_tid` edge for every field
that **embeds by value** — the F5 edge rule (`layoutFieldNeedsEdge`):
struct/tagged_union/union/packed_union/enum/array/tuple/optional/error_union. Pointer/slice/fn/
error_set/primitive/void fields are always-resolved fixed-size → no edge (a pointer field would
otherwise create a false self-reference cycle for `struct Node { next: *Node }`). The Kahn pass
(`typeResolverResolve`, with its cycle guard) then guarantees every field type is laid out before
its container. `phase_TypeResolution` calls it AFTER `typeResolverResolveNames` (which runs
`resolveAggregateFieldTypesAll`) and BEFORE `typeResolverBuild`/`typeResolverResolve`.

The readers (`comptime_eval.zig`), the layout math, and the C emitter needed no change.

**Surfaced follow-up (NOT this fix):** a plain untagged `union` is emitted as a C `struct` with
all variants stacked (`c89_emit` `ZIG_UNION_` guard, `struct` body) while its layout uses the
max-member model — so a union-holding struct's `@sizeOf` can under-size the emitted C struct.
Tracked for the F3 closeout / union-emission task; tagged unions are unaffected. See Known Issues.

### classifyTypeEmissionGroups

Computes which types can be emitted as pointer-only forward declarations (C89 requirement) vs must have full value layout.

1. **Forward pass** (per type kind):
   - Check every field (or element for array/error_union) of a value-embedding kind:
     - If field is `struct_type`/`tagged_union_type`/`union_type`/`packed_union_type`/`array_type`/`tuple_type`/`enum_type`/`error_set_type` → type is NOT pointer-only (requires full definition)
     - If field is `optional_type` or `error_union_type` → add a backward edge from parent to optional's/error_union's *payload* (the payload type's resolution status may propagate)
   - If none of these conditions trigger → type marked pointer-only (1)
2. **Backward propagation** (worklist):
   - Types that are NOT pointer-only (0) propagate: any parent that depends on them (via optional/error_union edge) also becomes NOT pointer-only
3. **Result**: returns `ClassificationResult{ids, len}` — sorted list of pointer-only TypeIds

Internal helpers:
- `fieldEmbedsByValue`: returns true for `struct/tagged_union/union/packed_union/array/tuple/enum/error_set` — these kinds require the full type definition when used as fields.
  `enum_type` and `error_set_type` were added (F-S8): both emit as inline integer typedef aliases
  (`typedef <backing> <cname>;` / `typedef int <cname>;`), so a holder whose field is an
  enum/error_set embeds it by value and must NOT be classified pointer-only. A struct whose *only*
  by-value content is an enum/error_set (e.g. `struct { color: Color, next: *Node }`) moves
  CLS:p → CLS:v. **This is a classification-only rule**: `classifyTypeEmissionGroups` has NO
  `enum_type`/`error_set_type` branch, so the enum/error_set **itself** always stays CLS:p
  (`is_po = 1`, default). Enums are never seeded into `shared_set` by classification — their
  promotion happens via the `computeSharedSet` fixpoint in `c89_emit.zig` when a shared member
  references them. Do not "fix" this by adding an enum CLS:v branch: it would push every enum into
  the shared header and break slice/optional-of-enum ordering (08 §1.17).
- `growWpEdges`: 2x growth for the backward edge adjacency list.

### Type Expression Resolution

#### `resolveTypeExprFull`

`[inference: switch on AstKind (ident/struct/field_access/error_set/error_union/fn/ptr/many_ptr/slice/optional/array), resolve each child recursively, depth-limit 16, return tid or TYPE_UNDEFINED, emit RTD/NF/N2/OPTVOID/UND markers]` recursive type expression resolver.

| AST Kind | Behavior |
|----------|----------|
| `ident_expr` | **Task B2:** consult the function-local type scope (`env.local_types`, newest-first) FIRST, so a local named type shadows module names. Then current-module-first lookup: `nameCacheGet((module_id<<32)|canonical_id)` when `module_id != MODULE_ID_NONE`, then bare `nameCacheGet(canonical_id)` (primitive + module-0 named-type fallback), then a per-module `nameCacheGet` scan, then current-module `symbolRegistryQualifiedLookup`, then all-module symbol scan, then `parseArbIntWidth`/`typeRegistryGetOrCreateArbInt` for `uN`/`iN` names. Returns `s.type_id` or `TYPE_UNDEFINED`. Emits `NF`, `N2`, `OPTVOID:*` markers. |
| `struct_decl` / `enum_decl` / `union_decl` | **Task B2:** all three delegate to `registerContainerType(env, node_idx, kind, depth)`: synthesize `anon_<node_idx>`, `nameCacheGet` short-circuit, `typeRegistryRegisterNamedType(module 0, kind)` (packed via `typeRegistrySetPacked` when `node.flags & 0x10`), then populate the payload — struct/union resolve each `field_decl.child_0` DIRECTLY (`feAppend` + `stAppend`/`unAppend`/`tuAppend`), enum reuses the shared `populateTypePayload`. The former struct arm's name/registration order is preserved so the inline-`struct` emitted C is byte-identical. |
| `field_access` | Resolve base expression. If base is `TYPE_UNDEFINED` and base is `ident_expr`, try module-qualified lookup (module symbol → field symbol). If base is `module_type`, look the field up in that module's symbol table. Emits `FAH:*` markers. |
| `error_set_decl` | Append each tag name to `xn_items` and create the error set via `typeRegistryGetOrCreateErrorSet`. |
| `error_union_type` | Resolve payload type (`child_1`) and optional error set (`child_0`). With no explicit error set, passes 0 (empty). Returns `typeRegistryGetOrCreateErrorUnion`. |
| `fn_type` | Resolve return type, resolve up to 16 param types. Builds unique name `"fnt_<ret>_<p0>..."` (`"fnts_"` prefix when the stdcall flag bit is set). Registers the fn type (passing the calling convention), marks it fn-ptr-used, and returns `typeRegistryGetOrCreatePtr(fn_tid, false)`. |
| `ptr_type` / `many_ptr_type` | Resolve child as base type. `is_const = (node.flags & 1) != 0`, `is_volatile = (node.flags & 2) != 0`. Returns `typeRegistryGetOrCreatePtrQ` / `typeRegistryGetOrCreateManyPtrQ`. Emits `PTR:i...`, `P<tid>` / `M<tid>`. |
| `slice_type` | `is_const = (node.flags & 1) != 0`. Returns `typeRegistryGetOrCreateSlice(child, is_const)`. |
| `optional_type` | Returns `typeRegistryGetOrCreateOptional(child)`. |
| `array_type` | Resolve element type (`child_0`). Evaluate length from `child_1`: `int_literal`, `add`/`sub`, `mul`/`div`/`mod_op`, `ident_expr`, or any other const-foldable expression via `evalConstU32Full` (including integer-valued `builtin_call` sizes). On success returns `typeRegistryGetOrCreateArray(elem, len)`; on failure emits `ERR_3050_ARRAY_SIZE_NOT_CONSTANT` (once per node) unless the size is the inferred `[_]` form. Emits `T0`, `T1e`, `T2L`, `T3a`, `A`/`a`. |

**Array-size evaluation:** the `array_type` arm's size-node handling covers `int_literal`, `add`/`sub`, `mul`/`div`/`mod_op` (div/mod by zero → uncomputable), `ident_expr`, and a catch-all const-fold via `evalConstU32Full` (which covers module-member `field_access`, function-local consts, and the integer-valued builtins `@intCast`/`@sizeOf`/`@alignOf`/`@bitSizeOf` — Task 11H also folds a struct's `@sizeOf`/`@alignOf`/`@bitSizeOf` by completing it on demand via `layoutEnsure`). An uncomputable size is a hard `ERR_3050_ARRAY_SIZE_NOT_CONSTANT` diagnostic instead of a silent `TYPE_UNDEFINED`.

#### `evalConstU32Full`

`[inference: return int_literal int_values[node.payload], fold arithmetic/negate, recurse into ident_expr decl.child_1, resolve field_access module members, fold integer-valued builtin_call, fallback 0xFFFFFFFF sentinel]` constant u32 expression evaluator:

1. **depth guard**: `depth > 16` → `0xFFFFFFFF` (const-cycle guard).
2. **int_literal**: returns stored `int_values[node.payload]`.
3. **add/sub/mul/div/mod_op**: evaluate both children; if both are known, compute (div/mod by zero → `0xFFFFFFFF`).
4. **negate**: `0 - child`.
5. **ident_expr**: consult the function-local const scope first (`localConstScopeLookup`), then `symbolLookupAllModules`; if the symbol is a const (`flags & 0x01 == 0`) recurse into `decl.child_1`.
6. **field_access**: resolve the base module via `evalConstModuleOfExpr`, then fold the member const's initializer.
7. **builtin_call** (Task 11F; aggregate fold added by Task 11H): fold the clear integer-valued builtins, else `0xFFFFFFFF`:
   - `@intCast(T, e)` → resolve the target (extra-child 0) and fold the operand (extra-child 1) **with `evalConstU32Full`** (the U32 evaluator is the one that consults the function-local const scope, so `const N = 7` resolves). **Task 11S (a):** require `intValueFitsType(env, target, v)`; on a fit return the value, otherwise emit `error[3000]` (once per node) and fall through to the `0xFFFFFFFF` sentinel (the array-type arm then also reports its pre-existing `ERR_3050` cascade). An unrecognized target or the sentinel operand keeps the `ERR_3050` reject. This repairs the Task 11F regression where the target was ignored and `[@intCast(u8, 300)]` folded to length 300;
   - `@sizeOf(T)` / `@alignOf(T)` / `@bitSizeOf(T)` → `resolveTypeExprFull` the type arg (extra-child 0). **Task 11H:** if the resolved type is a not-yet-complete `struct_type` (packed or not), call the shared `layoutEnsure(registry, bt_tid, 0)` first, then re-read the type. Fold only if COMPLETE (`state == 2`) and (`evalConstScalarKind(kind)` — the integer whitelist — OR `struct_type`); return the registry `size` / `alignment` / bit-size (`@bitSizeOf`: `size*8`, overridden by `typeRegistryIntWidthBits` for integer/enum, `1` for bool, and `typeRegistryGetPackedTotalBits` for a packed struct). The `state == 2` gate is mandatory — reading `size`/`alignment` before layout produced a silently wrong `[1]` for an aggregate field;
   - `@isWindows`/`@intToFloat`/`@floatCast` (bool/float), `@offsetOf`/`@bitOffsetOf`, and every non-struct aggregate kind (tuple/slice/union/tagged/packed-union/optional/error-union/enum) → `0xFFFFFFFF`, so the caller keeps the `ERR_3050` reject. A forward-referenced/mutual aggregate also defers (`layoutEnsure` returns false on a `TYPE_VOID` placeholder or past the depth cap), so it too stays `ERR_3050` — never silently wrong.
8. **Fallback**: returns `0xFFFFFFFF` (sentinel for "unknown").

Helpers: `symbolLookupAllModules` — linear scan of all symbol tables for a `name_id`; `evalConstModuleOfExpr` — resolves a field-access base to a module id by walking module aliases; `evalConstScalarKind` — true for the primitive/alias kinds whose `@sizeOf`/`@alignOf`/`@bitSizeOf` are safe to fold (excludes struct/union/tagged-union/packed-union/tuple/array/slice/optional/error-union/fn/module/type/unresolved/none); Task 11H keeps it as the integer whitelist and adds `struct_type` as the only on-demand-completed aggregate; `evalConstI64Full` — the `i64` companion used for enum backing values; Task 11J adds the depth cap (16), the integer binary/bitwise/shift/paren/char arms, and the integer-valued builtin arm (`@intCast`/`@as`/`@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf`, primitive/alias and named aggregates post-layout), returning `?i64`; `~`, enum-member references, bool/float builtins, and function calls stay `null` (rejected as `ERR_3055`). Task 11J also adds `enumMembersResolve` (the shared member walk) and `enumReevaluateAll` (the post-layout re-evaluation pass). Task 11J fix round 1 adds `intValueFitsType` and gates the `@as`/`@intCast` fold on an integer target whose width/signedness the value fits.

#### `resolveDeclAggregateFieldTypes`

`[inference: nameCacheGet lookup by (mod<<32)|name_id, walk field children, resolveTypeExprFull each field_decl.child_0, write result to fe_items[].type_id, emit B2/FSW/DFT/FTW/DTWR/TUI markers]` resolves field type annotations for `struct_type`, `tagged_union_type`, and `union_type`/`packed_union_type` declarations that have inline field type expressions.

#### `resolveNamedTypeExpressions`

`[inference: iterate modules/decls, filter by varDeclInitNeedsNameCache, resolveTypeExprFull on init, nameCachePut under (mod<<32)|name_id, set symbol.type_id]` iterates top-level `var_decl`s where the init expression is a type expression (not an inline type decl, import, ident, or fn_decl).

#### `resolveImportFieldAliases`

`[inference: iterate modules/decls; for a var_decl whose init is a field_access on an import_expr, resolve the imported symbol (recursing through chained aliases, depth 8), then set symbol.type_id and nameCachePut]` resolves `pub const Arena = @import("...").Arena` re-export aliases (helper `resolveImportFieldAlias`).

#### `resolveAggregateFieldTypesAll`

`[inference: iterate modules/decls, filter struct_decl/union_decl inits, call resolveDeclAggregateFieldTypes for each]` iterates all modules' top-level var_decls whose init is `struct_decl` or `union_decl`.

#### `resolveFnSignatures`

`[inference: iterate modules/decls, resolve fn return/param types via resolveTypeExprFull, create fn via typeRegistryGetOrCreateFn, resolve var_decl type annotations, update symbol.type_id and ResolvedTypeTable]` iterates all modules:
- **fn_decl**: skips a fn whose symbol already has a `type_id`; resolves return and param types via `resolveTypeExprFull` (param count capped at `MAX_FN_PARAMS = 64`, else `@panic`), creates the fn type via `typeRegistryGetOrCreateFn` (passing `is_extern` from `decl.flags & 0x04`, `is_variadic` from `decl.flags & 0x01`, and `proto.call_conv`), records it in `ResolvedTypeTable`, and sets `symbol.type_id`. The fn-pointer path (`resolveTypeExprFull`'s `fn_type` arm) always passes `is_variadic=0` and `is_extern=0`.
- **var_decl with explicit type annotation** (`child_0 != 0`): resolves the type expression, records it in `ResolvedTypeTable`, sets `symbol.type_id`.

#### `typeResolverResolveNames` (entry point)

Orchestrates all name resolution:
1. `resolveNamedTypeExpressions` — var_decl type expressions
2. `resolveImportFieldAliases` — import re-export field aliases (`pub const Arena = @import(...).Arena`)
3. `resolveAggregateFieldTypesAll` — field type annotations
4. `resolveFnSignatures` — fn signatures + annotated var types

#### D2 defect — bare `ident_expr` type resolution — FIXED (F1) [updated: 2026-08-14]

`resolveTypeExprFull`'s `ident_expr` arm resolves a bare type name (e.g. a fn return type `Arena`)
in tiers:

1. **current-module name_cache**: `nameCacheGet((module_id<<32)|canonical_id)` when
   `module_id != MODULE_ID_NONE`.
2. **bare name_cache**: `nameCacheGet(canonical_id)` — the key shared by primitive names
   (`registerPrimitiveName` in `type_registry.zig`) and module-0 named types
   (`typeRegistryRegisterNamedType` writes `(0<<32)|name_id == name_id`).
3. **per-module name_cache scan**: builds `(mi << 32) | canonical_id` for each module and returns
   the **first** match, lowest module_id first.
4. **symbol scan**: current-module `symbolRegistryQualifiedLookup`, then all-module scan.
5. **arbitrary-width int**: `parseArbIntWidth` / `typeRegistryGetOrCreateArbInt` for `uN`/`iN`.

The pre-F1 defect was that the per-module scan ran before the current module, so `create()` in
module instance N resolved its return type `Arena` to module 0's `Arena` TypeId, not instance N's
own. The `field_access` arm never had this problem — `arena_mod.Arena` resolves the base
`module_type` then looks the field up in *that* module's table.

Emission consequence: the struct typedef is emitted from the type's *own* `module_id` (so the
instance-N `Arena` typedef mangles with a collision suffix), but the fn signature/return type
referenced the *module-0* TypeId, emitting the unsuffixed name — gcc rejects the C as `return type
is an incomplete type`. Reproduced by `repro/mi_matrix/arena_multi_inst_xmod/` (two-path import
`a/std_arena.zig` + `b/std_arena.zig`).

**FIXED (F1, 2026-08-14), then reordered (F-task, 2026-08-14).** `TypeResolveEnv` gained
`module_id: u32` (sentinel `MODULE_ID_NONE = 0xFFFFFFFF` = "no module context", global fallback).
The bare name-cache key collides with module-0's scoped key, so an un-scoped
`nameCacheGet(canonical_id)` silently resolved module-0-first; the F1 reorder alone was still
vulnerable because its bare lookup ran first. The F-task fix makes the current-module scoped lookup
run **first**, the bare lookup **second** (the primitive + module-0 named-type fallback), and the
all-modules scan **third**. For module 0 the scoped key equals the bare key, so the reorder is a
no-op (control behavior preserved). Every `resolveTypeExprFull` call site sets `module_id`
explicitly; the genuinely-global sites (comptime `@sizeOf`/`@alignOf`/`@intCast` type args, enum
backing type) use `MODULE_ID_NONE`.

---

## const_alias_prepass.zig (`sf/src/const_alias_prepass.zig`)

Resolves `const Alias = TypeName` patterns where the RHS is a simple identifier referring to another type. Invoked from `phase_TypeResolution` (`main.zig`) before `typeResolverResolveNames`.

### Functions

| Function | Scope | `[inference]` | Description |
|----------|-------|---------------|-------------|
| `resolveWellKnownTypeName` | private | `[inference: switch on string length (2-5), byte-compare for built-in type names, return sentinel or TYPE_UNDEFINED]` | Matches string names to TypeId sentinels: void(4), bool(4), i32/u32(3), u64/i64(3), f32/f64(3), i8/u8(2), usize/isize(5). Returns `TYPE_UNDEFINED` for non-well-known. |
| `growDep` | private | `[inference: 2x growth (min 16), sandAlloc for to/next arrays, copy old elements, update pointers and cap]` | Grows the dependency tracking arrays (`to_ptr`, `next_ptr`) used during the catalog phase. |
| `constAliasPrepass` | pub | `[inference: 3-phase Kahn worklist: catalog global const aliases, seed resolvable ones, propagate resolved types through dep chain]` | Resolves `const X = Y` type aliases before full type resolution. |

### constAliasPrepass — Three Phases

```
Phase 1 — Catalog:
  for each module's symbol table:
    for each SymbolKind.global symbol with type_id == 0 and decl kind == 1 (var_decl):
      if init is ident_expr (AstKind 24):
        record alias: alias_name[count] = canonicalized dep_name
        record dep edge: dep_head[dep_name] → alias_count (linked list)
        alias_count += 1
    Emits: GATE:g0/g1/g2/g3, CAT:ik, CAT:dn markers

Phase 2 — Seed:
  for each alias:
    lookup dep_name in (first hit wins):
      (1) name_cache((alias mod_id)<<32 | name_id)  → alias's declaring-module name
      (2) name_cache(name_id only)  → global/primitive name
      (3) name_cache(module<<32 | name_id) scan  → per-module fallback
      (4) resolveWellKnownTypeName → "void", "i32", etc.
    if resolved:
      sym.type_id = resolved
      sym.kind = SymbolKind.type_alias
      nameCachePut((mod_id<<32) | dep_name, resolved)
      worklist.push(alias_idx)

Phase 3 — Kahn propagation:
  while worklist not empty:
    resolved_idx = worklist.pop()
    resolved_sym.type_id = rt  (the resolved TypeId)
    alias_own_name = resolved_sym's declared name
    for each dependent alias (linked list via dep_head[alias_own_name]):
      if dep_sym.type_id == 0:
        dep_sym.type_id = rt
        dep_sym.kind = SymbolKind.type_alias
        nameCachePut((dep_mod<<32) | dep_name, rt)
        worklist.push(dep_alias_idx)
    Emits: KAHN:start, KAHN:end markers
```

The source file-top comment calls the pass "KEPT (unwired)", but it **is** wired: `phase_TypeResolution` calls it before `typeResolverResolveNames`. It catalogs only `SymbolKind.global` symbols, so a symbol already classified `type_alias` is skipped.

---

## front_resolution.zig (`sf/src/front_resolution.zig`)

The front pass that resolves module-level initializer/type-annotation expressions and function-body statement type annotations into the `ResolvedTypeTable`. `phase_FrontResolution` (`main.zig`) runs **after** `phase_TypeResolution` and **before** `phase_ComptimeEvaluation`; it builds a `FrontResCtx` and calls `frontResolveModuleInits`. The `resolveStmtTypes` entry point is called from `phase_SemanticAnalysis`, once per function body, before `semanticAnalyzerResolveFnBody`.

### Types

| Type | Description |
|------|-------------|
| `FrontResCtx` | Bundle passed to both entry points: `store`, `typereg`, `symbol_reg`, `resolved_types`, `module_reg`, `interner`, `diag`, `scratch(*Sand)`, `coercion_table`, `enum_value_table`, `error_code_registry`, `call_arg_types`, `call_param_map`, `suspending_fns` |

### Functions

| Function | Scope | Description |
|----------|-------|-------------|
| `resolveTypeExpr` | private | Wraps `type_resolver.resolveTypeExprFull` with a `TypeResolveEnv` built from the `FrontResCtx` (threads `module_id`, `source_file_id`, `diag`, and the local-const scope). |
| `countUntypedGlobals` | private | Counts `SymbolKind.global`/`type_alias` symbols with `type_id == 0`; bounds the `frontResolveModuleInits` fixed-point loop. |
| `frontResolveModuleInits` | pub | Resolves module-level declarations to a fixed point (see below). |
| `resolveStmtTypes` | pub | Public wrapper that creates a `LocalConstScope` (`type_resolver.localConstScopeInit`) and calls the recursive helper. |
| `resolveStmtTypesRec` | private | Walks a statement subtree (depth cap 16); resolves `var_decl` type annotations, records function-local `const`s in the scope, and resolves `array_init`/`struct_init`/`tuple_literal` type annotations. Does not descend into `builtin_call` children. |

### `frontResolveModuleInits` behavior

1. `sandReset(scratch)`; loop bound = `countUntypedGlobals + 1` iterations.
2. For each module, build a `SemanticAnalyzer` via `semanticAnalyzerInit` and walk its top-level decls.
3. For each `var_decl`:
   - `child_0` (type annotation) → `resolveTypeExpr`; on success record the type in the `ResolvedTypeTable` for both the annotation node and the decl node.
   - `child_1` (init) that is not a `struct_decl`/`union_decl` → `semanticAnalyzerResolveModuleVarDecl`.
     - `ident_expr` init: `nameCachePut((module_id<<32)|decl_payload, init_type)`; if the referenced symbol is a `type_alias` and the decl's own symbol is not, promote the decl's symbol to `SymbolKind.type_alias` (sets `changed`).
     - Record the init type on the decl node, excluding `TYPE_VOID`/`TYPE_UNDEFINED`/`TYPE_TYPE`.
     - `TYPE_INT_LIT` with an annotation: copy the annotation's resolved type onto the init node.
     - Back-fill `symbol.type_id` for the declaring symbol (sets `changed`).
4. Repeat until a full pass makes no change (`changed == 0`), then `sandReset(scratch)`.

---

## Data Flow

```
phase_TypeResolution (main.zig)
    │
    │  scratch arena reset; re-run registerModuleSymbols(populate=false)
    │
    ├─ constAliasPrepass (const_alias_prepass.zig)
    │   │  marker: "CAP:ent"
    │   │
    │   ├─ Phase 1 — Catalog: find all "const X = Y" aliases
    │   │   └─ dep_head linked list per name_id
    │   │
    │   ├─ Phase 2 — Seed: resolve directly-known names
    │   │   └─ scoped nameCache, bare nameCache, per-module scan, well-known types
    │   │
    │   └─ Phase 3 — Kahn: propagate through alias chain
    │       └─ emit KAHN:start / KAHN:end
    │
    ├─ typeResolverResolveNames (type_resolver.zig)
    │   │
    │   ├─ resolveNamedTypeExpressions
    │   │   └─ var_decl type expressions → nameCachePut
    │   │
    │   ├─ resolveImportFieldAliases
    │   │   └─ `pub const A = @import(...).A` re-export aliases
    │   │
    │   ├─ resolveAggregateFieldTypesAll
    │   │   └─ resolveDeclAggregateFieldTypes (per struct/tagged_union/union)
    │   │       ├─ resolveTypeExprFull for each field_decl.child_0
    │   │       └─ fe_items[].type_id = resolved type
    │   │
    │   └─ resolveFnSignatures
    │       ├─ fn_decl return type + param types → resolveTypeExprFull
    │       ├─ var_decl with type annotation → resolveTypeExprFull
    │       ├─ → typeRegistryGetOrCreateFn (is_extern, is_variadic, call_conv)
    │       ├─ → ResolvedTypeTable.set
    │       └─ → symbol.type_id = resolved
    │
    ├─ typeResolverInit (type_resolver.zig)
    │   └─ zero init
    │
    ├─ typeResolverBuildDependencyGraph (type_resolver.zig)   [Defect D fix, F5]
    │   ├─ iterate all types
    │   ├─ struct/tagged_union/union/packed_union → layoutAddFieldEdges (real field_type -> container)
    │   ├─ array/tuple → elem edge; optional/error_union → payload edge
    │   └─ skips pointer/slice/fn/error_set/primitive/void fields (embeds-by-value rule)
    │
    ├─ typeResolverBuild (type_resolver.zig)
    │   ├─ copy DepGraph edges from symbol_registrator (dummy 0->tid) + real F5 edges
    │   ├─ alloc sorted_items[0..types_len]
    │   ├─ alloc in_degree_items[0..types_len]
    │   └─ count edges per target type
    │
    ├─ typeResolverResolve (type_resolver.zig)
    │   │  Kahn's algorithm:
    │   │
    │   ├─ Seed: push zero-in-degree types to worklist
    │   │
    │   ├─ Loop: pop → layoutEnsure (→ layoutCompute) → state=2
    │   │   ├─ struct_type   → sequential offset+size per field (packed → bit layout)
    │   │   ├─ enum_type     → backing_type.size/align
    │   │   ├─ union_type    → max field size/align
    │   │   ├─ packed_union  → max member bit width
    │   │   ├─ tagged_union  → tag + max payload, aligned
    │   │   ├─ optional      → payload + 4-byte tag
    │   │   ├─ error_union   → union + 4-byte error code
    │   │   ├─ array_type    → elem.size * length
    │   │   └─ tuple_type    → sequential layout
    │   │   │
    │   │   └─ decrement dependents' in_degree
    │   │       └─ push newly-zero types
    │   │
    │   └─ Cycle detection: unresolved → ERR_3005 → void_type fallback
    │
    ├─ typeResolverGetSorted → topological order
    │
    └─ classifyTypeEmissionGroups (type_resolver.zig)
        └─ pointer-only classification for C89 forward decls

phase_FrontResolution (main.zig)   [runs after phase_TypeResolution]
    └─ frontResolveModuleInits (front_resolution.zig)
        ├─ fixed-point over untyped globals/type-aliases
        ├─ var_decl type annotations → resolveTypeExprFull → ResolvedTypeTable
        ├─ module-var init expressions → semanticAnalyzerResolveModuleVarDecl
        ├─ ident_expr init → nameCachePut + global→type_alias promotion
        └─ symbol.type_id back-fill

phase_SemanticAnalysis (main.zig)
    └─ resolveStmtTypes (front_resolution.zig) per fn body
        └─ function-local type annotations + local-const scope for array sizes

State transitions in types_items[*].state:
  0 (initial) → 2 (resolved) — set by layoutEnsure (the normal-pass wrapper `typeResolverResolveLayout` falls back to `layoutCompute` when the shared walk declines, then `typeResolverResolve` sets `state = 2`)
```

### Data Structures After Type Resolution

```
TypeRegistry (permanent arena)
    │
    ├─ types_items[0..n] — all types, state=2 for resolved
    │   ├─ [1-21] primitives (state=2 from registration)
    │   ├─ [22..] user types (state updated during resolve)
    │   └─ size, alignment, width_bits, is_signed, payload_idx populated
    │
    ├─ Per-kind payload arrays
    │   ├─ st_items[*] → StructPayload{fields_start, fields_count}
    │   ├─ fe_items[*] → FieldEntry{name_id, type_id, offset}
    │   ├─ en_items[*] → EnumPayload{members_start, count, backing, explicit_backing}
    │   ├─ em_items[*] → EnumMember{name_id, value}
    │   ├─ pk_items[*] → PackedBitField{bit_offset, bit_width}
    │   ├─ pk_struct_items[*] → PackedStructInfo{pk_start, pk_count, total_bits}
    │   ├─ pk_un_items[*] → PackedStructInfo (packed-union variant)
    │   └─ ... (all payload types populated)
    │
    ├─ Caches (hash maps)
    │   ├─ ptr_cache: (base<<2)|(const|volatile<<1) → TypeId
    │   ├─ many_ptr_cache: (base<<2)|(const|volatile<<1) → TypeId
    │   ├─ slice_cache: (elem<<1)|const → TypeId
    │   ├─ array_cache: (elem<<32)|len → TypeId
    │   ├─ optional_cache: payload → TypeId
    │   ├─ eu_cache: (payload<<32)|es → TypeId
    │   ├─ es_cache: hash(tags) → TypeId
    │   └─ name_cache: (mod<<32)|name → TypeId
    │
    └─ All Type entries with state=2 (resolved). Size/alignment are populated for the 9
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

| Marker | File | Description |
|--------|------|-------------|
| `CAP:ent` | `const_alias_prepass.zig` | constAliasPrepass entry |
| `CAP:ac<count>` | `const_alias_prepass.zig` | Alias count after catalog |
| `CAP:ac0` | `const_alias_prepass.zig` | No aliases found, early exit |
| `KAHN:start` / `KAHN:end` | `const_alias_prepass.zig` | Kahn propagation loop start / end |
| `CLS:c<count>` | `type_resolver.zig` | classifyTypeEmissionGroups result count |

### Type Creation Markers (type_registry.zig)

| Marker | Description |
|--------|-------------|
| `DC:k<kind>n<name_id>t<type_id>` | Type created — kind enum, name_id, assigned TypeId |
| `X:<id>` | Struct type created (TypeId) |
| `MC<id>` | Module type created (TypeId) |
| `NP:k<key_lo>v<type_id>` | nameCachePut — key low 16 bits + cached type_id |
| `NGC:g1<result>` | nameCacheGet for `key_lo == 1` (debug only) |
| `RN:m<mod>n<name>k<kind>t<tid>` | Register named type — module_id, name_id, kind enum, assigned tid |
| `U2H:e<elem>r<existing>c<const>` | Slice cache hit (U2H="use-to-hit") |
| `U2N:e<elem>r<new_tid>c<const>` | Slice cache miss, created new (U2N="use-to-new") |
| `O0:e<elem>L<len>` | Array type creation start |
| `O1H<existing>` | Array cache hit |
| `O2N<new_tid>` | Array cache miss, new type ID |
| `P2:n<name_id>H<existing_tid>` | Fn type hit (linear scan) |
| `P2:n<name_id><tid>` | Fn type created |

### Type Expression Resolution Markers (type_resolver.zig)

| Marker | Description |
|--------|-------------|
| `RTD:n<node>k<kind>` | `resolveTypeExprFull` entry — node index and AstKind |
| `T0` | Array type resolution start |
| `T1e<elem>` | Array element type ID |
| `T2L<len>` | Array length |
| `T3a<tid>` | Array type created (TypeId) |
| `A` / `a` | Array success (`A`) or `TYPE_UNDEFINED` (`a`) |
| `FAH:r<resolved>` | Field access hit — resolved type ID |
| `FAH:m<child_0>` | Field access miss — base node index |
| `FAH:N<node>` | Field access no match |
| `PTR:i<node>k<kind>c<child>` | Pointer / many-pointer type resolution |
| `P<tid>` / `M<tid>` | Pointer (`P`) or many-pointer (`M`) created |
| `SL:e<elem>s<tid>` | Slice type created |
| `OPTVOID:*` | Optional / void type resolution markers (`id`, `nc`, `ids`, `idF`, `fntR`, `fntT`, `opt`, `optR`) |
| `FER:n<idx>t<type_id>` | Field entry read during tagged_union layout |
| `FSW:n<fe_idx>t<type_id>` | Field slot write during struct field resolution |
| `DFT:n<fi>t<tid>` | Decl field type tag (tagged_union) |
| `FTW:n<fe_idx>t<tid>` | Field type write (tagged_union) |
| `B2:p<payload>t<tid>` | Field decl payload and resolved type |
| `DTWR` | Field type written (tagged_union) |
| `DTSK` | Field type skipped (`TYPE_UNDEFINED`, tagged_union) |
| `TUI:fs<start>fc<count>` | Tagged union field range |
| `NF` | Name not found in global name_cache |
| `N2` | Name not found in per-module caches |
| `UND:n<node>k<kind>` | `resolveTypeExprFull` returning `TYPE_UNDEFINED` |

### constAliasPrepass Markers

| Marker | Description |
|--------|-------------|
| `CAP:tlm<total>` | Total symbols across all modules |
| `CAP:tl0` | No symbols, early return |
| `GATE:g0<type_id>` | Global alias type check (must be 0 to continue) |
| `GATE:g1` | Gate passed: `type_id == 0` |
| `GATE:g2<kind>` | Gate failed: not a const decl (`kind != 1`) |
| `GATE:g3` | Gate failed: no `child_1` (no init expr) |
| `CAT:ik<init_kind>` | Catalog: init expression AstKind |
| `CAT:dn<name_id>` | Catalog: dependency name_id |

### classifyTypeEmissionGroups Markers

| Marker | Description |
|--------|-------------|
| `CLS:c<count>` | Total pointer-only type count |
| `CLS:p<tid>k<kind>` | Per pointer-only type |
| `CLS:v<tid>k<kind>` | Per value-emitted type |

### Diagnostic Error Codes

| Constant | Description |
|----------|-------------|
| `ERR_3005_CIRCULAR_TYPE_DEPENDENCY` | Type refers to itself (directly or transitively). Emitted during `typeResolverResolve` cycle detection; the offending type is set to `void_type` as fallback. |
| `ERR_3050_ARRAY_SIZE_NOT_CONSTANT` | An array-size expression could not be const-folded (emitted once per node by `resolveTypeExprFull`'s `array_type` arm; `[_]T` inferred length is exempt). |

The `3005`/`3050` in the constant names are labels, not discriminants — the `ErrorCode` enum auto-increments several early members, so `ERR_3005_*` has a small ordinal value (see `00_shared_infra.md`).

### How to Inspect TypeId Values

Use the marker system (`pal_mod.markerWrite` / `markerWriteInt`):

```
Marker format: "<prefix><key><value>\n"
Examples:
  "DC:k17n493t25\n"   → created type kind=17 name_id=493 TypeId=25
  "RN:m1n200k12t30\n" → registered named type mod=1 name=200 kind=12 TypeId=30
  "NP:k3a5v22\n"      → name_cache put key_low=0x3a5→type_id=22
```

Type ID values are dense monotonically increasing u32s starting at 0. Sentinels occupy 0-21 (index 0 is the `none_sentinel` sentinel at type_id=0, though `TYPE_VOID=1` is the first meaningful type; `TYPE_VA_LIST=21` is the last primitive). The stale `FIRST_USER_TYPE = 20` constant means user types in practice start at TypeId ≥ 22.

To trace a specific TypeId through the pipeline:
- Search `DC:k*` for creation
- Search `RN:t<id>` for named type registration
- Search `NP:v<id>` for cache population
- `RTD:n<node>k<kind>` traces every `resolveTypeExprFull` entry

### Known Issues

1. **Linear dedup for `fn_type`**: `typeRegistryGetOrCreateFn` scans all of `types_items` on every call (no hash cache). The scan now also matches on the calling-convention bit (`FN_FLAG_STDCALL`), so a cdecl and a stdcall function of the same name are distinct entries.

2. **`typeRegistryGetOrCreateModule`**: linear scan of all types for a matching `module_type+module_id`. No hash cache.

3. **No hash cache for optional when unresolved**: `typeRegistryGetOrCreateOptional` populates `optional_cache` only when the payload is already resolved (`state == 2`). Unresolved optionals miss the cache on subsequent lookups.

4. **Depth limit in `resolveTypeExprFull`**: hardcoded max depth of 16 (the `evalConstU32Full` const-cycle guard uses the same cap). Deeply nested type expressions silently return `TYPE_UNDEFINED`.

5. **`evalConstU32Full` fallback ambiguity**: `0xFFFFFFFF` is both a valid `u32` and the "uncomputable" sentinel, so a zero-sized array of length `0xFFFFFFFF` cannot be distinguished from a failed fold. The evaluator folds `add`/`sub`/`mul`/`div`/`mod_op`/`negate`, `ident_expr` (module + function-local consts), `field_access` module-member consts, and the integer-valued `builtin_call`s `@intCast`/`@sizeOf`/`@alignOf`/`@bitSizeOf` (complete primitive/alias types, plus Task 11H's on-demand-completed `struct_type`); everything else falls back to the sentinel. Task 11H keeps forward-referenced/mutual aggregates, `@offsetOf`/`@bitOffsetOf`, and non-struct aggregates on the sentinel (`ERR_3050`) — never silently wrong.

6. **SURFACED (2026-08-13, F5): plain untagged `union` layout vs C emission mismatch.** A bare `union` layout uses the max-member model (`typeResolverResolveLayout` union branch, `size = alignUp(max_sz, max_align)`), but `c89_emit` emits a plain union as a C `struct` with ALL variants stacked — so a union-holding struct's `@sizeOf` can under-size the emitted C struct, overflowing arena bump-alloc slots. Pre-fix masked by the Defect D 1/1 clamp; post-F5 `lisp_interpreter` `(+ 1 2)` SEGFAULTs (was silent fail) because eval now runs against the still-mismatched `Value` size. Tagged unions are unaffected (emitted correctly). Tracked for the F3 closeout / union-emission task.

7. **`FIRST_USER_TYPE = 20` is stale**: `type_registry.zig` still defines it as `20`, but primitives now occupy TypeIds 1-21, so user types in practice start at ≥22 (`TYPE_TYPE` was already a primitive while the constant was never bumped). Docs-only task — the source constant is left unchanged.

8. **`canLiteralFitInType` does not cover arbitrary-width / enum-backed ints**: it range-checks only the fixed sentinel TypeIds (`TYPE_I8`…`TYPE_USIZE`, `TYPE_F32`/`TYPE_F64`), so an integer literal targeted at an `arb_int_type`/`arb_uint_type` (or an `enum(uN)` backed by one) is not range-checked by this helper.

9. **FIXED (2026-08-08, F1): `@ptrToInt` resolves to `usize` for single-arg calls.** The `builtin_call` resolver in `semantic_analyzer.zig` had the `@ptrToInt → TYPE_USIZE` branch nested *inside* the `ec.len >= 2` guard, making it dead code for the single-arg `@ptrToInt(x)` form — the call fell through to the `ec.len >= 1` branch and returned the *argument's* type (a pointer). An untyped `const current_pos = @ptrToInt(ptr);` was typed as the pointer, and a following `(current_pos + mask) & ~mask` chain failed the bitwise equal-integer-types check → const init resolved to `TYPE_VOID` → `error[3000]`. Fix: the `ptrtoint_name_id` check is hoisted above the `ec.len` dispatch, mirroring the lowerer's already-correct handling. `@ptrToInt` now resolves to `TYPE_USIZE` regardless of arg count.
