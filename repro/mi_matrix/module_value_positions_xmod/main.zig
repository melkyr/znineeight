// module_value_positions_xmod — nested-module value access in non-var-init
// positions: call-argument, return, arithmetic.
//
// All three positions lower the base `mid.leaf` as a value and fail the same
// way (position does not change the outcome); the lowerer reports all three:
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access   (x3)
//   warning[3023]: module used as value expression           (x3)
//   dump rc=2, 0 `.c`. Corpus classifier: ICE (`error[3042]`).
//
// Expected GREEN contract: all three checks hold; dump rc=0, gcc clean,
// link+run rc=0, no stdout.
const mid = @import("mid.zig");

fn sink(n: usize) void {
    if (n != 16) {
        @panic("module_value_positions_xmod: call-arg");
    }
}

fn get() usize {
    return mid.leaf.HEADER_SIZE;
}

pub fn main() void {
    sink(mid.leaf.HEADER_SIZE);
    if (get() != 16) {
        @panic("module_value_positions_xmod: return");
    }
    var n: usize = mid.leaf.HEADER_SIZE + 1;
    if (n != 17) {
        @panic("module_value_positions_xmod: arithmetic");
    }
}
