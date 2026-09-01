const std = @import("std");

pub fn main() void {
    var arr = [4]u32{1, 2, 3, 4};
    _ = arr[0];
    var sl = arr[0..2];
    _ = sl;
    _ = arr;
}
