// stdlib_zstd_dict_mismatch_xmod — std_zstd (L4) RFC 8878 dict-id rejection.
//
// Covers: a frame carrying a nonzero dictionary id must raise error.Corrupt
// (a) through the no-dict entry point, (b) through zstdDecompressDict with a
// magic dictionary whose id differs, and (c) through zstdDecompressDict with a
// raw-content dictionary (raw dictionaries are legal for dict-id-0 frames
// only). expected.txt/expected.rc pin the success line; expected_error.txt is
// documentation only.
//
// GREEN (contract): catch error.Corrupt on every path and emit deterministic
// byte-exact stdout `zstd dict mismatch ok\n` (rc 0).
const io = @import("std_io.zig");
const zstd = @import("std_zstd.zig");
const data = @import("data.zig");

var g_dst: [65536]u8 = undefined;

fn expectNoDictCorrupt(src: []const u8, what: []const u8) void {
    const n = zstd.zstdDecompress(src, g_dst[0..], 21) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

fn expectDictCorrupt(src: []const u8, dict: []const u8, what: []const u8) void {
    const n = zstd.zstdDecompressDict(src, g_dst[0..], dict, 21) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    expectNoDictCorrupt(data.frame_slice(), "no-dict API accepted dict frame");
    expectDictCorrupt(data.frame_slice(), data.wrong_dict_slice(),
                      "wrong magic dictionary id accepted");
    expectDictCorrupt(data.frame_slice(), data.raw_dict_slice(),
                      "raw dict accepted for nonzero frame id");
    io.write("zstd dict mismatch ok\n");
}
