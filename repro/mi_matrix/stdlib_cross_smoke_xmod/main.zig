// stdlib_cross_smoke_xmod — Task 1 crosscheck substrate smoke fixture.
//
// Default mode (fixture gate): deterministic `cross smoke ok\n`.
// `--crosscheck` mode: reads `a b` per stdin line and prints `a + b` per line.
// The C89 reference at scripts/stdlib/ref/smoke/ref.c implements the same sum;
// the crosscheck harness compares Z98 stdout, ref stdout, and the committed
// .out vector in three ways.
const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const parse = @import("std_parse.zig");

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

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn crossMain() void {
    var buf: [512]u8 = undefined;
    while (true) {
        const line_opt = stdin.readLine(buf[0..]) catch @panic("crosscheck read");
        if (line_opt) |line| {
            var i: usize = 0;
            while (i < line.len and isWs(line[i])) : (i += 1) {}
            var j: usize = i;
            while (j < line.len and !isWs(line[j])) : (j += 1) {}
            if (j == i) @panic("crosscheck parse a");
            var k: usize = j;
            while (k < line.len and isWs(line[k])) : (k += 1) {}
            var m: usize = k;
            while (m < line.len and !isWs(line[m])) : (m += 1) {}
            if (m == k) @panic("crosscheck parse b");

            if (parse.parseInt64(line[i..j])) |a| {
                if (parse.parseInt64(line[k..m])) |b| {
                    var outbuf: [32]u8 = undefined;
                    var s = parse.itoa64(outbuf[0..], a + b);
                    std.io.write(s);
                    std.io.write("\n");
                } else {
                    @panic("crosscheck parse b");
                }
            } else {
                @panic("crosscheck parse a");
            }
        } else {
            break;
        }
    }
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (isCrosscheck()) {
        crossMain();
    } else {
        std.io.write("cross smoke ok\n");
    }
}
