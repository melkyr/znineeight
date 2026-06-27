const std = @import("std");
const val_mod = @import("test_b_value.zig");

fn test_fn(val: *val_mod.Value) void {
    switch (val.*) {
        .Int => |v| { _ = v; },
        .Bool => |b| { _ = b; },
        .Cons => |data| { _ = data.car; },
        .Nil => {},
    }
}

pub fn main() void {
    _ = test_fn;
}
