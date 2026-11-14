const std = @import("std.zig");
fn run() void {
    var a: i32 = 1 + 2;
    std.io.printInt(a);
}
pub fn main() void {
    run();
}
