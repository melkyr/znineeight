// D1 cross-module RED: both the plain-`defer` function and the `for`-body
// `defer` function live in helper.zig; main.zig only calls them.
// The one-module trigger survives the module boundary as long as BOTH shapes
// stay in the same module.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    helper.plain();
    helper.loopDefer();
}
