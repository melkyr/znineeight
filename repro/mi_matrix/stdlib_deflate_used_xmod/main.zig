// stdlib_deflate_used_xmod -- std_deflate (L4) consumed-input fixture.
//
// Two independent zlib streams are concatenated. Decoding the first must report
// exactly its own byte length in `used` (wrapper bytes included) so a caller can
// start the second stream at src[used..]. Both exact output lengths and both
// exact `used` values are asserted (Review Focus 2).
//
// GREEN: deterministic byte-exact stdout `deflate used ok\n` (rc 0).
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

pub fn main() void {
    const all = fx.used_concat_slice();
    const first = fx.used_first_slice();
    const second = fx.used_second_slice();
    const expect1 = fx.used_first_len();
    const expect2 = fx.used_second_len();
    const out1 = fx.used_first_out_len();
    const out2 = fx.used_second_out_len();

    var used1: usize = 0;
    const n1 = deflate.inflateZlib(all[0..], g_dst[0..], &used1) catch {
        @panic("first stream");
    };
    ck(@intCast(usize, n1) == out1, "first output length");
    ck(used1 == expect1, "first used exact");
    ck(used1 == first.len, "first used slice length");
    ckBytes(g_dst[0..@intCast(usize, n1)], fx.used_first_out_slice(), "first output bytes");

    var used2: usize = 0;
    const n2 = deflate.inflateZlib(all[used1..], g_dst[0..], &used2) catch {
        @panic("second stream");
    };
    ck(@intCast(usize, n2) == out2, "second output length");
    ck(used2 == expect2, "second used exact");
    ck(used2 == second.len, "second used slice length");
    ckBytes(g_dst[0..@intCast(usize, n2)], fx.used_second_out_slice(), "second output bytes");
    ck(used1 + used2 == all.len, "concat consumed");

    io.write("deflate used ok\n");
}
