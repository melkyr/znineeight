// stdlib_zstd_dict_entropy_xmod — std_zstd (L4) RFC 8878 dict entropy tables.
//
// Covers: a frame whose first compressed block actually consumes the magic
// dictionary's entropy tables. libzstd emits Treeless literals (reusing the
// dictionary Huffman table) and Repeat match-length mode (reusing the
// dictionary ML FSE table); the generator asserts those block-mode bytes so
// this fixture cannot silently regress to Raw/predefined tables.
//
// GREEN (contract): deterministic byte-exact stdout `zstd dict entropy ok\n`
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
                "dict entropy frame");
    expectCorrupt(data.frame_slice(), 21, "no-dict API rejects dict frame");
    io.write("zstd dict entropy ok\n");
}
