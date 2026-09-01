@cInclude("<stdio.h>");

const File = void;

extern fn fopen(filename: [*]const u8, mode: [*]const u8) ?*File;

const std = @import("std");

pub fn main() void {
    var path: [*]const u8 = "none.txt";
    var mode: [*]const u8 = "r";
    var f: ?*File = fopen(path, mode);
    if (f != null) { std.io.printInt(@intCast(i32, 1)); }
    else { std.io.printInt(@intCast(i32, 0)); }
}
