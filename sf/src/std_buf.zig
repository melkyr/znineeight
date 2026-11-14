// std_buf.zig — Z98 std lib L2: growable byte buffer over an arena.
//
// Contract (blueprint §3 L2): alloc arena | errors OutOfMemory only | coroutine
// no. Bytes only — not a general-purpose container. Growth is doubling; the
// arena owns all storage, so `slice()` stays valid until the next append that
// grows and `clear` retains capacity. There is no `deinit`; arena reset
// reclaims. The module imports only std_arena (L0), so the L2 layer stays
// cycle-free — it is the one sanctioned L1->L2 target of std_debug.backtrace.
//
// The append*BE/append*LE families exist because BitTorrent, debugger, and BMP
// consumers all need endian-aware writes and would otherwise hand-roll them.

const arena_mod = @import("std_arena.zig");

pub const Buf = struct {
    arena: *arena_mod.Arena,
    data: []u8,
    len: usize,
};

pub fn init(arena: *arena_mod.Arena) Buf {
    return Buf{ .arena = arena, .data = arena.data[0..0], .len = 0 };
}

pub fn initCapacity(arena: *arena_mod.Arena, cap: usize) !Buf {
    var raw = try arena_mod.alloc(arena, cap);
    return Buf{ .arena = arena, .data = raw[0..cap], .len = 0 };
}

pub fn capacity(b: *Buf) usize {
    return b.data.len;
}

pub fn slice(b: *Buf) []u8 {
    return b.data[0..b.len];
}

// clear keeps the backing storage and capacity; only the logical length resets.
pub fn clear(b: *Buf) void {
    b.len = 0;
}

// Ensure `len + extra` bytes fit, doubling capacity until it does. On arena
// exhaustion the error propagates and `b` is left untouched (no partial write).
pub fn reserve(b: *Buf, extra: usize) !void {
    var need: usize = b.len + extra;
    if (need <= b.data.len) return;
    var new_cap: usize = b.data.len;
    if (new_cap == 0) new_cap = 1;
    while (new_cap < need) {
        new_cap = new_cap * 2;
    }
    var raw = try arena_mod.alloc(b.arena, new_cap);
    var i: usize = 0;
    while (i < b.len) : (i += 1) {
        raw[i] = b.data[i];
    }
    b.data = raw[0..new_cap];
}

pub fn append(b: *Buf, bytes: []const u8) !void {
    try reserve(b, bytes.len);
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        b.data[b.len + i] = bytes[i];
    }
    b.len += bytes.len;
}

pub fn appendByte(b: *Buf, byte: u8) !void {
    try reserve(b, 1);
    b.data[b.len] = byte;
    b.len += 1;
}

pub fn appendU16BE(b: *Buf, v: u16) !void {
    try reserve(b, 2);
    b.data[b.len] = @intCast(u8, v >> 8);
    b.data[b.len + 1] = @intCast(u8, v & 0xFF);
    b.len += 2;
}

pub fn appendU16LE(b: *Buf, v: u16) !void {
    try reserve(b, 2);
    b.data[b.len] = @intCast(u8, v & 0xFF);
    b.data[b.len + 1] = @intCast(u8, v >> 8);
    b.len += 2;
}

pub fn appendU32BE(b: *Buf, v: u32) !void {
    try reserve(b, 4);
    b.data[b.len] = @intCast(u8, v >> 24);
    b.data[b.len + 1] = @intCast(u8, (v >> 16) & 0xFF);
    b.data[b.len + 2] = @intCast(u8, (v >> 8) & 0xFF);
    b.data[b.len + 3] = @intCast(u8, v & 0xFF);
    b.len += 4;
}

pub fn appendU32LE(b: *Buf, v: u32) !void {
    try reserve(b, 4);
    b.data[b.len] = @intCast(u8, v & 0xFF);
    b.data[b.len + 1] = @intCast(u8, (v >> 8) & 0xFF);
    b.data[b.len + 2] = @intCast(u8, (v >> 16) & 0xFF);
    b.data[b.len + 3] = @intCast(u8, v >> 24);
    b.len += 4;
}

pub fn appendU64BE(b: *Buf, v: u64) !void {
    try reserve(b, 8);
    b.data[b.len] = @intCast(u8, v >> 56);
    b.data[b.len + 1] = @intCast(u8, (v >> 48) & 0xFF);
    b.data[b.len + 2] = @intCast(u8, (v >> 40) & 0xFF);
    b.data[b.len + 3] = @intCast(u8, (v >> 32) & 0xFF);
    b.data[b.len + 4] = @intCast(u8, (v >> 24) & 0xFF);
    b.data[b.len + 5] = @intCast(u8, (v >> 16) & 0xFF);
    b.data[b.len + 6] = @intCast(u8, (v >> 8) & 0xFF);
    b.data[b.len + 7] = @intCast(u8, v & 0xFF);
    b.len += 8;
}

pub fn appendU64LE(b: *Buf, v: u64) !void {
    try reserve(b, 8);
    b.data[b.len] = @intCast(u8, v & 0xFF);
    b.data[b.len + 1] = @intCast(u8, (v >> 8) & 0xFF);
    b.data[b.len + 2] = @intCast(u8, (v >> 16) & 0xFF);
    b.data[b.len + 3] = @intCast(u8, (v >> 24) & 0xFF);
    b.data[b.len + 4] = @intCast(u8, (v >> 32) & 0xFF);
    b.data[b.len + 5] = @intCast(u8, (v >> 40) & 0xFF);
    b.data[b.len + 6] = @intCast(u8, (v >> 48) & 0xFF);
    b.data[b.len + 7] = @intCast(u8, v >> 56);
    b.len += 8;
}
