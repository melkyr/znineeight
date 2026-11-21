// stdlib_http_percentencode_xmod — STDLIB std_http (M0 §4.3) percentEncode.
//
// Encodes 20 raw bytes including NUL, '/', '+', space and 0x80, exercising the
// unreserved passthrough set [A-Za-z0-9._~-] and the `%` + uppercase-hex escape
// for everything else (required for raw info_hash / peer_id in announce URLs).
//
// GREEN: deterministic byte-exact stdout (rc 0).
const std = @import("std");
const http = @import("std_http.zig");
const io = @import("std_io.zig");

pub fn main() void {
    var ar_storage: [256]u8 = undefined;
    var ar = std.arena.init(ar_storage[0..]);

    var raw: [20]u8 = undefined;
    raw[0] = 'A';
    raw[1] = 'z';
    raw[2] = '0';
    raw[3] = '9';
    raw[4] = '.';
    raw[5] = '_';
    raw[6] = '~';
    raw[7] = '-';
    raw[8] = 0;
    raw[9] = '/';
    raw[10] = '+';
    raw[11] = ' ';
    raw[12] = 0x80;
    raw[13] = ':';
    raw[14] = '?';
    raw[15] = '=';
    raw[16] = '&';
    raw[17] = '%';
    raw[18] = 0x1F;
    raw[19] = '@';

    var src: []const u8 = raw[0..];
    const enc = http.percentEncode(&ar, src) catch @panic("encode");
    io.write("encoded ");
    io.write(enc);
    io.write("\n");
}
