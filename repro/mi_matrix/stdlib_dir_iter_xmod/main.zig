// stdlib_dir_iter_xmod — STDLIB std_file (L3) directory iteration GREEN
// fixture.
//
// Contract (M7 Task 1 / Amendment 1): openDir(arena, path) Dir, readDir(arena,
// d) FileError!?DirEntry (null at end-of-listing), closeDir(d) void. The
// listing is OS order, so the fixture sorts after collection. `.`/`..` are
// returned, not filtered. DirEntry.name is arena-owned and not NUL-terminated.
//
// Setup uses fixture-only libc mkdir/rmdir (std_file deliberately has no
// directory-creation API), matching the stdout/rc contract:
//
// GREEN (contract): deterministic byte-exact stdout `dir iter ok\n` (rc 0).
const f = @import("std_file.zig");
const io = @import("std_io.zig");
const arena_mod = @import("std_arena.zig");

@cInclude("<sys/stat.h>");
@cInclude("<unistd.h>");
extern "c" fn mkdir(path: [*]const u8, mode: i32) i32;
extern "c" fn rmdir(path: [*]const u8) i32;

const MAX_ENTRIES: usize = 16;

var g_storage: [65536]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn cstr(path: []const u8, out: []u8) bool {
    if (path.len >= out.len) return false;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        out[i] = path[i];
    }
    out[path.len] = 0;
    return true;
}

fn mkdirP(path: []const u8) void {
    var b: [256]u8 = undefined;
    if (!cstr(path, b[0..])) @panic("mkdir path");
    if (mkdir(@ptrCast([*]const u8, &b[0]), 511) != 0) @panic("mkdir");
}

fn rmdirP(path: []const u8) void {
    var b: [256]u8 = undefined;
    if (!cstr(path, b[0..])) @panic("rmdir path");
    if (rmdir(@ptrCast([*]const u8, &b[0])) != 0) @panic("rmdir");
}

fn strLess(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    while (i < a.len and i < b.len) : (i += 1) {
        if (a[i] < b[i]) return true;
        if (a[i] > b[i]) return false;
    }
    return a.len < b.len;
}

fn strEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn sortEntries(names: [][]const u8, dirs: []bool) void {
    var i: usize = 1;
    while (i < names.len) : (i += 1) {
        const cur = names[i];
        const cur_dir = dirs[i];
        var j: usize = i;
        while (j > 0 and strLess(cur, names[j - 1])) : (j -= 1) {
            names[j] = names[j - 1];
            dirs[j] = dirs[j - 1];
        }
        names[j] = cur;
        dirs[j] = cur_dir;
    }
}

pub fn main() void {
    mkdirP("t_dir_iter");
    f.writeAll("t_dir_iter/a.txt", "a") catch @panic("write a");
    f.writeAll("t_dir_iter/b.ogg", "b") catch @panic("write b");
    mkdirP("t_dir_iter/sub");
    f.writeAll("t_dir_iter/sub/c.bin", "c") catch @panic("write c");

    var d = f.openDir(&g_arena, "t_dir_iter") catch @panic("openDir");

    var nraw = arena_mod.alloc(&g_arena, MAX_ENTRIES * @sizeOf([]const u8)) catch @panic("alloc names");
    var names: [][]const u8 = (@ptrCast([*][]const u8, nraw))[0..MAX_ENTRIES];
    var dirs: [MAX_ENTRIES]bool = undefined;

    var saw_dot = false;
    var saw_dotdot = false;
    var count: usize = 0;
    while (true) {
        const maybe = f.readDir(&g_arena, &d) catch @panic("readDir");
        if (maybe) |e| {
            if (e.name.len == 1 and e.name[0] == '.') {
                saw_dot = true;
            } else if (e.name.len == 2 and e.name[0] == '.' and e.name[1] == '.') {
                saw_dotdot = true;
            } else {
                ck(count < MAX_ENTRIES, "too many entries");
                names[count] = e.name;
                dirs[count] = e.is_dir;
                count += 1;
            }
        } else {
            break;
        }
    }
    f.closeDir(&d);

    ck(saw_dot, "saw .");
    ck(saw_dotdot, "saw ..");
    ck(count == 3, "entry count");

    sortEntries(names[0..count], dirs[0..count]);

    ck(strEq(names[0], "a.txt"), "entry 0 name");
    ck(!dirs[0], "entry 0 is_dir");
    ck(strEq(names[1], "b.ogg"), "entry 1 name");
    ck(!dirs[1], "entry 1 is_dir");
    ck(strEq(names[2], "sub"), "entry 2 name");
    ck(dirs[2], "entry 2 is_dir");

    f.remove("t_dir_iter/a.txt") catch @panic("remove a");
    f.remove("t_dir_iter/b.ogg") catch @panic("remove b");
    f.remove("t_dir_iter/sub/c.bin") catch @panic("remove c");
    rmdirP("t_dir_iter/sub");
    rmdirP("t_dir_iter");

    io.write("dir iter ok\n");
}
