// safe_bounds_inbounds_xmod — in-bounds control for the A5F `-fsafe` index
// guard. Both the array and slice paths must NOT trap for legal indices.
//
// Expected under `-fsafe`, `-ffast`, and PRE: rc 0, `v=30 w=20`.
const std = @import("std");

pub fn main() void {
    var arr: [3]i32 = [_]i32{10, 20, 30};
    var i: usize = 2;
    var v: i32 = arr[i];
    arr[0] = v + 1;
    var s: []i32 = &arr;
    var j: usize = 1;
    var w: i32 = s[j];
    std.io.writeStr("v=");
    std.io.printInt(v);
    std.io.writeStr(" w=");
    std.io.printInt(w);
    std.io.writeByte('\n');
}
