// stdlib_stdin_readall_xmod — STDLIB std_stdin (L3) readAll GREEN fixture.
//
// Contract (blueprint §3 L3): readAll(arena) ![]u8 reads all of process stdin
// and returns it as one arena-allocated slice; the only error is OutOfMemory
// (R1/§6 arena gate).
//
// Deterministic stdin: the runtime gate runs with no stdin, so the fixture
// writes its input to a CWD-relative file and dup2()s it onto fd 0 before the
// first read.
//
// GREEN (contract): deterministic byte-exact stdout `stdin readall ok\n`.
const stdin = @import("std_stdin.zig");
const f = @import("std_file.zig");
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
    var name: []const u8 = "t_stdin_readall.txt";
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

fn oomReadAll(ar: *arena_mod.Arena) bool {
    _ = stdin.readAll(ar) catch |e| {
        if (e == error.OutOfMemory) return true;
        return false;
    };
    return false;
}

pub fn main() void {
    feed("abc\ndef\n");

    var got = stdin.readAll(&g_arena) catch @panic("readAll");
    ck(got.len == 8, "readAll length");
    ck(got[0] == 'a', "readAll first");
    ck(got[3] == '\n', "readAll newline kept");
    ck(got[7] == '\n', "readAll last");

    // Arena gate (spec §6): an arena too small for readAll's first allocation
    // reports exactly OutOfMemory and is left untouched (used == 0).
    var tiny_storage: [8]u8 = undefined;
    var tiny = arena_mod.init(tiny_storage[0..]);
    ck(oomReadAll(&tiny), "readAll OutOfMemory");
    ck(tiny.used == 0, "readAll OOM no arena use");

    io.write("stdin readall ok\n");
}
