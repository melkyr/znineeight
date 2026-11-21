// stdlib_file_read_xmod — STDLIB std_file (L3) read + EOF GREEN fixture.
//
// Contract (blueprint §3 L3): read(f, buf) FileError!usize returns the bytes
// read; 0 at EOF (not an error). A short read of a regular file is allowed.
//
// GREEN (contract): deterministic byte-exact stdout `file read ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.writeAll("t_read.txt", "hello world") catch @panic("setup writeAll");
    var file = f.open(&g_arena, "t_read.txt", f.Mode.Read) catch @panic("open");

    var buf: [16]u8 = undefined;
    var n = f.read(&file, buf[0..5]) catch @panic("read1");
    ck(n == 5, "read1 count");
    ck(buf[0] == 'h', "read1 h");
    ck(buf[4] == 'o', "read1 o");

    n = f.read(&file, buf[0..16]) catch @panic("read2");
    ck(n == 6, "read2 count");
    ck(buf[0] == ' ', "read2 space");
    ck(buf[5] == 'd', "read2 d");

    n = f.read(&file, buf[0..16]) catch @panic("read3");
    ck(n == 0, "read3 EOF zero");

    f.close(&file);
    f.remove("t_read.txt") catch {};
    io.write("file read ok\n");
}
