> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project.

# Self-Hosted Type System & Semantic Analysis

**Version:** 1.0  
**Component:** Type representation, resolution, semantic passes, coercion, comptime evaluation  
**Parent Document:** DESIGN.md v3.0 (Sections 6–7)  
**Supersedes:** Bootstrap `Bootstrap_type_system_and_semantics.md`

---

## 0. Scope and Relationship to Bootstrap

This document specifies the complete type system and semantic analysis pipeline for the self-hosted Z98 compiler (`zig1`). It replaces the bootstrap's mutable-placeholder, pointer-chasing C++ implementation with an immutable, index-based, side-table-driven architecture.

### What Changed from Bootstrap

| Bootstrap (`zig0`) | Self-Hosted (`zig1`) | Why |
|---|---|---|
| `Type*` pointers with mutable `union as` | `TypeId` indices into `TypeRegistry` with parallel payload arrays | No pointer invalidation; cache-friendly |
| `TYPE_PLACEHOLDER` with in-place mutation | `TypeKind.unresolved_name` + Kahn's algorithm | No snapshotting, no iterator corruption |
| `DynamicArray<Type*>` for struct fields | `ArrayList(FieldEntry)` indexed by payload start/count | Flat, arena-backed |
| `DependentNode*` linked list for refresh cascade | Dependency graph `(source → target)` pairs processed by Kahn's | Deterministic, single-pass |
| `TypeInterner` with pointer-keyed dedup | `U64ToU32Map` / `U32ToU32Map` keyed on structural identity | Concrete maps, no generics |
| `is_resolving` flag on Type struct for cycle detection | `state: u8` (0=unresolved, 1=resolving, 2=resolved) in `Type` | Same semantics, explicit encoding |
| `coerceNode` mutates AST `resolved_type` in-place | `CoercionTable` side-table maps node index → coercion kind | AST is immutable after parsing |
| `ExpectedTypeGuard` RAII stack for downward inference | `expected_type_stack: ArrayList(TypeId)` with manual push/pop | Z98 has no RAII; explicit management |
| `resolvePrimitiveTypeName(const char*)` string comparison | Pre-registered primitive TypeIds at init time | O(1) lookup by well-known index |
| `TypeCreationScope` RAII guard | Explicit registration in `TypeRegistry.name_cache` | Z98 constraint |
| `forEachChild` + `ChildVisitor` virtual dispatch | Iterative DFS with `ArrayList(u32)` stack | No vtable, no recursion |

### What Didn't Change

- The set of supported types is identical (Z98 language spec).
- Assignment compatibility rules are identical (C89 strict equality + literal exception + pointer rules).
- C89 type mapping table is identical.
- 32-bit target platform assumptions are identical.
- Error union / optional / tagged union C89 struct representations are identical.

---

## 1. Type Representation

### 1.1 TypeKind Enum

```zig
pub const TypeKind = enum(u8) {
    // ═══ Primitives ═══
    void_type,           // void — size 0, align 0
    bool_type,           // bool — size 4 (C89 int), align 4
    noreturn_type,       // noreturn — size 0
    i8_type,  i16_type,  i32_type,  i64_type,
    u8_type,  u16_type,  u32_type,  u64_type,
    isize_type,          // i32 on 32-bit target
    usize_type,          // u32 on 32-bit target
    c_char_type,         // C 'char' (signedness implementation-defined)
    f32_type,  f64_type,

    // ═══ Compound ═══
    ptr_type,            // *T, *const T (single-item pointer)
    many_ptr_type,       // [*]T, [*]const T (many-item pointer)
    array_type,          // [N]T (fixed-size array)
    slice_type,          // []T, []const T (ptr + len struct)
    optional_type,       // ?T (value + has_value struct)
    error_union_type,    // E!T or !T (payload/err union + is_error flag)
    error_set_type,      // error { A, B, ... } (maps to int)
    fn_type,             // fn(P1, P2) R (function signature)
    struct_type,         // struct { fields... }
    enum_type,           // enum(backing) { members... }
    union_type,          // union { fields... } (bare, C union)
    tagged_union_type,   // union(enum) { variants... } (tag + payload struct)
    tuple_type,          // struct { T1, T2, ... } (positional fields)

    // ═══ Special ═══
    unresolved_name,     // Forward reference (name known, layout unknown)
    type_type,           // The type of types (for `const T = struct { ... }`)
    module_type,         // Pseudo-type for @import results
    null_type,           // Type of the `null` literal
    undefined_type,      // Type of the `undefined` literal
    integer_literal_type, // Type of unsuffixed integer literals (context-dependent)

    // ═══ Anonymous (pending resolution) ═══
    anon_struct_init,    // .{ .x = 1 } — awaiting target type
    anon_array,          // .{ 1, 2, 3 } — positional, awaiting array context
    anon_tuple,          // .{ a, b } — positional, awaiting tuple context
    anon_union,          // .{ .Tag = val } — awaiting tagged union context

    // ═══ Reserved for extensibility ═══
    // comptime_int, comptime_float, anytype_type, anyerror_type,
    // opaque_type, vector_type,
};
```

**Total: 39 type kinds** in `u8`.

The bootstrap had 35 (`TypeKind` enum values). New additions: `null_type`, `undefined_type`, `integer_literal_type` (bootstrap used `TYPE_NULL`, `TYPE_UNDEFINED`, `TYPE_INTEGER_LITERAL` respectively — same concepts, cleaner naming), `module_type` (bootstrap used `TYPE_MODULE`).

### 1.2 Type Struct

```zig
pub const TypeId = u32;

pub const Type = struct {
    kind: TypeKind,      // u8
    state: u8,           // 0=unresolved, 1=resolving, 2=resolved
    flags: u8,           // bit0=is_const (for ptr/slice), bit1=is_many (for ptr), bit2=is_tagged (for union)
    _pad: u8,            // alignment padding
    size: u32,           // bytes (computed during resolution)
    alignment: u32,      // bytes (computed during resolution)
    name_id: u32,        // interned string ID (0 = anonymous)
    c_name_id: u32,      // interned mangled C name (0 = not yet computed)
    module_id: u32,      // defining module index
    payload_idx: u32,    // index into kind-specific payload array
};
// sizeof = 28 bytes on 32-bit target
```

**No `resolved_type` on AST nodes.** The bootstrap stored `Type*` on every `ASTNode`. In zig1, resolved types live in a separate `ResolvedTypeTable` mapping `u32 node_idx → TypeId`. This keeps the AST immutable and the type data cache-friendly.

**No `dependents_head`/`dependents_tail`.** The bootstrap used a linked list of dependent types for cascade refresh. In zig1, the dependency graph is a flat list of `(source, target)` pairs processed by Kahn's algorithm in one pass.

### 1.3 Well-Known TypeIds

Primitives are pre-registered at `TypeRegistry.init` time with fixed indices:

```zig
pub const TYPE_VOID:     TypeId = 1;
pub const TYPE_BOOL:     TypeId = 2;
pub const TYPE_NORETURN: TypeId = 3;
pub const TYPE_I8:       TypeId = 4;
pub const TYPE_I16:      TypeId = 5;
pub const TYPE_I32:      TypeId = 6;
pub const TYPE_I64:      TypeId = 7;
pub const TYPE_U8:       TypeId = 8;
pub const TYPE_U16:      TypeId = 9;
pub const TYPE_U32:      TypeId = 10;
pub const TYPE_U64:      TypeId = 11;
pub const TYPE_ISIZE:    TypeId = 12;
pub const TYPE_USIZE:    TypeId = 13;
pub const TYPE_C_CHAR:   TypeId = 14;
pub const TYPE_F32:      TypeId = 15;
pub const TYPE_F64:      TypeId = 16;
pub const TYPE_NULL:     TypeId = 17;
pub const TYPE_UNDEFINED:TypeId = 18;
pub const TYPE_INT_LIT:  TypeId = 19;  // integer literal type
// First user-defined type starts at index 20
pub const FIRST_USER_TYPE: TypeId = 20;
```

This eliminates the bootstrap's `resolvePrimitiveTypeName(const char*)` string-comparison function. Primitive type lookup is O(1) — the semantic analysis pass recognizes primitive names during symbol registration and maps them directly to these IDs.

### 1.4 Type Payloads

Each compound TypeKind stores its extra data in a parallel array indexed by `Type.payload_idx`:

```zig
// ═══ Pointer / Many-Pointer ═══
pub const PtrPayload = struct {
    base: TypeId,        // pointee type
    // is_const and is_many are in Type.flags
};

// ═══ Array ═══
pub const ArrayPayload = struct {
    elem: TypeId,        // element type
    length: u32,         // number of elements
};

// ═══ Slice ═══
pub const SlicePayload = struct {
    elem: TypeId,        // element type
    // is_const is in Type.flags
};

// ═══ Optional ═══
pub const OptionalPayload = struct {
    payload: TypeId,     // wrapped type
};

// ═══ Error Union ═══
pub const ErrorUnionPayload = struct {
    payload: TypeId,     // success type
    error_set: TypeId,   // error set type (0 = inferred/anonymous)
};

// ═══ Error Set ═══
pub const ErrorSetPayload = struct {
    tags_start: u16,     // start index into extra_names array
    tags_count: u16,     // number of error tags
};

// ═══ Function ═══
pub const FnPayload = struct {
    name_id: u32,        // function name (interned)
    params_start: u16,   // start index into extra_types array
    params_count: u16,   // number of parameters
    return_type: TypeId, // return type
    flags: u8,           // bit0=is_extern, bit1=is_pub, bit2=is_export
};

// ═══ Struct ═══
pub const StructPayload = struct {
    fields_start: u16,   // start index into field_entries array
    fields_count: u16,   // number of fields
};

// ═══ Enum ═══
pub const EnumPayload = struct {
    backing_type: TypeId,      // backing integer type (default TYPE_I32)
    members_start: u16,        // start index into enum_members array
    members_count: u16,        // number of members
    min_value: i64,
    max_value: i64,
};

// ═══ Union (bare) ═══
pub const UnionPayload = struct {
    fields_start: u16,
    fields_count: u16,
};

// ═══ Tagged Union ═══
pub const TaggedUnionPayload = struct {
    tag_type: TypeId,          // auto-generated or explicit enum type
    fields_start: u16,         // start index into field_entries
    fields_count: u16,         // number of variants
};

// ═══ Tuple ═══
pub const TuplePayload = struct {
    elems_start: u16,          // start index into extra_types array
    elems_count: u16,          // number of elements
};

// ═══ Unresolved Name (forward reference) ═══
pub const UnresolvedPayload = struct {
    name_id: u32,              // the name we're looking for
    module_id: u32,            // where it was referenced
};
```

### 1.5 Shared Storage Arrays

Variable-length sub-structures (struct fields, enum members, function parameter types) are stored in shared flat arrays:

```zig
pub const FieldEntry = struct {
    name_id: u32,        // interned field name
    type_id: TypeId,     // field type
    offset: u32,         // byte offset in struct (computed during resolution)
};

pub const EnumMember = struct {
    name_id: u32,        // interned member name
    value: i64,          // integer value (explicit or auto-incremented)
};

// In TypeRegistry:
field_entries: ArrayList(FieldEntry),      // shared by structs, unions, tagged unions
enum_members: ArrayList(EnumMember),       // shared by enums
extra_types: ArrayList(TypeId),            // shared by fn params, tuple elements
extra_names: ArrayList(u32),              // shared by error set tags (interned name IDs)
```

---

## 2. TypeRegistry

### 2.1 Structure

```zig
pub const TypeRegistry = struct {
    types: ArrayList(Type),
    allocator: *Allocator,
    interner: *StringInterner,

    // ═══ Kind-specific payload arrays ═══
    ptr_payloads: ArrayList(PtrPayload),
    array_payloads: ArrayList(ArrayPayload),
    slice_payloads: ArrayList(SlicePayload),
    optional_payloads: ArrayList(OptionalPayload),
    eu_payloads: ArrayList(ErrorUnionPayload),
    error_set_payloads: ArrayList(ErrorSetPayload),
    fn_payloads: ArrayList(FnPayload),
    struct_payloads: ArrayList(StructPayload),
    enum_payloads: ArrayList(EnumPayload),
    union_payloads: ArrayList(UnionPayload),
    tagged_union_payloads: ArrayList(TaggedUnionPayload),
    tuple_payloads: ArrayList(TuplePayload),
    unresolved_payloads: ArrayList(UnresolvedPayload),

    // ═══ Shared sub-structure arrays ═══
    field_entries: ArrayList(FieldEntry),
    enum_members: ArrayList(EnumMember),
    extra_types: ArrayList(TypeId),
    extra_names: ArrayList(u32),

    // ═══ Deduplication caches (concrete maps, no generics) ═══
    ptr_cache: U64ToU32Map,      // key = (base_tid << 1) | is_const → TypeId
    many_ptr_cache: U64ToU32Map, // key = (base_tid << 1) | is_const → TypeId
    slice_cache: U64ToU32Map,    // key = (elem_tid << 1) | is_const → TypeId
    optional_cache: U32ToU32Map, // key = payload_tid → TypeId
    array_cache: U64ToU32Map,    // key = (elem_tid << 32) | length → TypeId

    // ═══ Named type lookup ═══
    name_cache: U64ToU32Map,     // key = (module_id << 32) | name_hash → TypeId
};
```

### 2.2 Initialization

```zig
pub fn init(alloc: *Allocator, interner: *StringInterner) !TypeRegistry {
    var self = TypeRegistry{ /* init all ArrayLists and maps */ };

    // Reserve index 0 as null sentinel
    try self.types.append(Type{
        .kind = .void_type, .state = 2, .flags = 0, ._pad = 0,
        .size = 0, .alignment = 0, .name_id = 0, .c_name_id = 0,
        .module_id = 0, .payload_idx = 0,
    });

    // Register all primitives at well-known indices
    try self.registerPrimitive(.void_type,    0, 0, "void");      // index 1
    try self.registerPrimitive(.bool_type,    4, 4, "bool");      // index 2
    try self.registerPrimitive(.noreturn_type,0, 0, "noreturn");  // index 3
    try self.registerPrimitive(.i8_type,      1, 1, "i8");        // index 4
    try self.registerPrimitive(.i16_type,     2, 2, "i16");       // index 5
    try self.registerPrimitive(.i32_type,     4, 4, "i32");       // index 6
    try self.registerPrimitive(.i64_type,     8, 8, "i64");       // index 7
    try self.registerPrimitive(.u8_type,      1, 1, "u8");        // index 8
    try self.registerPrimitive(.u16_type,     2, 2, "u16");       // index 9
    try self.registerPrimitive(.u32_type,     4, 4, "u32");       // index 10
    try self.registerPrimitive(.u64_type,     8, 8, "u64");       // index 11
    try self.registerPrimitive(.isize_type,   4, 4, "isize");     // index 12
    try self.registerPrimitive(.usize_type,   4, 4, "usize");     // index 13
    try self.registerPrimitive(.c_char_type,  1, 1, "c_char");    // index 14
    try self.registerPrimitive(.f32_type,     4, 4, "f32");       // index 15
    try self.registerPrimitive(.f64_type,     8, 8, "f64");       // index 16
    try self.registerPrimitive(.null_type,    0, 0, "null");      // index 17
    try self.registerPrimitive(.undefined_type,0,0, "undefined"); // index 18
    try self.registerPrimitive(.integer_literal_type,0,0,"<int_lit>"); // index 19

    return self;
}
```

### 2.3 Type Creation (Deduplicated)

```zig
/// Get or create a pointer type. Deduplicates via ptr_cache.
pub fn getOrCreatePtr(self: *TypeRegistry, base: TypeId, is_const: bool) !TypeId {
    const key = (@intCast(u64, base) << 1) | @intCast(u64, @boolToInt(is_const));
    if (self.ptr_cache.get(key)) |existing| return existing;

    const payload_idx = @intCast(u32, self.ptr_payloads.items.len);
    try self.ptr_payloads.append(.{ .base = base });

    const tid = @intCast(TypeId, self.types.items.len);
    try self.types.append(.{
        .kind = .ptr_type,
        .state = 2,  // pointers are always resolved (size=4)
        .flags = if (is_const) 1 else 0,
        ._pad = 0,
        .size = 4, .alignment = 4,
        .name_id = 0, .c_name_id = 0,
        .module_id = 0,
        .payload_idx = payload_idx,
    });
    try self.ptr_cache.put(key, tid);
    return tid;
}

/// Get or create a slice type. Always size=8, align=4 (ptr + len).
pub fn getOrCreateSlice(self: *TypeRegistry, elem: TypeId, is_const: bool) !TypeId {
    const key = (@intCast(u64, elem) << 1) | @intCast(u64, @boolToInt(is_const));
    if (self.slice_cache.get(key)) |existing| return existing;

    const payload_idx = @intCast(u32, self.slice_payloads.items.len);
    try self.slice_payloads.append(.{ .elem = elem });

    const tid = @intCast(TypeId, self.types.items.len);
    try self.types.append(.{
        .kind = .slice_type, .state = 2, // slices always have known layout
        .flags = if (is_const) 1 else 0, ._pad = 0,
        .size = 8, .alignment = 4,
        .name_id = 0, .c_name_id = 0, .module_id = 0,
        .payload_idx = payload_idx,
    });
    try self.slice_cache.put(key, tid);
    return tid;
}

/// Get or create an optional type.
/// Size = align_up(payload.size, 4) + 4, padded to max(payload.align, 4).
/// If payload is unresolved, size/alignment are deferred (set to 0).
pub fn getOrCreateOptional(self: *TypeRegistry, payload: TypeId) !TypeId {
    if (self.optional_cache.get(payload)) |existing| return existing;

    const pay_type = self.types.items[payload];
    var opt_size: u32 = 0;
    var opt_align: u32 = 0;
    var opt_state: u8 = 0; // unresolved if payload is unresolved

    if (pay_type.state == 2) {
        const pay_align = if (pay_type.alignment > 4) pay_type.alignment else 4;
        opt_size = alignUp(pay_type.size, 4) + 4;
        opt_size = alignUp(opt_size, pay_align);
        opt_align = pay_align;
        opt_state = 2;
    }

    const payload_idx = @intCast(u32, self.optional_payloads.items.len);
    try self.optional_payloads.append(.{ .payload = payload });

    const tid = @intCast(TypeId, self.types.items.len);
    try self.types.append(.{
        .kind = .optional_type, .state = opt_state, .flags = 0, ._pad = 0,
        .size = opt_size, .alignment = opt_align,
        .name_id = 0, .c_name_id = 0, .module_id = 0,
        .payload_idx = payload_idx,
    });

    // Only cache if fully resolved
    if (opt_state == 2) try self.optional_cache.put(payload, tid);
    return tid;
}
```

Similar `getOrCreate*` methods exist for `error_union`, `array`, `many_ptr`, `fn`, and `error_set` types.

### 2.4 Named Type Registration

Named types (structs, enums, unions, tagged unions) are registered during symbol registration (pass 3):

```zig
/// Register a named type. Returns existing TypeId if already registered.
pub fn registerNamedType(self: *TypeRegistry, module_id: u32, name_id: u32,
                         kind: TypeKind) !TypeId {
    const name_hash = self.interner.entries.items[name_id].hash;
    const key = (@intCast(u64, module_id) << 32) | @intCast(u64, name_hash);

    if (self.name_cache.get(key)) |existing| return existing;

    const tid = @intCast(TypeId, self.types.items.len);
    try self.types.append(.{
        .kind = kind, .state = 0, // unresolved
        .flags = 0, ._pad = 0,
        .size = 0, .alignment = 0,
        .name_id = name_id, .c_name_id = 0,
        .module_id = module_id, .payload_idx = 0,
    });
    try self.name_cache.put(key, tid);
    return tid;
}
```

### 2.5 Lookup Helpers

```zig
pub fn isNumeric(self: *TypeRegistry, tid: TypeId) bool {
    const kind = self.types.items[tid].kind;
    return switch (kind) {
        .i8_type, .i16_type, .i32_type, .i64_type,
        .u8_type, .u16_type, .u32_type, .u64_type,
        .isize_type, .usize_type, .f32_type, .f64_type,
        .integer_literal_type => true,
        else => false,
    };
}

pub fn isInteger(self: *TypeRegistry, tid: TypeId) bool {
    const kind = self.types.items[tid].kind;
    return switch (kind) {
        .i8_type, .i16_type, .i32_type, .i64_type,
        .u8_type, .u16_type, .u32_type, .u64_type,
        .isize_type, .usize_type, .integer_literal_type => true,
        else => false,
    };
}

pub fn isUnsigned(self: *TypeRegistry, tid: TypeId) bool {
    const kind = self.types.items[tid].kind;
    return switch (kind) {
        .u8_type, .u16_type, .u32_type, .u64_type, .usize_type => true,
        else => false,
    };
}

pub fn isPointer(self: *TypeRegistry, tid: TypeId) bool {
    const kind = self.types.items[tid].kind;
    return kind == .ptr_type or kind == .many_ptr_type;
}

pub fn isSlice(self: *TypeRegistry, tid: TypeId) bool {
    return self.types.items[tid].kind == .slice_type;
}

pub fn getPointeeType(self: *TypeRegistry, tid: TypeId) ?TypeId {
    const ty = self.types.items[tid];
    if (ty.kind != .ptr_type and ty.kind != .many_ptr_type) return null;
    return self.ptr_payloads.items[ty.payload_idx].base;
}

pub fn getSliceElem(self: *TypeRegistry, tid: TypeId) ?TypeId {
    const ty = self.types.items[tid];
    if (ty.kind != .slice_type) return null;
    return self.slice_payloads.items[ty.payload_idx].elem;
}

pub fn getStructFields(self: *TypeRegistry, tid: TypeId) []const FieldEntry {
    const ty = self.types.items[tid];
    const p = self.struct_payloads.items[ty.payload_idx];
    return self.field_entries.items[p.fields_start .. p.fields_start + p.fields_count];
}
```

---

## 3. Type Resolution: Kahn's Algorithm

### 3.1 Dependency Graph Construction

During symbol registration (pipeline pass 3), every type definition is analyzed for value dependencies:

```zig
pub const DepEntry = struct {
    source: TypeId,   // "this type must be resolved first"
    target: TypeId,   // "before this type can be resolved"
};

pub const DepGraph = struct {
    edges: ArrayList(DepEntry),
    in_degree: []u32,     // indexed by TypeId, allocated for types.items.len
    allocator: *Allocator,
};
```

**Dependency rules:**
- Struct field of type `T` (by value): add edge `T → this_struct`.
- Struct field of type `*T` or `[]T`: **no edge** (pointers/slices have fixed size regardless of `T`).
- Array `[N]T`: add edge `T → this_array`.
- Optional `?T`: add edge `T → this_optional` (size depends on payload).
- Error union `!T`: add edge `T → this_eu` and `E → this_eu` if named error set.
- Tagged union variant with payload `T` (by value): add edge `T → this_union`.
- Tagged union variant with `*T` payload: **no edge**.
- Enum: **no edges** (enums depend only on their backing integer, which is always resolved).
- Function: **no edges** (function types only need param/return types for signature checking, not for layout).

```zig
fn addValueDependencies(dep: *DepGraph, reg: *TypeRegistry, tid: TypeId) !void {
    const ty = reg.types.items[tid];
    switch (ty.kind) {
        .struct_type => {
            const sp = reg.struct_payloads.items[ty.payload_idx];
            const fields = reg.field_entries.items[sp.fields_start .. sp.fields_start + sp.fields_count];
            var i: usize = 0;
            while (i < fields.len) : (i += 1) {
                const ft = reg.types.items[fields[i].type_id];
                // Only add dependency if field is by-value (not pointer/slice/fn)
                if (isValueDependency(ft.kind)) {
                    try dep.edges.append(.{ .source = fields[i].type_id, .target = tid });
                    dep.in_degree[tid] += 1;
                }
            }
        },
        .tagged_union_type => {
            const tp = reg.tagged_union_payloads.items[ty.payload_idx];
            const fields = reg.field_entries.items[tp.fields_start .. tp.fields_start + tp.fields_count];
            var i: usize = 0;
            while (i < fields.len) : (i += 1) {
                if (fields[i].type_id == TYPE_VOID) continue; // void payload
                const ft = reg.types.items[fields[i].type_id];
                if (isValueDependency(ft.kind)) {
                    try dep.edges.append(.{ .source = fields[i].type_id, .target = tid });
                    dep.in_degree[tid] += 1;
                }
            }
        },
        .optional_type => {
            const op = reg.optional_payloads.items[ty.payload_idx];
            const pt = reg.types.items[op.payload];
            if (isValueDependency(pt.kind)) {
                try dep.edges.append(.{ .source = op.payload, .target = tid });
                dep.in_degree[tid] += 1;
            }
        },
        .error_union_type => {
            const ep = reg.eu_payloads.items[ty.payload_idx];
            const pt = reg.types.items[ep.payload];
            if (isValueDependency(pt.kind)) {
                try dep.edges.append(.{ .source = ep.payload, .target = tid });
                dep.in_degree[tid] += 1;
            }
        },
        .array_type => {
            const ap = reg.array_payloads.items[ty.payload_idx];
            const et = reg.types.items[ap.elem];
            if (isValueDependency(et.kind)) {
                try dep.edges.append(.{ .source = ap.elem, .target = tid });
                dep.in_degree[tid] += 1;
            }
        },
        else => {}, // primitives, pointers, slices, fns: no value deps
    }
}

fn isValueDependency(kind: TypeKind) bool {
    return switch (kind) {
        .struct_type, .union_type, .tagged_union_type, .enum_type,
        .array_type, .optional_type, .error_union_type, .tuple_type,
        .unresolved_name => true,
        else => false, // primitives, pointers, slices, fns → fixed layout
    };
}
```

### 3.2 Resolution Algorithm

```zig
pub fn resolveAllTypes(reg: *TypeRegistry, dep: *DepGraph, diag: *DiagnosticCollector,
                       alloc: *Allocator) !void {
    var worklist = ArrayList(TypeId).init(alloc);
    defer worklist.deinit();

    // Seed: all types with in_degree == 0
    var tid: TypeId = FIRST_USER_TYPE;
    while (tid < @intCast(TypeId, reg.types.items.len)) : (tid += 1) {
        if (dep.in_degree[tid] == 0 and reg.types.items[tid].state != 2) {
            try worklist.append(tid);
        }
    }

    var resolved_count: u32 = 0;

    while (worklist.items.len > 0) {
        const id = worklist.pop().?;
        var ty = &reg.types.items[id];
        if (ty.state == 2) continue; // already resolved (e.g., pointer)

        ty.state = 1; // resolving
        try resolveLayout(reg, id);
        ty.state = 2; // resolved
        resolved_count += 1;

        // Decrease in-degree of dependents
        var i: usize = 0;
        while (i < dep.edges.items.len) : (i += 1) {
            if (dep.edges.items[i].source == id) {
                const target = dep.edges.items[i].target;
                dep.in_degree[target] -= 1;
                if (dep.in_degree[target] == 0) {
                    try worklist.append(target);
                }
            }
        }
    }

    // Cycle detection
    tid = FIRST_USER_TYPE;
    while (tid < @intCast(TypeId, reg.types.items.len)) : (tid += 1) {
        if (reg.types.items[tid].state != 2 and dep.in_degree[tid] > 0) {
            try diag.diagnostics.append(.{
                .level = 0,
                .file_id = reg.types.items[tid].module_id,
                .span_start = 0, .span_end = 0,
                .message = "circular type dependency (infinite size)",
            });
        }
    }
}
```

### 3.3 Layout Resolution

```zig
fn resolveLayout(reg: *TypeRegistry, tid: TypeId) !void {
    var ty = &reg.types.items[tid];
    switch (ty.kind) {
        .struct_type => {
            const sp = reg.struct_payloads.items[ty.payload_idx];
            var fields = reg.field_entries.items[sp.fields_start .. sp.fields_start + sp.fields_count];
            var offset: u32 = 0;
            var max_align: u32 = 1;
            var i: usize = 0;
            while (i < fields.len) : (i += 1) {
                const ft = reg.types.items[fields[i].type_id];
                if (ft.kind == .void_type) {
                    fields[i].offset = offset; // void fields: size 0, align 1
                    i += 1; continue;
                }
                offset = alignUp(offset, ft.alignment);
                fields[i].offset = offset;
                offset += ft.size;
                if (ft.alignment > max_align) max_align = ft.alignment;
            }
            ty.size = alignUp(offset, max_align);
            ty.alignment = max_align;
        },
        .enum_type => {
            const ep = reg.enum_payloads.items[ty.payload_idx];
            const backing = reg.types.items[ep.backing_type];
            ty.size = backing.size;
            ty.alignment = backing.alignment;
        },
        .union_type => {
            const up = reg.union_payloads.items[ty.payload_idx];
            const fields = reg.field_entries.items[up.fields_start .. up.fields_start + up.fields_count];
            var max_size: u32 = 0;
            var max_align: u32 = 1;
            var i: usize = 0;
            while (i < fields.len) : (i += 1) {
                const ft = reg.types.items[fields[i].type_id];
                if (ft.size > max_size) max_size = ft.size;
                if (ft.alignment > max_align) max_align = ft.alignment;
            }
            ty.size = alignUp(max_size, max_align);
            ty.alignment = max_align;
        },
        .tagged_union_type => {
            const tp = reg.tagged_union_payloads.items[ty.payload_idx];
            const tag_ty = reg.types.items[tp.tag_type];
            const fields = reg.field_entries.items[tp.fields_start .. tp.fields_start + tp.fields_count];
            // Union part: max of all payload sizes/alignments
            var max_payload_size: u32 = 0;
            var max_payload_align: u32 = 1;
            var i: usize = 0;
            while (i < fields.len) : (i += 1) {
                const ft = reg.types.items[fields[i].type_id];
                if (ft.kind == .void_type) continue;
                if (ft.size > max_payload_size) max_payload_size = ft.size;
                if (ft.alignment > max_payload_align) max_payload_align = ft.alignment;
            }
            // Layout: tag first, then padding, then union payload
            const overall_align = if (tag_ty.alignment > max_payload_align) tag_ty.alignment else max_payload_align;
            var total = tag_ty.size;
            total = alignUp(total, max_payload_align);
            total += alignUp(max_payload_size, max_payload_align);
            ty.size = alignUp(total, overall_align);
            ty.alignment = overall_align;
        },
        .optional_type => {
            const op = reg.optional_payloads.items[ty.payload_idx];
            const pt = reg.types.items[op.payload];
            const pay_align = if (pt.alignment > 4) pt.alignment else 4;
            ty.size = alignUp(alignUp(pt.size, 4) + 4, pay_align);
            ty.alignment = pay_align;
        },
        .error_union_type => {
            const ep = reg.eu_payloads.items[ty.payload_idx];
            const pt = reg.types.items[ep.payload];
            // Layout: union { T payload; int err; } data; int is_error;
            const union_size = if (pt.size > 4) pt.size else 4;
            const union_align = if (pt.alignment > 4) pt.alignment else 4;
            var total = alignUp(union_size, union_align); // union
            total = alignUp(total, 4) + 4; // is_error (int)
            ty.size = alignUp(total, union_align);
            ty.alignment = union_align;
        },
        .array_type => {
            const ap = reg.array_payloads.items[ty.payload_idx];
            const et = reg.types.items[ap.elem];
            ty.size = et.size * ap.length;
            ty.alignment = et.alignment;
        },
        .tuple_type => {
            const tp = reg.tuple_payloads.items[ty.payload_idx];
            const elems = reg.extra_types.items[tp.elems_start .. tp.elems_start + tp.elems_count];
            var offset: u32 = 0;
            var max_align: u32 = 1;
            var i: usize = 0;
            while (i < elems.len) : (i += 1) {
                const et = reg.types.items[elems[i]];
                offset = alignUp(offset, et.alignment);
                offset += et.size;
                if (et.alignment > max_align) max_align = et.alignment;
            }
            ty.size = alignUp(offset, max_align);
            ty.alignment = max_align;
            // Empty tuple: size 1 (dummy byte for C89)
            if (ty.size == 0) { ty.size = 1; ty.alignment = 1; }
        },
        else => {}, // primitives already resolved
    }
}

fn alignUp(value: u32, alignment: u32) u32 {
    return (value + alignment - 1) & ~(alignment - 1);
}
```

---

## 4. Resolved Type Table (Side-Table)

The bootstrap stored `Type* resolved_type` directly on each `ASTNode`. The self-hosted compiler uses a separate side-table, keeping the AST immutable.

```zig
pub const ResolvedTypeTable = struct {
    entries: ArrayList(TypeTableEntry),
    /// Sparse map: not every AST node has a resolved type.
    /// Only expression nodes and declaration nodes get entries.
    index: U32ToU32Map,   // ast_node_idx → entry_idx
    allocator: *Allocator,

    pub const TypeTableEntry = struct {
        node_idx: u32,
        type_id: TypeId,
    };

    pub fn set(self: *ResolvedTypeTable, node_idx: u32, type_id: TypeId) !void {
        if (self.index.get(node_idx)) |existing| {
            self.entries.items[existing].type_id = type_id;
        } else {
            const idx = @intCast(u32, self.entries.items.len);
            try self.entries.append(.{ .node_idx = node_idx, .type_id = type_id });
            try self.index.put(node_idx, idx);
        }
    }

    pub fn get(self: *ResolvedTypeTable, node_idx: u32) ?TypeId {
        if (self.index.get(node_idx)) |idx| {
            return self.entries.items[idx].type_id;
        }
        return null;
    }
};
```

---

## 5. Coercion Rules and Table

### 5.1 Assignment Compatibility

The rules are identical to the bootstrap. The self-hosted compiler encodes them as a function:

```zig
pub fn isAssignable(reg: *TypeRegistry, source: TypeId, target: TypeId) bool {
    if (source == target) return true;

    const src = reg.types.items[source];
    const tgt = reg.types.items[target];

    // Integer literal rule: literal fits in any numeric target
    if (src.kind == .integer_literal_type and reg.isNumeric(target)) return true;

    // Null to any pointer or optional
    if (src.kind == .null_type) {
        return reg.isPointer(target) or tgt.kind == .optional_type or
               tgt.kind == .fn_type;
    }

    // T → ?T (implicit optional wrapping)
    if (tgt.kind == .optional_type) {
        const opt_pay = reg.optional_payloads.items[tgt.payload_idx];
        if (isAssignable(reg, source, opt_pay.payload)) return true;
        if (src.kind == .null_type) return true;
    }

    // T → !T (implicit error union success wrapping)
    if (tgt.kind == .error_union_type) {
        const eu_pay = reg.eu_payloads.items[tgt.payload_idx];
        if (isAssignable(reg, source, eu_pay.payload)) return true;
    }

    // error.X → !T (implicit error wrapping)
    if (src.kind == .error_set_type and tgt.kind == .error_union_type) return true;

    // *T → *void (implicit upcast)
    if (src.kind == .ptr_type and tgt.kind == .ptr_type) {
        const tgt_base = reg.ptr_payloads.items[tgt.payload_idx].base;
        if (tgt_base == TYPE_VOID) return true;
    }

    // *void → *T (bootstrap compatibility)
    if (src.kind == .ptr_type and tgt.kind == .ptr_type) {
        const src_base = reg.ptr_payloads.items[src.payload_idx].base;
        if (src_base == TYPE_VOID) return true;
    }

    // *T → *const T (const-adding)
    if (src.kind == .ptr_type and tgt.kind == .ptr_type) {
        if ((tgt.flags & 1) != 0 and (src.flags & 1) == 0) {
            const src_base = reg.ptr_payloads.items[src.payload_idx].base;
            const tgt_base = reg.ptr_payloads.items[tgt.payload_idx].base;
            if (src_base == tgt_base) return true;
        }
    }

    // []T → []const T, [*]T → [*]const T (const-adding for slices/many-ptrs)
    if (src.kind == tgt.kind and (src.kind == .slice_type or src.kind == .many_ptr_type)) {
        if ((tgt.flags & 1) != 0 and (src.flags & 1) == 0) {
            const src_elem = if (src.kind == .slice_type)
                reg.slice_payloads.items[src.payload_idx].elem
            else
                reg.ptr_payloads.items[src.payload_idx].base;
            const tgt_elem = if (tgt.kind == .slice_type)
                reg.slice_payloads.items[tgt.payload_idx].elem
            else
                reg.ptr_payloads.items[tgt.payload_idx].base;
            if (src_elem == tgt_elem) return true;
        }
    }

    // [N]T → []T (array to slice coercion)
    if (src.kind == .array_type and tgt.kind == .slice_type) {
        const arr_elem = reg.array_payloads.items[src.payload_idx].elem;
        const slc_elem = reg.slice_payloads.items[tgt.payload_idx].elem;
        if (arr_elem == slc_elem) return true;
        // Also allow [N]T → []const T
        if ((tgt.flags & 1) != 0 and arr_elem == slc_elem) return true;
    }

    // [N]T → [*]T (array to many-pointer)
    if (src.kind == .array_type and tgt.kind == .many_ptr_type) {
        const arr_elem = reg.array_payloads.items[src.payload_idx].elem;
        const ptr_base = reg.ptr_payloads.items[tgt.payload_idx].base;
        if (arr_elem == ptr_base) return true;
    }

    // []T → [*]T (slice to many-pointer via .ptr)
    if (src.kind == .slice_type and tgt.kind == .many_ptr_type) {
        const slc_elem = reg.slice_payloads.items[src.payload_idx].elem;
        const ptr_base = reg.ptr_payloads.items[tgt.payload_idx].base;
        if (slc_elem == ptr_base) return true;
    }

    // *T → ?*T (pointer to optional pointer)
    if (src.kind == .ptr_type and tgt.kind == .optional_type) {
        const opt_pay = reg.optional_payloads.items[tgt.payload_idx];
        if (reg.types.items[opt_pay.payload].kind == .ptr_type) {
            return isAssignable(reg, source, opt_pay.payload);
        }
    }

    // u8 ↔ c_char (bidirectional for C interop)
    if ((source == TYPE_U8 and target == TYPE_C_CHAR) or
        (source == TYPE_C_CHAR and target == TYPE_U8)) return true;

    // String literal coercions are handled during semantic analysis
    // when the source type is *const [N]u8

    return false;
}
```

### 5.2 Coercion Table (Side-Table)

Coercions are recorded during semantic analysis and consumed during LIR lowering:

```zig
pub const CoercionKind = enum(u8) {
    none,
    wrap_optional,          // T → ?T
    wrap_error_success,     // T → !T
    wrap_error_err,         // error.X → !T
    array_to_slice,         // [N]T → []T
    array_to_many_ptr,      // [N]T → [*]T
    slice_to_many_ptr,      // []T → [*]T
    ptr_to_optional_ptr,    // *T → ?*T
    string_to_slice,        // *const [N]u8 → []const u8
    string_to_many_ptr,     // *const [N]u8 → [*]const u8
    string_to_ptr,          // *const [N]u8 → *const u8
    const_qualify_ptr,      // *T → *const T
    const_qualify_slice,    // []T → []const T
    int_widen,              // i8 → i32, u8 → u32, etc.
    float_widen,            // f32 → f64
    int_literal_coerce,     // <int_lit> → concrete integer type
};

pub const CoercionEntry = struct {
    node_idx: u32,
    kind: CoercionKind,
    target_type: TypeId,
};

pub const CoercionTable = struct {
    entries: ArrayList(CoercionEntry),
    index: U32ToU32Map,   // node_idx → entry_idx
    allocator: *Allocator,

    pub fn add(self: *CoercionTable, node_idx: u32, kind: CoercionKind, target: TypeId) !void {
        const idx = @intCast(u32, self.entries.items.len);
        try self.entries.append(.{ .node_idx = node_idx, .kind = kind, .target_type = target });
        try self.index.put(node_idx, idx);
    }

    pub fn get(self: *CoercionTable, node_idx: u32) ?CoercionEntry {
        if (self.index.get(node_idx)) |idx| return self.entries.items[idx];
        return null;
    }
};
```

### 5.3 Integer Literal Range Checking

```zig
pub fn canLiteralFitInType(value: i64, target: TypeId) bool {
    return switch (target) {
        TYPE_I8  => value >= -128 and value <= 127,
        TYPE_I16 => value >= -32768 and value <= 32767,
        TYPE_I32 => value >= -2147483648 and value <= 2147483647,
        TYPE_I64 => true, // i64 can hold any i64
        TYPE_U8  => value >= 0 and value <= 255,
        TYPE_U16 => value >= 0 and value <= 65535,
        TYPE_U32 => value >= 0 and value <= 4294967295,
        TYPE_U64 => value >= 0, // u64 can hold any non-negative i64
        TYPE_ISIZE => value >= -2147483648 and value <= 2147483647,
        TYPE_USIZE => value >= 0 and value <= 4294967295,
        TYPE_F32, TYPE_F64 => true, // integer to float always fits
        else => false,
    };
}
```

---

## 6. Symbol Table

### 6.1 Structure

```zig
pub const SymbolTable = struct {
    scopes: ArrayList(Scope),
    current_scope: u32,
    allocator: *Allocator,

    pub const Scope = struct {
        parent: u32,         // index of parent scope (0 = none)
        depth: u32,          // nesting depth (0 = global)
        symbols: ArrayList(Symbol),
    };

    pub const SymbolKind = enum(u8) {
        local,       // stack-allocated variable
        param,       // function parameter
        global,      // top-level declaration
        function,    // function name
        type_alias,  // const T = struct { ... }
        module,      // @import result
    };

    pub const Symbol = struct {
        name_id: u32,        // interned name
        type_id: TypeId,     // resolved type
        kind: SymbolKind,
        flags: u16,          // bit0=is_const, bit1=is_pub, bit2=is_mutable, bit3=is_extern, bit4=is_export
        decl_node: u32,      // AST node index of declaration
        module_id: u32,      // defining module
        scope_depth: u32,    // scope depth at declaration
    };

    pub fn init(alloc: *Allocator) !SymbolTable {
        var self = SymbolTable{
            .scopes = ArrayList(Scope).init(alloc),
            .current_scope = 0,
            .allocator = alloc,
        };
        // Create global scope at index 0
        try self.scopes.append(.{
            .parent = 0,
            .depth = 0,
            .symbols = ArrayList(Symbol).init(alloc),
        });
        return self;
    }

    pub fn enterScope(self: *SymbolTable) !u32 {
        const idx = @intCast(u32, self.scopes.items.len);
        const parent_depth = self.scopes.items[self.current_scope].depth;
        try self.scopes.append(.{
            .parent = self.current_scope,
            .depth = parent_depth + 1,
            .symbols = ArrayList(Symbol).init(self.allocator),
        });
        self.current_scope = idx;
        return idx;
    }

    pub fn exitScope(self: *SymbolTable) void {
        self.current_scope = self.scopes.items[self.current_scope].parent;
    }

    pub fn insert(self: *SymbolTable, sym: Symbol) !bool {
        // Check for redefinition in current scope only
        const scope = &self.scopes.items[self.current_scope];
        var i: usize = 0;
        while (i < scope.symbols.items.len) : (i += 1) {
            if (scope.symbols.items[i].name_id == sym.name_id) return false;
        }
        var s = sym;
        s.scope_depth = scope.depth;
        try scope.symbols.append(s);
        return true;
    }

    /// Lookup: walk from current scope outward to global.
    pub fn lookup(self: *SymbolTable, name_id: u32) ?*Symbol {
        var scope_idx = self.current_scope;
        while (true) {
            const scope = &self.scopes.items[scope_idx];
            var i: usize = 0;
            while (i < scope.symbols.items.len) : (i += 1) {
                if (scope.symbols.items[i].name_id == name_id) {
                    return &scope.symbols.items[i];
                }
            }
            if (scope_idx == 0) break; // reached global scope
            scope_idx = scope.parent;
        }
        return null;
    }

    /// Lookup in a specific module's global scope.
    pub fn lookupInModule(self: *SymbolTable, name_id: u32, module_scope: u32) ?*Symbol {
        const scope = &self.scopes.items[module_scope];
        var i: usize = 0;
        while (i < scope.symbols.items.len) : (i += 1) {
            if (scope.symbols.items[i].name_id == name_id) {
                return &scope.symbols.items[i];
            }
        }
        return null;
    }
};
```

### 6.2 Module-Qualified Lookup

When the semantic analyzer encounters `module.Symbol` (a field access where the base is a module):

1. Look up the base identifier → should resolve to `SymbolKind.module`.
2. Get the module's global scope index.
3. Call `lookupInModule(field_name_id, module_scope)`.
4. If found and is `pub`, return the symbol. If not `pub`, emit diagnostic.

For chained access like `module.Enum.Member`:
1. Resolve `module` → module symbol.
2. Resolve `Enum` in module's scope → type alias symbol.
3. Resolve `Member` as an enum member of that type → constant fold to integer.

---

## 7. Semantic Analysis Pipeline

### 7.1 Pass Overview

```
Pass 3: Symbol Registration
    │   Register all top-level names as symbols.
    │   Create unresolved_name types for structs/unions/enums.
    │   Build type dependency graph.
    ▼
Pass 4: Type Resolution (Kahn's Algorithm)
    │   Resolve all type layouts in topological order.
    │   Compute size, alignment, field offsets.
    │   Detect cycles.
    ▼
Pass 5: Semantic Analysis
    │   5a: Comptime Evaluation (@sizeOf, @alignOf, constant folding)
    │   5b: Constraint Checking (assignments, calls, operators, control flow)
    │   5c: Coercion Insertion (build CoercionTable side-table)
    │   5d: std.debug.print Decomposition
    ▼
Pass 6-9: Static Analyzers (separate document)
```

### 7.2 Pass 3: Symbol Registration

Walk every module's top-level declarations (iteratively via `module_root` extra\_children) and:

```zig
fn registerTopLevelSymbols(ctx: *SemanticContext, module_root_idx: u32) !void {
    const root = ctx.store.nodes.items[module_root_idx];
    const decls = ctx.store.getExtraChildren(root.payload);
    var i: usize = 0;
    while (i < decls.len) : (i += 1) {
        const decl = ctx.store.nodes.items[decls[i]];
        switch (decl.kind) {
            .var_decl => {
                const name_id = ctx.store.identifiers.items[decl.payload];
                // Check if this is a type alias: const T = struct { ... }
                if (decl.child_1 != 0) {
                    const init_node = ctx.store.nodes.items[decl.child_1];
                    if (init_node.kind == .struct_decl or init_node.kind == .enum_decl or
                        init_node.kind == .union_decl) {
                        // Register as named type
                        const tid = try ctx.reg.registerNamedType(ctx.module_id, name_id, init_node.kind);
                        try ctx.symbols.insert(.{
                            .name_id = name_id, .type_id = TYPE_TYPE,
                            .kind = .type_alias, .flags = decl.flags,
                            .decl_node = decls[i], .module_id = ctx.module_id,
                            .scope_depth = 0,
                        });
                        // Register fields/variants for dependency graph
                        try registerTypeFields(ctx, tid, init_node);
                        continue;
                    }
                }
                // Regular variable — type resolved in pass 5
                try ctx.symbols.insert(.{
                    .name_id = name_id, .type_id = 0, // resolved later
                    .kind = .global, .flags = decl.flags,
                    .decl_node = decls[i], .module_id = ctx.module_id,
                    .scope_depth = 0,
                });
            },
            .fn_decl => {
                const proto = ctx.store.fn_protos.items[decl.payload];
                try ctx.symbols.insert(.{
                    .name_id = proto.name_id, .type_id = 0, // resolved in pass 5
                    .kind = .function, .flags = decl.flags,
                    .decl_node = decls[i], .module_id = ctx.module_id,
                    .scope_depth = 0,
                });
            },
            else => {},
        }
    }
}
```

### 7.3 Pass 5: Semantic Analysis — The Core Visitor

The semantic analyzer walks each function body iteratively, visiting statements in order and building the `ResolvedTypeTable` and `CoercionTable`.

```zig
pub const SemanticAnalyzer = struct {
    ctx: *SemanticContext,
    type_table: *ResolvedTypeTable,
    coercion_table: *CoercionTable,
    expected_type_stack: ArrayList(TypeId),
    current_fn_return: TypeId,
    current_fn_name: u32,

    /// Resolve the type of an expression node. Stores result in type_table.
    fn resolveExpr(self: *SemanticAnalyzer, node_idx: u32) !TypeId {
        if (node_idx == 0) return TYPE_VOID;
        const node = self.ctx.store.nodes.items[node_idx];

        const result: TypeId = switch (node.kind) {
            // ═══ Literals ═══
            .int_literal => TYPE_INT_LIT,
            .float_literal => TYPE_F64,
            .string_literal => try self.resolveStringLiteral(node),
            .char_literal => TYPE_U8,
            .bool_literal => TYPE_BOOL,
            .null_literal => TYPE_NULL,
            .undefined_literal => TYPE_UNDEFINED,
            .unreachable_expr => TYPE_NORETURN,
            .enum_literal => try self.resolveEnumLiteral(node, node_idx),
            .error_literal => try self.resolveErrorLiteral(node),

            // ═══ Identifiers ═══
            .ident_expr => try self.resolveIdentifier(node),
            .field_access => try self.resolveFieldAccess(node, node_idx),
            .index_access => try self.resolveIndexAccess(node),
            .slice_expr => try self.resolveSliceExpr(node),
            .deref => try self.resolveDeref(node),
            .address_of => try self.resolveAddressOf(node),
            .fn_call => try self.resolveFnCall(node, node_idx),
            .builtin_call => try self.resolveBuiltinCall(node, node_idx),

            // ═══ Binary ops ═══
            .add, .sub, .mul, .div, .mod_op => try self.resolveArithmetic(node),
            .bit_and, .bit_or, .bit_xor, .shl, .shr => try self.resolveBitwise(node),
            .bool_and, .bool_or => try self.resolveLogical(node),
            .cmp_eq, .cmp_ne, .cmp_lt, .cmp_le, .cmp_gt, .cmp_ge => try self.resolveComparison(node),
            .assign, .add_assign, .sub_assign, .mul_assign, .div_assign, .mod_assign,
            .shl_assign, .shr_assign, .and_assign, .xor_assign, .or_assign,
            => try self.resolveAssignment(node),

            // ═══ Unary ops ═══
            .negate => try self.resolveNegate(node),
            .bool_not => try self.resolveBoolNot(node),
            .bit_not => try self.resolveBitNot(node),

            // ═══ Error/Optional ═══
            .try_expr => try self.resolveTryExpr(node),
            .catch_expr => try self.resolveCatchExpr(node),
            .orelse_expr => try self.resolveOrelseExpr(node),

            // ═══ Control flow expressions ═══
            .if_expr => try self.resolveIfExpr(node),
            .switch_expr => try self.resolveSwitchExpr(node, node_idx),

            // ═══ Aggregate literals ═══
            .tuple_literal => try self.resolveTupleLiteral(node, node_idx),
            .struct_init => try self.resolveStructInit(node, node_idx),

            // ═══ Type expressions (resolve to TYPE_TYPE) ═══
            .ptr_type, .many_ptr_type, .array_type, .slice_type,
            .optional_type, .error_union_type, .fn_type,
            => TYPE_TYPE,

            .paren_expr => try self.resolveExpr(node.child_0),
            .import_expr => try self.resolveImport(node),

            else => blk: {
                try self.ctx.diag.diagnostics.append(.{
                    .level = 0, .file_id = 0,
                    .span_start = node.span_start, .span_end = node.span_end,
                    .message = "cannot resolve type of expression",
                });
                break :blk TYPE_VOID;
            },
        };

        try self.type_table.set(node_idx, result);
        return result;
    }
};
```

### 7.4 Key Resolution Methods

#### Arithmetic (`+`, `-`, `*`, `/`, `%`)

```zig
fn resolveArithmetic(self: *SemanticAnalyzer, node: AstNode) !TypeId {
    const lhs_type = try self.resolveExpr(node.child_0);
    const rhs_type = try self.resolveExpr(node.child_1);
    const reg = self.ctx.reg;

    // Pointer arithmetic: ptr +/- unsigned_int
    if (node.kind == .add or node.kind == .sub) {
        if (reg.isPointer(lhs_type) or reg.isSlice(lhs_type)) {
            if (reg.isUnsigned(rhs_type)) return lhs_type;
        }
        if (node.kind == .add and reg.isUnsigned(lhs_type) and reg.isPointer(rhs_type)) {
            return rhs_type; // unsigned + ptr → ptr (commutative)
        }
        // ptr - ptr → isize
        if (node.kind == .sub and reg.isPointer(lhs_type) and reg.isPointer(rhs_type)) {
            return TYPE_ISIZE;
        }
    }

    // Integer literal promotion: <lit> op T → T, T op <lit> → T
    if (lhs_type == TYPE_INT_LIT and reg.isNumeric(rhs_type)) return rhs_type;
    if (rhs_type == TYPE_INT_LIT and reg.isNumeric(lhs_type)) return lhs_type;

    // Strict: both operands must be same numeric type
    if (lhs_type != rhs_type or !reg.isNumeric(lhs_type)) {
        try self.emitTypeMismatch(node, lhs_type, rhs_type, "arithmetic");
        return TYPE_VOID;
    }
    return lhs_type;
}
```

#### Function Calls

```zig
fn resolveFnCall(self: *SemanticAnalyzer, node: AstNode, node_idx: u32) !TypeId {
    const callee_type = try self.resolveExpr(node.child_0);
    const callee_ty = self.ctx.reg.types.items[callee_type];

    if (callee_ty.kind != .fn_type) {
        try self.ctx.diag.diagnostics.append(.{
            .level = 0, .file_id = 0,
            .span_start = node.span_start, .span_end = node.span_end,
            .message = "expression is not callable",
        });
        return TYPE_VOID;
    }

    const fp = self.ctx.reg.fn_payloads.items[callee_ty.payload_idx];
    const param_types = self.ctx.reg.extra_types.items[fp.params_start .. fp.params_start + fp.params_count];
    const args = self.ctx.store.getExtraChildren(node.payload);

    // Check argument count
    if (args.len != param_types.len) {
        try self.ctx.diag.diagnostics.append(.{
            .level = 0, .file_id = 0,
            .span_start = node.span_start, .span_end = node.span_end,
            .message = "wrong number of arguments",
        });
        return fp.return_type;
    }

    // Check argument types with coercion
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        // Push expected type for downward inference
        try self.expected_type_stack.append(param_types[i]);
        const arg_type = try self.resolveExpr(args[i]);
        _ = self.expected_type_stack.pop();

        if (!isAssignable(self.ctx.reg, arg_type, param_types[i])) {
            // Check literal fit
            if (arg_type == TYPE_INT_LIT) {
                const lit_val = self.ctx.store.int_values.items[
                    self.ctx.store.nodes.items[args[i]].payload
                ];
                if (!canLiteralFitInType(@intCast(i64, lit_val), param_types[i])) {
                    try self.emitTypeMismatch2(node, arg_type, param_types[i], "argument");
                }
            } else {
                try self.emitTypeMismatch2(node, arg_type, param_types[i], "argument");
            }
        } else {
            // Record coercion if types differ
            if (arg_type != param_types[i]) {
                const kind = classifyCoercion(self.ctx.reg, arg_type, param_types[i]);
                try self.coercion_table.add(args[i], kind, param_types[i]);
            }
        }
    }

    return fp.return_type;
}
```

#### Try Expression

```zig
fn resolveTryExpr(self: *SemanticAnalyzer, node: AstNode) !TypeId {
    const inner_type = try self.resolveExpr(node.child_0);
    const reg = self.ctx.reg;
    const inner = reg.types.items[inner_type];

    if (inner.kind != .error_union_type) {
        try self.ctx.diag.diagnostics.append(.{
            .level = 0, .file_id = 0,
            .span_start = node.span_start, .span_end = node.span_end,
            .message = "try requires error union type",
        });
        return TYPE_VOID;
    }

    // Verify enclosing function returns compatible error union
    const eu = reg.eu_payloads.items[inner.payload_idx];
    return eu.payload; // try unwraps to payload type
}
```

#### Struct Initialization

```zig
fn resolveStructInit(self: *SemanticAnalyzer, node: AstNode, node_idx: u32) !TypeId {
    // Check for expected type (downward inference)
    var target_type: TypeId = 0;
    if (node.child_0 != 0) {
        // Typed init: Type{ .x = 1 }
        target_type = try self.resolveTypeExpr(node.child_0);
    } else if (self.expected_type_stack.items.len > 0) {
        // Anonymous init: .{ .x = 1 } with expected type
        target_type = self.expected_type_stack.items[self.expected_type_stack.items.len - 1];
    }

    if (target_type == 0) {
        // Cannot resolve without context — mark as anonymous
        try self.type_table.set(node_idx, TYPE_VOID); // will be resolved during coercion
        return TYPE_VOID;
    }

    const tgt = self.ctx.reg.types.items[target_type];
    const field_inits = self.ctx.store.getExtraChildren(node.payload);

    switch (tgt.kind) {
        .struct_type => try self.validateStructFields(target_type, field_inits, node),
        .tagged_union_type => try self.validateTaggedUnionInit(target_type, field_inits, node),
        .union_type => try self.validateUnionInit(target_type, field_inits, node),
        else => {
            try self.ctx.diag.diagnostics.append(.{
                .level = 0, .file_id = 0,
                .span_start = node.span_start, .span_end = node.span_end,
                .message = "cannot initialize non-aggregate type",
            });
        },
    }

    return target_type;
}
```

---

## 8. Comptime Evaluation

### 8.1 Supported Operations

```zig
pub const ComptimeEval = struct {
    reg: *TypeRegistry,
    store: *AstStore,
    interner: *StringInterner,

    /// Try to evaluate a node as a compile-time constant.
    /// Returns null if not evaluable.
    pub fn evaluate(self: *ComptimeEval, node_idx: u32) ?i64 {
        if (node_idx == 0) return null;
        const node = self.store.nodes.items[node_idx];
        return switch (node.kind) {
            .int_literal => @intCast(i64, self.store.int_values.items[node.payload]),
            .char_literal => @intCast(i64, self.store.int_values.items[node.payload]),
            .bool_literal => if (node.flags & 1 != 0) @intCast(i64, 1) else 0,
            .negate => blk: {
                const inner = self.evaluate(node.child_0) orelse return null;
                break :blk -inner;
            },
            .add => self.evalBinOp(node, .add),
            .sub => self.evalBinOp(node, .sub),
            .mul => self.evalBinOp(node, .mul),
            .div => self.evalBinOp(node, .div),
            .mod_op => self.evalBinOp(node, .mod_op),
            .builtin_call => self.evalBuiltin(node),
            .ident_expr => self.evalConstIdent(node),
            .paren_expr => self.evaluate(node.child_0),
            else => null,
        };
    }

    fn evalBuiltin(self: *ComptimeEval, node: AstNode) ?i64 {
        const name = self.interner.get(node.payload);
        if (mem_eql(name, "@sizeOf")) {
            const type_id = self.resolveTypeArg(node.child_0) orelse return null;
            const ty = self.reg.types.items[type_id];
            if (ty.state != 2) return null; // unresolved
            return @intCast(i64, ty.size);
        }
        if (mem_eql(name, "@alignOf")) {
            const type_id = self.resolveTypeArg(node.child_0) orelse return null;
            const ty = self.reg.types.items[type_id];
            if (ty.state != 2) return null;
            return @intCast(i64, ty.alignment);
        }
        if (mem_eql(name, "@intCast")) {
            // Fold if second arg is constant
            return self.evaluate(node.child_1);
        }
        return null;
    }
};
```

### 8.2 Builtin Dispatch Table

| Builtin | Args | Comptime? | C89 Emission | Notes |
|---|---|---|---|---|
| `@sizeOf(T)` | 1: type | Yes → `u64` constant | `sizeof(mangled_T)` or literal | Auto-resolves placeholders |
| `@alignOf(T)` | 1: type | Yes → `u64` constant | Literal | Auto-resolves placeholders |
| `@offsetOf(T,"f")` | 2: type, string | Yes → `u64` constant | Literal | Field offset in struct |
| `@intCast(T, e)` | 2: type, expr | If e is const | `(T)e` or `__bootstrap_T_from_U(e)` | Checked at runtime if not const |
| `@floatCast(T, e)` | 2: type, expr | If e is const | `(T)e` | |
| `@ptrCast(T, e)` | 2: type, expr | No | `(T)e` | Both must be pointers |
| `@intToPtr(T, e)` | 2: type, expr | No | `(T)e` | |
| `@ptrToInt(e)` | 1: expr | No | `(unsigned int)e` | Result is `usize` |
| `@intToFloat(T, e)` | 2: type, expr | If e is const | `(T)e` | |
| `@enumToInt(e)` | 1: expr | If enum constant | `(backing_type)e` | |
| `@intToEnum(T, e)` | 2: type, expr | If e is const | `(T)e` | |
| `@import("path")` | 1: string | — | Module reference | Handled during import resolution |

---

## 9. C89 Compatibility

### 9.1 Type Mapping Table

| Z98 Type | C89 Equivalent | Size | Align | Notes |
|---|---|---|---|---|
| `void` | `void` | 0 | 0 | |
| `bool` | `int` | 4 | 4 | C89 has no `_Bool` |
| `i8` | `signed char` | 1 | 1 | |
| `i16` | `short` | 2 | 2 | |
| `i32` | `int` | 4 | 4 | |
| `i64` | `__int64` | 8 | 8 | MSVC/OpenWatcom |
| `u8` | `unsigned char` | 1 | 1 | |
| `u16` | `unsigned short` | 2 | 2 | |
| `u32` | `unsigned int` | 4 | 4 | |
| `u64` | `unsigned __int64` | 8 | 8 | MSVC/OpenWatcom |
| `isize` | `int` | 4 | 4 | 32-bit target |
| `usize` | `unsigned int` | 4 | 4 | 32-bit target |
| `c_char` | `char` | 1 | 1 | |
| `f32` | `float` | 4 | 4 | |
| `f64` | `double` | 8 | 8 | |
| `*T` | `T*` | 4 | 4 | |
| `[*]T` | `T*` | 4 | 4 | |
| `[N]T` | `T[N]` | N×sz | align(T) | |
| `[]T` | `struct {T* ptr; uint len;}` | 8 | 4 | |
| `?T` | `struct {T value; int has_value;}` | varies | varies | |
| `!T` | `struct {union{T p; int e;} d; int is_err;}` | varies | varies | |
| `error{...}` | `int` + `#define` constants | 4 | 4 | |
| `enum(T)` | `typedef T` + `#define` members | sz(T) | align(T) | |
| `struct` | `struct` | calculated | calculated | |
| `union` | `union` | max field | max align | |
| `union(enum)` | `struct {int tag; union {...} payload;}` | calculated | calculated | |

### 9.2 Signature Validation

The `SignatureAnalyzer` (STATIC_ANALYZERS.md Section 3) validates that all function parameters and return types have C89 representations. Types that are structurally lowered (slices, optionals, error unions, tagged unions) are accepted because the C89 emitter knows how to produce their struct definitions.

### 9.3 C89 Rejected Features

| Feature | Detection Point | Diagnostic |
|---|---|---|
| `anytype` parameter | Symbol registration | ERR: `anytype` not supported |
| `comptime` parameter | Symbol registration | ERR: `comptime` params not supported |
| `anyerror` | Type resolution | ERR: `anyerror` not supported |
| Opaque types | Type resolution | ERR: opaque types not supported |
| Methods on structs | Semantic analysis | ERR: method syntax not supported |
| Variadic functions | Parser | ERR: variadic not supported |

---

## 10. Anonymous Literal Resolution

### 10.1 Resolution Flow

Anonymous literals (`.{ ... }`) cannot be typed without context. The resolution flow is:

1. **Parser**: Creates `AstKind.struct_init` with `child_0 = 0` (no type expr) or `AstKind.tuple_literal`.
2. **Semantic pass**: If `expected_type_stack` has a target type, resolve immediately against it. If not, mark as anonymous (`anon_struct_init`, `anon_array`, `anon_tuple`, or `anon_union`).
3. **Coercion**: When the anonymous node appears in a context with a known target (assignment, return, function argument), `classifyCoercion` triggers re-resolution using the target type.
4. **LIR lowering**: By this point, all anonymous literals are resolved to concrete types.

### 10.2 Expected Type Propagation (Downward Inference)

```zig
// Push expected type before visiting RHS of assignment
try self.expected_type_stack.append(lhs_type);
const rhs_type = try self.resolveExpr(rhs_node_idx);
_ = self.expected_type_stack.pop();
```

Contexts that push expected types:
- Assignment RHS: push LHS type.
- Variable declaration initializer: push declared type.
- Function call arguments: push parameter type.
- Return statement: push function return type.
- If/switch expression branches: push outer expected type.

---

## 11. Error Handling Type Semantics

### 11.1 Error Set Representation

Error tags are assigned globally unique positive integers. `0` is reserved for success.

```zig
pub const GlobalErrorRegistry = struct {
    tags: ArrayList(ErrorTag),
    by_name: U32ToU32Map,  // name_id → error code
    next_code: u32,
    allocator: *Allocator,

    pub const ErrorTag = struct {
        name_id: u32,
        code: u32,
    };

    pub fn getOrCreate(self: *GlobalErrorRegistry, name_id: u32) !u32 {
        if (self.by_name.get(name_id)) |existing| return existing;
        self.next_code += 1;
        try self.tags.append(.{ .name_id = name_id, .code = self.next_code });
        try self.by_name.put(name_id, self.next_code);
        return self.next_code;
    }
};
```

### 11.2 Implicit Wrapping Rules

| From | To | Allowed? |
|---|---|---|
| `T` | `!T` | Yes (success wrapping) |
| `error.X` | `!T` | Yes (error wrapping) |
| `!T` | `T` | **No** (must use `try` or `catch`) |
| `error.X` | `i32` | **No** (error sets are not integers in Z98) |

### 11.3 Optional Type Semantics

| From | To | Allowed? |
|---|---|---|
| `T` | `?T` | Yes (present wrapping) |
| `null` | `?T` | Yes |
| `*T` | `?*T` | Yes |
| `?T` | `T` | **No** (must use `orelse` or `if` capture) |

Member access on optionals:
- `.has_value` → `bool` (read-only)
- `.value` → `T` (read-only; only after null check)

---

## 12. Extensibility

### 12.1 Adding `comptime` Evaluation

The `ComptimeEval` struct (Section 8) is the seed. After self-hosting:
1. Add `comptime_int` and `comptime_float` TypeKinds for arbitrary-precision compile-time numbers.
2. Extend `evaluate()` to handle function calls (interpret function bodies at compile time).
3. Add `comptime` parameter support: when a function has `comptime T: type`, monomorphize it for each concrete `T` at call sites.

### 12.2 Adding Generics

1. Add `anytype` as a parameter type kind in `TypeKind`.
2. During semantic analysis, when a generic function is called with concrete types, clone the function's AST, substitute `anytype` with concrete types, and re-analyze.
3. Each monomorphization produces a unique `FnPayload` with a mangled name.

### 12.3 Adding Method Syntax

Desugar `expr.method(args)` → `Type.method(expr, args)` during semantic analysis. No type system changes needed — just a lookup in the type's namespace for a function with `self` as first parameter.

---

## Appendix A: Operator Type Rules (Complete)

| Operator | LHS Type | RHS Type | Result Type | Notes |
|---|---|---|---|---|
| `+`, `-`, `*`, `/`, `%` | numeric T | numeric T | T | Strict same-type |
| `+`, `-`, `*`, `/`, `%` | numeric T | `<int_lit>` | T | Literal promotion |
| `+`, `-` | `[*]T` / `[]T` | unsigned int | `[*]T` / `[]T` | Pointer arithmetic |
| `+` | unsigned int | `[*]T` / `[]T` | `[*]T` / `[]T` | Commutative |
| `-` | `[*]T` / `[]T` | `[*]T` / `[]T` | `isize` | Pointer distance |
| `==`, `!=`, `<`, `<=`, `>`, `>=` | numeric T | numeric T | `bool` | Same-type comparison |
| `==`, `!=` | `?T` | `null` | `bool` | Optional null check |
| `==`, `!=` | error set | error set | `bool` | Error comparison |
| `and`, `or` | `bool` | `bool` | `bool` | |
| `&`, `\|`, `^`, `<<`, `>>` | integer T | integer T | T | Same-type bitwise |
| `!` (prefix) | `bool` / int / ptr | — | `bool` | |
| `-` (prefix) | numeric T | — | T | |
| `~` (prefix) | integer T | — | T | |
| `&` (prefix) | l-value of type T | — | `*T` | |
| `.*` (postfix) | `*T` / `[*]T` | — | T | Dereference |
| `[i]` (postfix) | `[*]T` / `[N]T` / `[]T` | integer | T | Indexing |
| `.field` (postfix) | struct / union / module | — | field type | |
| `try` (prefix) | `!T` | — | T | Error propagation |
| `catch` (infix) | `!T` | T / block | T | Error fallback |
| `orelse` (infix) | `?T` | T / block | T | Optional fallback |
