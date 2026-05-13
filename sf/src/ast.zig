pub const AstKind = enum(u8) {
    err,
    var_decl,
    fn_decl,
    struct_decl,
    enum_decl,
    union_decl,
    field_decl,
    param_decl,
    test_decl,
    error_set_decl,
    int_literal,
    float_literal,
    string_literal,
    char_literal,
    bool_literal,
    null_literal,
    undefined_literal,
    unreachable_expr,
    enum_literal,
    error_literal,
    tuple_literal,
    struct_init,
    array_init,
    field_init,
    ident_expr,
    field_access,
    index_access,
    slice_expr,
    deref,
    address_of,
    fn_call,
    builtin_call,
    paren_expr,
    add,
    sub,
    mul,
    div,
    mod_op,
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,
    bool_and,
    bool_or,
    cmp_eq,
    cmp_ne,
    cmp_lt,
    cmp_le,
    cmp_gt,
    cmp_ge,
    assign,
    add_assign,
    sub_assign,
    mul_assign,
    div_assign,
    mod_assign,
    shl_assign,
    shr_assign,
    and_assign,
    xor_assign,
    or_assign,
    negate,
    bool_not,
    bit_not,
    try_expr,
    catch_expr,
    orelse_expr,
    if_stmt,
    if_expr,
    if_capture,
    while_stmt,
    while_capture,
    for_stmt,
    switch_expr,
    switch_prong,
    block,
    return_stmt,
    break_stmt,
    continue_stmt,
    defer_stmt,
    errdefer_stmt,
    labeled_stmt,
    expr_stmt,
    ptr_type,
    many_ptr_type,
    array_type,
    slice_type,
    optional_type,
    error_union_type,
    fn_type,
    import_expr,
    module_root,
    payload_capture,
    range_exclusive,
    range_inclusive,
};

pub const AstNode = struct {
    kind: AstKind,    // u8  — offset 0
    flags: u8,        // u8  — offset 1 (bit0=is_const, bit1=is_pub, bit2=is_extern,
                      //        bit3=is_export, bit4=has_capture, bit5=has_index_capture,
                      //        bit6=is_inclusive, bit7=is_mutable)
    span_len: u16,    // u16 — offset 2 (byte length; span_end = span_start + span_len)
    span_start: u32,  // u32 — offset 4
    child_0: u32,     // u32 — offset 8
    child_1: u32,     // u32 — offset 12
    child_2: u32,     // u32 — offset 16
    payload: u32,     // u32 — offset 20
}; // total: 24 bytes (32-bit layout)

pub const FnProto = struct {
    name_id: u32,
    params_start: u16,
    params_count: u16,
    return_type_node: u32,
};

const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

fn u32ArrayListAppendInner(items: *[*]u32, len: *usize, capacity: *usize, arena: *Sand, value: u32) void {
    if (len.* >= capacity.*) {
        var new_cap = capacity.*;
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (new_cap < len.* * 2) new_cap = len.* * 2;
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
        var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 24) * new_cap, @intCast(usize, 4)) catch unreachable;
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
        var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 12) * new_cap, @intCast(usize, 4)) catch unreachable;
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
    allocator: *Sand,
};

// Payload field semantics per AstKind:
//   int_literal       → int_values index
//   float_literal     → float_values index
//   string_literal     → string_values index (interned string ID)
//   ident_expr         → identifiers index (interned string ID)
//   fn_decl           → fn_protos index
//   fn_call, block, struct_decl, enum_decl, union_decl, switch_expr,
//     tuple_literal, struct_init → extra_children packed (start << 16 | count)
//   builtin_call      → interned string ID of builtin name
//   var_decl, field_decl, param_decl, field_access, enum_literal, error_literal → name ID
//   labeled_stmt, break_stmt, continue_stmt → label name ID (0=unlabeled)
//   struct_init → extra_children (field_init nodes), child_0=base expr (0=anonymous)
//   if_capture, while_capture, for_stmt → capture name ID
//   import_expr       → path string ID
//   array_init        → child_0=type_node, payload=extra_children (value exprs)

pub fn astStoreInit(arena: *Sand) AstStore {
    var null_node = AstNode{
        .kind = AstKind.err, .flags = @intCast(u8, 0),
        .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 0),
        .child_0 = @intCast(u32, 0), .child_1 = @intCast(u32, 0),
        .child_2 = @intCast(u32, 0),
        .payload = @intCast(u32, 0),
    };
    var store = AstStore{
        .nodes = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .extra_children = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .identifiers = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .int_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .float_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .fn_protos = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .string_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .allocator = arena,
    };
    astNodeArrayListAppendInner(&store.nodes.items, &store.nodes.len, &store.nodes.capacity, arena, null_node);
    return store;
}

pub fn astStoreAddNode(store: *AstStore, kind: AstKind, flags: u8, span_start: u32, span_end: u32, c0: u32, c1: u32, c2: u32, payload: u32) u32 {
    var span_len = @intCast(u16, span_end - span_start);
    var node = AstNode{
        .kind = kind, .flags = flags,
        .span_start = span_start, .span_len = span_len,
        .child_0 = c0, .child_1 = c1, .child_2 = c2,
        .payload = payload,
    };
    astNodeArrayListAppendInner(&store.nodes.items, &store.nodes.len, &store.nodes.capacity, store.allocator, node);
    return @intCast(u32, store.nodes.len - 1);
}

pub fn astStoreAddExtraChildren(store: *AstStore, children: []const u32) u32 {
    var start = @intCast(u32, store.extra_children.len);
    var i: usize = 0;
    while (i < children.len) {
        u32ArrayListAppendInner(&store.extra_children.items, &store.extra_children.len, &store.extra_children.capacity, store.allocator, children[i]);
        i += 1;
    }
    return (start << @intCast(u32, 16)) | @intCast(u32, children.len);
}

pub fn astStoreGetExtraChildren(store: *AstStore, payload: u32) []const u32 {
    var start = @intCast(usize, payload >> 16);
    var count = @intCast(usize, payload & @intCast(u32, 0xFFFF));
    return store.extra_children.items[start .. start + count];
}

pub fn astStoreAddIntLiteral(store: *AstStore, value: u64, span_start: u32, span_end: u32) u32 {
    var val_idx = @intCast(u32, store.int_values.len);
    u64ArrayListAppendInner(&store.int_values.items, &store.int_values.len, &store.int_values.capacity, store.allocator, value);
    return astStoreAddNode(store, AstKind.int_literal, @intCast(u8, 0), span_start, span_end, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), val_idx);
}

pub fn astStoreAddFloatLiteral(store: *AstStore, value: f64, span_start: u32, span_end: u32) u32 {
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
        AstKind.switch_expr => { return true; },
        AstKind.tuple_literal => { return true; },
        AstKind.struct_init => { return true; },
        AstKind.array_init => { return true; },
        AstKind.module_root => { return true; },
        AstKind.switch_prong => { return true; },
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
        var node = store.nodes.items[node_idx];
        callback(store, node_idx);
        if (nodeHasExtraChildren(node.kind) and node.payload != 0) {
            var ec = astStoreGetExtraChildren(store, node.payload);
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
