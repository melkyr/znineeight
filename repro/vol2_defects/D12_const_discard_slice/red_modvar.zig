// D12 sibling shape (added by the FC conversion): MODULE-LEVEL const-discarding
// declarations — previously silent for both the slice -> slice and the
// slice -> many-ptr forms.
const std = @import("std");

var arr: [3]i32 = [3]i32{ 1, 2, 3 };
const c: []const i32 = arr;
var m: []i32 = c;
var mp: [*]i32 = c;

pub fn main() void {
    m[0] = 9;
    mp[0] = 8;
    std.io.print("m0={} mp0={}\n", .{ m[0], mp[0] });
}
