pub const TypeId = u32;

pub const TypeKind = enum(u8) {
    void_type,
    bool_type,
    noreturn_type,
    i8_type,
    i16_type,
    i32_type,
    i64_type,
    u8_type,
    u16_type,
    u32_type,
    u64_type,
    isize_type,
    usize_type,
    c_char_type,
    f32_type,
    f64_type,
    ptr_type,
    many_ptr_type,
    array_type,
    slice_type,
    optional_type,
    error_union_type,
    error_set_type,
    fn_type,
    struct_type,
    enum_type,
    union_type,
    tagged_union_type,
    tuple_type,
    unresolved_name,
    type_type,
    module_type,
};

pub const Type = struct {
    kind: TypeKind,
    state: u8,
    size: u32,
    alignment: u32,
    name_id: u32,
    c_name_id: u32,
    module_id: u32,
    payload_idx: u32,
};

pub const PtrPayload = struct { base: TypeId, is_const: bool };
pub const ArrayPayload = struct { elem: TypeId, length: u32 };
pub const SlicePayload = struct { elem: TypeId, is_const: bool };
pub const OptionalPayload = struct { payload: TypeId };
pub const EUPayload = struct { payload: TypeId, error_set: TypeId };
pub const StructField = struct { name_id: u32, type_id: TypeId, offset: u32 };
pub const StructPayload = struct { fields: u32, field_count: u16 };
pub const EnumMember = struct { name_id: u32, value: i64 };
pub const EnumPayload = struct { members: u32, member_count: u16, backing_type: TypeId };
pub const UnionPayload = struct { members: u32, member_count: u16, tag_type: TypeId };
pub const FnParam = struct { name_id: u32, type_id: TypeId };
pub const FnPayload = struct { params: u32, param_count: u16, return_type: TypeId };
pub const TuplePayload = struct { fields: u32, field_count: u16 };

pub const U32ToU32Map = struct {
    keys: []u32,
    values: []u32,
    occupied: []bool,
    capacity: u32,
    count: u32,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator, capacity: u32) U32ToU32Map {}
    pub fn get(self: *U32ToU32Map, key: u32) ?u32 {}
    pub fn put(self: *U32ToU32Map, key: u32, value: u32) !void {}
    fn grow(self: *U32ToU32Map) !void {}
};

pub const U64ToU32Map = struct {
    keys: []u64,
    values: []u32,
    occupied: []bool,
    capacity: u32,
    count: u32,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator, capacity: u32) U64ToU32Map {}
    pub fn get(self: *U64ToU32Map, key: u64) ?u32 {}
    pub fn put(self: *U64ToU32Map, key: u64, value: u32) !void {}
    fn grow(self: *U64ToU32Map) !void {}
};

pub const TypeRegistry = struct {
    types: std.ArrayList(Type),
    interner: *StringInterner,
    allocator: *Allocator,
    ptr_payloads: std.ArrayList(PtrPayload),
    array_payloads: std.ArrayList(ArrayPayload),
    slice_payloads: std.ArrayList(SlicePayload),
    optional_payloads: std.ArrayList(OptionalPayload),
    error_union_payloads: std.ArrayList(EUPayload),
    struct_fields: std.ArrayList(StructField),
    struct_payloads: std.ArrayList(StructPayload),
    enum_members: std.ArrayList(EnumMember),
    enum_payloads: std.ArrayList(EnumPayload),
    union_payloads: std.ArrayList(UnionPayload),
    fn_params: std.ArrayList(FnParam),
    fn_payloads: std.ArrayList(FnPayload),
    tuple_payloads: std.ArrayList(TuplePayload),
    ptr_cache: U64ToU32Map,
    slice_cache: U64ToU32Map,
    optional_cache: U32ToU32Map,
    array_cache: U64ToU32Map,
    name_cache: U64ToU32Map,

    pub fn init(allocator: *Allocator, interner: *StringInterner) TypeRegistry {}
    pub fn getOrCreatePtr(self: *TypeRegistry, base: TypeId, is_const: bool) !TypeId {}
    pub fn getOrCreateSlice(self: *TypeRegistry, elem: TypeId, is_const: bool) !TypeId {}
    pub fn registerPrimitives(self: *TypeRegistry) !void {}
    pub fn registerNamedType(self: *TypeRegistry, module_id: u32, name_id: u32, kind: TypeKind) !TypeId {}
};

const std = @import("std");
const StringInterner = @import("string_interner.zig").StringInterner;
const Allocator = @import("allocator.zig").Allocator;
