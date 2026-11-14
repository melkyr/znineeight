const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const lz4 = @import("std_lz4.zig");

var g_arena_backing: [262144]u8 = undefined;
var g_dst: [65536]u8 = undefined;

fn sliceEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn isCrosscheck() bool {
    var i: usize = 1;
    while (i < os.argc()) : (i += 1) {
        if (sliceEq(os.argv(i), "--crosscheck")) return true;
    }
    return false;
}

fn writeU32(v: u32) void {
    if (v == 0) {
        std.io.write("0");
        return;
    }
    var buf: [10]u8 = undefined;
    var n: usize = 0;
    var x: u32 = v;
    while (x > 0) {
        buf[n] = @intCast(u8, @intCast(u32, '0') + (x % 10));
        n += 1;
        x /= 10;
    }
    while (n > 0) {
        n -= 1;
        std.io.write(buf[n .. n + 1]);
    }
}

fn crossMain() void {
    var ar = std.arena.init(g_arena_backing[0..]);
    var src = stdin.readAll(&ar) catch {
        std.io.write("corrupt\n");
        return;
    };
    var n = lz4.lz4DecompressBlock(src[0..], g_dst[0..]) catch {
        std.io.write("corrupt\n");
        return;
    };
    std.io.write("ok ");
    writeU32(n);
    std.io.write("\n");
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (isCrosscheck()) {
        crossMain();
    } else {
        std.io.write("lz4 cross ok\n");
    }
}
