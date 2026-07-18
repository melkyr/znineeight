extern fn __bootstrap_print_int(x: i32) void;
const util = @import("util.zig");

pub fn main() void {
    var r = util.parse_int() catch {
        __bootstrap_print_int(1);
        return;
    };
    __bootstrap_print_int(r);
}
