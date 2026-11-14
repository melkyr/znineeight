// stdlib_stream_crlf_boundary_xmod — Plan B Task 4 (L6) CRLF-at-buffer-boundary
// GREEN fixture for the blocking readFileLineSync reader.
//
// Contract: when a `\r` lands as the last byte of a full overflow buffer,
// takeOverflow strips it and carries it; the next read consumes the following
// `\n` as the same CRLF terminator, so the returned line has no `\r` and no
// spurious empty line is produced. A 1-byte buffer keeps a literal `\r` (the
// carry is disabled there) so a following non-`\n` byte is never lost.
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

// Silent exact-line assertion (keeps the golden stable).
fn expectSync(lr: *st.FileLineReader, want: []const u8, what: []const u8) void {
    const m = st.readFileLineSync(lr) catch @panic(what);
    if (m) |line| {
        if (line.len != want.len) @panic(what);
        var i: usize = 0;
        while (i < want.len) : (i += 1) {
            if (line[i] != want[i]) @panic(what);
        }
    } else {
        @panic(what);
    }
}

pub fn main() void {
    f.writeAll("t_stream_crlf.txt", "ab\r\ncd\n") catch @panic("setup");
    var file = f.open(&g_arena, "t_stream_crlf.txt", f.Mode.Read) catch @panic("open");
    var rbuf: [3]u8 = undefined;
    var lr = st.initFileLineReader(&file, rbuf[0..]);

    const a = st.readFileLineSync(&lr) catch @panic("readFileLineSync first");
    if (a) |line| {
        show(line);
    } else {
        @panic("first line missing");
    }
    const b = st.readFileLineSync(&lr) catch @panic("readFileLineSync second");
    if (b) |line| {
        show(line);
    } else {
        @panic("second line missing");
    }
    const c = st.readFileLineSync(&lr) catch @panic("readFileLineSync third");
    if (c) |_| @panic("spurious line at EOF");

    f.close(&file);
    f.remove("t_stream_crlf.txt") catch {};

    // 1-byte buffer: a literal CR before a non-\n byte must not be dropped.
    f.writeAll("t_stream_crlf1.txt", "a\rX\n") catch @panic("setup1");
    var file1 = f.open(&g_arena, "t_stream_crlf1.txt", f.Mode.Read) catch @panic("open1");
    var rbuf1: [1]u8 = undefined;
    var lr1 = st.initFileLineReader(&file1, rbuf1[0..]);
    expectSync(&lr1, "a", "1buf a");
    expectSync(&lr1, "\r", "1buf literal CR kept");
    expectSync(&lr1, "X", "1buf X not lost");
    expectSync(&lr1, "", "1buf empty line");
    if ((st.readFileLineSync(&lr1) catch @panic("1buf eof")) != null) @panic("1buf spurious line");
    f.close(&file1);
    f.remove("t_stream_crlf1.txt") catch {};

    io.write("done\n");
}
