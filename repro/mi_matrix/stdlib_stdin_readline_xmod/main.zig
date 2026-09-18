// stdlib_stdin_readline_xmod — STDLIB std_stdin (L3) readLine GREEN fixture.
//
// Contract (blueprint §3 L3): readLine(buf) ?[]u8 reads one line from process
// stdin, strips a trailing \n (and the \r of \r\n), returns a slice INTO buf
// (no allocation), and returns null at EOF with no partial line.
//
// Deterministic stdin: the runtime gate runs with no stdin, so the fixture
// writes its input to a CWD-relative file and dup2()s it onto fd 0 before the
// first readLine; the run then reads its own bytes regardless of the harness.
//
// GREEN (contract): deterministic byte-exact stdout `stdin readline ok\n`.
const stdin = @import("std_stdin.zig");
const f = @import("std_file.zig");
const io = @import("std_io.zig");

@cInclude("<fcntl.h>");
@cInclude("<unistd.h>");
extern "c" fn open(path: [*]const u8, flags: i32, mode: i32) i32;
extern "c" fn dup2(oldfd: i32, newfd: i32) i32;
extern "c" fn close(fd: i32) i32;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn feed(data: []const u8) void {
    var name: []const u8 = "t_stdin_readline.txt";
    f.writeAll(name, data) catch @panic("setup writeAll");
    var cbuf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < name.len) : (i += 1) cbuf[i] = name[i];
    cbuf[name.len] = 0;
    const fd = open(@ptrCast([*]const u8, &cbuf[0]), 0, 0);
    if (fd < 0) @panic("setup open");
    if (dup2(fd, 0) < 0) @panic("setup dup2");
    _ = close(fd);
}

pub fn main() void {
    feed("hello\n");

    var buf: [16]u8 = undefined;
    var got: []u8 = undefined;
    if (stdin.readLine(buf[0..])) |line| {
        got = line;
    } else {
        @panic("readline line1");
    }
    ck(got.len == 5, "line1 length");
    ck(got[0] == 'h', "line1 first");
    ck(got[4] == 'o', "line1 last");

    // The returned slice aliases buf (no copy): a write through it is visible
    // in buf.
    got[0] = 'H';
    ck(buf[0] == 'H', "readline slice into buf");

    // No second line and no partial: null at EOF.
    ck(stdin.readLine(buf[0..]) == null, "readline EOF null");

    io.write("stdin readline ok\n");
}
