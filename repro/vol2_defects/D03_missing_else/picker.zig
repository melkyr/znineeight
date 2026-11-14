// D3 cross-module RED: the no-`else` switch lives in picker.zig and is called
// from main.zig; the unmatched value still yields silent garbage.
const std = @import("std");

pub fn pick(x: i32) i32 {
    return switch (x) {
        1 => 100,
        2 => 200,
    };
}

pub fn pickElse(x: i32) i32 {
    return switch (x) {
        1 => 100,
        2 => 200,
        else => -1,
    };
}
