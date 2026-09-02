const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeId = @import("type_registry.zig").TypeId;
const pal_mod = @import("pal.zig");
const panic_mod = @import("panic.zig");
const hash_mod = @import("util/hash.zig");

// Dense spill record = the type half only: { type_id u32 @0, present u8 @4 } =
// 5 B/node (was 10 B/node with the dead source half inlined; the source
// relation is now sparse + resident, see src_map). Record->offset math:
// file_byte_off = block x RTT_BLOCK_BYTES + (node_idx % RTT_BLOCK_NODES) x 5.
pub const RTT_BLOCK_NODES: u32 = 409; // 2045 B block = 409 node records (5 B/node)
pub const RTT_BLOCK_BYTES: u32 = 2045;
pub const RTT_REC_BYTES: u32 = 5;
pub const RTT_SLOTS: u32 = 8;
const EMPTY_BLOCK: u32 = 0xFFFFFFFF;
const SEEK_MAX: u32 = 0x7FFFFFFF;
const WRITE_MODE: [*]const u8 = "w+b";

pub const ResolvedTypeTable = struct {
    cap: usize, // logical node extent (file covers blocks up to aligned(cap))
    entries_alloc: *Sand, // supplies the small resident cache window
    spill_handle: ?*void, // FILE* of the dense spill file (opened at first reserve/Set)
    spill_path: [512]u8,
    spill_path_len: usize,
    cache_buf: [*]u8, // RTT_SLOTS * RTT_BLOCK_BYTES resident window
    cache_allocated: u8,
    slot_block: [8]u32, // resident slot -> block index (EMPTY_BLOCK = empty)
    slot_dirty: [8]u8, // write-back flag per resident slot
    ring_next: u32, // next eviction candidate
    src_map: hash_mod.U32ToU32Map, // sparse resident node_idx -> source_name_id (only-on-Set)
};

pub fn resolvedTypeTableInit(alloc: *Sand) ResolvedTypeTable {
    var t = ResolvedTypeTable{
        .cap = @intCast(usize, 0),
        .entries_alloc = alloc,
        .spill_handle = null,
        .spill_path = undefined,
        .spill_path_len = @intCast(usize, 0),
        .cache_buf = undefined,
        .cache_allocated = @intCast(u8, 0),
        .slot_block = undefined,
        .slot_dirty = undefined,
        .ring_next = @intCast(u32, 0),
        .src_map = .{ .keys = undefined, .values = undefined, .occupied = undefined, .capacity = @intCast(usize, 0), .count = @intCast(usize, 0), .alloc = alloc },
    };
    var si: u32 = 0;
    while (si < RTT_SLOTS) : (si += 1) {
        t.slot_block[si] = EMPTY_BLOCK;
        t.slot_dirty[si] = @intCast(u8, 0);
    }
    var dp: []const u8 = ".zig1_res.tmp";
    var di: usize = 0;
    while (di < dp.len) : (di += 1) {
        t.spill_path[di] = dp[di];
    }
    t.spill_path_len = dp.len;
    return t;
}

pub fn resolvedTypeTableSetSpillPath(self: *ResolvedTypeTable, path: []const u8) void {
    var i: usize = 0;
    while (i < path.len and i < @intCast(usize, 511)) : (i += 1) {
        self.spill_path[i] = path[i];
    }
    self.spill_path_len = i;
    self.spill_path[i] = @intCast(u8, 0);
}

fn rttAlignedNodes(n: usize) usize {
    var mult: usize = (n + @intCast(usize, RTT_BLOCK_NODES) - 1) / @intCast(usize, RTT_BLOCK_NODES);
    return mult * @intCast(usize, RTT_BLOCK_NODES);
}

fn rttOpenSpill(self: *ResolvedTypeTable) void {
    if (self.spill_handle != null) return;
    self.spill_handle = pal_mod.streamOpen(self.spill_path[0..self.spill_path_len], WRITE_MODE);
    if (self.spill_handle == null) {
        var emsg: []const u8 = "resolved-type spill open failed (rttOpenSpill)";
        var ef: []const u8 = "resolved_type_table.zig";
        panic_mod.panicHandler(emsg, ef, 99);
    }
}

fn rttExtend(self: *ResolvedTypeTable, new_cap: usize) void {
    if (new_cap <= self.cap) return;
    rttOpenSpill(self);
    var h = self.spill_handle orelse return;
    var old_an = rttAlignedNodes(self.cap);
    var new_an = rttAlignedNodes(new_cap);
    if (new_an > old_an) {
        var old_bytes: u32 = @intCast(u32, old_an) * RTT_REC_BYTES;
        var new_bytes: u32 = @intCast(u32, new_an) * RTT_REC_BYTES;
        if (new_bytes > SEEK_MAX) {
            var emsg: []const u8 = "resolved-type spill exceeds seek limit (rttExtend)";
            var ef: []const u8 = "resolved_type_table.zig";
            panic_mod.panicHandler(emsg, ef, 112);
            return;
        }
        pal_mod.streamSeek(h, @intCast(i32, old_bytes));
        var zero_buf: [RTT_BLOCK_BYTES]u8 = undefined;
        var zi: usize = 0;
        while (zi < @intCast(usize, RTT_BLOCK_BYTES)) : (zi += 1) {
            zero_buf[zi] = @intCast(u8, 0);
        }
        var to_write: u32 = new_bytes - old_bytes;
        while (to_write > @intCast(u32, 0)) : (to_write -= RTT_BLOCK_BYTES) {
            pal_mod.streamWrite(h, zero_buf[0..@intCast(usize, RTT_BLOCK_BYTES)]);
        }
    }
    self.cap = new_cap;
}

fn rttEnsureCache(self: *ResolvedTypeTable) void {
    if (self.cache_allocated != @intCast(u8, 0)) return;
    var raw = alloc_mod.sandAlloc(self.entries_alloc, @intCast(usize, RTT_SLOTS) * @intCast(usize, RTT_BLOCK_BYTES), @intCast(usize, 4)) catch unreachable;
    self.cache_buf = raw;
    self.cache_allocated = @intCast(u8, 1);
}

fn rttSlotBuf(self: *ResolvedTypeTable, s: u32) [*]u8 {
    return self.cache_buf + @intCast(usize, s) * @intCast(usize, RTT_BLOCK_BYTES);
}

fn rttResidentSlot(self: *ResolvedTypeTable, block: u32) u32 {
    var s: u32 = 0;
    while (s < RTT_SLOTS) : (s += 1) {
        if (self.slot_block[s] == block) return s;
    }
    return RTT_SLOTS; // not resident
}

fn rttWriteBack(self: *ResolvedTypeTable, s: u32) void {
    var h = self.spill_handle orelse return;
    var block = self.slot_block[s];
    var off: u32 = block * RTT_BLOCK_BYTES;
    if (off > SEEK_MAX - RTT_BLOCK_BYTES) {
        var emsg: []const u8 = "resolved-type spill exceeds seek limit (rttWriteBack)";
        var ef: []const u8 = "resolved_type_table.zig";
        panic_mod.panicHandler(emsg, ef, 151);
        return;
    }
    pal_mod.streamSeek(h, @intCast(i32, off));
    pal_mod.streamWrite(h, rttSlotBuf(self, s)[0..@intCast(usize, RTT_BLOCK_BYTES)]);
    self.slot_dirty[s] = @intCast(u8, 0);
}

fn rttBlockEnsure(self: *ResolvedTypeTable, block: u32) u32 {
    var r = rttResidentSlot(self, block);
    if (r < RTT_SLOTS) return r;
    rttEnsureCache(self);
    var v = self.ring_next;
    if (self.slot_block[v] != EMPTY_BLOCK and self.slot_dirty[v] != @intCast(u8, 0)) {
        rttWriteBack(self, v);
    }
    rttOpenSpill(self);
    var h = self.spill_handle orelse return v;
    var off: u32 = block * RTT_BLOCK_BYTES;
    if (off > SEEK_MAX - RTT_BLOCK_BYTES) {
        var emsg: []const u8 = "resolved-type spill exceeds seek limit (rttBlockEnsure)";
        var ef: []const u8 = "resolved_type_table.zig";
        panic_mod.panicHandler(emsg, ef, 174);
        return v;
    }
    pal_mod.streamSeek(h, @intCast(i32, off));
    pal_mod.streamRead(h, rttSlotBuf(self, v)[0..@intCast(usize, RTT_BLOCK_BYTES)]);
    self.slot_block[v] = block;
    self.slot_dirty[v] = @intCast(u8, 0);
    self.ring_next = v + 1;
    if (self.ring_next >= RTT_SLOTS) self.ring_next = @intCast(u32, 0);
    return v;
}

fn rttReadU32(p: [*]const u8, off: usize) u32 {
    var v: u32 = @intCast(u32, p[off]);
    v = v | (@intCast(u32, p[off + 1]) << @intCast(u32, 8));
    v = v | (@intCast(u32, p[off + 2]) << @intCast(u32, 16));
    v = v | (@intCast(u32, p[off + 3]) << @intCast(u32, 24));
    return v;
}

fn rttWriteU32(p: [*]u8, off: usize, v: u32) void {
    p[off] = @intCast(u8, v & @intCast(u32, 0xFF));
    p[off + 1] = @intCast(u8, (v >> @intCast(u32, 8)) & @intCast(u32, 0xFF));
    p[off + 2] = @intCast(u8, (v >> @intCast(u32, 16)) & @intCast(u32, 0xFF));
    p[off + 3] = @intCast(u8, (v >> @intCast(u32, 24)) & @intCast(u32, 0xFF));
}

// Dense record (5 B/node, LE): { type_id u32 @0, present u8 @4 }. The source
// relation is sparse and resident (src_map), populated only on Set; the dense
// spill file never carries source bytes.
pub fn resolvedTypeTableReserve(self: *ResolvedTypeTable, node_count: usize) void {
    rttExtend(self, node_count);
}

pub fn resolvedTypeTableSet(self: *ResolvedTypeTable, node_idx: u32, type_id: TypeId) void {
    var ni: usize = @intCast(usize, node_idx);
    if (ni >= self.cap) rttExtend(self, ni + 1);
    var block: u32 = @intCast(u32, ni / @intCast(usize, RTT_BLOCK_NODES));
    var s = rttBlockEnsure(self, block);
    var buf = rttSlotBuf(self, s);
    var rec_off: usize = (ni % @intCast(usize, RTT_BLOCK_NODES)) * @intCast(usize, RTT_REC_BYTES);
    rttWriteU32(buf, rec_off, @intCast(u32, type_id));
    buf[rec_off + 4] = @intCast(u8, 1);
    self.slot_dirty[s] = @intCast(u8, 1);
}

pub fn resolvedTypeTableGet(self: *ResolvedTypeTable, node_idx: u32) ?TypeId {
    var ni: usize = @intCast(usize, node_idx);
    if (ni >= self.cap) return null;
    var block: u32 = @intCast(u32, ni / @intCast(usize, RTT_BLOCK_NODES));
    var s = rttBlockEnsure(self, block);
    var buf = rttSlotBuf(self, s);
    var rec_off: usize = (ni % @intCast(usize, RTT_BLOCK_NODES)) * @intCast(usize, RTT_REC_BYTES);
    if (buf[rec_off + 4] != @intCast(u8, 0)) {
        return rttReadU32(buf, rec_off);
    }
    return null;
}

pub fn resolvedSourceTableSet(self: *ResolvedTypeTable, node_idx: u32, source_name_id: u32) void {
    hash_mod.u32ToU32MapPut(&self.src_map, node_idx, source_name_id);
}

pub fn resolvedSourceTableGet(self: *ResolvedTypeTable, node_idx: u32) ?u32 {
    return hash_mod.u32ToU32MapGet(&self.src_map, node_idx);
}

pub fn resolvedTypeTableClose(self: *ResolvedTypeTable) void {
    if (self.spill_handle) |h| {
        var s: u32 = 0;
        while (s < RTT_SLOTS) : (s += 1) {
            if (self.slot_block[s] != EMPTY_BLOCK and self.slot_dirty[s] != @intCast(u8, 0)) {
                rttWriteBack(self, s);
            }
        }
        pal_mod.streamClose(h);
        self.spill_handle = null;
    }
}

