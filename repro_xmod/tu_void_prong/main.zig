const lib = @import("lib.zig");

pub fn main() void {
    var u: lib.MyUnion = undefined;
    switch (u) {
        .Empty => |x| {
            _ = x;
        },
        .Value => |n| {
            _ = n;
        },
    }
}
