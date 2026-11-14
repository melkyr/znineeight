// const_size_member_xmod — a module-level `const` whose initializer is an
// ARITHMETIC EXPRESSION over a NESTED-module member const, used in array-size
// position: `const C = mid.leaf.HEADER_SIZE * 2; var x: [C]u8`.
//
// GREEN (Task 2c-F, fixed point 960575b70302c78a19cf6bc0cc129df5): the Task-2b-F
// #1 `field_access` fix (walking the module-alias chain for
// `mid.leaf.HEADER_SIZE`) composes with the Task-2c-F `binary` case to fold
// `C -> (mid.leaf.HEADER_SIZE * 2)`. This fixture was RED at the Task-2b-F
// fixed point 0da3f1391075e3e77c54b626d5550e3b: the recursion hit the `binary`
// node with no case for it, returned 0xFFFFFFFF, and the first use reported
// `error[20]: identifier 'x' is not declared or imported in this module`
// (dump rc=2, 0 `.c`).
//
// GREEN contract: `C` folds to 32; `x.len == 32`; dump rc=0, 4 `.c`, gcc
// -m32 -std=c89 clean, link+run rc=0, no stdout.
const mid = @import("mid.zig");

const C = mid.leaf.HEADER_SIZE * 2;

pub fn main() void {
    var x: [C]u8 = undefined;
    if (x.len != 32) {
        @panic("const_size_member_xmod: array size mismatch");
    }
}
