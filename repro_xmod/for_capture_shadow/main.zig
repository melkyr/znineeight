const lib = @import("lib.zig");

pub fn main() void {
    var list_a: [3]lib.ItemA = undefined;
    var list_b: [3]lib.ItemB = undefined;

    for (list_a) |item| {
        _ = item.x;
    }

    for (list_b) |item| {
        _ = item.key;
    }
}
