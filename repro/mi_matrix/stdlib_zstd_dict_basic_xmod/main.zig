// stdlib_zstd_dict_basic_xmod — std_zstd (L4) RFC 8878 magic-dictionary GREEN.
//
// Covers: an RFC-format dictionary (magic 0xEC30A437 + id + Huffman/FSE tables
// + content) produced by libzstd; the dict-id-bearing frame decodes only
// through the additive `zstdDecompressDict` entry point. The existing
// `zstdDecompress` entry must keep rejecting dictionary frames with
// error.Corrupt.
//
// GREEN (contract): deterministic byte-exact stdout `zstd dict basic ok\n`
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
    expectBytes(data.frame_slice(), data.dict_slice(), data.want_slice(), 21,
                "magic dict frame");
    expectCorrupt(data.frame_slice(), 21, "no-dict API rejects dict frame");
    expectCorrupt(data.frame_slice()[0..4], 21, "magic-only truncation");
    io.write("zstd dict basic ok\n");
}
