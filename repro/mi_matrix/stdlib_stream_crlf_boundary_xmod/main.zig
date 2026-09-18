// stdlib_stream_crlf_boundary_xmod — Plan B Task 4 (L6) CRLF-at-buffer-boundary
// GREEN fixture for the blocking readLineSync reader.
//
// Contract: when a `\r` lands as the last byte of a full overflow buffer,
// takeOverflow strips it and carries it; the next read consumes the following
// `\n` as the same CRLF terminator, so the returned line has no `\r` and no
// spurious empty line is produced.
//
// GREEN: bracketed lines `[ab]` `[cd]`, then `done`; RUNRC=0.
const f = @import("std_file.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn show(line: []const u8) void {
    io.writeByte('[');
    io.write(line);
    io.writeByte(']');
    io.writeByte('\n');
}

pub fn main() void {
    f.writeAll("t_stream_crlf.txt", "ab\r\ncd\n") catch @panic("setup");
    var file = f.open(&g_arena, "t_stream_crlf.txt", f.Mode.Read) catch @panic("open");
    var rbuf: [3]u8 = undefined;
    var lr = st.initFileLineReader(&file, rbuf[0..]);

    const a = st.readLineSync(&lr) catch @panic("readLineSync first");
    if (a) |line| {
        show(line);
    } else {
        @panic("first line missing");
    }
    const b = st.readLineSync(&lr) catch @panic("readLineSync second");
    if (b) |line| {
        show(line);
    } else {
        @panic("second line missing");
    }
    const c = st.readLineSync(&lr) catch @panic("readLineSync third");
    if (c) |_| @panic("spurious line at EOF");

    f.close(&file);
    f.remove("t_stream_crlf.txt") catch {};
    io.write("done\n");
}
