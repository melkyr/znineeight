// stdlib_stdin_crlf_boundary_xmod — STDLIB std_stdin (L3) CRLF-at-buffer-
// boundary GREEN fixture.
//
// Contract: when a `\r` lands as the last byte of a full buffer and the `\n` is
// the next unread byte, the CRLF is consumed as ONE terminator: the returned
// line has no `\r` and the next call does NOT return a spurious empty line.
//
// Deterministic stdin: the fixture writes its input to a CWD-relative file and
// dup2()s it onto fd 0 before the first read (the gate runs with no stdin).
//
// GREEN (contract): deterministic byte-exact stdout `stdin crlf boundary ok\n`.
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
    var name: []const u8 = "t_stdin_crlf_boundary.txt";
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
    if (stdin.readLine(buf) catch @panic(what)) |line| {
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
    // "ab\r\ncd\n" into a 3-byte buffer: the `\r` is the last byte of the first
    // full buffer (a, b, \r), so its `\n` must be consumed as the same CRLF.
    // Before the fix this returned "ab\r", then "" (spurious empty), then "cd".
    feed("ab\r\ncd\n");

    var buf: [3]u8 = undefined;
    expectLine(buf[0..], "ab", "crlf boundary first line");
    expectLine(buf[0..], "cd", "crlf boundary second line (no spurious empty)");
    ck((stdin.readLine(buf[0..]) catch @panic("crlf boundary EOF")) == null, "crlf boundary EOF null");

    io.write("stdin crlf boundary ok\n");
}
