// stdlib_debug_backtrace_xmod — STDLIB std_debug.backtrace GREEN fixture.
//
// Contract (blueprint §3 L1): `backtrace(ctx, out: *std.buf.Buf) !void` walks
// the `ebp` frame chain starting at `ctx.ebp`, appending each frame pointer to
// `out` (via the std_buf endian append) in walk order, and stops at a null or a
// non-increasing frame pointer. This is the single documented L1->L2 import of
// std_buf (R3 exception, operator ruling m1243).
//
// The fixture builds a synthetic ebp chain in a global u32 array: each frame is
// two words [saved-ebp, return-address]; only saved-ebp is read. Three scenarios
// are pinned: a valid 3-frame chain, a null start (empty result), and a
// non-increasing successor (walk stops before it).
//
// GREEN (contract): deterministic byte-exact stdout `backtrace ok\n` (RUNRC=0).
const std = @import("std");

// 8 words = 3 frames (indices 0, 2, 4) + a spare.
var g_chain: [8]u32 = undefined;
var g_backing: [128]u8 = undefined;
var g_arena = std.arena.init(g_backing[0..]);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

// Decode one little-endian u32 from the buffer bytes.
fn leU32(s: []const u8, off: usize) u32 {
    var v: u32 = @intCast(u32, s[off]);
    v = v | (@intCast(u32, s[off + 1]) << 8);
    v = v | (@intCast(u32, s[off + 2]) << 16);
    v = v | (@intCast(u32, s[off + 3]) << 24);
    return v;
}

fn runValid() void {
    std.arena.reset(&g_arena);
    g_chain[0] = @intCast(u32, @ptrToInt(&g_chain[2]));
    g_chain[2] = @intCast(u32, @ptrToInt(&g_chain[4]));
    g_chain[4] = 0;

    var ctx: std.debug.TrapContext = undefined;
    ctx.ebp = @intCast(u32, @ptrToInt(&g_chain[0]));
    var b = std.buf.init(&g_arena);
    std.debug.backtrace(&ctx, &b) catch {
        g_fail += 1;
    };

    var s = std.buf.slice(&b);
    ck(s.len == 12, "valid chain length");
    ck(leU32(s, 0) == @intCast(u32, @ptrToInt(&g_chain[0])), "valid frame 0");
    ck(leU32(s, 4) == @intCast(u32, @ptrToInt(&g_chain[2])), "valid frame 1");
    ck(leU32(s, 8) == @intCast(u32, @ptrToInt(&g_chain[4])), "valid frame 2");
}

fn runNull() void {
    std.arena.reset(&g_arena);
    var ctx: std.debug.TrapContext = undefined;
    ctx.ebp = 0;
    var b = std.buf.init(&g_arena);
    std.debug.backtrace(&ctx, &b) catch {
        g_fail += 1;
    };
    ck(std.buf.slice(&b).len == 0, "null ebp terminates immediately");
}

fn runNonIncreasing() void {
    std.arena.reset(&g_arena);
    g_chain[0] = @intCast(u32, @ptrToInt(&g_chain[2]));
    // Successor points back below the current frame -> non-increasing, stop.
    g_chain[2] = @intCast(u32, @ptrToInt(&g_chain[0]));

    var ctx: std.debug.TrapContext = undefined;
    ctx.ebp = @intCast(u32, @ptrToInt(&g_chain[0]));
    var b = std.buf.init(&g_arena);
    std.debug.backtrace(&ctx, &b) catch {
        g_fail += 1;
    };

    var s = std.buf.slice(&b);
    ck(s.len == 8, "non-increasing chain length");
    ck(leU32(s, 0) == @intCast(u32, @ptrToInt(&g_chain[0])), "non-increasing frame 0");
    ck(leU32(s, 4) == @intCast(u32, @ptrToInt(&g_chain[2])), "non-increasing frame 1");
}

pub fn main() void {
    runValid();
    runNull();
    runNonIncreasing();

    if (g_fail == 0) {
        std.io.write("backtrace ok\n");
    } else {
        std.io.write("backtrace FAIL\n");
    }
}
