const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const StringInterner = @import("string_interner.zig").StringInterner;
const interner_mod = @import("string_interner.zig");
const hash_mod = @import("util/hash.zig");

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

pub const PtrPayload = struct { base: TypeId };
pub const ArrayPayload = struct { elem: TypeId, length: u32 };
pub const SlicePayload = struct { elem: TypeId };
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

    ptr_cache: hash_mod.U64ToU32Map,
    many_ptr_cache: hash_mod.U64ToU32Map,
    slice_cache: hash_mod.U64ToU32Map,
    optional_cache: hash_mod.U32ToU32Map,
    array_cache: hash_mod.U64ToU32Map,

    name_cache: hash_mod.U64ToU32Map,
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
pub fn stAppend(self: *TypeRegistry, v: StructPayload) void {
    payloadEnsure(@ptrCast(*[*]u8, &self.st_items), &self.st_len, &self.st_cap, self.types_alloc, @sizeOf(StructPayload), self.st_len + 1);
    self.st_items[self.st_len] = v; self.st_len += 1;
}
pub fn enAppend(self: *TypeRegistry, v: EnumPayload) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.en_items), &self.en_len, &self.en_cap, self.types_alloc, @sizeOf(EnumPayload), self.en_len + 1);
     self.en_items[self.en_len] = v; self.en_len += 1;
 }
 pub fn unAppend(self: *TypeRegistry, v: UnionPayload) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.un_items), &self.un_len, &self.un_cap, self.types_alloc, @sizeOf(UnionPayload), self.un_len + 1);
     self.un_items[self.un_len] = v; self.un_len += 1;
 }
 pub fn tuAppend(self: *TypeRegistry, v: TaggedUnionPayload) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.tu_items), &self.tu_len, &self.tu_cap, self.types_alloc, @sizeOf(TaggedUnionPayload), self.tu_len + 1);
     self.tu_items[self.tu_len] = v; self.tu_len += 1;
 }
 pub fn tupAppend(self: *TypeRegistry, v: TuplePayload) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.tup_items), &self.tup_len, &self.tup_cap, self.types_alloc, @sizeOf(TuplePayload), self.tup_len + 1);
     self.tup_items[self.tup_len] = v; self.tup_len += 1;
 }
 fn unrAppend(self: *TypeRegistry, v: UnresolvedPayload) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.unr_items), &self.unr_len, &self.unr_cap, self.types_alloc, @sizeOf(UnresolvedPayload), self.unr_len + 1);
     self.unr_items[self.unr_len] = v; self.unr_len += 1;
 }
 pub fn feAppend(self: *TypeRegistry, v: FieldEntry) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.fe_items), &self.fe_len, &self.fe_cap, self.types_alloc, @sizeOf(FieldEntry), self.fe_len + 1);
     self.fe_items[self.fe_len] = v; self.fe_len += 1;
 }
 pub fn emAppend(self: *TypeRegistry, v: EnumMember) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.em_items), &self.em_len, &self.em_cap, self.types_alloc, @sizeOf(EnumMember), self.em_len + 1);
     self.em_items[self.em_len] = v; self.em_len += 1;
 }
 pub fn xtAppend(self: *TypeRegistry, v: TypeId) void {
     payloadEnsure(@ptrCast(*[*]u8, &self.xt_items), &self.xt_len, &self.xt_cap, self.types_alloc, @intCast(usize, 4), self.xt_len + 1);
     self.xt_items[self.xt_len] = v; self.xt_len += 1;
 }
 pub fn xnAppend(self: *TypeRegistry, v: u32) void {
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

pub fn alignUp(v: u32, a: u32) u32 {
    return (v + a - @intCast(u32, 1)) & ~(a - @intCast(u32, 1));
}

fn initArray(items: *[*]u8, len: *usize, cap: *usize) void {
    items.* = undefined;
    len.* = @intCast(usize, 0);
    cap.* = @intCast(usize, 0);
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
        .ptr_cache = hash_mod.u64ToU32MapInit(alloc),
        .many_ptr_cache = hash_mod.u64ToU32MapInit(alloc),
        .slice_cache = hash_mod.u64ToU32MapInit(alloc),
        .optional_cache = hash_mod.u32ToU32MapInit(alloc),
        .array_cache = hash_mod.u64ToU32MapInit(alloc),
        .name_cache = hash_mod.u64ToU32MapInit(alloc),
    };
    return reg;
}

pub fn nameCacheGet(self: *TypeRegistry, key: u64) ?u32 {
    return hash_mod.u64ToU32MapGet(&self.name_cache, key);
}

fn nameCachePut(self: *TypeRegistry, key: u64, value: u32) void {
    hash_mod.u64ToU32MapPut(&self.name_cache, key, value);
}

pub fn typeRegistryGetOrCreatePtr(self: *TypeRegistry, base: TypeId, is_const: bool) u32 {
    var ic: u64 = if (is_const) @intCast(u64, 1) else @intCast(u64, 0);
    var key: u64 = (@intCast(u64, base) << @intCast(u64, 1)) | ic;
    if (hash_mod.u64ToU32MapGet(&self.ptr_cache, key)) |existing| return existing;
    ptrAppend(self, PtrPayload{ .base = base });
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.ptr_type, .state = @intCast(u8, 2),
        .flags = @intCast(u8, if (is_const) 1 else 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 4), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.ptr_len - @intCast(usize, 1)),
    });
    hash_mod.u64ToU32MapPut(&self.ptr_cache, key, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateManyPtr(self: *TypeRegistry, base: TypeId, is_const: bool) u32 {
    var ic: u64 = if (is_const) @intCast(u64, 1) else @intCast(u64, 0);
    var key: u64 = (@intCast(u64, base) << @intCast(u64, 1)) | ic;
    if (hash_mod.u64ToU32MapGet(&self.many_ptr_cache, key)) |existing| return existing;
    ptrAppend(self, PtrPayload{ .base = base });
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.many_ptr_type, .state = @intCast(u8, 2),
        .flags = @intCast(u8, if (is_const) 1 else 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 4), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.ptr_len - @intCast(usize, 1)),
    });
    hash_mod.u64ToU32MapPut(&self.many_ptr_cache, key, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateSlice(self: *TypeRegistry, elem: TypeId, is_const: bool) u32 {
    var ic: u64 = if (is_const) @intCast(u64, 1) else @intCast(u64, 0);
    var key: u64 = (@intCast(u64, elem) << @intCast(u64, 1)) | ic;
    if (hash_mod.u64ToU32MapGet(&self.slice_cache, key)) |existing| return existing;
    sliceAppend(self, SlicePayload{ .elem = elem });
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.slice_type, .state = @intCast(u8, 2),
        .flags = @intCast(u8, if (is_const) 1 else 0), ._pad = @intCast(u8, 0),
        .size = @intCast(u32, 8), .alignment = @intCast(u32, 4),
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.slice_len - @intCast(usize, 1)),
    });
    hash_mod.u64ToU32MapPut(&self.slice_cache, key, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateOptional(self: *TypeRegistry, payload: TypeId) u32 {
    if (hash_mod.u32ToU32MapGet(&self.optional_cache, payload)) |existing| return existing;
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
    if (opt_state == @intCast(u8, 2)) hash_mod.u32ToU32MapPut(&self.optional_cache, payload, tid);
    return tid;
}

pub fn typeRegistryGetOrCreateErrorUnion(self: *TypeRegistry, payload: TypeId, error_set: TypeId) u32 {
    var pay_type = self.types_items[payload];
    var eu_size: u32 = 0;
    var eu_align: u32 = 0;
    var eu_state: u8 = 0;
    if (pay_type.state == @intCast(u8, 2)) {
        var union_size = if (pay_type.size > @intCast(u32, 4)) pay_type.size else @intCast(u32, 4);
        var union_align = if (pay_type.alignment > @intCast(u32, 4)) pay_type.alignment else @intCast(u32, 4);
        var total = alignUp(union_size, union_align);
        total = alignUp(total, @intCast(u32, 4)) + @intCast(u32, 4);
        eu_size = alignUp(total, union_align);
        eu_align = union_align;
        eu_state = @intCast(u8, 2);
    }
    euAppend(self, EUPayload{ .payload = payload, .error_set = error_set });
    return typeRegistryAppend(self, Type{
        .kind = TypeKind.error_union_type, .state = eu_state, .flags = @intCast(u8, 0), ._pad = @intCast(u8, 0),
        .size = eu_size, .alignment = eu_align,
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.eu_len - @intCast(usize, 1)),
    });
}

pub fn typeRegistryGetOrCreateArray(self: *TypeRegistry, elem: TypeId, length: u32) u32 {
    var key = (@intCast(u64, elem) << @intCast(u64, 32)) | @intCast(u64, length);
    if (hash_mod.u64ToU32MapGet(&self.array_cache, key)) |existing| return existing;
    arrayAppend(self, ArrayPayload{ .elem = elem, .length = length });
    var elem_ty = self.types_items[elem];
    var arr_size: u32 = 0;
    var arr_align: u32 = 0;
    var arr_state: u8 = 0;
    if (elem_ty.state == @intCast(u8, 2)) {
        arr_size = elem_ty.size * length;
        arr_align = elem_ty.alignment;
        arr_state = @intCast(u8, 2);
    }
    var tid = typeRegistryAppend(self, Type{
        .kind = TypeKind.array_type, .state = arr_state, .flags = @intCast(u8, 0), ._pad = @intCast(u8, 0),
        .size = arr_size, .alignment = arr_align,
        .name_id = @intCast(u32, 0), .c_name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .payload_idx = @intCast(u32, self.array_len - @intCast(usize, 1)),
    });
    if (elem_ty.state == @intCast(u8, 2)) hash_mod.u64ToU32MapPut(&self.array_cache, key, tid);
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
    var pn: []const u8 = "void"; registerPrimitiveName(self, @intCast(u32, 1), pn);
    pn = "bool"; registerPrimitiveName(self, @intCast(u32, 2), pn);
    pn = "i8"; registerPrimitiveName(self, @intCast(u32, 4), pn);
    pn = "i16"; registerPrimitiveName(self, @intCast(u32, 5), pn);
    pn = "i32"; registerPrimitiveName(self, @intCast(u32, 6), pn);
    pn = "i64"; registerPrimitiveName(self, @intCast(u32, 7), pn);
    pn = "u8"; registerPrimitiveName(self, @intCast(u32, 8), pn);
    pn = "u16"; registerPrimitiveName(self, @intCast(u32, 9), pn);
    pn = "u32"; registerPrimitiveName(self, @intCast(u32, 10), pn);
    pn = "u64"; registerPrimitiveName(self, @intCast(u32, 11), pn);
    pn = "isize"; registerPrimitiveName(self, @intCast(u32, 12), pn);
    pn = "usize"; registerPrimitiveName(self, @intCast(u32, 13), pn);
    pn = "c_char"; registerPrimitiveName(self, @intCast(u32, 14), pn);
    pn = "f32"; registerPrimitiveName(self, @intCast(u32, 15), pn);
    pn = "f64"; registerPrimitiveName(self, @intCast(u32, 16), pn);
    pn = "null"; registerPrimitiveName(self, @intCast(u32, 17), pn);
    pn = "undefined"; registerPrimitiveName(self, @intCast(u32, 18), pn);
    pn = "type"; registerPrimitiveName(self, @intCast(u32, 20), pn);
    self.next_type_id = @intCast(u32, self.types_len);
}

fn registerPrimitiveName(self: *TypeRegistry, tid: u32, name: []const u8) void {
    var nid = interner_mod.stringInternerIntern(self.interner, name);
    var ty = self.types_items[@intCast(usize, tid)];
    ty.name_id = nid;
    self.types_items[@intCast(usize, tid)] = ty;
    nameCachePut(self, @intCast(u64, nid), tid);
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

pub fn typeRegistryGetTypeState(self: *TypeRegistry, tid: u32) u8 {
    return self.types_items[tid].state;
}

pub fn typeRegistryIsNumeric(self: *TypeRegistry, tid: u32) bool {
    var kind = self.types_items[tid].kind;
    if (kind == TypeKind.i8_type) return true;
    if (kind == TypeKind.i16_type) return true;
    if (kind == TypeKind.i32_type) return true;
    if (kind == TypeKind.i64_type) return true;
    if (kind == TypeKind.u8_type) return true;
    if (kind == TypeKind.u16_type) return true;
    if (kind == TypeKind.u32_type) return true;
    if (kind == TypeKind.u64_type) return true;
    if (kind == TypeKind.isize_type) return true;
    if (kind == TypeKind.usize_type) return true;
    if (kind == TypeKind.f32_type) return true;
    if (kind == TypeKind.f64_type) return true;
    if (kind == TypeKind.integer_literal_type) return true;
    return false;
}

pub fn typeRegistryIsInteger(self: *TypeRegistry, tid: u32) bool {
    var kind = self.types_items[tid].kind;
    if (kind == TypeKind.i8_type) return true;
    if (kind == TypeKind.i16_type) return true;
    if (kind == TypeKind.i32_type) return true;
    if (kind == TypeKind.i64_type) return true;
    if (kind == TypeKind.u8_type) return true;
    if (kind == TypeKind.u16_type) return true;
    if (kind == TypeKind.u32_type) return true;
    if (kind == TypeKind.u64_type) return true;
    if (kind == TypeKind.isize_type) return true;
    if (kind == TypeKind.usize_type) return true;
    if (kind == TypeKind.integer_literal_type) return true;
    return false;
}

pub fn typeRegistryIsUnsigned(self: *TypeRegistry, tid: u32) bool {
    var kind = self.types_items[tid].kind;
    if (kind == TypeKind.u8_type) return true;
    if (kind == TypeKind.u16_type) return true;
    if (kind == TypeKind.u32_type) return true;
    if (kind == TypeKind.u64_type) return true;
    if (kind == TypeKind.usize_type) return true;
    return false;
}

pub fn typeRegistryIsPointer(self: *TypeRegistry, tid: u32) bool {
    var kind = self.types_items[tid].kind;
    return kind == TypeKind.ptr_type or kind == TypeKind.many_ptr_type;
}

pub fn typeRegistryIsSlice(self: *TypeRegistry, tid: u32) bool {
    return self.types_items[tid].kind == TypeKind.slice_type;
}

pub fn typeRegistryGetPointeeType(self: *TypeRegistry, tid: u32) ?u32 {
    var ty = self.types_items[tid];
    if (ty.kind != TypeKind.ptr_type and ty.kind != TypeKind.many_ptr_type) return null;
    return self.ptr_items[ty.payload_idx].base;
}

pub fn typeRegistryGetSliceElem(self: *TypeRegistry, tid: u32) ?u32 {
    var ty = self.types_items[tid];
    if (ty.kind != TypeKind.slice_type) return null;
    return self.slice_items[ty.payload_idx].elem;
}

pub fn typeRegistryGetStructFields(self: *TypeRegistry, tid: u32, out: *[]FieldEntry) void {
    var ty = self.types_items[tid];
    var sp = self.st_items[ty.payload_idx];
    var fstart: usize = @intCast(usize, sp.fields_start);
    var fcount: usize = @intCast(usize, sp.fields_count);
    out.* = self.fe_items[fstart .. fstart + fcount];
}
