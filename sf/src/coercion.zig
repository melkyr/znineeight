pub const CoercionKind = enum(u8) {
    none,
    wrap_optional,
    wrap_error_success,
    wrap_error_err,
    unwrap_optional,
    array_to_slice,
    array_to_many_ptr,
    slice_to_many_ptr,
    string_to_slice,
    string_to_many_ptr,
    string_to_ptr,
    ptr_to_optional_ptr,
    const_qualify,
    int_widen,
    float_widen,
    int_literal_coerce,
};

const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeId = @import("type_registry.zig").TypeId;
const type_mod = @import("type_registry.zig");
const hash_mod = @import("util/hash.zig");

pub const CoercionEntry = struct {
    node_idx: u32,
    kind: CoercionKind,
    target_type: TypeId,
};

pub const CoercionTable = struct {
    entries_items: [*]CoercionEntry,
    entries_len: usize,
    entries_cap: usize,
    entries_alloc: *Sand,
    index: hash_mod.U32ToU32Map,
};

fn coercionTableEnsureCapacity(self: *CoercionTable, new_cap: usize) void {
    if (new_cap <= self.entries_cap) return;
    var nc = new_cap;
    if (nc < self.entries_cap * 2) nc = self.entries_cap * 2;
    if (nc < 8) nc = 8;
    var raw = alloc_mod.sandAlloc(self.entries_alloc, @intCast(usize, 12) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]CoercionEntry, raw);
    for (self.entries_items[0..self.entries_len]) |item, i| { new_items[i] = item; }
    self.entries_items = new_items;
    self.entries_cap = nc;
}

pub fn coercionTableInit(alloc: *Sand) CoercionTable {
    return CoercionTable{
        .entries_items = undefined,
        .entries_len = @intCast(usize, 0),
        .entries_cap = @intCast(usize, 0),
        .entries_alloc = alloc,
        .index = hash_mod.u32ToU32MapInit(alloc),
    };
}

pub fn coercionTableAdd(self: *CoercionTable, node_idx: u32, kind: CoercionKind, target_type: TypeId) void {
    var entry = CoercionEntry{ .node_idx = node_idx, .kind = kind, .target_type = target_type };
    var existing = hash_mod.u32ToU32MapGet(&self.index, node_idx);
    if (existing) |idx| {
        self.entries_items[@intCast(usize, idx)] = entry;
        return;
    }
    coercionTableEnsureCapacity(self, self.entries_len + 1);
    var idx = @intCast(u32, self.entries_len);
    self.entries_items[@intCast(usize, idx)] = entry;
    self.entries_len += 1;
    hash_mod.u32ToU32MapPut(&self.index, node_idx, idx);
}

pub fn coercionTableGet(self: *CoercionTable, node_idx: u32) ?CoercionEntry {
    var entry_idx = hash_mod.u32ToU32MapGet(&self.index, node_idx);
    if (entry_idx) |idx| return self.entries_items[@intCast(usize, idx)];
    return null;
}

pub fn classifyCoercion(reg: *type_mod.TypeRegistry, source: TypeId, target: TypeId) CoercionKind {
    if (source == target) return CoercionKind.none;
    var src = reg.types_items[@intCast(usize, source)];
    var tgt = reg.types_items[@intCast(usize, target)];

    if (src.kind == type_mod.TypeKind.integer_literal_type and type_mod.typeRegistryIsNumeric(reg, target)) return CoercionKind.int_literal_coerce;

    if (type_mod.typeRegistryIsInteger(reg, source) and type_mod.typeRegistryIsInteger(reg, target) and source != type_mod.TYPE_INT_LIT) {
        if (type_mod.typeRegistryIsUnsigned(reg, source) == type_mod.typeRegistryIsUnsigned(reg, target) and src.size < tgt.size) return CoercionKind.int_widen;
    }
    if (source == type_mod.TYPE_F32 and target == type_mod.TYPE_F64) return CoercionKind.float_widen;

    if (src.kind == type_mod.TypeKind.null_type) {
        if (type_mod.typeRegistryIsPointer(reg, target)) return CoercionKind.none;
        if (tgt.kind == type_mod.TypeKind.optional_type) return CoercionKind.none;
        if (tgt.kind == type_mod.TypeKind.fn_type) return CoercionKind.none;
    }
    if (tgt.kind == type_mod.TypeKind.optional_type) {
        var opt = reg.opt_items[@intCast(usize, tgt.payload_idx)];
        if (type_mod.typeRegistryIsAssignable(reg, source, opt.payload)) return CoercionKind.wrap_optional;
        if (src.kind == type_mod.TypeKind.null_type) return CoercionKind.none;
    }
    if (tgt.kind == type_mod.TypeKind.error_union_type) {
        var eu = reg.eu_items[@intCast(usize, tgt.payload_idx)];
        if (type_mod.typeRegistryIsAssignable(reg, source, eu.payload)) return CoercionKind.wrap_error_success;
    }
    if (src.kind == type_mod.TypeKind.error_set_type and tgt.kind == type_mod.TypeKind.error_union_type) return CoercionKind.wrap_error_err;

    if (src.kind == type_mod.TypeKind.ptr_type and tgt.kind == type_mod.TypeKind.ptr_type) {
        var tgt_pp = reg.ptr_items[@intCast(usize, tgt.payload_idx)];
        var src_pp = reg.ptr_items[@intCast(usize, src.payload_idx)];
        if (tgt_pp.base == type_mod.TYPE_VOID) return CoercionKind.none;
        if (src_pp.base == type_mod.TYPE_VOID) return CoercionKind.none;
        if ((tgt.flags & @intCast(u8, 1)) != @intCast(u8, 0) and (src.flags & @intCast(u8, 1)) == @intCast(u8, 0)) {
            if (src_pp.base == tgt_pp.base) return CoercionKind.const_qualify;
        }
    }
    if (tgt.kind == type_mod.TypeKind.slice_type and src.kind == type_mod.TypeKind.slice_type) {
        if ((tgt.flags & @intCast(u8, 1)) != @intCast(u8, 0) and (src.flags & @intCast(u8, 1)) == @intCast(u8, 0)) {
            var s_sl = reg.slice_items[@intCast(usize, src.payload_idx)];
            var t_sl = reg.slice_items[@intCast(usize, tgt.payload_idx)];
            if (s_sl.elem == t_sl.elem) return CoercionKind.const_qualify;
        }
    }
    if (tgt.kind == type_mod.TypeKind.many_ptr_type and src.kind == type_mod.TypeKind.many_ptr_type) {
        if ((tgt.flags & @intCast(u8, 1)) != @intCast(u8, 0) and (src.flags & @intCast(u8, 1)) == @intCast(u8, 0)) {
            var s_pp = reg.ptr_items[@intCast(usize, src.payload_idx)];
            var t_pp = reg.ptr_items[@intCast(usize, tgt.payload_idx)];
            if (s_pp.base == t_pp.base) return CoercionKind.const_qualify;
        }
    }
    if (src.kind == type_mod.TypeKind.array_type and tgt.kind == type_mod.TypeKind.slice_type) {
        var arr = reg.array_items[@intCast(usize, src.payload_idx)];
        var sl = reg.slice_items[@intCast(usize, tgt.payload_idx)];
        if (arr.elem == sl.elem) return CoercionKind.array_to_slice;
        if ((tgt.flags & @intCast(u8, 1)) != @intCast(u8, 0) and arr.elem == sl.elem) return CoercionKind.array_to_slice;
    }
    if (src.kind == type_mod.TypeKind.array_type and tgt.kind == type_mod.TypeKind.many_ptr_type) {
        var arr = reg.array_items[@intCast(usize, src.payload_idx)];
        var pp = reg.ptr_items[@intCast(usize, tgt.payload_idx)];
        if (arr.elem == pp.base) return CoercionKind.array_to_many_ptr;
    }
    if (src.kind == type_mod.TypeKind.slice_type and tgt.kind == type_mod.TypeKind.many_ptr_type) {
        var sl = reg.slice_items[@intCast(usize, src.payload_idx)];
        var pp = reg.ptr_items[@intCast(usize, tgt.payload_idx)];
        if (sl.elem == pp.base) return CoercionKind.slice_to_many_ptr;
    }
    if (src.kind == type_mod.TypeKind.ptr_type and tgt.kind == type_mod.TypeKind.optional_type) {
        var opt2 = reg.opt_items[@intCast(usize, tgt.payload_idx)];
        var opt_ty = reg.types_items[@intCast(usize, opt2.payload)];
        if (opt_ty.kind == type_mod.TypeKind.ptr_type) {
            if (type_mod.typeRegistryIsAssignable(reg, source, opt2.payload)) return CoercionKind.ptr_to_optional_ptr;
        }
    }
    if ((source == type_mod.TYPE_U8 and target == type_mod.TYPE_C_CHAR) or (source == type_mod.TYPE_C_CHAR and target == type_mod.TYPE_U8)) return CoercionKind.none;

    return CoercionKind.none;
}
