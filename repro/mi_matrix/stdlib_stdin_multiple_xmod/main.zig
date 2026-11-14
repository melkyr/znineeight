// stdlib_stdin_multiple_xmod — Plan B hardening Task 5a-I: exact-multiple
// long-line RED pin for std_stdin.readLine (L3).
//
// Contract (blueprint §3 L3, clarified 5a-I): a line whose length is an exact
// multiple of buf.len must NOT yield a trailing empty line. "abcd\n" read
// through a 4-byte buffer returns "abcd" for the overflow call; the following
// readLine consumes the line's own '\n' terminator and returns the NEXT line
// ("z"), not an empty line.
//
// RED before Task 5a-F: the current compiler returns ["abcd", "", "z"] (the
// exact-multiple boundary is misread as a new empty line), so the second
// expectLine traps -> rc=133 SIGTRAP.
//
// GREEN (desired): lines are exactly "abcd" then "z", then null; stdout
// `stdin multiple ok\n`, rc=0.
//
// Deterministic stdin: the fixture writes its input to a CWD-relative file and
// dup2()s it onto fd 0 before the first read (the gate runs with no stdin).
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
    var name: []const u8 = "t_stdin_multiple.txt";
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
    // "abcd\n" is an exact multiple of the 4-byte buffer; "z\n" then fits.
    feed("abcd\nz\n");

    var buf: [4]u8 = undefined;
    expectLine(buf[0..], "abcd", "exact-multiple first line");
    expectLine(buf[0..], "z", "exact-multiple next line (no spurious empty)");
    ck((stdin.readLine(buf[0..]) catch @panic("multiple EOF")) == null, "multiple EOF null");

    io.write("stdin multiple ok\n");
}
