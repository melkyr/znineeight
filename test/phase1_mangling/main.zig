const lib_a = @import("lib_a.zig");
const lib_b = @import("lib_b.zig");

pub fn main() void {
    lib_b.use_lib_a();
    lib_a.print_green("Hello");
}
