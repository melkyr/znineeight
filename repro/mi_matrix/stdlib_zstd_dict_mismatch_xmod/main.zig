// stdlib_zstd_dict_mismatch_xmod — std_zstd (L4) RFC 8878 dict-id rejection.
//
// Covers: a frame carrying a nonzero dictionary id must remain error.Corrupt
// through the no-dictionary entry point (the supplied `wrong_dict` in data.zig
// has a different id; this fixture intentionally exercises only the existing
// zstdDecompress API, so it is runtime-RED/GREEN without the new symbol).
//
// GREEN (contract): catch error.Corrupt and emit deterministic byte-exact
// stdout `zstd dict mismatch ok\n` (rc 0).
const io = @import("std_io.zig");
const zstd = @import("std_zstd.zig");
const data = @import("data.zig");

var g_dst: [65536]u8 = undefined;

pub fn main() void {
    _ = data.wrong_dict_slice();
    const n = zstd.zstdDecompress(data.frame_slice(), g_dst[0..], 21) catch |e| {
        if (e == error.Corrupt) {
            io.write("zstd dict mismatch ok\n");
            return;
        }
        @panic("wrong error");
    };
    _ = n;
    @panic("dictionary frame accepted by no-dict API");
}
