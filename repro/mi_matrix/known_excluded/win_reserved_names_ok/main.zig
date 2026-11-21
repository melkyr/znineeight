// win_reserved_names_ok — Task TE Win9x-truth fixture (off-corpus:
// known_excluded/). Source identifiers that MSVC 6 / OpenWatcom reserve in C
// mode (plus the emitted runtime's zT_/zF_/zG_/Z98_/zig_/pal_ prefixes) must
// be escaped by name_mangler's raw-mint path, while convention tokens stay raw.
// Expected stdout: `win reserved ok`.
const std = @import("std");

const Names = struct {
    cdecl: i32,
    stdcall: i32,
    pal_trap: i32,
};

fn add(near: i32, far: i32) i32 {
    return near + far;
}

pub fn main() void {
    var cdecl: i32 = 1;
    var stdcall: i32 = 2;
    var near: i32 = 1;
    var far: i32 = 3;
    var pal_trap: i32 = 4;
    var Z98_STDCALL: i32 = 5;
    var zig_arena: i32 = 6;
    var zT_5: i32 = 7;
    var n: Names = Names{ .cdecl = cdecl, .stdcall = stdcall, .pal_trap = pal_trap };
    var r: i32 = add(near, far) + Z98_STDCALL + zig_arena + zT_5;
    r = r + n.cdecl + n.stdcall + n.pal_trap;
    if (r == 29) {
        std.io.write("win reserved ok\n");
    } else {
        std.io.write("win reserved BAD\n");
    }
}
