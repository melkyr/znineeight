const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const StringInterner = @import("string_interner.zig").StringInterner;

pub const TypeId = u32;

pub const TYPE_VOID:      TypeId = 1;
pub const TYPE_BOOL:      TypeId = 2;
pub const TYPE_NORETURN:  TypeId = 3;
pub const TYPE_I8:        TypeId = 4;
pub const TYPE_I16:       TypeId = 5;
pub const TYPE_I32:       TypeId = 6;
pub const TYPE_I64:       TypeId = 7;
pub const TYPE_U8:        TypeId = 8;
pub const TYPE_U16:       TypeId = 9;
pub const TYPE_U32:       TypeId = 10;
pub const TYPE_U64:       TypeId = 11;
pub const TYPE_ISIZE:     TypeId = 12;
pub const TYPE_USIZE:     TypeId = 13;
pub const TYPE_C_CHAR:    TypeId = 14;
pub const TYPE_F32:       TypeId = 15;
pub const TYPE_F64:       TypeId = 16;
pub const TYPE_NULL:      TypeId = 17;
pub const TYPE_UNDEFINED: TypeId = 18;
pub const TYPE_INT_LIT:   TypeId = 19;
pub const FIRST_USER_TYPE: TypeId = 20;

pub const TypeKind = enum(u8) {
    none_sentinel,
    void_type, bool_type, noreturn_type,
    i8_type, i16_type, i32_type, i64_type,
    u8_type, u16_type, u32_type, u64_type,
    isize_type, usize_type, c_char_type,
    f32_type, f64_type,
    ptr_type, many_ptr_type, array_type, slice_type,
    optional_type, error_union_type, error_set_type,
    fn_type,
    struct_type, enum_type, union_type, tagged_union_type,
    tuple_type, unresolved_name,
    type_type, module_type,
    null_type, undefined_type,
    integer_literal_type,
    anon_struct_init, anon_array, anon_tuple, anon_union,
};

pub const Type = struct {
    kind: TypeKind,
    state: u8,
    flags: u8,
    _pad: u8,
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
pub const ErrorSetPayload = struct { tags_start: u16, tags_count: u16 };
pub const FnPayload = struct { name_id: u32, params_start: u16, params_count: u16, return_type: TypeId, flags_packed: u8 };
pub const StructPayload = struct { fields_start: u16, fields_count: u16 };
pub const EnumPayload = struct { members_start: u16, members_count: u16, backing_type: TypeId };
pub const UnionPayload = struct { fields_start: u16, fields_count: u16, tag_type: TypeId };
pub const TaggedUnionPayload = struct { tag_type: TypeId, fields_start: u16, fields_count: u16 };
pub const TuplePayload = struct { elems_start: u16, elems_count: u16 };
pub const UnresolvedPayload = struct { name_id: u32, module_id: u32 };
pub const FieldEntry = struct { name_id: u32, type_id: TypeId, offset: u32 };
pub const EnumMember = struct { name_id: u32, value: i64 };
pub const FnParam = struct { name_id: u32, type_id: TypeId };

pub const TypeRegistry = struct {
    types_items: [*]Type,
    types_len: usize,
    types_cap: usize,
    types_alloc: *Sand,
    interner: *StringInterner,
    next_type_id: u32,

    ptr_items: [*]PtrPayload, ptr_len: usize, ptr_cap: usize,
    array_items: [*]ArrayPayload, array_len: usize, array_cap: usize,
    slice_items: [*]SlicePayload, slice_len: usize, slice_cap: usize,
    opt_items: [*]OptionalPayload, opt_len: usize, opt_cap: usize,
    eu_items: [*]EUPayload, eu_len: usize, eu_cap: usize,
    es_items: [*]ErrorSetPayload, es_len: usize, es_cap: usize,
    fn_items: [*]FnPayload, fn_len: usize, fn_cap: usize,
    st_items: [*]StructPayload, st_len: usize, st_cap: usize,
    en_items: [*]EnumPayload, en_len: usize, en_cap: usize,
    un_items: [*]UnionPayload, un_len: usize, un_cap: usize,
    tu_items: [*]TaggedUnionPayload, tu_len: usize, tu_cap: usize,
    tup_items: [*]TuplePayload, tup_len: usize, tup_cap: usize,
    unr_items: [*]UnresolvedPayload, unr_len: usize, unr_cap: usize,

    fe_items: [*]FieldEntry, fe_len: usize, fe_cap: usize,
    em_items: [*]EnumMember, em_len: usize, em_cap: usize,
    xt_items: [*]TypeId, xt_len: usize, xt_cap: usize,
    xn_items: [*]u32, xn_len: usize, xn_cap: usize,

    pc_keys: [*]u64, pc_values: [*]u32, pc_occupied: [*]u8, pc_capacity: usize, pc_count: usize,
    mpc_keys: [*]u64, mpc_values: [*]u32, mpc_occupied: [*]u8, mpc_capacity: usize, mpc_count: usize,
    slc_keys: [*]u64, slc_values: [*]u32, slc_occupied: [*]u8, slc_capacity: usize, slc_count: usize,
    optc_keys: [*]u32, optc_values: [*]u32, optc_occupied: [*]u8, optc_capacity: usize, optc_count: usize,
    arrc_keys: [*]u64, arrc_values: [*]u32, arrc_occupied: [*]u8, arrc_capacity: usize, arrc_count: usize,

    name_keys: [*]u64,
    name_values: [*]u32,
    name_occupied: [*]u8,
    name_capacity: usize,
    name_count: usize,
};

fn arrayGrow(items_out: *[*]u8, len_ptr: *usize, cap_ptr: *usize, alloc: *Sand, elem_size: usize) void {
    var nc = if (cap_ptr.* < @intCast(usize, 8)) @intCast(usize, 8) else cap_ptr.* * @intCast(usize, 2);
    var raw = alloc_mod.sandAlloc(alloc, elem_size * nc, @intCast(usize, 4)) catch unreachable;
    var src = @ptrCast([*]u8, items_out.*);
    var dst = @ptrCast([*]u8, raw);
    var i: usize = 0;
    while (i < len_ptr.*) { dst[i] = src[i]; i += 1; }
    items_out.* = raw;
    cap_ptr.* = nc;
}

fn payloadEnsure(items_out: *[*]u8, len_ptr: *usize, cap_ptr: *usize, alloc: *Sand, elem_size: usize, new_cap: usize) void {
    if (new_cap <= cap_ptr.*) return;
    arrayGrow(items_out, len_ptr, cap_ptr, alloc, elem_size);
}

fn typeRegistryEnsureCapacity(self: *TypeRegistry, new_cap: usize) void {
    if (new_cap <= self.types_cap) return;
    var nc = new_cap;
    if (nc < self.types_cap * 2) nc = self.types_cap * 2;
    if (nc < 32) nc = 32;
    var raw = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 28) * nc, @intCast(usize, 4)) catch unreachable;
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

fn ptrAppend(self: *TypeRegistry, v: PtrPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.ptr_items), &self.ptr_len, &self.ptr_cap, self.types_alloc, @sizeOf(PtrPayload), self.ptr_len + 1);
    self.ptr_items[self.ptr_len] = v; self.ptr_len += 1;
}
fn arrayAppend(self: *TypeRegistry, v: ArrayPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.array_items), &self.array_len, &self.array_cap, self.types_alloc, @sizeOf(ArrayPayload), self.array_len + 1);
    self.array_items[self.array_len] = v; self.array_len += 1;
}
fn sliceAppend(self: *TypeRegistry, v: SlicePayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.slice_items), &self.slice_len, &self.slice_cap, self.types_alloc, @sizeOf(SlicePayload), self.slice_len + 1);
    self.slice_items[self.slice_len] = v; self.slice_len += 1;
}
fn optAppend(self: *TypeRegistry, v: OptionalPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.opt_items), &self.opt_len, &self.opt_cap, self.types_alloc, @sizeOf(OptionalPayload), self.opt_len + 1);
    self.opt_items[self.opt_len] = v; self.opt_len += 1;
}
fn euAppend(self: *TypeRegistry, v: EUPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.eu_items), &self.eu_len, &self.eu_cap, self.types_alloc, @sizeOf(EUPayload), self.eu_len + 1);
    self.eu_items[self.eu_len] = v; self.eu_len += 1;
}
fn esAppend(self: *TypeRegistry, v: ErrorSetPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.es_items), &self.es_len, &self.es_cap, self.types_alloc, @sizeOf(ErrorSetPayload), self.es_len + 1);
    self.es_items[self.es_len] = v; self.es_len += 1;
}
fn fnAppend(self: *TypeRegistry, v: FnPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.fn_items), &self.fn_len, &self.fn_cap, self.types_alloc, @sizeOf(FnPayload), self.fn_len + 1);
    self.fn_items[self.fn_len] = v; self.fn_len += 1;
}
fn stAppend(self: *TypeRegistry, v: StructPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.st_items), &self.st_len, &self.st_cap, self.types_alloc, @sizeOf(StructPayload), self.st_len + 1);
    self.st_items[self.st_len] = v; self.st_len += 1;
}
fn enAppend(self: *TypeRegistry, v: EnumPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.en_items), &self.en_len, &self.en_cap, self.types_alloc, @sizeOf(EnumPayload), self.en_len + 1);
    self.en_items[self.en_len] = v; self.en_len += 1;
}
fn unAppend(self: *TypeRegistry, v: UnionPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.un_items), &self.un_len, &self.un_cap, self.types_alloc, @sizeOf(UnionPayload), self.un_len + 1);
    self.un_items[self.un_len] = v; self.un_len += 1;
}
fn tuAppend(self: *TypeRegistry, v: TaggedUnionPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.tu_items), &self.tu_len, &self.tu_cap, self.types_alloc, @sizeOf(TaggedUnionPayload), self.tu_len + 1);
    self.tu_items[self.tu_len] = v; self.tu_len += 1;
}
fn tupAppend(self: *TypeRegistry, v: TuplePayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.tup_items), &self.tup_len, &self.tup_cap, self.types_alloc, @sizeOf(TuplePayload), self.tup_len + 1);
    self.tup_items[self.tup_len] = v; self.tup_len += 1;
}
fn unrAppend(self: *TypeRegistry, v: UnresolvedPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.unr_items), &self.unr_len, &self.unr_cap, self.types_alloc, @sizeOf(UnresolvedPayload), self.unr_len + 1);
    self.unr_items[self.unr_len] = v; self.unr_len += 1;
}
fn feAppend(self: *TypeRegistry, v: FieldEntry) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.fe_items), &self.fe_len, &self.fe_cap, self.types_alloc, @sizeOf(FieldEntry), self.fe_len + 1);
    self.fe_items[self.fe_len] = v; self.fe_len += 1;
}
fn emAppend(self: *TypeRegistry, v: EnumMember) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.em_items), &self.em_len, &self.em_cap, self.types_alloc, @sizeOf(EnumMember), self.em_len + 1);
    self.em_items[self.em_len] = v; self.em_len += 1;
}
fn xtAppend(self: *TypeRegistry, v: TypeId) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.xt_items), &self.xt_len, &self.xt_cap, self.types_alloc, @intCast(usize, 4), self.xt_len + 1);
    self.xt_items[self.xt_len] = v; self.xt_len += 1;
}
fn xnAppend(self: *TypeRegistry, v: u32) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.xn_items), &self.xn_len, &self.xn_cap, self.types_alloc, @intCast(usize, 4), self.xn_len + 1);
    self.xn_items[self.xn_len] = v; self.xn_len += 1;
}

fn registerPrimitive(self: *TypeRegistry, kind: TypeKind, size: u32, alignment: u32) u32 {
    return typeRegistryAppend(self, Type{
        .kind = kind,
        .state = @intCast(u8, 2),
        .flags = @intCast(u8, 0),
        ._pad = @intCast(u8, 0),
        .size = size,
        .alignment = alignment,
        .name_id = @intCast(u32, 0),
        .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0),
        .payload_idx = @intCast(u32, 0),
    });
}

fn alignUp(v: u32, a: u32) u32 {
    return (v + a - @intCast(u32, 1)) & ~(a - @intCast(u32, 1));
}

fn initArray(items: *[*]u8, len: *usize, cap: *usize) void {
    items.* = undefined;
    len.* = @intCast(usize, 0);
    cap.* = @intCast(usize, 0);
}

fn initCache64(keys: *[*]u64, values: *[*]u32, occupied: *[*]u8, capacity: *usize, count: *usize) void {
    keys.* = undefined; values.* = undefined; occupied.* = undefined;
    capacity.* = @intCast(usize, 0); count.* = @intCast(usize, 0);
}

fn initCache32(keys: *[*]u32, values: *[*]u32, occupied: *[*]u8, capacity: *usize, count: *usize) void {
    keys.* = undefined; values.* = undefined; occupied.* = undefined;
    capacity.* = @intCast(usize, 0); count.* = @intCast(usize, 0);
}

pub fn typeRegistryInit(alloc: *Sand, interner: *StringInterner) TypeRegistry {
    var reg = TypeRegistry{
        .types_items = undefined, .types_len = @intCast(usize, 0), .types_cap = @intCast(usize, 0), .types_alloc = alloc,
        .interner = interner, .next_type_id = @intCast(u32, 0),
        .ptr_items = undefined, .ptr_len = @intCast(usize, 0), .ptr_cap = @intCast(usize, 0),
        .array_items = undefined, .array_len = @intCast(usize, 0), .array_cap = @intCast(usize, 0),
        .slice_items = undefined, .slice_len = @intCast(usize, 0), .slice_cap = @intCast(usize, 0),
        .opt_items = undefined, .opt_len = @intCast(usize, 0), .opt_cap = @intCast(usize, 0),
        .eu_items = undefined, .eu_len = @intCast(usize, 0), .eu_cap = @intCast(usize, 0),
        .es_items = undefined, .es_len = @intCast(usize, 0), .es_cap = @intCast(usize, 0),
        .fn_items = undefined, .fn_len = @intCast(usize, 0), .fn_cap = @intCast(usize, 0),
        .st_items = undefined, .st_len = @intCast(usize, 0), .st_cap = @intCast(usize, 0),
        .en_items = undefined, .en_len = @intCast(usize, 0), .en_cap = @intCast(usize, 0),
        .un_items = undefined, .un_len = @intCast(usize, 0), .un_cap = @intCast(usize, 0),
        .tu_items = undefined, .tu_len = @intCast(usize, 0), .tu_cap = @intCast(usize, 0),
        .tup_items = undefined, .tup_len = @intCast(usize, 0), .tup_cap = @intCast(usize, 0),
        .unr_items = undefined, .unr_len = @intCast(usize, 0), .unr_cap = @intCast(usize, 0),
        .fe_items = undefined, .fe_len = @intCast(usize, 0), .fe_cap = @intCast(usize, 0),
        .em_items = undefined, .em_len = @intCast(usize, 0), .em_cap = @intCast(usize, 0),
        .xt_items = undefined, .xt_len = @intCast(usize, 0), .xt_cap = @intCast(usize, 0),
        .xn_items = undefined, .xn_len = @intCast(usize, 0), .xn_cap = @intCast(usize, 0),
        .pc_keys = undefined, .pc_values = undefined, .pc_occupied = undefined, .pc_capacity = @intCast(usize, 0), .pc_count = @intCast(usize, 0),
        .mpc_keys = undefined, .mpc_values = undefined, .mpc_occupied = undefined, .mpc_capacity = @intCast(usize, 0), .mpc_count = @intCast(usize, 0),
        .slc_keys = undefined, .slc_values = undefined, .slc_occupied = undefined, .slc_capacity = @intCast(usize, 0), .slc_count = @intCast(usize, 0),
        .optc_keys = undefined, .optc_values = undefined, .optc_occupied = undefined, .optc_capacity = @intCast(usize, 0), .optc_count = @intCast(usize, 0),
        .arrc_keys = undefined, .arrc_values = undefined, .arrc_occupied = undefined, .arrc_capacity = @intCast(usize, 0), .arrc_count = @intCast(usize, 0),
        .name_keys = undefined,
        .name_values = undefined,
        .name_occupied = undefined,
        .name_capacity = @intCast(usize, 0),
        .name_count = @intCast(usize, 0),
    };
    return reg;
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

fn cacheGetU64(keys: [*]u64, values: [*]u32, occupied: [*]u8, capacity: usize, key: u64) ?u32 {
    if (capacity == @intCast(usize, 0)) return null;
    var mask = capacity - @intCast(usize, 1);
    var idx = @intCast(usize, @intCast(u32, key & @intCast(u64, 0xFFFFFFFF))) & mask;
    while (occupied[idx] != @intCast(u8, 0)) {
        if (keys[idx] == key) return values[idx];
        idx = (idx + @intCast(usize, 1)) & mask;
    }
    return null;
}

fn cacheGrowU64(self: *TypeRegistry, keys: *[*]u64, values: *[*]u32, occupied: *[*]u8, capacity: *usize, count: *usize) void {
    var old_cap = capacity.*;
    var old_keys = keys.*;
    var old_values = values.*;
    var old_occupied = occupied.*;
    var new_cap = if (old_cap < @intCast(usize, 8)) @intCast(usize, 8) else old_cap * @intCast(usize, 2);
    var raw_keys = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 8) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_vals = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_occ = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 1) * new_cap, @intCast(usize, 4)) catch unreachable;
    keys.* = @ptrCast([*]u64, raw_keys);
    values.* = @ptrCast([*]u32, raw_vals);
    occupied.* = @ptrCast([*]u8, raw_occ);
    capacity.* = new_cap;
    count.* = @intCast(usize, 0);
    var zi: usize = 0;
    while (zi < new_cap) { occupied.*[zi] = @intCast(u8, 0); zi += 1; }
    var ri: usize = 0;
    while (ri < old_cap) {
        if (old_occupied[ri] != @intCast(u8, 0)) {
            var k = old_keys[ri];
            var v = old_values[ri];
            var mask2 = new_cap - @intCast(usize, 1);
            var idx = @intCast(usize, @intCast(u32, k & @intCast(u64, 0xFFFFFFFF))) & mask2;
            while (occupied.*[idx] != @intCast(u8, 0)) { idx = (idx + @intCast(usize, 1)) & mask2; }
            keys.*[idx] = k;
            values.*[idx] = v;
            occupied.*[idx] = @intCast(u8, 1);
            count.* += 1;
        }
        ri += 1;
    }
}

fn cachePutU64(self: *TypeRegistry, keys: *[*]u64, values: *[*]u32, occupied: *[*]u8, capacity: *usize, count: *usize, key: u64, value: u32) void {
    if (count.* * @intCast(usize, 4) >= capacity.* * @intCast(usize, 3)) { cacheGrowU64(self, keys, values, occupied, capacity, count); }
    if (capacity.* == @intCast(usize, 0)) { cacheGrowU64(self, keys, values, occupied, capacity, count); }
    var mask = capacity.* - @intCast(usize, 1);
    var idx = @intCast(usize, @intCast(u32, key & @intCast(u64, 0xFFFFFFFF))) & mask;
    while (occupied.*[idx] != @intCast(u8, 0)) {
        if (keys.*[idx] == key) { values.*[idx] = value; return; }
        idx = (idx + @intCast(usize, 1)) & mask;
    }
    keys.*[idx] = key;
    values.*[idx] = value;
    occupied.*[idx] = @intCast(u8, 1);
    count.* += 1;
}

fn cacheGetU32(keys: [*]u32, values: [*]u32, occupied: [*]u8, capacity: usize, key: u32) ?u32 {
    if (capacity == @intCast(usize, 0)) return null;
    var mask = capacity - @intCast(usize, 1);
    var idx = @intCast(usize, key) & mask;
    while (occupied[idx] != @intCast(u8, 0)) {
        if (keys[idx] == key) return values[idx];
        idx = (idx + @intCast(usize, 1)) & mask;
    }
    return null;
}

fn cacheGrowU32(self: *TypeRegistry, keys: *[*]u32, values: *[*]u32, occupied: *[*]u8, capacity: *usize, count: *usize) void {
    var old_cap = capacity.*;
    var old_keys = keys.*;
    var old_values = values.*;
    var old_occupied = occupied.*;
    var new_cap = if (old_cap < @intCast(usize, 8)) @intCast(usize, 8) else old_cap * @intCast(usize, 2);
    var raw_keys = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_vals = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_occ = alloc_mod.sandAlloc(self.types_alloc, @intCast(usize, 1) * new_cap, @intCast(usize, 4)) catch unreachable;
    keys.* = @ptrCast([*]u32, raw_keys);
    values.* = @ptrCast([*]u32, raw_vals);
    occupied.* = @ptrCast([*]u8, raw_occ);
    capacity.* = new_cap;
    count.* = @intCast(usize, 0);
    var zi: usize = 0;
    while (zi < new_cap) { occupied.*[zi] = @intCast(u8, 0); zi += 1; }
    var ri: usize = 0;
    while (ri < old_cap) {
        if (old_occupied[ri] != @intCast(u8, 0)) {
            var k = old_keys[ri];
            var v = old_values[ri];
            var mask2 = new_cap - @intCast(usize, 1);
            var idx = @intCast(usize, k) & mask2;
            while (occupied.*[idx] != @intCast(u8, 0)) { idx = (idx + @intCast(usize, 1)) & mask2; }
            keys.*[idx] = k;
            values.*[idx] = v;
            occupied.*[idx] = @intCast(u8, 1);
            count.* += 1;
        }
        ri += 1;
    }
}

fn cachePutU32(self: *TypeRegistry, keys: *[*]u32, values: *[*]u32, occupied: *[*]u8, capacity: *usize, count: *usize, key: u32, value: u32) void {
    if (count.* * @intCast(usize, 4) >= capacity.* * @intCast(usize, 3)) { cacheGrowU32(self, keys, values, occupied, capacity, count); }
    if (capacity.* == @intCast(usize, 0)) { cacheGrowU32(self, keys, values, occupied, capacity, count); }
    var mask = capacity.* - @intCast(usize, 1);
    var idx = @intCast(usize, key) & mask;
    while (occupied.*[idx] != @intCast(u8, 0)) {
        if (keys.*[idx] == key) { values.*[idx] = value; return; }
        idx = (idx + @intCast(usize, 1)) & mask;
    }
    keys.*[idx] = key;
    values.*[idx] = value;
    occupied.*[idx] = @intCast(u8, 1);
    count.* += 1;
}

pub fn typeRegistryGetOrCreatePtr(self: *TypeRegistry, base: TypeId, is_const: bool) u32 {
    var ic: u64 = if (is_const) @intCast(u64, 1) else @intCast(u64, 0);
    var key: u64 = (@intCast(u64, base) << @intCast(u64, 1)) | ic;
    if (cacheGetU64(self.pc_keys, self.pc_values, self.pc_occupied, self.pc_capacity, key)) |existing| return existing;
    ptrAppend(self, PtrPayload{ .base = base, .is_const = is_const });
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.ptr_type, .state = @intCast(u8, 2),
        .flags = @intCast(u8, if (is_const) 1 else 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 4), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.ptr_len - @intCast(usize, 1)),
    });
    cachePutU64(self, &self.pc_keys, &self.pc_values, &self.pc_occupied, &self.pc_capacity, &self.pc_count, key, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateManyPtr(self: *TypeRegistry, base: TypeId, is_const: bool) u32 {
    var ic: u64 = if (is_const) @intCast(u64, 1) else @intCast(u64, 0);
    var key: u64 = (@intCast(u64, base) << @intCast(u64, 1)) | ic;
    if (cacheGetU64(self.mpc_keys, self.mpc_values, self.mpc_occupied, self.mpc_capacity, key)) |existing| return existing;
    ptrAppend(self, PtrPayload{ .base = base, .is_const = is_const });
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.many_ptr_type, .state = @intCast(u8, 2),
        .flags = @intCast(u8, if (is_const) 1 else 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 4), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.ptr_len - @intCast(usize, 1)),
    });
    cachePutU64(self, &self.mpc_keys, &self.mpc_values, &self.mpc_occupied, &self.mpc_capacity, &self.mpc_count, key, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateSlice(self: *TypeRegistry, elem: TypeId, is_const: bool) u32 {
    var ic: u64 = if (is_const) @intCast(u64, 1) else @intCast(u64, 0);
    var key: u64 = (@intCast(u64, elem) << @intCast(u64, 1)) | ic;
    if (cacheGetU64(self.slc_keys, self.slc_values, self.slc_occupied, self.slc_capacity, key)) |existing| return existing;
    sliceAppend(self, SlicePayload{ .elem = elem, .is_const = is_const });
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.slice_type, .state = @intCast(u8, 2),
        .flags = @intCast(u8, if (is_const) 1 else 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 8), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.slice_len - @intCast(usize, 1)),
    });
    cachePutU64(self, &self.slc_keys, &self.slc_values, &self.slc_occupied, &self.slc_capacity, &self.slc_count, key, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateOptional(self: *TypeRegistry, payload: TypeId) u32 {
    if (cacheGetU32(self.optc_keys, self.optc_values, self.optc_occupied, self.optc_capacity, payload)) |existing| return existing;
    var pay_type = self.types_items[payload];
    var opt_size: u32 = 0;
    var opt_align: u32 = 0;
    var opt_state: u8 = 0;
    if (pay_type.state == @intCast(u8, 2)) {
        var pay_align = if (pay_type.alignment > @intCast(u32, 4)) pay_type.alignment else @intCast(u32, 4);
        opt_size = alignUp(pay_type.size, @intCast(u32, 4)) + @intCast(u32, 4);
        opt_size = alignUp(opt_size, pay_align);
        opt_align = pay_align;
        opt_state = @intCast(u8, 2);
    }
    optAppend(self, OptionalPayload{ .payload = payload });
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.optional_type, .state = opt_state, .flags = @intCast(u8, 0), ._pad = @intCast(u8, 0),
        .size = opt_size, .alignment = opt_align,
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.opt_len - @intCast(usize, 1)),
    });
    if (opt_state == @intCast(u8, 2)) cachePutU32(self, &self.optc_keys, &self.optc_values, &self.optc_occupied, &self.optc_capacity, &self.optc_count, payload, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateErrorUnion(self: *TypeRegistry, payload: TypeId, error_set: TypeId) u32 {
    euAppend(self, EUPayload{ .payload = payload, .error_set = error_set });
    return typeRegistryAppend(self, Type{
        .kind = TypeKind.error_union_type, .state = @intCast(u8, 2), .flags = @intCast(u8, 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 8), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.eu_len - @intCast(usize, 1)),
    });
}

pub fn typeRegistryGetOrCreateArray(self: *TypeRegistry, elem: TypeId, length: u32) u32 {
    var key = (@intCast(u64, elem) << @intCast(u64, 32)) | @intCast(u64, length);
    if (cacheGetU64(self.arrc_keys, self.arrc_values, self.arrc_occupied, self.arrc_capacity, key)) |existing| return existing;
    arrayAppend(self, ArrayPayload{ .elem = elem, .length = length });
    var elem_ty = self.types_items[elem];
    var arr_size: u32 = 0;
    var arr_align: u32 = 0;
    if (elem_ty.state == @intCast(u8, 2)) {
        arr_size = elem_ty.size * length;
        arr_align = elem_ty.alignment;
    }
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.array_type, .state = @intCast(u8, 2), .flags = @intCast(u8, 0), ._pad = @intCast(u8, 0),
        .size = arr_size, .alignment = arr_align,
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.array_len - @intCast(usize, 1)),
    });
    if (elem_ty.state == @intCast(u8, 2)) cachePutU64(self, &self.arrc_keys, &self.arrc_values, &self.arrc_occupied, &self.arrc_capacity, &self.arrc_count, key, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateFn(self: *TypeRegistry, name_id: u32, params_start: u16, params_count: u16, return_type: TypeId) u32 {
    fnAppend(self, FnPayload{ .name_id = name_id, .params_start = params_start, .params_count = params_count, .return_type = return_type, .flags_packed = @intCast(u8, 0) });
    return typeRegistryAppend(self, Type{
        .kind = TypeKind.fn_type, .state = @intCast(u8, 2), .flags = @intCast(u8, 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 4), .alignment = @intCast(u32, 4),
        .name_id = name_id, .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.fn_len - @intCast(usize, 1)),
    });
}

pub fn typeRegistryGetOrCreateErrorSet(self: *TypeRegistry, tags_start: u16, tags_count: u16) u32 {
    esAppend(self, ErrorSetPayload{ .tags_start = tags_start, .tags_count = tags_count });
    return typeRegistryAppend(self, Type{
        .kind = TypeKind.error_set_type, .state = @intCast(u8, 2), .flags = @intCast(u8, 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 4), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.es_len - @intCast(usize, 1)),
    });
}

pub fn typeRegistryRegisterPrimitives(self: *TypeRegistry) void {
    registerPrimitive(self, TypeKind.none_sentinel, @intCast(u32, 0), @intCast(u32, 0));
    registerPrimitive(self, TypeKind.void_type, @intCast(u32, 0), @intCast(u32, 0));
    registerPrimitive(self, TypeKind.bool_type, @intCast(u32, 4), @intCast(u32, 4));
    registerPrimitive(self, TypeKind.noreturn_type, @intCast(u32, 0), @intCast(u32, 0));
    registerPrimitive(self, TypeKind.i8_type, @intCast(u32, 1), @intCast(u32, 1));
    registerPrimitive(self, TypeKind.i16_type, @intCast(u32, 2), @intCast(u32, 2));
    registerPrimitive(self, TypeKind.i32_type, @intCast(u32, 4), @intCast(u32, 4));
    registerPrimitive(self, TypeKind.i64_type, @intCast(u32, 8), @intCast(u32, 8));
    registerPrimitive(self, TypeKind.u8_type, @intCast(u32, 1), @intCast(u32, 1));
    registerPrimitive(self, TypeKind.u16_type, @intCast(u32, 2), @intCast(u32, 2));
    registerPrimitive(self, TypeKind.u32_type, @intCast(u32, 4), @intCast(u32, 4));
    registerPrimitive(self, TypeKind.u64_type, @intCast(u32, 8), @intCast(u32, 8));
    registerPrimitive(self, TypeKind.isize_type, @intCast(u32, 4), @intCast(u32, 4));
    registerPrimitive(self, TypeKind.usize_type, @intCast(u32, 4), @intCast(u32, 4));
    registerPrimitive(self, TypeKind.c_char_type, @intCast(u32, 1), @intCast(u32, 1));
    registerPrimitive(self, TypeKind.f32_type, @intCast(u32, 4), @intCast(u32, 4));
    registerPrimitive(self, TypeKind.f64_type, @intCast(u32, 8), @intCast(u32, 8));
    registerPrimitive(self, TypeKind.null_type, @intCast(u32, 0), @intCast(u32, 0));
    registerPrimitive(self, TypeKind.undefined_type, @intCast(u32, 0), @intCast(u32, 0));
    registerPrimitive(self, TypeKind.integer_literal_type, @intCast(u32, 0), @intCast(u32, 0));
    registerPrimitive(self, TypeKind.type_type, @intCast(u32, 0), @intCast(u32, 0));
    self.next_type_id = @intCast(u32, self.types_len);
}

pub fn typeRegistryRegisterNamedType(self: *TypeRegistry, module_id: u32, name_id: u32, kind: TypeKind) u32 {
    var tid = self.next_type_id;
    self.next_type_id += 1;
    typeRegistryAppend(self, Type{
        .kind = kind,
        .state = @intCast(u8, 0),
        .flags = @intCast(u8, 0),
        ._pad = @intCast(u8, 0),
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

pub fn isValueDependency(kind: TypeKind) bool {
    if (kind == TypeKind.struct_type) return true;
    if (kind == TypeKind.union_type) return true;
    if (kind == TypeKind.tagged_union_type) return true;
    if (kind == TypeKind.enum_type) return true;
    if (kind == TypeKind.array_type) return true;
    if (kind == TypeKind.optional_type) return true;
    if (kind == TypeKind.error_union_type) return true;
    if (kind == TypeKind.tuple_type) return true;
    if (kind == TypeKind.unresolved_name) return true;
    return false;
}
