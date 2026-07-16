@cInclude("<stdio.h>");

const File = void;

extern fn fopen(filename: [*]const u8, mode: [*]const u8) ?*File;

extern fn __bootstrap_print_int(n: i32) void;

pub fn main() void {
    var path: [*]const u8 = "none.txt";
    var mode: [*]const u8 = "r";
    var f: ?*File = fopen(path, mode);
    if (f != null) { __bootstrap_print_int(@intCast(i32, 1)); }
    else { __bootstrap_print_int(@intCast(i32, 0)); }
}
