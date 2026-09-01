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
const panic_mod = @import("panic.zig");
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

// ---- Block-based disk-backed node storage (S-AST) ----
// Nodes (AstNode, 24 B) and the parallel payload side table are stored in
// fixed 4096-entry blocks. The head (append) block is pinned resident; when it
// fills it is spilled to a temp file and a fresh block is started. Readers
// access nodes through astStoreNodeAt, which faults a block into one of the
// AST_WINDOW_SLOTS resident slots (ring-evicted) if it is not already resident.
// No dirty flag / write-back: the AST is write-once, so eviction is free.
pub const AST_BLOCK_SHIFT: u32 = 12;
pub const AST_BLOCK_NODES: u32 = 4096;
pub const AST_BLOCK_NODE_BYTES: u32 = 98304;    // 4096 * 24 (AstNode)
pub const AST_BLOCK_PAYLOAD_BYTES: u32 = 16384; // 4096 * 4 (u32 payload)
pub const AST_BLOCK_REC_SIZE: u32 = 114688;     // node array + payload array
pub const AST_SPILL_MAX_BLOCKS: u32 = 18724;    // i32 max / AST_BLOCK_REC_SIZE; seek offset must fit i32
pub const AST_BLOCK_MASK: u32 = 4095;
pub const AST_WINDOW_SLOTS: u32 = 8;
pub const AST_HEAD_SLOT: u32 = 0;

pub const NodeBlockInfo = struct {
    disk_off: u32, // byte offset of this block's record in the spill file
    resident: u8,  // 1 = block currently in a resident slot
    slot: u32,     // resident slot index (0xFFFFFFFF when not resident)
};

const AstSlot = struct {
    node_buf: [*]AstNode,  // node buffer (grows to AST_BLOCK_NODES for the head)
    node_cap: usize,
    payload_buf: [*]u32,   // parallel payload buffer
    payload_cap: usize,
    in_use: u8,
};

pub const AstStore = struct {
    nodes: struct {
        // `len` is the flat node ordinal count; node data lives in disk-backed
        // blocks (astStoreNodeAt), the contiguous items/capacity array is gone.
        len: usize,
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
        // `len` is maintained == nodes.len; payload data is block-parallel in
        // the same disk-backed blocks as nodes (astStoreNodePayload).
        len: usize,
    },
    extra_ranges: struct {
        items: [*]u64,
        len: usize,
        capacity: usize,
    },
    allocator: *Sand,
    block_table: struct {
        items: [*]NodeBlockInfo,
        len: usize,
        capacity: usize,
    },
    slots: [8]AstSlot,
    slot_block: [8]u32, // resident slot -> block index it currently holds
    cur_block: u32,     // current head block index (pinned resident, slot 0)
    cur_block_len: u32, // nodes appended so far in the head block
    ring_next: u32,     // next eviction candidate slot (1..AST_WINDOW_SLOTS-1)
    spill_handle: ?*void, // FILE* of the spill temp file (lazily opened)
    spill_path: [512]u8,
    spill_path_len: usize,
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
        .nodes = .{ .len = @intCast(usize, 0) },
        .extra_children = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .identifiers = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .int_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .float_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .fn_protos = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .string_values = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .payload = .{ .len = @intCast(usize, 0) },
        .extra_ranges = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .allocator = arena,
        .block_table = .{ .items = undefined, .len = @intCast(usize, 0), .capacity = @intCast(usize, 0) },
        .slots = undefined,
        .slot_block = undefined,
        .cur_block = @intCast(u32, 0),
        .cur_block_len = @intCast(u32, 0),
        .ring_next = @intCast(u32, 1),
        .spill_handle = null,
        .spill_path = undefined,
        .spill_path_len = @intCast(usize, 0),
    };
    var si: u32 = 0;
    while (si < AST_WINDOW_SLOTS) : (si += 1) {
        store.slots[si] = AstSlot{ .node_buf = undefined, .node_cap = @intCast(usize, 0), .payload_buf = undefined, .payload_cap = @intCast(usize, 0), .in_use = @intCast(u8, 0) };
        store.slot_block[si] = @intCast(u32, 0);
    }
    store.slots[AST_HEAD_SLOT].in_use = @intCast(u8, 1);
    astBlockTableEnsure(&store, @intCast(usize, 1));
    store.block_table.items[0] = NodeBlockInfo{ .disk_off = @intCast(u32, 0), .resident = @intCast(u8, 1), .slot = AST_HEAD_SLOT };
    store.slot_block[AST_HEAD_SLOT] = @intCast(u32, 0);
    var default_path: []const u8 = ".zig1_ast.tmp";
    var pi: usize = 0;
    while (pi < default_path.len) : (pi += 1) {
        store.spill_path[pi] = default_path[pi];
    }
    store.spill_path_len = default_path.len;
    astStoreNodeAppend(&store, null_node, @intCast(u32, 0));
    u64ArrayListAppendInner(&store.extra_ranges.items, &store.extra_ranges.len, &store.extra_ranges.capacity, arena, @intCast(u64, 0));
    return store;
}

pub fn astStoreSetSpillPath(store: *AstStore, path: []const u8) void {
    var i: usize = 0;
    while (i < path.len and i < @intCast(usize, 511)) : (i += 1) {
        store.spill_path[i] = path[i];
    }
    store.spill_path_len = i;
    store.spill_path[i] = @intCast(u8, 0);
}

pub fn astStoreCloseSpill(store: *AstStore) void {
    if (store.spill_handle) |h| {
        pal.streamClose(h);
        store.spill_handle = null;
    }
}


pub fn astStoreAddNode(store: *AstStore, kind: AstKind, flags: u8, span_start: u32, span_end: u32, c0: u32, c1: u32, c2: u32, payload: u32) u32 {
    var span_len: u32 = @intCast(u32, span_end - span_start);
    var node = AstNode{
        .kind = kind, .flags = flags,
        .span_start = span_start, .span_len = span_len,
        .child_0 = c0, .child_1 = c1, .child_2 = c2,
    };
    astStoreNodeAppend(store, node, payload);
    return @intCast(u32, store.nodes.len - 1);
}

fn astStoreNodeAppend(store: *AstStore, node: AstNode, payload: u32) void {
    var node_idx = store.nodes.len;
    var bi: u32 = @intCast(u32, node_idx >> 12);
    if (bi != store.cur_block) {
        astBlockSpillHead(store);
        astBlockAdvanceHead(store, bi);
    }
    var off: usize = node_idx & @intCast(usize, 4095);
    astSlotEnsureNodeCap(store, AST_HEAD_SLOT, off + @intCast(usize, 1));
    astSlotEnsurePayloadCap(store, AST_HEAD_SLOT, off + @intCast(usize, 1));
    store.slots[AST_HEAD_SLOT].node_buf[off] = node;
    store.slots[AST_HEAD_SLOT].payload_buf[off] = payload;
    store.nodes.len += 1;
    store.payload.len += 1;
    store.cur_block_len += 1;
}

fn astBlockTableEnsure(store: *AstStore, new_len: usize) void {
    if (new_len <= store.block_table.len) return;
    var new_cap = store.block_table.capacity;
    if (new_cap < @intCast(usize, 16)) new_cap = @intCast(usize, 16);
    while (new_cap < new_len) new_cap *= 2;
    var raw = alloc_mod.sandAlloc(store.allocator, @sizeOf(NodeBlockInfo) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]NodeBlockInfo, raw);
    var i: usize = 0;
    while (i < store.block_table.len) : (i += 1) {
        new_items[i] = store.block_table.items[i];
    }
    store.block_table.items = new_items;
    store.block_table.capacity = new_cap;
    store.block_table.len = new_len;
}

fn astBlockOpenSpill(store: *AstStore) void {
    if (store.spill_handle != null) return;
    // "w+b" (truncate + read/write): the same handle is used to write spilled
    // blocks during parse and fault them back in during the read phases.
    store.spill_handle = pal.streamOpen(store.spill_path[0..store.spill_path_len], "w+b");
    if (store.spill_handle == null) {
        var emsg: []const u8 = "AST spill file open failed (astBlockOpenSpill)";
        var ef: []const u8 = "ast.zig";
        panic_mod.panicHandler(emsg, ef, 518);
    }
}

fn astBlockSpillHead(store: *AstStore) void {
    astBlockOpenSpill(store);
    var h = store.spill_handle orelse return;
    var bi = store.cur_block;
    if (bi > AST_SPILL_MAX_BLOCKS) {
        var emsg: []const u8 = "S-AST spill block count exceeds i32 seek limit (astBlockSpillHead)";
        var ef: []const u8 = "ast.zig";
        panic_mod.panicHandler(emsg, ef, 537);
        return;
    }
    var disk_off: u32 = bi * AST_BLOCK_REC_SIZE;
    var entry = store.block_table.items[bi];
    entry.disk_off = disk_off;
    entry.resident = @intCast(u8, 0);
    entry.slot = 0xFFFFFFFF;
    store.block_table.items[bi] = entry;
    pal.streamSeek(h, @intCast(i32, disk_off));
    var nraw: [*]u8 = @ptrCast([*]u8, store.slots[AST_HEAD_SLOT].node_buf);
    pal.streamWrite(h, nraw[0..@intCast(usize, AST_BLOCK_NODE_BYTES)]);
    var praw: [*]u8 = @ptrCast([*]u8, store.slots[AST_HEAD_SLOT].payload_buf);
    pal.streamWrite(h, praw[0..@intCast(usize, AST_BLOCK_PAYLOAD_BYTES)]);
}

fn astBlockAdvanceHead(store: *AstStore, new_bi: u32) void {
    astBlockTableEnsure(store, @intCast(usize, new_bi) + 1);
    store.block_table.items[new_bi] = NodeBlockInfo{ .disk_off = new_bi * AST_BLOCK_REC_SIZE, .resident = @intCast(u8, 1), .slot = AST_HEAD_SLOT };
    store.slots[AST_HEAD_SLOT].in_use = @intCast(u8, 1);
    store.slot_block[AST_HEAD_SLOT] = new_bi;
    store.cur_block = new_bi;
    store.cur_block_len = @intCast(u32, 0);
}

fn astSlotEnsureNodeCap(store: *AstStore, s: u32, need: usize) void {
    if (store.slots[s].node_cap >= need) return;
    var new_cap = store.slots[s].node_cap;
    if (new_cap < @intCast(usize, 64)) new_cap = @intCast(usize, 64);
    while (new_cap < need) new_cap *= 2;
    if (new_cap > @intCast(usize, AST_BLOCK_NODES)) new_cap = @intCast(usize, AST_BLOCK_NODES);
    var raw = alloc_mod.sandAlloc(store.allocator, @sizeOf(AstNode) * new_cap, @intCast(usize, 4)) catch unreachable;
    var nb = @ptrCast([*]AstNode, raw);
    var i: usize = 0;
    while (i < store.slots[s].node_cap) : (i += 1) {
        nb[i] = store.slots[s].node_buf[i];
    }
    store.slots[s].node_buf = nb;
    store.slots[s].node_cap = new_cap;
}

fn astSlotEnsurePayloadCap(store: *AstStore, s: u32, need: usize) void {
    if (store.slots[s].payload_cap >= need) return;
    var new_cap = store.slots[s].payload_cap;
    if (new_cap < @intCast(usize, 64)) new_cap = @intCast(usize, 64);
    while (new_cap < need) new_cap *= 2;
    if (new_cap > @intCast(usize, AST_BLOCK_NODES)) new_cap = @intCast(usize, AST_BLOCK_NODES);
    var raw = alloc_mod.sandAlloc(store.allocator, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var nb = @ptrCast([*]u32, raw);
    var i: usize = 0;
    while (i < store.slots[s].payload_cap) : (i += 1) {
        nb[i] = store.slots[s].payload_buf[i];
    }
    store.slots[s].payload_buf = nb;
    store.slots[s].payload_cap = new_cap;
}

fn astSlotEnsureFull(store: *AstStore, s: u32) void {
    astSlotEnsureNodeCap(store, s, @intCast(usize, AST_BLOCK_NODES));
    astSlotEnsurePayloadCap(store, s, @intCast(usize, AST_BLOCK_NODES));
}

fn astSlotAcquire(store: *AstStore) u32 {
    var i: u32 = 1;
    while (i < AST_WINDOW_SLOTS) : (i += 1) {
        if (store.slots[i].in_use == @intCast(u8, 0)) {
            store.slots[i].in_use = @intCast(u8, 1);
            return i;
        }
    }
    var victim: u32 = store.ring_next;
    if (victim == AST_HEAD_SLOT) victim = 1;
    if (victim >= AST_WINDOW_SLOTS) victim = 1;
    var vblock: u32 = store.slot_block[victim];
    var ventry: NodeBlockInfo = store.block_table.items[vblock];
    ventry.resident = @intCast(u8, 0);
    ventry.slot = 0xFFFFFFFF;
    store.block_table.items[vblock] = ventry;
    var nv: u32 = victim + @intCast(u32, 1);
    if (nv >= AST_WINDOW_SLOTS) nv = 1;
    store.ring_next = nv;
    return victim;
}

fn astBlockFaultIn(store: *AstStore, bi: u32) void {
    astBlockOpenSpill(store);
    var h = store.spill_handle orelse return;
    if (bi > AST_SPILL_MAX_BLOCKS) {
        var emsg: []const u8 = "S-AST spill block count exceeds i32 seek limit (astBlockFaultIn)";
        var ef: []const u8 = "ast.zig";
        panic_mod.panicHandler(emsg, ef, 627);
        return;
    }
    var entry = store.block_table.items[bi];
    var s = astSlotAcquire(store);
    astSlotEnsureFull(store, s);
    pal.streamSeek(h, @intCast(i32, entry.disk_off));
    var nraw: [*]u8 = @ptrCast([*]u8, store.slots[s].node_buf);
    pal.streamRead(h, nraw[0..@intCast(usize, AST_BLOCK_NODE_BYTES)]);
    var praw: [*]u8 = @ptrCast([*]u8, store.slots[s].payload_buf);
    pal.streamRead(h, praw[0..@intCast(usize, AST_BLOCK_PAYLOAD_BYTES)]);
    store.slots[s].in_use = @intCast(u8, 1);
    store.slot_block[s] = bi;
    entry.resident = @intCast(u8, 1);
    entry.slot = s;
    store.block_table.items[bi] = entry;
}

pub fn astStoreNodeAt(store: *AstStore, idx: u32) AstNode {
    var bi: u32 = idx >> 12;
    var off: u32 = idx & @intCast(u32, 4095);
    var entry: NodeBlockInfo = store.block_table.items[bi];
    if (entry.resident == @intCast(u8, 0)) {
        astBlockFaultIn(store, bi);
        entry = store.block_table.items[bi];
    }
    return store.slots[entry.slot].node_buf[off];
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
    var bi: u32 = node_idx >> 12;
    var off: u32 = node_idx & @intCast(u32, 4095);
    var entry: NodeBlockInfo = store.block_table.items[bi];
    if (entry.resident == @intCast(u8, 0)) {
        astBlockFaultIn(store, bi);
        entry = store.block_table.items[bi];
    }
    return store.slots[entry.slot].payload_buf[off];
}

pub fn astStoreNodePayloadPacked(store: *AstStore, node_idx: u32, kind: AstKind) u64 {
    var v = astStoreNodePayload(store, node_idx);
    if (v == @intCast(u32, 0)) return @intCast(u64, 0);
    if (nodeHasExtraChildren(kind) or kind == AstKind.builtin_call) {
        return store.extra_ranges.items[@intCast(usize, v)];
    }
    return @intCast(u64, v);
}

pub fn astStoreNodeExtraChildren(store: *AstStore, node_idx: u32) []const u32 {
    var range_idx = astStoreNodePayload(store, node_idx);
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
    if (pal.isMarkersEnabled()) {
        var as0_buf: [64]u8 = undefined;
        var as0 = format_mod.formatF64(value, as0_buf[0..], 64);
        var as0s: []const u8 = "AS:"; pal.markerWrite(as0s);
        pal.markerWrite(as0);
        var as0n: []const u8 = "\n"; pal.markerWrite(as0n);
    }
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
        var node = astStoreNodeAt(store, node_idx);
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
    var resident_blocks: u32 = 0;
    var bi: usize = 0;
    while (bi < store.block_table.len) : (bi += 1) {
        if (store.block_table.items[bi].resident != @intCast(u8, 0)) {
            resident_blocks += 1;
        }
    }
    total += @intCast(u64, resident_blocks) * @intCast(u64, AST_BLOCK_REC_SIZE);
    total += @intCast(u64, store.block_table.len) * @sizeOf(NodeBlockInfo);
    total += @intCast(u64, store.extra_children.len) * @sizeOf(u32);
    total += @intCast(u64, store.identifiers.len) * @sizeOf(u32);
    total += @intCast(u64, store.int_values.len) * @sizeOf(u64);
    total += @intCast(u64, store.float_values.len) * @sizeOf(f64);
    total += @intCast(u64, store.string_values.len) * @sizeOf(u32);
    total += @intCast(u64, store.fn_protos.len) * @sizeOf(FnProto);
    total += @intCast(u64, store.extra_ranges.len) * @sizeOf(u64);
    return total;
}
