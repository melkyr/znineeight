const std = @import("std");
var counter: i32 = 0;
fn bump() void {
    counter = counter + 1;
}
pub fn main() void {
    bump();
    bump();
    std.io.printInt(counter);
}
