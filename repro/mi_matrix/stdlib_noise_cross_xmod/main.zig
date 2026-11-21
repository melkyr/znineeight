// stdlib_noise_cross_xmod — std_noise (L5) crosscheck driver.
//
// Default mode (fixture gate): deterministic `noise cross ok\n`.
// `--crosscheck` reads one line per input:
//   `2 <seed> <x> <y>` or `3 <seed> <x> <y> <z>`  (decimal)
// re-initializes `opensimplexInit(seed)` for each line and prints exactly one
// line: the 16 lowercase hex digits of the IEEE-754 f64 bit pattern returned
// by `noise2d`/`noise3d`. Malformed input is skipped and the process always
// exits 0. The C89 reference at scripts/stdlib/ref/std_noise/ref.c implements
// the same protocol.
const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const parse = @import("std_parse.zig");
const noise = @import("std_noise.zig");

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

fn nextToken(line: []const u8, pos: *usize) ?[]const u8 {
    var i: usize = pos.*;
    while (i < line.len and isWs(line[i])) : (i += 1) {}
    if (i >= line.len) {
        pos.* = i;
        return null;
    }
    var j: usize = i;
    while (j < line.len and !isWs(line[j])) : (j += 1) {}
    pos.* = j;
    return line[i..j];
}

fn bitsOf(v: f64) u64 {
    var p: *u64 = @ptrCast(*u64, &v);
    return p.*;
}

fn hexChar(v: u64) u8 {
    if (v < 10) return @intCast(u8, @intCast(u32, '0') + @intCast(u32, v));
    return @intCast(u8, @intCast(u32, 'a') + @intCast(u32, v - 10));
}

fn writeHex16(v: u64) void {
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        var sh: u64 = @intCast(u64, (15 - i) * 4);
        buf[i] = hexChar((v >> sh) & 15);
    }
    std.io.write(buf[0..16]);
    std.io.write("\n");
}

fn crossMain() void {
    var buf: [1024]u8 = undefined;
    while (true) {
        const line_opt = stdin.readLine(buf[0..]) catch {
            return;
        };
        if (line_opt) |line| {
            var pos: usize = 0;
            const dim_s = nextToken(line[0..], &pos) orelse {
                continue;
            };
            const seed_s = nextToken(line[0..], &pos) orelse {
                continue;
            };
            const x_s = nextToken(line[0..], &pos) orelse {
                continue;
            };
            const y_s = nextToken(line[0..], &pos) orelse {
                continue;
            };
            const dim = parse.parseUint(dim_s) orelse {
                continue;
            };
            const seed = parse.parseUint64(seed_s) orelse {
                continue;
            };
            const x = parse.parseFloat(x_s) orelse {
                continue;
            };
            const y = parse.parseFloat(y_s) orelse {
                continue;
            };
            var n = noise.opensimplexInit(seed);
            if (dim == 2) {
                writeHex16(bitsOf(noise.noise2d(&n, x, y)));
            } else if (dim == 3) {
                const z_s = nextToken(line[0..], &pos) orelse {
                    continue;
                };
                const z = parse.parseFloat(z_s) orelse {
                    continue;
                };
                writeHex16(bitsOf(noise.noise3d(&n, x, y, z)));
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
        std.io.write("noise cross ok\n");
    }
}
