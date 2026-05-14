const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const StringInterner = @import("string_interner.zig").StringInterner;

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

pub const TypeRegistry = struct {
    types_items: [*]Type,
    types_len: usize,
    types_cap: usize,
    types_alloc: *Sand,
    interner: *StringInterner,
    next_type_id: u32,
    name_keys: [*]u64,
    name_values: [*]u32,
    name_occupied: [*]u8,
    name_capacity: usize,
    name_count: usize,
};

fn typeRegistryEnsureCapacity(self: *TypeRegistry, new_cap: usize) void {
    if (new_cap <= self.types_cap) return;
    var nc = new_cap;
    if (nc < self.types_cap * 2) nc = self.types_cap * 2;
    if (nc < 32) nc = 32;
    var raw = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 32) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]Type, raw);
    for (self.types_items[0..self.types_len]) |item, i| { new_items[i] = item; }
    self.types_items = new_items;
    self.types_cap = nc;
}

fn typeRegistryAppend(self: *TypeRegistry, t: Type) u32 {
    typeRegistryEnsureCapacity(self, self.types_len + 1);
    var id = @intCast(u32, self.types_len);
    self.types_items[self.types_len] = t;
    self.types_len += 1;
    return id;
}

fn addPrimitive(self: *TypeRegistry, kind: TypeKind) u32 {
    return typeRegistryAppend(self, Type{
        .kind = kind,
        .state = @intCast(u8, 2),
        .size = @intCast(u32, 0),
        .alignment = @intCast(u32, 1),
        .name_id = @intCast(u32, 0),
        .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0),
        .payload_idx = @intCast(u32, 0),
    });
}

fn nameCacheInit(self: *TypeRegistry) void {
    self.name_keys = undefined;
    self.name_values = undefined;
    self.name_occupied = undefined;
    self.name_capacity = @intCast(usize, 0);
    self.name_count = @intCast(usize, 0);
}

fn nameCacheGrow(self: *TypeRegistry) void {
    var old_cap = self.name_capacity;
    var old_keys = self.name_keys;
    var old_values = self.name_values;
    var old_occupied = self.name_occupied;
    var new_cap = if (old_cap < @intCast(usize, 8)) @intCast(usize, 8) else old_cap * @intCast(usize, 2);
    var raw_keys = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 8) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_vals = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_occ = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 1) * new_cap, @intCast(usize, 4)) catch unreachable;
    self.name_keys = @ptrCast([*]u64, raw_keys);
    self.name_values = @ptrCast([*]u32, raw_vals);
    self.name_occupied = @ptrCast([*]u8, raw_occ);
    self.name_capacity = new_cap;
    self.name_count = @intCast(usize, 0);
    var zi: usize = 0;
    while (zi < new_cap) { self.name_occupied[zi] = @intCast(u8, 0); zi += 1; }
    var ri: usize = 0;
    while (ri < old_cap) {
        if (old_occupied[ri] != @intCast(u8, 0)) {
            var k = old_keys[ri];
            var v = old_values[ri];
            var mask2 = new_cap - @intCast(usize, 1);
            var idx = @intCast(usize, @intCast(u32, k & @intCast(u64, 0xFFFFFFFF))) & mask2;
            while (self.name_occupied[idx] != @intCast(u8, 0)) { idx = (idx + @intCast(usize, 1)) & mask2; }
            self.name_keys[idx] = k;
            self.name_values[idx] = v;
            self.name_occupied[idx] = @intCast(u8, 1);
            self.name_count += 1;
        }
        ri += 1;
    }
}

pub fn nameCacheGet(self: *TypeRegistry, key: u64) ?u32 {
    if (self.name_capacity == @intCast(usize, 0)) return null;
    var mask = self.name_capacity - @intCast(usize, 1);
    var i = @intCast(usize, @intCast(u32, key & @intCast(u64, 0xFFFFFFFF))) & mask;
    while (self.name_occupied[i] != @intCast(u8, 0)) {
        if (self.name_keys[i] == key) return self.name_values[i];
        i = (i + @intCast(usize, 1)) & mask;
    }
    return null;
}

fn nameCachePut(self: *TypeRegistry, key: u64, value: u32) void {
    if (self.name_count * @intCast(usize, 4) >= self.name_capacity * @intCast(usize, 3)) { nameCacheGrow(self); }
    if (self.name_capacity == @intCast(usize, 0)) { nameCacheGrow(self); }
    var mask = self.name_capacity - @intCast(usize, 1);
    var i = @intCast(usize, @intCast(u32, key & @intCast(u64, 0xFFFFFFFF))) & mask;
    while (self.name_occupied[i] != @intCast(u8, 0)) {
        if (self.name_keys[i] == key) { self.name_values[i] = value; return; }
        i = (i + @intCast(usize, 1)) & mask;
    }
    self.name_keys[i] = key;
    self.name_values[i] = value;
    self.name_occupied[i] = @intCast(u8, 1);
    self.name_count += 1;
}

pub fn typeRegistryInit(alloc: *Sand, interner: *StringInterner) TypeRegistry {
    var reg = TypeRegistry{
        .types_items = undefined,
        .types_len = @intCast(usize, 0),
        .types_cap = @intCast(usize, 0),
        .types_alloc = alloc,
        .interner = interner,
        .next_type_id = @intCast(u32, 0),
        .name_keys = undefined,
        .name_values = undefined,
        .name_occupied = undefined,
        .name_capacity = @intCast(usize, 0),
        .name_count = @intCast(usize, 0),
    };
    nameCacheInit(&reg);
    return reg;
}

pub fn typeRegistryRegisterPrimitives(self: *TypeRegistry) void {
    var tid = addPrimitive(self, TypeKind.void_type);
    _ = tid;
    var tb = addPrimitive(self, TypeKind.bool_type);
    _ = tb;
    var tn = addPrimitive(self, TypeKind.noreturn_type);
    _ = tn;
    addPrimitive(self, TypeKind.i8_type);
    addPrimitive(self, TypeKind.i16_type);
    addPrimitive(self, TypeKind.i32_type);
    addPrimitive(self, TypeKind.i64_type);
    addPrimitive(self, TypeKind.u8_type);
    addPrimitive(self, TypeKind.u16_type);
    addPrimitive(self, TypeKind.u32_type);
    addPrimitive(self, TypeKind.u64_type);
    addPrimitive(self, TypeKind.isize_type);
    addPrimitive(self, TypeKind.usize_type);
    addPrimitive(self, TypeKind.c_char_type);
    addPrimitive(self, TypeKind.f32_type);
    addPrimitive(self, TypeKind.f64_type);
    addPrimitive(self, TypeKind.type_type);
    self.next_type_id = @intCast(u32, self.types_len);
}

pub fn typeRegistryRegisterNamedType(self: *TypeRegistry, module_id: u32, name_id: u32, kind: TypeKind) u32 {
    var tid = self.next_type_id;
    self.next_type_id += 1;
    typeRegistryAppend(self, Type{
        .kind = kind,
        .state = @intCast(u8, 0),
        .size = @intCast(u32, 0),
        .alignment = @intCast(u32, 0),
        .name_id = name_id,
        .c_name_id = @intCast(u32, 0),
        .module_id = module_id,
        .payload_idx = @intCast(u32, 0),
    });
    var key: u64 = @intCast(u64, module_id) * @intCast(u64, 4294967296) + @intCast(u64, name_id);
    nameCachePut(self, key, tid);
    return tid;
}
