pub const AstKind = enum(u8) {
    err = 0,
    var_decl = 1,
    fn_decl = 2,
    struct_decl = 3,
    enum_decl = 4,
    union_decl = 5,
    field_decl = 6,
    param_decl = 7,
    test_decl = 8,
    error_set_decl = 9,
    int_literal = 10,
    float_literal = 11,
    string_literal = 12,
    char_literal = 13,
    bool_literal = 14,
    null_literal = 15,
    undefined_literal = 16,
    unreachable_expr = 17,
    enum_literal = 18,
    error_literal = 19,
    tuple_literal = 20,
    struct_init = 21,
    array_init = 22,
    field_init = 23,
    ident_expr = 24,
    field_access = 25,
    index_access = 26,
    slice_expr = 27,
    deref = 28,
    address_of = 29,
    fn_call = 30,
    builtin_call = 31,
    paren_expr = 32,
    add = 33,
    sub = 34,
    mul = 35,
    div = 36,
    mod_op = 37,
    bit_and = 38,
    bit_or = 39,
    bit_xor = 40,
    shl = 41,
    shr = 42,
    bool_and = 43,
    bool_or = 44,
    cmp_eq = 45,
    cmp_ne = 46,
    cmp_lt = 47,
    cmp_le = 48,
    cmp_gt = 49,
    cmp_ge = 50,
    plain_assign = 51,
    add_assign = 52,
    sub_assign = 53,
    mul_assign = 54,
    div_assign = 55,
    mod_assign = 74,
    shl_assign = 57,
    shr_assign = 58,
    and_assign = 59,
    xor_assign = 60,
    or_assign = 61,
    negate = 62,
    bool_not = 63,
    bit_not = 64,
    try_expr = 65,
    catch_expr = 66,
    orelse_expr = 67,
    if_stmt = 68,
    if_expr = 69,
    if_capture = 70,
    while_stmt = 71,
    while_capture = 72,
    for_stmt = 73,
    swt_ex = 56,
    swt_prong = 75,
    block = 76,
    return_stmt = 77,
    break_stmt = 78,
    continue_stmt = 79,
    defer_stmt = 80,
    errdefer_stmt = 81,
    labeled_stmt = 82,
    expr_stmt = 83,
    ptr_type = 84,
    many_ptr_type = 85,
    array_type = 86,
    slice_type = 87,
    optional_type = 88,
    error_union_type = 89,
    fn_type = 90,
    import_expr = 91,
    module_root = 92,
    payload_capture = 93,
    range_exclusive = 94,
    range_inclusive = 95,
    c_include = 96,
    wrap_add = 97,
    wrap_sub = 98,
    wrap_mul = 99,
    wrap_negate = 100,
    wrap_add_assign = 101,
    wrap_sub_assign = 102,
    wrap_mul_assign = 103,
    sat_add = 104,
    sat_sub = 105,
    sat_mul = 106,
    sat_shl = 107,
    sat_add_assign = 108,
    sat_sub_assign = 109,
    sat_mul_assign = 110,
    sat_shl_assign = 111,
};

pub const AstNode = struct {
    kind: AstKind,    // u8  — offset 0
    flags: u8,        // u8  — offset 1 (bit0=is_const, bit1=is_pub, bit2=is_extern,
                      //        bit3=is_export, bit4=has_capture, bit5=has_index_capture,
                      //        bit6=is_inclusive, bit7=is_mutable)
    span_len: u32,    // u32 — offset 4 (byte length; span_end = span_start + span_len)
    span_start: u32,  // u32 — offset 8
    child_0: u32,     // u32 — offset 12
    child_1: u32,     // u32 — offset 16
    child_2: u32,     // u32 — offset 20
}; // total: 24 bytes (32-bit layout; payload moved to AstStore side tables)
const zzz_astnode_sz = "ZZZ_ASTNODE_24B_OFFSETS_kind0_flags1_pad2_spanlen4_spanstart8_child0_12_child1_16_child2_20";

pub const FnProto = struct {
    name_id: u32,
    params_start: u32,
    params_count: u16,
    return_type_node: u32,
};

const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const pal = @import("pal.zig");
const format_mod = @import("util/format.zig");

fn u32ArrayListAppendInner(items: *[*]u32, len: *usize, capacity: *usize, arena: *Sand, value: u32) void {
    if (len.* >= capacity.*) {
        var new_cap = capacity.*;
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (new_cap < len.* * 2) new_cap = len.* * 2;
        if (capacity.* > 0) {
            var grown = alloc_mod.sandTryReallocInPlace(arena,
                @ptrCast([*]u8, items.*),
                capacity.* * @intCast(usize, 4),
                new_cap * @intCast(usize, 4),
                @intCast(usize, 4));
            if (grown != null) {
                capacity.* = new_cap;
                items.*[len.*] = value;
                len.* += 1;
                return;
            }
        }
        var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
        var new_items_p = @ptrCast([*]u32, raw);
        for (items.*[0..len.*]) |item, i| {
            new_items_p[i] = item;
        }
        items.* = new_items_p;
        capacity.* = new_cap;
    }
    items.*[len.*] = value;
    len.* += 1;
}

fn astNodeArrayListAppendInner(items: *[*]AstNode, len: *usize, capacity: *usize, arena: *Sand, value: AstNode) void {
    if (len.* >= capacity.*) {
        var new_cap = capacity.*;
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (new_cap < len.* * 2) new_cap = len.* * 2;
        var raw = alloc_mod.sandAlloc(arena, @sizeOf(AstNode) * new_cap, @intCast(usize, 4)) catch unreachable;
        var new_items_p = @ptrCast([*]AstNode, raw);
        for (items.*[0..len.*]) |item, i| {
            new_items_p[i] = item;
        }
        items.* = new_items_p;
        capacity.* = new_cap;
    }
    items.*[len.*] = value;
    len.* += 1;
}

fn u64ArrayListAppendInner(items: *[*]u64, len: *usize, capacity: *usize, arena: *Sand, value: u64) void {
    if (len.* >= capacity.*) {
        var new_cap = capacity.*;
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (new_cap < len.* * 2) new_cap = len.* * 2;
        if (capacity.* > 0) {
            var grown = alloc_mod.sandTryReallocInPlace(arena,
                @ptrCast([*]u8, items.*),
                capacity.* * @intCast(usize, 8),
                new_cap * @intCast(usize, 8),
                @intCast(usize, 4));
            if (grown != null) {
                capacity.* = new_cap;
                items.*[len.*] = value;
                len.* += 1;
                return;
            }
        }
        var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 8) * new_cap, @intCast(usize, 4)) catch unreachable;
        var new_items_p = @ptrCast([*]u64, raw);
        for (items.*[0..len.*]) |item, i| {
            new_items_p[i] = item;
        }
        items.* = new_items_p;
        capacity.* = new_cap;
    }
    items.*[len.*] = value;
    len.* += 1;
}

fn f64ArrayListAppendInner(items: *[*]f64, len: *usize, capacity: *usize, arena: *Sand, value: f64) void {
    if (len.* >= capacity.*) {
        var new_cap = capacity.*;
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (new_cap < len.* * 2) new_cap = len.* * 2;
        if (capacity.* > 0) {
            var grown = alloc_mod.sandTryReallocInPlace(arena,
                @ptrCast([*]u8, items.*),
                capacity.* * @intCast(usize, 8),
                new_cap * @intCast(usize, 8),
                @intCast(usize, 4));
            if (grown != null) {
                capacity.* = new_cap;
                items.*[len.*] = value;
                len.* += 1;
                return;
            }
        }
        var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 8) * new_cap, @intCast(usize, 4)) catch unreachable;
        var new_items_p = @ptrCast([*]f64, raw);
        for (items.*[0..len.*]) |item, i| {
            new_items_p[i] = item;
        }
        items.* = new_items_p;
        capacity.* = new_cap;
    }
    items.*[len.*] = value;
    len.* += 1;
}

fn fnProtoArrayListAppendInner(items: *[*]FnProto, len: *usize, capacity: *usize, arena: *Sand, value: FnProto) void {
    if (len.* >= capacity.*) {
        var new_cap = capacity.*;
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (new_cap < len.* * 2) new_cap = len.* * 2;
        if (capacity.* > 0) {
            var grown = alloc_mod.sandTryReallocInPlace(arena,
                @ptrCast([*]u8, items.*),
                capacity.* * @sizeOf(FnProto),
                new_cap * @sizeOf(FnProto),
                @intCast(usize, 4));
            if (grown != null) {
                capacity.* = new_cap;
                items.*[len.*] = value;
                len.* += 1;
                return;
            }
        }
        var raw = alloc_mod.sandAlloc(arena, @intCast(usize, @sizeOf(FnProto)) * new_cap, @intCast(usize, 4)) catch unreachable;
        var new_items_p = @ptrCast([*]FnProto, raw);
        for (items.*[0..len.*]) |item, i| {
            new_items_p[i] = item;
        }
        items.* = new_items_p;
        capacity.* = new_cap;
    }
    items.*[len.*] = value;
    len.* += 1;
}

pub const AstStore = struct {
    nodes: struct {
        items: [*]AstNode,
        len: usize,
        capacity: usize,
    },
    extra_children: struct {
        items: [*]u32,
        len: usize,
        capacity: usize,
    },
    identifiers: struct {
        items: [*]u32,
        len: usize,
        capacity: usize,
    },
    int_values: struct {
        items: [*]u64,
        len: usize,
        capacity: usize,
    },
    float_values: struct {
        items: [*]f64,
        len: usize,
        capacity: usize,
    },
    string_values: struct {
        items: [*]u32,
        len: usize,
        capacity: usize,
    },
    fn_protos: struct {
        items: [*]FnProto,
        len: usize,
        capacity: usize,
    },
    payload: struct {
        items: [*]u32,
        len: usize,
        capacity: usize,
    },
    extra_ranges: struct {
        items: [*]u64,
        len: usize,
        capacity: usize,
    },
    allocator: *Sand,
};

// Payload side-table semantics (AstNode.payload removed; u32 value stored in
// `store.payload`, parallel to `nodes`):
//   int_literal, char_literal → int_values index
//   float_literal            → float_values index
//   string_literal           → string_values index (interned string ID)
//   ident_expr               → identifiers index (interned string ID)
//   fn_decl                  → fn_protos index
//   var_decl, field_decl, param_decl, field_access, enum_literal, error_literal → name ID
//   labeled_stmt, break_stmt, continue_stmt → label name ID (0=unlabeled)
//   builtin_call             → builtin name ID (child_0); payload = extra-children index
//   if_capture, while_capture, for_stmt → capture name ID
//   import_expr              → path string ID
//   fn_call, block, struct_decl, enum_decl, union_decl, swt_ex, tuple_literal,
//     struct_init, array_init, module_root, swt_prong, error_set_decl, builtin_call
//     → extra-children range index into `store.extra_ranges` (0 = no children)
// The extra-children range pool stores the packed (start << 32 | count) with start
// as u32 (69,026+ ranges on self-compile exceed u16) and slot 0 reserved as a
// 0 sentinel so a payload-side value of 0 means "no range".

pub fn astStoreInit(arena: *Sand) AstStore {
    var null_node = AstNode{
        .kind = AstKind.err, .flags = @intCast(u8, 0),
        .span_start = @intCast(u32, 0), .span_len = @intCast(u32, 0),
        .child_0 = @intCast(u32, 0), .child_1 = @intCast(u32, 0),
        .child_2 = @intCast(u32, 0),
    };
    var store = AstStore{
        .nodes = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .extra_children = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .identifiers = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .int_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .float_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .fn_protos = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .string_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .payload = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .extra_ranges = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .allocator = arena,
    };
    astNodeArrayListAppendInner(&store.nodes.items, &store.nodes.len, &store.nodes.capacity, arena, null_node);
    u32ArrayListAppendInner(&store.payload.items, &store.payload.len, &store.payload.capacity, arena, @intCast(u32, 0));
    u64ArrayListAppendInner(&store.extra_ranges.items, &store.extra_ranges.len, &store.extra_ranges.capacity, arena, @intCast(u64, 0));
    return store;
}

pub fn astStoreEnsureNodesCapacity(store: *AstStore, new_capacity: usize) void {
    if (new_capacity <= store.nodes.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    if (store.nodes.capacity > @intCast(usize, 0)) {
        var grown = alloc_mod.sandReallocInPlace(store.allocator,
            @ptrCast([*]u8, store.nodes.items),
            store.nodes.capacity * @sizeOf(AstNode),
            new_cap * @sizeOf(AstNode),
            @intCast(usize, 4));
        if (grown != null) {
            store.nodes.capacity = new_cap;
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(store.allocator, @sizeOf(AstNode) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]AstNode, raw);
    for (store.nodes.items[0..store.nodes.len]) |item, i| {
        new_items[i] = item;
    }
    store.nodes.items = new_items;
    store.nodes.capacity = new_cap;
}

pub fn astStoreEnsureExtraChildrenCapacity(store: *AstStore, new_capacity: usize) void {
    if (new_capacity <= store.extra_children.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    if (store.extra_children.capacity > @intCast(usize, 0)) {
        var grown = alloc_mod.sandReallocInPlace(store.allocator,
            @ptrCast([*]u8, store.extra_children.items),
            store.extra_children.capacity * @intCast(usize, 4),
            new_cap * @intCast(usize, 4),
            @intCast(usize, 4));
        if (grown != null) {
            store.extra_children.capacity = new_cap;
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(store.allocator, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    for (store.extra_children.items[0..store.extra_children.len]) |item, i| {
        new_items[i] = item;
    }
    store.extra_children.items = new_items;
    store.extra_children.capacity = new_cap;
}


pub fn astStoreAddNode(store: *AstStore, kind: AstKind, flags: u8, span_start: u32, span_end: u32, c0: u32, c1: u32, c2: u32, payload: u32) u32 {
    var span_len: u32 = @intCast(u32, span_end - span_start);
    var node = AstNode{
        .kind = kind, .flags = flags,
        .span_start = span_start, .span_len = span_len,
        .child_0 = c0, .child_1 = c1, .child_2 = c2,
    };
    astNodeArrayListAppendInner(&store.nodes.items, &store.nodes.len, &store.nodes.capacity, store.allocator, node);
    u32ArrayListAppendInner(&store.payload.items, &store.payload.len, &store.payload.capacity, store.allocator, payload);
    return @intCast(u32, store.nodes.len - 1);
}

pub fn astStoreAddExtraChildren(store: *AstStore, children: []const u32) u32 {
    var start = @intCast(u32, store.extra_children.len);
    var i: usize = 0;
    while (i < children.len) {
        u32ArrayListAppendInner(&store.extra_children.items, &store.extra_children.len, &store.extra_children.capacity, store.allocator, children[i]);
        i += 1;
    }
    var range_idx = @intCast(u32, store.extra_ranges.len);
    u64ArrayListAppendInner(&store.extra_ranges.items, &store.extra_ranges.len, &store.extra_ranges.capacity, store.allocator, (@intCast(u64, start) << @intCast(u64, 32)) | @intCast(u64, children.len));
    return range_idx;
}

pub fn astStoreGetExtraChildren(store: *AstStore, payload: u64) []const u32 {
    var start: usize = @intCast(usize, payload >> 32);
    var count: usize = @intCast(usize, payload & @intCast(u64, 0xFFFFFFFF));
    return store.extra_children.items[start .. start + count];
}

pub fn astStoreNodePayload(store: *AstStore, node_idx: u32) u32 {
    return store.payload.items[@intCast(usize, node_idx)];
}

pub fn astStoreNodePayloadPacked(store: *AstStore, node_idx: u32, kind: AstKind) u64 {
    var v = store.payload.items[@intCast(usize, node_idx)];
    if (v == @intCast(u32, 0)) return @intCast(u64, 0);
    if (nodeHasExtraChildren(kind) or kind == AstKind.builtin_call) {
        return store.extra_ranges.items[@intCast(usize, v)];
    }
    return @intCast(u64, v);
}

pub fn astStoreNodeExtraChildren(store: *AstStore, node_idx: u32) []const u32 {
    var range_idx = store.payload.items[@intCast(usize, node_idx)];
    if (range_idx == @intCast(u32, 0)) {
        return store.extra_children.items[0..0];
    }
    var packed_range = store.extra_ranges.items[@intCast(usize, range_idx)];
    var start: usize = @intCast(usize, packed_range >> 32);
    var count: usize = @intCast(usize, packed_range & @intCast(u64, 0xFFFFFFFF));
    return store.extra_children.items[start .. start + count];
}

pub fn astStoreAddIntLiteral(store: *AstStore, value: u64, span_start: u32, span_end: u32) u32 {
    var val_idx = @intCast(u32, store.int_values.len);
    u64ArrayListAppendInner(&store.int_values.items, &store.int_values.len, &store.int_values.capacity, store.allocator, value);
    return astStoreAddNode(store, AstKind.int_literal, @intCast(u8, 0), span_start, span_end, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), val_idx);
}

pub fn astStoreAddCharLiteral(store: *AstStore, value: u64, span_start: u32, span_end: u32) u32 {
    var val_idx = @intCast(u32, store.int_values.len);
    u64ArrayListAppendInner(&store.int_values.items, &store.int_values.len, &store.int_values.capacity, store.allocator, value);
    return astStoreAddNode(store, AstKind.char_literal, @intCast(u8, 0), span_start, span_end, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), val_idx);
}

pub fn astStoreAddFloatLiteral(store: *AstStore, value: f64, span_start: u32, span_end: u32) u32 {
    var as0_buf: [64]u8 = undefined;
    var as0 = format_mod.formatF64(value, as0_buf[0..], 64);
    var as0s: []const u8 = "AS:"; pal.stderr_write(as0s);
    pal.stderr_write(as0);
    var as0n: []const u8 = "\n"; pal.stderr_write(as0n);
    var val_idx = @intCast(u32, store.float_values.len);
    f64ArrayListAppendInner(&store.float_values.items, &store.float_values.len, &store.float_values.capacity, store.allocator, value);
    return astStoreAddNode(store, AstKind.float_literal, @intCast(u8, 0), span_start, span_end, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), val_idx);
}

pub fn astStoreAddStringLiteral(store: *AstStore, string_id: u32, span_start: u32, span_end: u32) u32 {
    var sv_idx = @intCast(u32, store.string_values.len);
    u32ArrayListAppendInner(&store.string_values.items, &store.string_values.len, &store.string_values.capacity, store.allocator, string_id);
    return astStoreAddNode(store, AstKind.string_literal, @intCast(u8, 0), span_start, span_end, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), sv_idx);
}

pub fn astStoreAddIdentifier(store: *AstStore, kind: AstKind, string_id: u32, span_start: u32, span_end: u32) u32 {
    var id_idx = @intCast(u32, store.identifiers.len);
    u32ArrayListAppendInner(&store.identifiers.items, &store.identifiers.len, &store.identifiers.capacity, store.allocator, string_id);
    return astStoreAddNode(store, kind, @intCast(u8, 0), span_start, span_end, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), id_idx);
}

pub fn astStoreAddFnProto(store: *AstStore, proto: FnProto) u32 {
    var idx = @intCast(u32, store.fn_protos.len);
    fnProtoArrayListAppendInner(&store.fn_protos.items, &store.fn_protos.len, &store.fn_protos.capacity, store.allocator, proto);
    return idx;
}

pub fn nodeHasExtraChildren(kind: AstKind) bool {
    switch (kind) {
        AstKind.fn_call => { return true; },
        AstKind.block => { return true; },
        AstKind.struct_decl => { return true; },
        AstKind.enum_decl => { return true; },
        AstKind.union_decl => { return true; },
        AstKind.swt_ex => { return true; },
        AstKind.tuple_literal => { return true; },
        AstKind.struct_init => { return true; },
        AstKind.array_init => { return true; },
        AstKind.module_root => { return true; },
        AstKind.swt_prong => { return true; },
        AstKind.error_set_decl => { return true; },
        else => { return false; },
    }
}

pub fn visitPreOrder(store: *AstStore, root: u32, callback: fn(*AstStore, u32) void) void {
    var stack: [512]u32 = undefined;
    var sp: usize = 0;
    stack[sp] = root;
    sp += 1;
    while (sp > 0) {
        sp -= 1;
        var node_idx = stack[sp];
        if (node_idx == 0) continue;
        var node = store.nodes.items[node_idx];
        callback(store, node_idx);
        if (nodeHasExtraChildren(node.kind) and astStoreNodePayload(store, node_idx) != 0) {
            var ec = astStoreNodeExtraChildren(store, node_idx);
            var ei: usize = 0;
            while (ei < ec.len) {
                stack[sp] = ec[ec.len - 1 - ei];
                sp += 1;
                ei += 1;
            }
        }
        if (node.child_2 != 0) { stack[sp] = node.child_2; sp += 1; }
        if (node.child_1 != 0) { stack[sp] = node.child_1; sp += 1; }
        if (node.child_0 != 0) { stack[sp] = node.child_0; sp += 1; }
    }
}

pub fn astStoreComputeMemory(store: *AstStore) u64 {
    var total: u64 = 0;
    total += @intCast(u64, store.nodes.len) * @sizeOf(AstNode);
    total += @intCast(u64, store.extra_children.len) * @sizeOf(u32);
    total += @intCast(u64, store.identifiers.len) * @sizeOf(u32);
    total += @intCast(u64, store.int_values.len) * @sizeOf(u64);
    total += @intCast(u64, store.float_values.len) * @sizeOf(f64);
    total += @intCast(u64, store.string_values.len) * @sizeOf(u32);
    total += @intCast(u64, store.fn_protos.len) * @sizeOf(FnProto);
    total += @intCast(u64, store.payload.len) * @sizeOf(u32);
    total += @intCast(u64, store.extra_ranges.len) * @sizeOf(u64);
    return total;
}
