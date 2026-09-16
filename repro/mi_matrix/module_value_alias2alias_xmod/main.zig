// module_value_alias2alias_xmod — alias-to-alias (`const x = mid.leaf`).
//
// `x` is a local binding of a nested module alias; `x.HEADER_SIZE` reads a
// member through the re-bound module. The base `x` is a global whose registered
// type is `module_type`, so lowering returns TEMP_NONE at the module/fn-type
// guard (sf/src/lower.zig:3100-3106) and the field access reports:
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access
//   dump rc=2, 0 `.c` (NOTE: no warning[3023] here — the module is reached
//   through a typed global, not a bare module ident). Corpus classifier: ICE.
//
// Expected GREEN contract: `n == 16`; dump rc=0, gcc clean, link+run rc=0,
// no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    const x = mid.leaf;
    var n: usize = x.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_alias2alias_xmod: HEADER_SIZE mismatch");
    }
}
