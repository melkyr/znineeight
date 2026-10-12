const m1 = @import("m1.zig");
const m2 = @import("m2.zig");
const m3 = @import("m3.zig");
const m4 = @import("m4.zig");
const m5 = @import("m5.zig");
const m6 = @import("m6.zig");
const m7 = @import("m7.zig");
const std = @import("std");
pub fn main() void {
    var a = m1.make();
    std.io.printInt(a.v);
}
