const sand_mod = @import("../../examples/lisp_interpreter_adv/sand.zig");

pub const Value = union(enum) {
    Cons: struct {
        car: i32,
        cdr: i32,
    },
};

pub fn main() void {
    var v: Value = undefined;
    // BUG: Initialization with anonymous struct payload fails to generate C code
    v = Value{ .Cons = .{ .car = 1, .cdr = 2 } };
}
