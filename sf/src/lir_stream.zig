const lir_mod = @import("lir.zig");
const alloc_mod = @import("allocator.zig");
const hash_mod = @import("util/hash.zig");
const pal_mod = @import("pal.zig");
const panic_mod = @import("panic.zig");

const Sand = alloc_mod.Sand;
const LirFunction = lir_mod.LirFunction;
const LirSlot = lir_mod.LirSlot;

const READ_MODE: [*]const u8 = "rb";
const WRITE_MODE: [*]const u8 = "wb";

// Streaming-LIR spill stream. Each LirFunction is serialized to a single temp file
// during phase_LIRLowering (append-only, "wb") and faulted back in one function at a
// time during phase_C89Emission ("rb"). All LIR payloads are scalar (u32/u64/f64/u8 ids,
// no pointers/slices), so a raw byte dump of each array is byte-preserving.
pub const LirStream = struct {
    handle: ?*void, // FILE* ("wb" while writing, "rb" while reading)
    path: [512]u8,
    path_len: usize,
    write_offset: u32, // running byte offset while appending
};

pub fn lirStreamInit() LirStream {
    return LirStream{
        .handle = null,
        .path = undefined,
        .path_len = @intCast(usize, 0),
        .write_offset = @intCast(u32, 0),
    };
}

pub fn lirStreamBeginWrite(s: *LirStream, path: []const u8) void {
    var i: usize = @intCast(usize, 0);
    while (i < path.len and i < @intCast(usize, 511)) : (i += @intCast(usize, 1)) {
        s.path[i] = path[i];
    }
    s.path_len = i;
    s.path[i] = @intCast(u8, 0);
    s.write_offset = @intCast(u32, 0);
    s.handle = pal_mod.streamOpen(s.path[0..s.path_len], WRITE_MODE);
    if (s.handle == null) {
        var emsg: []const u8 = "LIR spill open failed (lirStreamBeginWrite)";
        var ef: []const u8 = "lir_stream.zig";
        panic_mod.panicHandler(emsg, ef, 46);
    }
}

pub fn lirStreamFinishWrite(s: *LirStream) void {
    if (s.handle) |h| {
        pal_mod.streamClose(h);
        s.handle = null;
    }
}

pub fn lirStreamBeginRead(s: *LirStream) void {
    s.handle = pal_mod.streamOpen(s.path[0..s.path_len], READ_MODE);
    if (s.handle == null) {
        var emsg: []const u8 = "LIR spill open failed (lirStreamBeginRead)";
        var ef: []const u8 = "lir_stream.zig";
        panic_mod.panicHandler(emsg, ef, 62);
    }
}

pub fn lirStreamEndRead(s: *LirStream) void {
    if (s.handle) |h| {
        pal_mod.streamClose(h);
        s.handle = null;
    }
}

fn wU32(s: *LirStream, v: u32) void {
    var h = s.handle orelse return;
    var b: [4]u8 = undefined;
    b[0] = @intCast(u8, v & @intCast(u32, 0xFF));
    b[1] = @intCast(u8, (v >> @intCast(u32, 8)) & @intCast(u32, 0xFF));
    b[2] = @intCast(u8, (v >> @intCast(u32, 16)) & @intCast(u32, 0xFF));
    b[3] = @intCast(u8, (v >> @intCast(u32, 24)) & @intCast(u32, 0xFF));
    pal_mod.streamWrite(h, b[0..]);
    s.write_offset += @intCast(u32, 4);
}

fn wU8(s: *LirStream, v: u8) void {
    var h = s.handle orelse return;
    var b: [1]u8 = undefined;
    b[0] = v;
    pal_mod.streamWrite(h, b[0..]);
    s.write_offset += @intCast(u32, 1);
}

fn wBytes(s: *LirStream, ptr: [*]const u8, len: usize) void {
    if (len == @intCast(usize, 0)) return;
    var h = s.handle orelse return;
    pal_mod.streamWrite(h, ptr[0..len]);
    s.write_offset += @intCast(u32, len);
}

fn rU32(s: *LirStream) u32 {
    var h = s.handle orelse return @intCast(u32, 0);
    var b: [4]u8 = undefined;
    pal_mod.streamRead(h, b[0..]);
    var v: u32 = @intCast(u32, 0);
    v = v | @intCast(u32, b[0]);
    v = v | (@intCast(u32, b[1]) << @intCast(u32, 8));
    v = v | (@intCast(u32, b[2]) << @intCast(u32, 16));
    v = v | (@intCast(u32, b[3]) << @intCast(u32, 24));
    return v;
}

fn rU8(s: *LirStream) u8 {
    var h = s.handle orelse return @intCast(u8, 0);
    var b: [1]u8 = undefined;
    pal_mod.streamRead(h, b[0..]);
    return b[0];
}

fn rBytes(s: *LirStream, dst: [*]u8, len: usize) void {
    if (len == @intCast(usize, 0)) return;
    var h = s.handle orelse return;
    pal_mod.streamRead(h, dst[0..len]);
}

pub fn lirStreamAppend(s: *LirStream, src_fn: LirFunction) LirSlot {
    var start: u32 = s.write_offset;
    wU32(s, src_fn.name_id);
    wU32(s, src_fn.module_id);
    wU32(s, src_fn.return_type);
    wU8(s, src_fn.is_extern);
    wU8(s, src_fn.is_pub);
    wU8(s, src_fn.is_variadic);
    wU8(s, @intCast(u8, 0)); // pad0 (keep 4-byte alignment)
    wU32(s, @intCast(u32, src_fn.params.len));
    wU32(s, @intCast(u32, src_fn.blocks.len));
    wU32(s, @intCast(u32, src_fn.hoisted_temps.len));
    wU32(s, @intCast(u32, src_fn.switch_cases.len));
    wU32(s, @intCast(u32, src_fn.side_table.len));
    wU32(s, @intCast(u32, src_fn.temp_variant_sub_field.capacity));
    wU32(s, @intCast(u32, src_fn.temp_variant_sub_field.count));

    if (src_fn.params.len > @intCast(usize, 0)) {
        wBytes(s, @ptrCast([*]const u8, src_fn.params.items), src_fn.params.len * @intCast(usize, @sizeOf(lir_mod.LirParam)));
    }
    var bi: usize = @intCast(usize, 0);
    while (bi < src_fn.blocks.len) : (bi += @intCast(usize, 1)) {
        var bb = &src_fn.blocks.items[bi];
        wU32(s, bb.id);
        wU8(s, bb.is_terminated);
        wU8(s, @intCast(u8, 0));
        wU8(s, @intCast(u8, 0));
        wU8(s, @intCast(u8, 0));
        wU32(s, @intCast(u32, bb.insts.len));
        if (bb.insts.len > @intCast(usize, 0)) {
            wBytes(s, @ptrCast([*]const u8, bb.insts.items), bb.insts.len * @intCast(usize, @sizeOf(lir_mod.LirInst)));
        }
    }
    if (src_fn.hoisted_temps.len > @intCast(usize, 0)) {
        wBytes(s, @ptrCast([*]const u8, src_fn.hoisted_temps.items), src_fn.hoisted_temps.len * @intCast(usize, @sizeOf(lir_mod.TempDecl)));
    }
    if (src_fn.switch_cases.len > @intCast(usize, 0)) {
        wBytes(s, @ptrCast([*]const u8, src_fn.switch_cases.items), src_fn.switch_cases.len * @intCast(usize, @sizeOf(lir_mod.SwitchCase)));
    }
    if (src_fn.side_table.len > @intCast(usize, 0)) {
        wBytes(s, @ptrCast([*]const u8, src_fn.side_table.items), src_fn.side_table.len * @intCast(usize, @sizeOf(lir_mod.LirSideEntry)));
    }
    if (src_fn.temp_variant_sub_field.capacity > @intCast(usize, 0)) {
        var cap = src_fn.temp_variant_sub_field.capacity;
        wBytes(s, @ptrCast([*]const u8, src_fn.temp_variant_sub_field.keys), cap * @intCast(usize, 4));
        wBytes(s, @ptrCast([*]const u8, src_fn.temp_variant_sub_field.values), cap * @intCast(usize, 4));
        wBytes(s, @ptrCast([*]const u8, src_fn.temp_variant_sub_field.occupied), cap * @intCast(usize, 1));
    }
    var byte_len: u32 = s.write_offset - start;
    return LirSlot{ .module_id = src_fn.module_id, .disk_offset = start, .byte_len = byte_len };
}

fn emptyLirFunction(dst: *Sand) LirFunction {
    return LirFunction{
        .name_id = @intCast(u32, 0),
        .module_id = @intCast(u32, 0),
        .return_type = @intCast(u32, 0),
        .params = lir_mod.lirParamArrayListInit(dst),
        .blocks = lir_mod.basicBlockArrayListInit(dst),
        .hoisted_temps = lir_mod.tempDeclArrayListInit(dst),
        .switch_cases = lir_mod.switchCaseArrayListInit(dst),
        .side_table = lir_mod.lirSideEntryArrayListInit(dst),
        .temp_variant_sub_field = hash_mod.u32ToU32MapInit(dst),
        .is_extern = @intCast(u8, 0),
        .is_pub = @intCast(u8, 0),
        .is_variadic = @intCast(u8, 0),
    };
}

pub fn lirStreamReadFunction(s: *LirStream, slot: LirSlot, dst: *Sand) LirFunction {
    alloc_mod.sandReset(dst);
    var h = s.handle orelse return emptyLirFunction(dst);
    pal_mod.streamSeek(h, @intCast(i32, slot.disk_offset));

    var name_id = rU32(s);
    var module_id = rU32(s);
    var return_type = rU32(s);
    var is_extern = rU8(s);
    var is_pub = rU8(s);
    var is_variadic = rU8(s);
    _ = rU8(s);
    var params_count = rU32(s);
    var blocks_count = rU32(s);
    var hoisted_temps_count = rU32(s);
    var switch_cases_count = rU32(s);
    var side_table_count = rU32(s);
    var tvsf_capacity = rU32(s);
    var tvsf_count = rU32(s);

    var expected_len: u32 = @intCast(u32, 44);
    expected_len += params_count * @intCast(u32, @sizeOf(lir_mod.LirParam));
    expected_len += blocks_count * @intCast(u32, 12);
    expected_len += hoisted_temps_count * @intCast(u32, @sizeOf(lir_mod.TempDecl));
    expected_len += switch_cases_count * @intCast(u32, @sizeOf(lir_mod.SwitchCase));
    expected_len += side_table_count * @intCast(u32, @sizeOf(lir_mod.LirSideEntry));
    if (tvsf_capacity > @intCast(u32, 0)) {
        expected_len += tvsf_capacity * @intCast(u32, 9);
    }

    var params = lir_mod.lirParamArrayListInit(dst);
    if (params_count > @intCast(u32, 0)) {
        var raw = alloc_mod.sandAlloc(dst, @intCast(usize, params_count) * @intCast(usize, @sizeOf(lir_mod.LirParam)), @intCast(usize, 4)) catch unreachable;
        params.items = @ptrCast([*]lir_mod.LirParam, raw);
        params.len = @intCast(usize, params_count);
        params.capacity = @intCast(usize, params_count);
        rBytes(s, @ptrCast([*]u8, params.items), @intCast(usize, params_count) * @intCast(usize, @sizeOf(lir_mod.LirParam)));
    }

    var blocks = lir_mod.basicBlockArrayListInit(dst);
    if (blocks_count > @intCast(u32, 0)) {
        var braw = alloc_mod.sandAlloc(dst, @intCast(usize, blocks_count) * @intCast(usize, @sizeOf(lir_mod.BasicBlock)), @intCast(usize, 4)) catch unreachable;
        var bitems = @ptrCast([*]lir_mod.BasicBlock, braw);
        blocks.items = bitems;
        blocks.len = @intCast(usize, blocks_count);
        blocks.capacity = @intCast(usize, blocks_count);
        var bi: usize = @intCast(usize, 0);
        while (bi < @intCast(usize, blocks_count)) : (bi += @intCast(usize, 1)) {
            var bb_id = rU32(s);
            var bb_term = rU8(s);
            _ = rU8(s);
            _ = rU8(s);
            _ = rU8(s);
            var insts_count = rU32(s);
            expected_len += insts_count * @intCast(u32, @sizeOf(lir_mod.LirInst));
            var binsts = lir_mod.lirInstArrayListInit(dst);
            if (insts_count > @intCast(u32, 0)) {
                var iraw = alloc_mod.sandAlloc(dst, @intCast(usize, insts_count) * @intCast(usize, @sizeOf(lir_mod.LirInst)), @intCast(usize, 4)) catch unreachable;
                binsts.items = @ptrCast([*]lir_mod.LirInst, iraw);
                binsts.len = @intCast(usize, insts_count);
                binsts.capacity = @intCast(usize, insts_count);
                rBytes(s, @ptrCast([*]u8, binsts.items), @intCast(usize, insts_count) * @intCast(usize, @sizeOf(lir_mod.LirInst)));
            }
            bitems[bi] = lir_mod.BasicBlock{ .id = bb_id, .insts = binsts, .is_terminated = bb_term };
        }
    }

    var hoisted_temps = lir_mod.tempDeclArrayListInit(dst);
    if (hoisted_temps_count > @intCast(u32, 0)) {
        var raw = alloc_mod.sandAlloc(dst, @intCast(usize, hoisted_temps_count) * @intCast(usize, @sizeOf(lir_mod.TempDecl)), @intCast(usize, 4)) catch unreachable;
        hoisted_temps.items = @ptrCast([*]lir_mod.TempDecl, raw);
        hoisted_temps.len = @intCast(usize, hoisted_temps_count);
        hoisted_temps.capacity = @intCast(usize, hoisted_temps_count);
        rBytes(s, @ptrCast([*]u8, hoisted_temps.items), @intCast(usize, hoisted_temps_count) * @intCast(usize, @sizeOf(lir_mod.TempDecl)));
    }

    var switch_cases = lir_mod.switchCaseArrayListInit(dst);
    if (switch_cases_count > @intCast(u32, 0)) {
        var raw = alloc_mod.sandAlloc(dst, @intCast(usize, switch_cases_count) * @intCast(usize, @sizeOf(lir_mod.SwitchCase)), @intCast(usize, 4)) catch unreachable;
        switch_cases.items = @ptrCast([*]lir_mod.SwitchCase, raw);
        switch_cases.len = @intCast(usize, switch_cases_count);
        switch_cases.capacity = @intCast(usize, switch_cases_count);
        rBytes(s, @ptrCast([*]u8, switch_cases.items), @intCast(usize, switch_cases_count) * @intCast(usize, @sizeOf(lir_mod.SwitchCase)));
    }

    var side_table = lir_mod.lirSideEntryArrayListInit(dst);
    if (side_table_count > @intCast(u32, 0)) {
        var raw = alloc_mod.sandAlloc(dst, @intCast(usize, side_table_count) * @intCast(usize, @sizeOf(lir_mod.LirSideEntry)), @intCast(usize, 4)) catch unreachable;
        side_table.items = @ptrCast([*]lir_mod.LirSideEntry, raw);
        side_table.len = @intCast(usize, side_table_count);
        side_table.capacity = @intCast(usize, side_table_count);
        rBytes(s, @ptrCast([*]u8, side_table.items), @intCast(usize, side_table_count) * @intCast(usize, @sizeOf(lir_mod.LirSideEntry)));
    }

    var tvsf = hash_mod.u32ToU32MapInit(dst);
    if (tvsf_capacity > @intCast(u32, 0)) {
        var cap = @intCast(usize, tvsf_capacity);
        var kraw = alloc_mod.sandAlloc(dst, @intCast(usize, 4) * cap, @intCast(usize, 4)) catch unreachable;
        var vraw = alloc_mod.sandAlloc(dst, @intCast(usize, 4) * cap, @intCast(usize, 4)) catch unreachable;
        var oraw = alloc_mod.sandAlloc(dst, @intCast(usize, 1) * cap, @intCast(usize, 4)) catch unreachable;
        tvsf.keys = @ptrCast([*]u32, kraw);
        tvsf.values = @ptrCast([*]u32, vraw);
        tvsf.occupied = @ptrCast([*]u8, oraw);
        tvsf.capacity = cap;
        tvsf.count = @intCast(usize, tvsf_count);
        rBytes(s, @ptrCast([*]u8, tvsf.keys), @intCast(usize, 4) * cap);
        rBytes(s, @ptrCast([*]u8, tvsf.values), @intCast(usize, 4) * cap);
        rBytes(s, @ptrCast([*]u8, tvsf.occupied), @intCast(usize, 1) * cap);
    }

    if (expected_len != slot.byte_len) {
        var emsg: []const u8 = "S-LIR byte_len mismatch on fault-in read";
        var ef: []const u8 = "lir_stream.zig";
        panic_mod.panicHandler(emsg, ef, 306);
        return emptyLirFunction(dst);
    }

    return LirFunction{
        .name_id = name_id,
        .module_id = module_id,
        .return_type = return_type,
        .params = params,
        .blocks = blocks,
        .hoisted_temps = hoisted_temps,
        .switch_cases = switch_cases,
        .side_table = side_table,
        .temp_variant_sub_field = tvsf,
        .is_extern = is_extern,
        .is_pub = is_pub,
        .is_variadic = is_variadic,
    };
}
