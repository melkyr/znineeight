const std = @import("std.zig");

fn swap(a: *[10]i32, i: usize, j: usize) void {
    const temp = a[i];
    a[i] = a[j];
    a[j] = temp;
}

pub fn main() void {
    var arr = [10]i32{ 12, 11, 13, 5, 6, 7, 20, 1, 15, 3 };
    swap(&arr, @intCast(usize, 0), @intCast(usize, 1));
    std.io.printInt(arr[0]); // expect 11 once fixed
}
