// stdlib_deflate_corrupt_xmod -- std_deflate (L4) malformed-input fixture.
//
// Every case must surface error.Corrupt (not a crash, not a silent success):
// bad FCHECK, FDICT (unsupported dictionary), bad Adler-32, truncated zlib,
// bad CM, truncated raw, and a reserved block type. The program catches and
// prints a deterministic success line, so expected.rc is 0.
//
// GREEN: deterministic byte-exact stdout `deflate corrupt rejected\n` (rc 0).
const io = @import("std_io.zig");
const deflate = @import("std_deflate.zig");
const fx = @import("fixtures_data.zig");

var g_dst: [65536]u8 = undefined;

fn expectCorruptZ(src: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateZlib(src, g_dst[0..], &used) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

fn expectCorruptRaw(src: []const u8, what: []const u8) void {
    var used: usize = 0;
    const n = deflate.inflateRaw(src, g_dst[0..], &used) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    expectCorruptZ(fx.corrupt_bad_fcheck_slice(), "bad fcheck");
    expectCorruptZ(fx.corrupt_fdict_slice(), "fdict");
    expectCorruptZ(fx.corrupt_bad_adler_slice(), "bad adler");
    expectCorruptZ(fx.corrupt_truncated_slice(), "truncated zlib");
    expectCorruptZ(fx.corrupt_bad_cm_slice(), "bad cm");
    expectCorruptRaw(fx.corrupt_raw_truncated_slice(), "truncated raw");
    expectCorruptRaw(fx.corrupt_raw_reserved_slice(), "reserved block type");

    io.write("deflate corrupt rejected\n");
}
