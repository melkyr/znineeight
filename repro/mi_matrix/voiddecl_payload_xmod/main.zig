const std = @import("std");

const Item = union(enum) {
    a: u32,
    b: void,
};

pub fn main() void {
    var x: Item = undefined;
    var p = x.payload;
    std.io.printInt(p);
}
