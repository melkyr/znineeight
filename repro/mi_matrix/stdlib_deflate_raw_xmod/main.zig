// stdlib_deflate_raw_xmod -- std_deflate (L4) RFC 1951 raw fixture.
//
// Covers raw (unwrapped) stored, fixed-Huffman and dynamic-Huffman blocks and
// verifies exact output bytes and `used == src.len`.
//
// GREEN: deterministic byte-exact stdout `deflate raw ok\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn expectRaw(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, g_dst[0..], &used) catch {
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
    expectRaw(fx.raw_stored_slice(), fx.raw_stored_out_slice(), "raw stored");
    expectRaw(fx.raw_fixed_slice(), fx.raw_fixed_out_slice(), "raw fixed");
    expectRaw(fx.raw_dynamic_slice(), fx.raw_dynamic_out_slice(), "raw dynamic");

    io.write("deflate raw ok\n");
}
