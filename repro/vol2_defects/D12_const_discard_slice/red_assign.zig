// D12 sibling shape (added by the FC conversion): a const-discarding slice
// ASSIGNMENT — the site that previously emitted only `warning[3000]` and then
// mutated the const slice's backing array through the alias.
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const c: []const i32 = arr;
    var m: []i32 = arr;
    m = c;
    m[0] = 9;
    std.io.print("m0={}\n", .{arr[0]});
}
