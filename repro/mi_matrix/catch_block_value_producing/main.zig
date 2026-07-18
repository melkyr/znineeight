extern fn __bootstrap_print_int(x: i32) void;
const helper = @import("helper.zig");

pub fn main() void {
    var result = helper.try_compute() catch |err| {
        _ = err;
        99
    };
    __bootstrap_print_int(result);
}
