// stdlib_default_lib_lookup_xmod — Task 5B regression: the compiler's DEFAULT
// standard-library lookup `<exe_dir>/lib` must be found on every target.
//
// DEFECT (before the fix): `phase_ImportResolution` guarded the default lib
// path with `pal.fileExists` (`fopen(path,"rb")`), and `fopen` on a DIRECTORY
// fails on win32 (msvcrt), so `<exe_dir>/lib` was never added as a search dir
// and a bare `@import("std")` failed `error[3048]`. On Linux glibc `fopen`s a
// directory, so the same layout worked and the defect was invisible there.
//
// FIX (Task 5B): `sf/src/main.zig:437` `pal.fileExists(lib_path)` ->
// `pal.dirExists(lib_path)` (the default lib path names a directory;
// `pal_dir_exists` probes with GetFileAttributesA on win32 / stat on POSIX).
//
// This fixture is the LINUX positive control: the harness builds it with NO
// `-I`, relying solely on the compiler's sibling `lib/` (the std runner and
// corpus classifier both invoke the compiler this way). It pulls in FOUR
// distinct std modules (`std_io`, `std_str`, `std_math`, `std_parse`) so the
// default-lib search path is exercised end-to-end. The win32 RED/GREEN
// discriminator is `scripts/win32_cross/default_lib_lookup.sh` (the Linux
// gates cannot distinguish the fix because glibc `fopen`s a directory).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   default-lib-lookup-ok
//   len=3
//   max=9
//   parsed=-42
//   done
const std = @import("std");
const parse = @import("std_parse.zig");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        @panic(what);
    }
}

pub fn main() void {
    var word: []const u8 = "z98";
    ck(std.str.len(word) == 3, "len");

    var got = parse.parseInt("-42");
    if (got) |v| {
        ck(v == -42, "parse");
    } else {
        ck(false, "parse-null");
    }

    std.io.write("default-lib-lookup-ok\n");
    std.io.write("len=");
    std.io.printInt(@intCast(i32, std.str.len(word)));
    std.io.write("\n");
    std.io.write("max=");
    std.io.printInt(std.math.max(3, 9));
    std.io.write("\n");
    std.io.write("parsed=");
    std.io.printInt(-42);
    std.io.write("\n");
    std.io.write("done\n");
}
