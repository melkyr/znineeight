// stdlib_stream_readlinesync_xmod — Plan B Task 4 (L6) blocking readFileLineSync.
//
// Contract: readFileLineSync blocks (no suspension, no coroutine); it strips the
// terminating \n and the \r of \r\n, returns a slice into the caller buffer,
// returns the final unterminated line, and returns null at EOF with no partial
// line. It is a SEPARATE implementation from readFileLineAsync (operator ruling
// m1449/m1451): the sync path never pulls the async runtime.
//
// GREEN: bracketed lines showing the CRLF strip, the empty line, and the final
// unterminated line; an empty file yields null; `done`; RUNRC=0.
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
    f.writeAll("t_stream_e.txt", "a\r\nb\n\nc") catch @panic("setup");
    f.writeAll("t_stream_f.txt", "") catch @panic("setup empty");
    var file = f.open(&g_arena, "t_stream_e.txt", f.Mode.Read) catch @panic("open");
    var rbuf: [16]u8 = undefined;
    var lr = st.initFileLineReader(&file, rbuf[0..]);

    while (true) {
        const m = st.readFileLineSync(&lr) catch @panic("readFileLineSync");
        if (m) |line| {
            show(line);
        } else {
            break;
        }
    }

    var empty = f.open(&g_arena, "t_stream_f.txt", f.Mode.Read) catch @panic("open empty");
    var ebuf: [16]u8 = undefined;
    var elr = st.initFileLineReader(&empty, ebuf[0..]);
    const e = st.readFileLineSync(&elr) catch @panic("readFileLineSync empty");
    if (e) |_| @panic("empty file returned a line");

    f.close(&file);
    f.close(&empty);
    f.remove("t_stream_e.txt") catch {};
    f.remove("t_stream_f.txt") catch {};
    io.write("done\n");
}
