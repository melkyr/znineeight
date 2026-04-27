// examples/rogue_mud/test/header_repro.zig
const mod = @import("header_repro_mod.zig");

pub const Container = struct {
    // This triggers "field has incomplete type" in C if mod.Data is only forward-declared
    // because it's wrapped in an Optional and used across modules.
    data: ?mod.Data,
};

pub fn main() void {
    var c: Container = undefined;
    c.data = null;
}
