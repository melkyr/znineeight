// stdlib_zstd_dict_raw_xmod — std_zstd (L4) RFC 8878 raw-content dictionary.
//
// Covers: a dictionary without the 0xEC30A437 header (raw content). It applies
// to dict-id-0 frames only; the frame payload is the last 1024 bytes of the
// dict content, so decoding requires the pre-seeded dictionary history.
//
// GREEN (contract): deterministic byte-exact stdout `zstd dict raw ok\n`
// (rc 0).
const io = @import("std_io.zig");
const zstd = @import("std_zstd.zig");
const data = @import("data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn expectBytes(src: []const u8, dict: []const u8, want: []const u8,
               max_log: u8, what: []const u8) void {
    const n = zstd.zstdDecompressDict(src, g_dst[0..], dict, max_log) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == want.len, what);
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(g_dst[i] == want[i], what);
    }
}

fn expectCorrupt(src: []const u8, max_log: u8, what: []const u8) void {
    const n = zstd.zstdDecompress(src, g_dst[0..], max_log) catch |e| {
        if (e == error.Corrupt) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    const dict = data.dict_slice();
    const want = dict[dict.len - 1024..];
    expectBytes(data.frame_slice(), dict, want, 21, "raw dict frame");
    expectCorrupt(data.frame_slice(), 21, "raw-dict frame without history");
    io.write("zstd dict raw ok\n");
}
