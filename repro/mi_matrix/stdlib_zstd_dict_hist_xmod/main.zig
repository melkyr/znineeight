// stdlib_zstd_dict_hist_xmod — std_zstd (L4) RFC 8878 dictionary history.
//
// Covers: frames whose first sequence is a match into the dictionary content
// at the window boundary. The payload is exactly the last 2^window_log bytes
// of the dictionary content, so the match offset equals the window size:
//   2^10 = 1024 at max_window_log 10, and 2^11 = 2048 at max_window_log 11.
// A cap below the frame window must still be WindowTooBig.
//
// GREEN (contract): deterministic byte-exact stdout `zstd dict hist ok\n`
// (rc 0).
const io = @import("std_io.zig");
const zstd = @import("std_zstd.zig");
const data = @import("data.zig");

var g_dst: [65536]u8 = undefined;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn checkTail(src: []const u8, dict: []const u8, tail_len: usize,
             max_log: u8, what: []const u8) void {
    const n = zstd.zstdDecompressDict(src, g_dst[0..], dict, max_log) catch {
        @panic(what);
    };
    ck(@intCast(usize, n) == tail_len, what);
    const tail = dict[dict.len - tail_len..];
    var i: usize = 0;
    while (i < tail_len) : (i += 1) {
        ck(g_dst[i] == tail[i], what);
    }
}

fn expectWindowTooBig(src: []const u8, dict: []const u8, max_log: u8,
                      what: []const u8) void {
    const n = zstd.zstdDecompressDict(src, g_dst[0..], dict, max_log) catch |e| {
        if (e == error.WindowTooBig) return;
        @panic(what);
    };
    _ = n;
    @panic(what);
}

pub fn main() void {
    const dict = data.dict_slice();
    checkTail(data.frame_w10_slice(), dict, 1024, 21, "dict history window 10");
    checkTail(data.frame_w11_slice(), dict, 2048, 21, "dict history window 11");
    expectWindowTooBig(data.frame_w11_slice(), dict, 10, "window cap below frame");
    io.write("zstd dict hist ok\n");
}
