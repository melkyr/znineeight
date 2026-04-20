const modA = @import("modA.zig");
const modB = @import("modB.zig");

pub fn main() void {
    const a = modA.createArena();
    modB.processArena(a);
}
