const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const pal = @import("pal.zig");
const panic_mod = @import("panic.zig");

// SpillStore: offset-addressed byte spill over a Disk (pal.stream*) or Ram
// (arena-backed growable byte buffer) backend. Each spill's producer/consumer
// treats the spill as byte-addressed opaque data, so byte-identity holds in
// both modes: the bytes written at each logical offset and read back are the
// same regardless of medium. The backend is selected once per spill from the
// immutable per-spill flag array (g_flags), a set-once prefix mask (indices
// < level are Ram; all-Disk by default). Ram buffers are allocated from the
// arena supplied at spillOpen (per-spill lifetime: module arena for spills
// dead at the module reset, emission arena for LIR which is read after it).

pub const SPILL_COUNT: u32 = 5;
pub const SPILL_SEEK_MAX: u32 = 0x7FFFFFFF; // uniform i32-seek guard (I-FMT carry-over)

pub const SpillBackend = enum(u8) {
    disk = 0,
    ram = 1,
};

pub const SpillId = enum(u8) {
    s_ast = 0, // S-AST nodes+payload
    s_lir = 1, // S-LIR functions
    s_hash = 2, // S-HASH module maps
    s_res = 3, // S-RES resolved types
    s_side = 4, // S-SIDE value pools
};

// Immutable-after-init prefix mask; deactivation order = index order
// (S-AST=0 -> S-LIR=1 -> S-HASH=2 -> S-RES=3 -> S-SIDE=4). Default all-Disk
// (u8 globals zero-init). -s<N> (parsed in F-S) sets indices < N to Ram via
// spillSetLevel. One scalar per spill: the Z98/zig0 emitter does not support
// subscripted stores into module-level global arrays (they are dropped), so
// the flag is 5 scalar module vars, not one array.
var g_s_ast: u8 = 0;
var g_s_lir: u8 = 0;
var g_s_hash: u8 = 0;
var g_s_res: u8 = 0;
var g_s_side: u8 = 0;

pub fn spillSetLevel(level: u32) void {
    var n = level;
    if (n > SPILL_COUNT) n = SPILL_COUNT;
    if (n >= @intCast(u32, 1)) g_s_ast = @intCast(u8, 1);
    if (n >= @intCast(u32, 2)) g_s_lir = @intCast(u8, 1);
    if (n >= @intCast(u32, 3)) g_s_hash = @intCast(u8, 1);
    if (n >= @intCast(u32, 4)) g_s_res = @intCast(u8, 1);
    if (n >= @intCast(u32, 5)) g_s_side = @intCast(u8, 1);
}

pub fn spillBackendFor(id: SpillId) SpillBackend {
    if (id == SpillId.s_ast) {
        if (g_s_ast != @intCast(u8, 0)) return SpillBackend.ram;
        return SpillBackend.disk;
    }
    if (id == SpillId.s_lir) {
        if (g_s_lir != @intCast(u8, 0)) return SpillBackend.ram;
        return SpillBackend.disk;
    }
    if (id == SpillId.s_hash) {
        if (g_s_hash != @intCast(u8, 0)) return SpillBackend.ram;
        return SpillBackend.disk;
    }
    if (id == SpillId.s_res) {
        if (g_s_res != @intCast(u8, 0)) return SpillBackend.ram;
        return SpillBackend.disk;
    }
    if (g_s_side != @intCast(u8, 0)) return SpillBackend.ram;
    return SpillBackend.disk;
}

pub const SpillStore = struct {
    backend: SpillBackend, // selected once (at first lazy open / write phase)
    opened: u8,            // 1 after spillOpen (Ram: buffer alive until arena reset)
    handle: ?*void,        // FILE* (Disk backend only)
    buf: [*]u8,            // Ram byte buffer; byte 0 == spill byte 0
    cap: u32,              // allocated Ram buffer bytes
    len: u32,              // logical high-water (highest byte written + 1)
    cur: u32,              // last I/O end offset (Disk fseek elision; Ram cursor)
    alloc: *Sand,          // arena backing the Ram buffer (unused on Disk)
};

pub fn spillStoreInit() SpillStore {
    return SpillStore{
        .backend = SpillBackend.disk,
        .opened = @intCast(u8, 0),
        .handle = null,
        .buf = undefined,
        .cap = @intCast(u32, 0),
        .len = @intCast(u32, 0),
        .cur = @intCast(u32, 0),
        .alloc = undefined,
    };
}

// Ram buffer growth: sandTryReallocInPlace first (wins at the arena tail),
// else fresh sandAlloc + copy (old bytes remain doubling-dead until the owning
// arena resets — the standard codebase cumulative-accounting pattern).
fn ramEnsure(s: *SpillStore, need: u32) void {
    if (need <= s.cap) return;
    var new_cap = s.cap;
    if (new_cap == @intCast(u32, 0)) new_cap = @intCast(u32, 65536);
    while (new_cap < need) : (new_cap *= @intCast(u32, 2)) {}
    if (s.cap == @intCast(u32, 0)) {
        var raw = alloc_mod.sandAlloc(s.alloc, @intCast(usize, new_cap), @intCast(usize, 4)) catch unreachable;
        s.buf = raw;
        s.cap = new_cap;
        return;
    }
    var grown = alloc_mod.sandTryReallocInPlace(s.alloc, s.buf, @intCast(usize, s.cap), @intCast(usize, new_cap), @intCast(usize, 4));
    if (grown != null) {
        s.cap = new_cap;
        return;
    }
    var raw = alloc_mod.sandAlloc(s.alloc, @intCast(usize, new_cap), @intCast(usize, 4)) catch unreachable;
    var i: usize = 0;
    while (i < @intCast(usize, s.cap)) : (i += 1) {
        raw[i] = s.buf[i];
    }
    s.buf = raw;
    s.cap = new_cap;
}

// Disk fopen (S-FIX-1 ICE on null); Ram no-op apart from recording the arena.
pub fn spillOpen(s: *SpillStore, backend: SpillBackend, path: []const u8, alloc: *Sand, mode: [*]const u8) void {
    s.backend = backend;
    s.cur = @intCast(u32, 0);
    if (backend == SpillBackend.disk) {
        s.handle = pal.streamOpen(path, mode);
        if (s.handle == null) {
            var emsg: []const u8 = "spill file open failed (spillOpen)";
            var ef: []const u8 = "spill_store.zig";
            panic_mod.panicHandler(emsg, ef, 132);
            return;
        }
    } else {
        s.alloc = alloc;
    }
    s.opened = @intCast(u8, 1);
}

// Disk fclose; Ram no-op (arena reset reclaims the buffer at its lifetime end).
pub fn spillClose(s: *SpillStore) void {
    if (s.backend == SpillBackend.disk) {
        if (s.handle) |h| {
            pal.streamClose(h);
            s.handle = null;
        }
    }
    s.opened = @intCast(u8, 0);
}

pub fn spillSeek(s: *SpillStore, off: u32) void {
    if (off > SPILL_SEEK_MAX) {
        var emsg: []const u8 = "spill seek offset exceeds i32 limit (spillSeek)";
        var ef: []const u8 = "spill_store.zig";
        panic_mod.panicHandler(emsg, ef, 154);
        return;
    }
    if (s.backend == SpillBackend.disk) {
        var h = s.handle orelse {
            var emsg: []const u8 = "spill seek on null handle (spillSeek)";
            var ef: []const u8 = "spill_store.zig";
            panic_mod.panicHandler(emsg, ef, 160);
            return;
        };
        pal.streamSeek(h, @intCast(i32, off));
    }
    s.cur = off;
}

pub fn spillWriteAt(s: *SpillStore, off: u32, bytes: []const u8) void {
    if (bytes.len == @intCast(usize, 0)) return;
    if (off > SPILL_SEEK_MAX or bytes.len > @intCast(usize, SPILL_SEEK_MAX) - @intCast(usize, off)) {
        var emsg: []const u8 = "spill write exceeds i32 seek limit (spillWriteAt)";
        var ef: []const u8 = "spill_store.zig";
        panic_mod.panicHandler(emsg, ef, 171);
        return;
    }
    var end = off + @intCast(u32, bytes.len);
    if (s.backend == SpillBackend.ram) {
        ramEnsure(s, end);
        var i: usize = 0;
        while (i < bytes.len) : (i += 1) {
            s.buf[@intCast(usize, off) + i] = bytes[i];
        }
        if (end > s.len) s.len = end;
        s.cur = end;
    } else {
        var h = s.handle orelse {
            var emsg: []const u8 = "spill write on null handle (spillWriteAt)";
            var ef: []const u8 = "spill_store.zig";
            panic_mod.panicHandler(emsg, ef, 187);
            return;
        };
        if (s.cur != off) pal.streamSeek(h, @intCast(i32, off));
        pal.streamWrite(h, bytes);
        s.cur = end;
    }
}

pub fn spillReadAt(s: *SpillStore, off: u32, dst: []u8) void {
    if (dst.len == @intCast(usize, 0)) return;
    if (off > SPILL_SEEK_MAX or dst.len > @intCast(usize, SPILL_SEEK_MAX) - @intCast(usize, off)) {
        var emsg: []const u8 = "spill read exceeds i32 seek limit (spillReadAt)";
        var ef: []const u8 = "spill_store.zig";
        panic_mod.panicHandler(emsg, ef, 199);
        return;
    }
    var end = off + @intCast(u32, dst.len);
    if (s.backend == SpillBackend.ram) {
        // read past the logical high-water == Disk short read (S-FIX-1 parity)
        if (end > s.len) {
            var emsg: []const u8 = "spill read past logical end (spillReadAt)";
            var ef: []const u8 = "spill_store.zig";
            panic_mod.panicHandler(emsg, ef, 207);
            return;
        }
        var i: usize = 0;
        while (i < dst.len) : (i += 1) {
            dst[i] = s.buf[@intCast(usize, off) + i];
        }
        s.cur = end;
    } else {
        var h = s.handle orelse {
            var emsg: []const u8 = "spill read on null handle (spillReadAt)";
            var ef: []const u8 = "spill_store.zig";
            panic_mod.panicHandler(emsg, ef, 221);
            return;
        };
        if (s.cur != off) pal.streamSeek(h, @intCast(i32, off));
        pal.streamRead(h, dst);
        s.cur = end;
    }
}
