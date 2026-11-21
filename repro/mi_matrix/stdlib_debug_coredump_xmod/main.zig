// stdlib_debug_coredump_xmod — STDLIB std_debug writeCoreDump GREEN fixture.
//
// R7 coverage for the public `writeCoreDump(ctx, path) DebugError!void`.
// Builds a synthetic TrapContext with fixed field values, dumps it to a
// CWD-relative temp file, reads the file back, asserts the bytes are exactly
// the documented `name=decimal` lines in struct order, then deletes the temp
// file (libc `remove` — std has no delete primitive) so the run leaves no
// artifact.
//
// Deterministic stdout contract (RUNRC=0): `coredump ok\n`.
const std = @import("std");

@cInclude("<stdio.h>");
extern "c" fn remove(path: [*]const u8) i32;

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    var ctx: std.debug.TrapContext = undefined;
    ctx.eip = 4660;
    ctx.esp = 1;
    ctx.ebp = 2;
    ctx.eflags = 3;
    ctx.eax = 4;
    ctx.ebx = 5;
    ctx.ecx = 6;
    ctx.edx = 7;
    ctx.esi = 8;
    ctx.edi = 9;

    var path: []const u8 = "stdlib_debug_coredump.txt";
    std.debug.writeCoreDump(&ctx, path) catch { g_fail += 1; };

    var want: []const u8 = "eip=4660\nesp=1\nebp=2\neflags=3\neax=4\nebx=5\necx=6\nedx=7\nesi=8\nedi=9\n";

    var rfd = std.io.fileOpen(path, false) orelse 0;
    ck(rfd != 0, "coredump reopen");
    var buf: [128]u8 = undefined;
    var got = std.io.fileRead(rfd, buf[0..]);
    std.io.fileClose(rfd);
    ck(got == want.len, "coredump length");
    ck(std.str.eql(buf[0..got], want), "coredump bytes");

    // Cleanup: NUL-terminate the path for the libc call.
    var cpath: [64]u8 = undefined;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        cpath[i] = path[i];
    }
    cpath[path.len] = 0;
    _ = remove(&cpath[0]);

    if (g_fail == 0) {
        std.io.write("coredump ok\n");
    } else {
        std.io.write("coredump FAIL\n");
    }
}
