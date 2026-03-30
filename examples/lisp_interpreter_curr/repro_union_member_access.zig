const value_mod = @import("value.zig");

pub fn main() void {
    var v: value_mod.Value = undefined;
    // Attempting to access .Cons directly if we "know" it's a Cons
    // In many Zig versions this is allowed if it's a tagged union.
    // In Z98, the compiler might accept it but generate invalid C
    // because it doesn't mangle the access to the anonymous union members correctly in some contexts.
    const car = v.Cons.car;
    _ = car;
}
