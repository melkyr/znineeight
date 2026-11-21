// stdlib_file_writeall_xmod — STDLIB std_file (L3) writeAll + binary GREEN.
//
// Contract (blueprint §3 L3): writeAll(path, data) FileError!void writes every
// byte (looping on partial writes). Binary-safe: the payload contains CR, LF,
// and NUL (the blueprint's `\r\n\0` binary round-trip shape).
//
// GREEN (contract): deterministic byte-exact stdout `file writeall ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    var data: [7]u8 = undefined;
    data[0] = 'A';
    data[1] = 13;
    data[2] = 10;
    data[3] = 0;
    data[4] = 'B';
    data[5] = 255;
    data[6] = 0;

    f.writeAll("t_writeall.bin", data[0..]) catch @panic("writeAll");
    var back = f.readAll(&g_arena, "t_writeall.bin") catch @panic("readAll");
    ck(back.len == 7, "roundtrip length");
    ck(back[0] == 'A', "byte A");
    ck(back[1] == 13, "byte CR");
    ck(back[2] == 10, "byte LF");
    ck(back[3] == 0, "byte NUL");
    ck(back[4] == 'B', "byte B");
    ck(back[5] == 255, "byte FF");
    ck(back[6] == 0, "byte trailing NUL");
    f.remove("t_writeall.bin") catch {};
    io.write("file writeall ok\n");
}
