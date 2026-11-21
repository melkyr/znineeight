// stdlib_deflate_zlib_basic_xmod -- std_deflate (L4) RFC 1950 fixture.
//
// Covers zlib-wrapped stored, fixed-Huffman and dynamic-Huffman blocks, verifies
// the exact output bytes and that `used` equals the whole stream (wrapper
// included), and pins error.OutputTooSmall when dst cannot hold the output.
//
// GREEN: deterministic byte-exact stdout `deflate zlib basic ok\n` (rc 0).
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

fn expectTooSmall(src: []const u8, dst: []u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, dst, &used) catch |e| {
        if (e == error.OutputTooSmall) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    expectZ(fx.z_stored_slice(), fx.z_stored_out_slice(), "zlib stored");
    expectZ(fx.z_fixed_slice(), fx.z_fixed_out_slice(), "zlib fixed");
    expectZ(fx.z_dynamic_slice(), fx.z_dynamic_out_slice(), "zlib dynamic");

    var small: [8]u8 = undefined;
    expectTooSmall(fx.z_dynamic_slice(), small[0..], "zlib dynamic too small");

    io.write("deflate zlib basic ok\n");
}
