// stdlib_arena_xmod — STDLIB std_arena per-arena allocator GREEN fixture.
//
// std_arena.zig was rewritten (spec §3.6) from a shared-global stub
// (`create(cap)` ignored its arg; every Arena aliased one module-global
// `g_storage[1048576]`/`g_used`) to a self-contained per-arena allocator:
//   init(data: []u8) Arena   — wraps caller-provided backing storage
//   alloc(self, size) ?[*]u8 — bump within self.data; null on exhaustion
//   reset(self) void         — self.used = 0
// The stub is DEMONSTRABLY GONE by running two Arenas over DISTINCT backing
// buffers in one module: exhausting A must NOT affect B, and reset(A) must not
// free or corrupt B's storage.
//
// This fixture imports via a BARE `@import("std")` (lib search path binds the
// canonical <exe>/lib std module) and rewrites the global-init form as
//   var g_buf: [N]u8 = undefined;
//   var arena = std.arena.init(g_buf[0..]);
// (the Task-1 §4 audit asked whether a slice-of-global-array global initializer
// parses/lowers — it does; confirmed by this fixture compiling and running).
//
// SHIPPED COMPILER FEATURES pinned alongside the module:
//   - optional return `?[*]u8` from alloc + `orelse` fallback
//   - optional return `?usize` from a local findIndex + `orelse` fallback
//   - `for` loop over a []u8 slice with element payload capture
//   - u32 width arithmetic (`u32` shifts/masks, u32 loop counter)
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0), one
// result per line via std.io.printInt + '\n':
//   1   alloc 8 in A succeeded
//   1   alloc 8 in B succeeded
//   1   alloc second 8 in A succeeded (A now exactly full, 16/16)
//   1   alloc 1 more in A returned null  <-- A's OWN limit (stub would succeed)
//   1   alloc 8 in B still succeeds (B independent of A's exhaustion)
//   1   u32 0x01020304 stored LE into B bytes: b1[0]==0x04 and b1[3]==0x01
//   1   A/B distinct buffers: a0[0]==0xA0 and b0[0]==0xB0
//   1   reset(A) then alloc 16 in A succeeds (A fully reusable)
//   1   B untouched by reset(A): b0[0]==0xB0
//   1   B content intact after reset(A): b1[0]==0x04
//   2   for-over-slice count of 0xA0 in a3[0..4]
//   0   findIndex(a3[0..4], 0xA0) orelse 99 — first index (optional ?usize)
//   99  findIndex(a3[0..4], 0x7F) orelse 99 — miss path (optional ?usize)
const std = @import("std");

var g_bufA: [16]u8 = undefined;
var g_bufB: [32]u8 = undefined;
var arenaA = std.arena.init(g_bufA[0..]);
var arenaB = std.arena.init(g_bufB[0..]);

const ZERO: [*]u8 = @ptrCast([*]u8, @intCast(usize, 0));

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

fn pb(cond: bool) void {
    if (cond) {
        p(1);
    } else {
        p(0);
    }
}

fn findIndex(s: []const u8, m: u8) ?usize {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == m) return i;
    }
    return null;
}

pub fn main() void {
    // A = 16-byte buffer, B = 32-byte buffer.
    var a0 = std.arena.alloc(&arenaA, 8) orelse ZERO;
    var b0 = std.arena.alloc(&arenaB, 8) orelse ZERO;
    a0[0] = 0xA0;
    b0[0] = 0xB0;
    pb(a0 != ZERO);
    pb(b0 != ZERO);

    // A now has 8 bytes left; the second 8-byte alloc exactly fills it.
    var a1 = std.arena.alloc(&arenaA, 8) orelse ZERO;
    pb(a1 != ZERO);

    // A is exhausted -> null. The shared-global stub would still hand out
    // another 1 MiB; per-arena must return null here.
    var a2 = std.arena.alloc(&arenaA, 1) orelse ZERO;
    pb(a2 == ZERO);

    // B is independent: A's exhaustion does not touch B.
    var b1 = std.arena.alloc(&arenaB, 8) orelse ZERO;
    pb(b1 != ZERO);

    // Store a u32 marker little-endian into B's second block.
    var w: u32 = 0x01020304;
    b1[0] = @intCast(u8, w & 0xFF);
    b1[1] = @intCast(u8, (w >> 8) & 0xFF);
    b1[2] = @intCast(u8, (w >> 16) & 0xFF);
    b1[3] = @intCast(u8, (w >> 24) & 0xFF);
    pb(b1[0] == 0x04 and b1[3] == 0x01);

    // A and B are separate buffers: each retains its own marker.
    pb(a0[0] == 0xA0 and b0[0] == 0xB0);

    // reset frees ONLY A.
    std.arena.reset(&arenaA);
    var a3 = std.arena.alloc(&arenaA, 16) orelse ZERO;
    pb(a3 != ZERO);
    pb(b0[0] == 0xB0);
    pb(b1[0] == 0x04);

    // for-over-slice: count the 0xA0 markers in a fresh 4-byte A window.
    a3[0] = 0xA0;
    a3[1] = 0x00;
    a3[2] = 0xA0;
    a3[3] = 0x00;
    var cnt: u32 = 0;
    for (a3[0..4]) |ch| {
        if (ch == 0xA0) cnt += 1;
    }
    p(@intCast(i32, cnt));

    // optional ?usize + orelse: hit and miss paths.
    var idx = findIndex(a3[0..4], 0xA0) orelse 99;
    p(@intCast(i32, idx));
    var miss = findIndex(a3[0..4], 0x7F) orelse 99;
    p(@intCast(i32, miss));
}
