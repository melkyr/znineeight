// stdlib_stdin_overflow_xmod — STDLIB std_stdin (L3) buffer-overflow GREEN
// fixture (blueprint §3 L3 named shape: buffer overflow behavior).
//
// Contract: readLine never writes past buf. When a line is longer than buf it
// returns a full buf (the line's prefix, no newline) and leaves the remainder
// of the line in the stream for the next readLine; the call after the last
// line returns null.
//
// Deterministic stdin: the fixture writes its input to a CWD-relative file and
// dup2()s it onto fd 0 before the first read (the gate runs with no stdin).
//
// GREEN (contract): deterministic byte-exact stdout `stdin overflow ok\n`.
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
    var name: []const u8 = "t_stdin_overflow.txt";
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
    // "abcdef\n" overflows a 4-byte buffer into "abcd" + "ef"; "xy\n" then
    // fits normally.
    feed("abcdef\nxy\n");

    var buf: [4]u8 = undefined;
    expectLine(buf[0..], "abcd", "overflow prefix");
    expectLine(buf[0..], "ef", "overflow remainder");
    expectLine(buf[0..], "xy", "overflow next line");
    ck(stdin.readLine(buf[0..]) == null, "overflow EOF null");

    io.write("stdin overflow ok\n");
}
