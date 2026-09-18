// stdlib_debug_stress_xmod — STDLIB std_debug (L1) hand-written stress table.
//
// No PRNG: every input is explicit. Stresses:
//   - backtrace over a deep hand-written 32-frame ebp chain (each frame's
//     saved-ebp points at the next, strictly increasing, last null); the walk
//     must append exactly 32 little-endian frame pointers in order.
//   - writeCoreDump at scale: three register contexts (all-zero, all-ones,
//     mixed max-width decimals) written to files and byte-compared against the
//     documented `name=decimal\n` layout, then removed.
//   - logInt at the i32 boundaries INT_MIN / INT_MAX / 0 / -1 / 1.
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0):
//   min: -2147483648
//   max: 2147483647
//   zero: 0
//   neg1: -1
//   one: 1
//   debug stress ok
const std = @import("std");

@cInclude("<stdio.h>");
extern "c" fn remove(path: [*]const u8) i32;

const ALL32: u32 = ~@intCast(u32, 0);
const NFRAMES: usize = 32;

var g_chain: [64]u32 = undefined;
var g_bt_backing: [1024]u8 = undefined;
var g_bt_arena = std.arena.init(g_bt_backing[0..]);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn leU32(s: []const u8, o: usize) u32 {
    var v: u32 = @intCast(u32, s[o]);
    v = v | (@intCast(u32, s[o + 1]) << 8);
    v = v | (@intCast(u32, s[o + 2]) << 16);
    v = v | (@intCast(u32, s[o + 3]) << 24);
    return v;
}

fn runDeepBacktrace() void {
    std.arena.reset(&g_bt_arena);
    var i: usize = 0;
    while (i < NFRAMES) : (i += 1) {
        if (i + 1 < NFRAMES) {
            g_chain[2 * i] = @intCast(u32, @ptrToInt(&g_chain[2 * (i + 1)]));
        } else {
            g_chain[2 * i] = 0;
        }
    }
    var ctx: std.debug.TrapContext = undefined;
    ctx.ebp = @intCast(u32, @ptrToInt(&g_chain[0]));
    var b = std.buf.init(&g_bt_arena);
    std.debug.backtrace(&ctx, &b) catch {
        g_fail += 1;
    };
    var s = std.buf.slice(&b);
    ck(s.len == NFRAMES * 4, "deep backtrace length");
    i = 0;
    while (i < NFRAMES) : (i += 1) {
        ck(leU32(s, i * 4) == @intCast(u32, @ptrToInt(&g_chain[2 * i])), "deep backtrace frame");
    }
}

fn checkDump(ctx: *const std.debug.TrapContext, path: []const u8, want: []const u8) void {
    std.debug.writeCoreDump(ctx, path) catch {
        g_fail += 1;
    };
    var rfd = std.io.fileOpen(path, false) orelse 0;
    ck(rfd != 0, "coredump reopen");
    var gotbuf: [256]u8 = undefined;
    var got = std.io.fileRead(rfd, gotbuf[0..]);
    std.io.fileClose(rfd);
    ck(got == want.len, "coredump length");
    ck(std.str.eql(gotbuf[0..got], want), "coredump bytes");
    var cpath: [64]u8 = undefined;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        cpath[i] = path[i];
    }
    cpath[path.len] = 0;
    _ = remove(&cpath[0]);
}

fn runCoreDumps() void {
    var ctx0: std.debug.TrapContext = undefined;
    ctx0.eip = 0;
    ctx0.esp = 0;
    ctx0.ebp = 0;
    ctx0.eflags = 0;
    ctx0.eax = 0;
    ctx0.ebx = 0;
    ctx0.ecx = 0;
    ctx0.edx = 0;
    ctx0.esi = 0;
    ctx0.edi = 0;
    var want0: []const u8 = "eip=0\nesp=0\nebp=0\neflags=0\neax=0\nebx=0\necx=0\nedx=0\nesi=0\nedi=0\n";
    checkDump(&ctx0, "cd_stress_0.txt", want0);

    var ctx1: std.debug.TrapContext = undefined;
    ctx1.eip = ALL32;
    ctx1.esp = ALL32;
    ctx1.ebp = ALL32;
    ctx1.eflags = ALL32;
    ctx1.eax = ALL32;
    ctx1.ebx = ALL32;
    ctx1.ecx = ALL32;
    ctx1.edx = ALL32;
    ctx1.esi = ALL32;
    ctx1.edi = ALL32;
    var want1: []const u8 = "eip=4294967295\nesp=4294967295\nebp=4294967295\neflags=4294967295\neax=4294967295\nebx=4294967295\necx=4294967295\nedx=4294967295\nesi=4294967295\nedi=4294967295\n";
    checkDump(&ctx1, "cd_stress_1.txt", want1);

    var ctx2: std.debug.TrapContext = undefined;
    ctx2.eip = ALL32;
    ctx2.esp = 0;
    ctx2.ebp = 1;
    ctx2.eflags = 2147483647;
    ctx2.eax = @intCast(u32, 2147483648);
    ctx2.ebx = @intCast(u32, 4000000000);
    ctx2.ecx = 123456789;
    ctx2.edx = 987654321;
    ctx2.esi = @intCast(u32, 4294967294);
    ctx2.edi = 1000000000;
    var want2: []const u8 = "eip=4294967295\nesp=0\nebp=1\neflags=2147483647\neax=2147483648\nebx=4000000000\necx=123456789\nedx=987654321\nesi=4294967294\nedi=1000000000\n";
    checkDump(&ctx2, "cd_stress_2.txt", want2);
}

fn runLogIntBoundaries() void {
    var imin: i32 = -2147483647;
    imin = imin - 1;
    var imax: i32 = 2147483647;
    std.debug.logInt("min", imin);
    std.debug.logInt("max", imax);
    std.debug.logInt("zero", 0);
    std.debug.logInt("neg1", -1);
    std.debug.logInt("one", 1);
}

pub fn main() void {
    runDeepBacktrace();
    runCoreDumps();
    runLogIntBoundaries();

    if (g_fail == 0) {
        std.io.write("debug stress ok\n");
    } else {
        std.io.write("debug stress FAIL\n");
    }
}
