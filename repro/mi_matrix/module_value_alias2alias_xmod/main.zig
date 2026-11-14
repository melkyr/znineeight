// module_value_alias2alias_xmod — alias-to-alias (`const x = mid.leaf`).
//
// `x` is a local binding of a nested module alias; `x.HEADER_SIZE` reads a
// member through the re-bound module. The base `x` is a global whose registered
// type is `module_type`, so lowering returns TEMP_NONE at the module/fn-type
// guard (sf/src/lower.zig:3100-3106) and the field access reports:
//
// GREEN (Task 2a-F, fixed point 43d41bfb903d56c153ebf653131aef6d): `n == 16`;
// dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout.
// Was RED at 286c9011691ccd39403534019baa12c6: error[3042] only (no
// warning[3023] — the module is reached through a typed global, not a bare
// module ident), dump rc=2, 0 `.c` (corpus classifier ICE).
const mid = @import("mid.zig");

pub fn main() void {
    const x = mid.leaf;
    var n: usize = x.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_alias2alias_xmod: HEADER_SIZE mismatch");
    }
}
