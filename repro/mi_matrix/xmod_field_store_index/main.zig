const t = @import("types.zig");

pub fn main() void {
    var d: t.T = undefined;
    t.init(&d);
}
