// stdlib_stream_multiple_xmod — Plan B hardening Task 5a-I: exact-multiple
// long-line RED pin for std_stream.readFileLineSync (L6).
//
// Contract (blueprint §3 L6, clarified 5a-I): a line whose length is an exact
// multiple of buf.len must NOT yield a trailing empty line. "abcd\n" read
// through a 4-byte FileLineReader buffer returns "abcd" for the overflow call;
// the following readFileLineSync consumes the line's own '\n' terminator and
// returns the NEXT line ("z"), not an empty line.
//
// RED before Task 5a-F: the current compiler returns ["abcd", "", "z"] (the
// exact-multiple boundary is misread as a new empty line), so the second
// ckLine traps -> rc=133 SIGTRAP.
//
// GREEN (desired): lines are exactly "abcd" then "z", then null; stdout
// `stream multiple ok\n`, rc=0.
const f = @import("std_file.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn ckLine(line: []const u8, want: []const u8, what: []const u8) void {
    ck(line.len == want.len, what);
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        ck(line[i] == want[i], what);
    }
}

pub fn main() void {
    // "abcd\n" is an exact multiple of the 4-byte reader buffer; "z\n" fits.
    f.writeAll("t_stream_multiple.txt", "abcd\nz\n") catch @panic("setup");
    var file = f.open(&g_arena, "t_stream_multiple.txt", f.Mode.Read) catch @panic("open");
    var rbuf: [4]u8 = undefined;
    var lr = st.initFileLineReader(&file, rbuf[0..]);

    const first = st.readFileLineSync(&lr) catch @panic("readFileLineSync first");
    if (first) |line| {
        ckLine(line, "abcd", "exact-multiple first line");
    } else {
        @panic("exact-multiple first line null");
    }

    const second = st.readFileLineSync(&lr) catch @panic("readFileLineSync second");
    if (second) |line| {
        ckLine(line, "z", "exact-multiple next line (no spurious empty)");
    } else {
        @panic("exact-multiple next line null");
    }

    const third = st.readFileLineSync(&lr) catch @panic("readFileLineSync third");
    if (third) |_| @panic("exact-multiple EOF returned a line");

    f.close(&file);
    f.remove("t_stream_multiple.txt") catch {};
    io.write("stream multiple ok\n");
}
