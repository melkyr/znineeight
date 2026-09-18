// stdlib_stdin_stress_xmod — STDLIB std_stdin (L3) hand-written stress table.
//
// No PRNG: every input is an explicit, deterministic table. Deterministic
// stdin: the fixture writes each input to a CWD-relative file and dup2()s it
// onto fd 0 before reading (the gate runs with no stdin).
//
// Stresses:
//   - long lines across the buffer-overflow boundary: a 4321-byte line read
//     through a 100-byte buffer yields 43 full 100-byte chunks, then a 21-byte
//     remainder (4321 % 100 != 0, so the terminator is consumed in the last
//     chunk and no spurious empty line is produced).
//   - a short line, a CRLF line (the \r is stripped), and a final line with NO
//     trailing newline (returned by the EOF path, not dropped).
//   - the readAll doubling growth: a 10000-byte explicit pattern crosses the
//     4096-byte READ_CHUNK boundary twice (4096 -> 8192 -> 16384) and must
//     round-trip byte-exact.
//
// GREEN (contract): deterministic byte-exact stdout `stdin stress ok\n` (rc 0).
const stdin = @import("std_stdin.zig");
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

@cInclude("<fcntl.h>");
@cInclude("<unistd.h>");
extern "c" fn open(path: [*]const u8, flags: i32, mode: i32) i32;
extern "c" fn dup2(oldfd: i32, newfd: i32) i32;
extern "c" fn close(fd: i32) i32;

const LINE_BUF: usize = 100;
const LONG_LEN: usize = 4321;
const ALL_LEN: usize = 10000;

var g_storage: [131072]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn feed(name: []const u8, data: []const u8) void {
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

fn expectCharLine(buf: []u8, ch: u8, len: usize, what: []const u8) void {
    if (stdin.readLine(buf) catch @panic(what)) |line| {
        ck(line.len == len, what);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            ck(line[i] == ch, what);
        }
    } else {
        @panic(what);
    }
}

pub fn main() void {
    // --- long line + CRLF + EOF-without-newline -----------------------------
    var in: [8192]u8 = undefined;
    var n: usize = 0;
    var i: usize = 0;
    while (i < LONG_LEN) : (i += 1) {
        in[n] = 'a';
        n += 1;
    }
    in[n] = '\n';
    n += 1;
    in[n] = 'b';
    n += 1;
    in[n] = '\n';
    n += 1;
    in[n] = 'c';
    n += 1;
    in[n] = 'd';
    n += 1;
    in[n] = '\r';
    n += 1;
    in[n] = '\n';
    n += 1;
    in[n] = 'e';
    n += 1;
    in[n] = 'f';
    n += 1;
    in[n] = 'g';
    n += 1;
    in[n] = 'h';
    n += 1;
    feed("t_stdin_stress_a.txt", in[0..n]);

    var buf: [LINE_BUF]u8 = undefined;
    var k: usize = 0;
    while (k < LONG_LEN / LINE_BUF) : (k += 1) {
        expectCharLine(buf[0..], 'a', LINE_BUF, "long line full chunk");
    }
    expectCharLine(buf[0..], 'a', LONG_LEN % LINE_BUF, "long line remainder");
    expectLine(buf[0..], "b", "short line");
    expectLine(buf[0..], "cd", "CRLF line stripped");
    expectLine(buf[0..], "efgh", "EOF without trailing newline");
    ck((stdin.readLine(buf[0..]) catch @panic("eof null")) == null, "EOF null");

    // --- readAll doubling growth over an explicit 10000-byte pattern --------
    var big: [ALL_LEN]u8 = undefined;
    i = 0;
    while (i < ALL_LEN) : (i += 1) {
        big[i] = @intCast(u8, (i * 13 + 5) % 256);
    }
    feed("t_stdin_stress_b.txt", big[0..ALL_LEN]);
    var all = stdin.readAll(&g_arena) catch @panic("readAll");
    ck(all.len == ALL_LEN, "readAll length");
    i = 0;
    while (i < ALL_LEN) : (i += 1) {
        ck(all[i] == big[i], "readAll byte");
    }

    io.write("stdin stress ok\n");
}
