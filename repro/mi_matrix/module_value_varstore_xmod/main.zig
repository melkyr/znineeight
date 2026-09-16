// module_value_varstore_xmod — `pub var` STORE via a 2-level module alias.
//
// `mid.leaf.counter = 9` is an l-value whose base is a nested module alias. The
// l-value path (`lowerLValueAddr`, sf/src/lower.zig:1399-1448) cannot resolve a
// module-typed base, so the field lookup misses and the ICE fires:
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   warning[3023]: module used as value expression
//   error[3043]: internal: unsupported address-of l-value (node N)
//   dump rc=3, 0 `.c`. Corpus classifier: ICE (`error[3043]`).
// (Distinct from the read case `error[3042]` — the fix must cover BOTH the
// value path and the l-value path.)
//
// Expected GREEN contract: `counter == 9`; dump rc=0, gcc clean, link+run
// rc=0, no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    mid.leaf.counter = 9;
    if (mid.leaf.counter != 9) {
        @panic("module_value_varstore_xmod: counter store mismatch");
    }
}
