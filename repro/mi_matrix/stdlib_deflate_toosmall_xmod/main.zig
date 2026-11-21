// stdlib_deflate_toosmall_xmod -- std_deflate (L4) OutputTooSmall fixture.
//
// Both entry points are given a valid generated stream and a destination that
// cannot hold the decoded payload. Each must return error.OutputTooSmall.
//
// GREEN: deterministic byte-exact stdout `deflate too small ok\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

fn expectTooSmallZ(src: []const u8, dst: []u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, dst, &used) catch |e| {
        if (e == error.OutputTooSmall) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

fn expectTooSmallRaw(src: []const u8, dst: []u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, dst, &used) catch |e| {
        if (e == error.OutputTooSmall) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    var small: [16]u8 = undefined;
    expectTooSmallZ(fx.ts_zlib_slice(), small[0..], "zlib too small");
    expectTooSmallRaw(fx.ts_raw_slice(), small[0..], "raw too small");

    io.write("deflate too small ok\n");
}
