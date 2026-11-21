// module_value_varstore_xmod — `pub var` STORE via a 2-level module alias.
//
// `mid.leaf.counter = 9` is an l-value whose base is a nested module alias. The
// l-value path (`lowerLValueAddr`, sf/src/lower.zig:1399-1448) cannot resolve a
// module-typed base, so the field lookup misses and the ICE fires:
//
// GREEN (Task 2a-F, fixed point 43d41bfb903d56c153ebf653131aef6d):
// `counter == 9`; dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout.
// Was RED at 286c9011691ccd39403534019baa12c6: warning[3023] + error[3043]:
// internal: unsupported address-of l-value (node N), dump rc=3, 0 `.c`
// (corpus classifier ICE).
// Fix: `lowerFieldStore` resolves a nested module-alias base (or module-typed
// global) to its owning module and emits `store_global` directly (no l-value
// address is taken).
const mid = @import("mid.zig");

pub fn main() void {
    mid.leaf.counter = 9;
    if (mid.leaf.counter != 9) {
        @panic("module_value_varstore_xmod: counter store mismatch");
    }
}
