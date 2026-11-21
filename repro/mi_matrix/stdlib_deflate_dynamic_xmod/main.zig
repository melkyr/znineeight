// stdlib_deflate_dynamic_xmod -- std_deflate (L4) dynamic-block fixture.
//
// The streams are real zlib output whose first DEFLATE block is dynamic
// (BTYPE=2): the code-length alphabet, literal/length alphabet and distance
// alphabet are all rebuilt from the per-block header. Exact output is checked.
//
// GREEN: deterministic byte-exact stdout `deflate dynamic ok\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn expectZ(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(g_dst[i] == want[i], what);
    }
}

pub fn main() void {
    expectZ(fx.dyn_lorem_slice(), fx.dyn_lorem_out_slice(), "dynamic lorem");
    expectZ(fx.dyn_english_slice(), fx.dyn_english_out_slice(), "dynamic english");

    io.write("deflate dynamic ok\n");
}
