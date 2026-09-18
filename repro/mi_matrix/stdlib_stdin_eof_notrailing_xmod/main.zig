// stdlib_stdin_eof_notrailing_xmod — STDLIB std_stdin (L3) EOF-with-no-trailing-
// newline GREEN fixture (blueprint §3 L3 named shape: EOF with no trailing
// newline).
//
// Contract: a final line not terminated by \n is returned as a partial line;
// the next readLine returns null. CRLF input is stripped to the line text.
//
// Deterministic stdin: the fixture writes its input to a CWD-relative file and
// dup2()s it onto fd 0 before the first read (the gate runs with no stdin).
//
// GREEN (contract): deterministic byte-exact stdout `stdin eof notrailing ok\n`.
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
    var name: []const u8 = "t_stdin_eof.txt";
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

fn expectLine(buf: []u8, want: []const u8, what: []const u8) void {
    if (stdin.readLine(buf)) |line| {
        ck(line.len == want.len, what);
        var i: usize = 0;
        while (i < want.len) : (i += 1) {
            ck(line[i] == want[i], what);
        }
    } else {
        @panic(what);
    }
}

pub fn main() void {
    // CRLF lines then a final line with no terminator at all.
    feed("a\r\nb\r\nc");

    var buf: [16]u8 = undefined;
    expectLine(buf[0..], "a", "eof a");
    expectLine(buf[0..], "b", "eof b");
    expectLine(buf[0..], "c", "eof c no trailing newline");
    ck(stdin.readLine(buf[0..]) == null, "eof null");

    io.write("stdin eof notrailing ok\n");
}
