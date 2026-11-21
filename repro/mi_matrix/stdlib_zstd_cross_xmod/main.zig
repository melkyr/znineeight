// stdlib_zstd_cross_xmod — std_zstd (L4) crosscheck driver.
//
// Default mode (fixture gate): deterministic `zstd cross ok\n`.
// `--crosscheck` reads a complete zstd frame from stdin, decodes it with the
// default window cap (21), and writes the decoded bytes verbatim to stdout.
// The committed vectors/std_zstd/<name>.expected files are the frozen decoded
// content produced by the host zstd CLI, so a ref-less three-way check reduces
// to Z98 output == .expected. Decode errors print `corrupt\n` (no vector in the
// committed corpus triggers this).
const arena_mod = @import("std_arena.zig");
const io = @import("std_io.zig");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const zstd = @import("std_zstd.zig");

var g_arena_storage: [1048576]u8 = undefined;
var g_arena = arena_mod.init(g_arena_storage[0..]);
var g_dst: [1048576]u8 = undefined;

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

fn crossMain() void {
    arena_mod.reset(&g_arena);
    const src = stdin.readAll(&g_arena) catch {
        io.write("corrupt\n");
        return;
    };
    const n = zstd.zstdDecompress(src, g_dst[0..], zstd.ZSTD_DEFAULT_WINDOW_LOG) catch {
        io.write("corrupt\n");
        return;
    };
    const len: usize = @intCast(usize, n);
    if (len > 0) io.write(g_dst[0..len]);
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (isCrosscheck()) {
        crossMain();
    } else {
        io.write("zstd cross ok\n");
    }
}
