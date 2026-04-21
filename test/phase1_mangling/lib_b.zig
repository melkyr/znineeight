const lib_a = @import("lib_a.zig");

pub fn use_lib_a() void {
    lib_a.print_green(lib_a.ANSI_GREEN);
    lib_a.global_counter = lib_a.global_counter + 1;
    const s = lib_a.MyStruct { .x = 10 };
}
