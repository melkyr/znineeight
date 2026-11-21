// stdlib_deflate_multiblock_xmod -- std_deflate (L4) multi-block fixture.
//
// The stream starts with a BFINAL=0 stored block, continues with a BFINAL=0
// fixed-Huffman block (plus zlib's sync-flush empty stored block), and ends
// with a BFINAL=1 fixed block. A decoder that mishandles `while (!final)` stops
// after the first block and fails the exact-output check.
//
// GREEN: deterministic byte-exact stdout `deflate multiblock ok\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn expectZ(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    ckBytes(g_dst[0..@intCast(usize, n)], want, what);
}

fn expectRaw(src: []const u8, want: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, g_dst[0..], &used) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    ck(used == src.len, what);
    ckBytes(g_dst[0..@intCast(usize, n)], want, what);
}

pub fn main() void {
    expectZ(fx.mb_zlib_slice(), fx.mb_out_slice(), "multiblock zlib");
    expectRaw(fx.mb_raw_slice(), fx.mb_out_slice(), "multiblock raw");

    io.write("deflate multiblock ok\n");
}
