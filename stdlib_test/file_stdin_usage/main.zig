// stdlib_test/file_stdin_usage — Plan B Task 5 (R7b) usage program.
//
// Composes std_file (L3) + std_stdin (L3) into one intended workflow: create a
// text file with std_file, verify it with exists/readAll/size/read/seek, then
// redirect that same file onto fd 0 and consume it line-by-line with
// std_stdin.readLine (CRLF strip, final unterminated line, EOF null).
//
// Deterministic stdin: the gate runs with no stdin, so the program writes its
// input to a CWD-relative file and dup2()s it onto fd 0 before the first read
// (the same pattern as the stdlib_stdin_*_xmod fixtures).
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0):
//   file_stdin_usage
//   exists: 1
//   readall: 14
//   size: 14
//   line: one
//   line: two
//   line: three
//   eof: 1
//   file_stdin ok
// A mismatch calls @panic; the final line is `file_stdin ok` only on success.
const f = @import("std_file.zig");
const stdin = @import("std_stdin.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

@cInclude("<fcntl.h>");
@cInclude("<unistd.h>");
extern "c" fn open(path: [*]const u8, flags: i32, mode: i32) i32;
extern "c" fn dup2(oldfd: i32, newfd: i32) i32;
extern "c" fn close(fd: i32) i32;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn feed(data: []const u8) void {
    var name: []const u8 = "t_file_stdin_usage.txt";
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
    // --- std_file: create + verify the fixture input ------------------------
    var name: []const u8 = "t_file_stdin_usage.txt";
    var data: []const u8 = "one\ntwo\r\nthree";
    f.writeAll(name, data) catch @panic("writeAll");

    var ex: bool = f.exists(name);
    ck(ex, "exists");

    var got = f.readAll(&g_arena, name) catch @panic("readAll");
    ck(got.len == 14, "readAll length");
    ck(got[0] == 'o' and got[3] == '\n' and got[13] == 'e', "readAll bytes");

    var file = f.open(&g_arena, name, f.Mode.Read) catch @panic("open");
    const sz = f.size(&file) catch @panic("size");
    ck(sz == @intCast(i64, 14), "size");
    var fbuf: [4]u8 = undefined;
    const r = f.read(&file, fbuf[0..]) catch @panic("read");
    ck(r == 4, "read 4");
    const sk = f.seek(&file, @intCast(i64, 0), f.SeekWhence.Set) catch @panic("seek");
    ck(sk == 0, "seek 0");
    f.close(&file);

    // --- std_stdin: consume the same file through fd 0 ----------------------
    feed(data);
    var buf: [16]u8 = undefined;
    expectLine(buf[0..], "one", "line one");
    expectLine(buf[0..], "two", "line two CRLF strip");
    expectLine(buf[0..], "three", "line three no trailing newline");
    var eof: bool = (stdin.readLine(buf[0..]) catch @panic("EOF readLine")) == null;
    ck(eof, "EOF null");

    f.remove(name) catch {};

    // --- stdout contract ----------------------------------------------------
    io.write("file_stdin_usage\n");
    io.write("exists: ");
    if (ex) io.printInt(1) else io.printInt(0);
    io.write("\n");
    io.write("readall: ");
    io.printInt(@intCast(i32, got.len));
    io.write("\n");
    io.write("size: ");
    io.printInt(@intCast(i32, sz));
    io.write("\n");
    io.write("line: one\n");
    io.write("line: two\n");
    io.write("line: three\n");
    io.write("eof: ");
    if (eof) io.printInt(1) else io.printInt(0);
    io.write("\n");
    io.write("file_stdin ok\n");
}
