// stdlib_file_seek_xmod — STDLIB std_file (L3) seek GREEN fixture.
//
// Contract (blueprint §3 L3): seek(f, offset, whence) FileError!i64 returns the
// resulting absolute offset for Set/Cur/End.
//
// GREEN (contract): deterministic byte-exact stdout `file seek ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    f.writeAll("t_seek.txt", "abcdef") catch @panic("setup writeAll");
    var file = f.open(&g_arena, "t_seek.txt", f.Mode.Read) catch @panic("open");

    var pos = f.seek(&file, @intCast(i64, 3), f.SeekWhence.Set) catch @panic("seek set");
    ck(pos == 3, "seek set pos");
    var buf: [8]u8 = undefined;
    var n = f.read(&file, buf[0..]) catch @panic("read");
    ck(n == 3, "read count");
    ck(buf[0] == 'd', "read d");

    pos = f.seek(&file, @intCast(i64, -2), f.SeekWhence.End) catch @panic("seek end");
    ck(pos == 4, "seek end pos");

    pos = f.seek(&file, @intCast(i64, 1), f.SeekWhence.Cur) catch @panic("seek cur");
    ck(pos == 5, "seek cur pos");

    f.close(&file);
    f.remove("t_seek.txt") catch {};
    io.write("file seek ok\n");
}
