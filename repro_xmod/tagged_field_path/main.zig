const lib = @import("lib.zig");

pub fn main() void {
    var u: lib.MyUnion = undefined;
    switch (u) {
        .List => |items| {
            for (items) |item| {
                _ = item.key;
            }
        },
        .Empty => {},
    }
}
