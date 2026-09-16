// const_size_member_xmod — a module-level `const` whose initializer is an
// ARITHMETIC EXPRESSION over a NESTED-module member const, used in array-size
// position: `const C = mid.leaf.HEADER_SIZE * 2; var x: [C]u8`.
//
// This composes the Task-2b-F #1 `field_access` fix (`evalConstU32Full` now
// walks the module-alias chain for `mid.leaf.HEADER_SIZE`) with the NEW missing
// `binary` case. Without the binary case the recursion
// `C -> (mid.leaf.HEADER_SIZE * 2)` hits a `binary` node and returns
// 0xFFFFFFFF, so the size never resolves.
//
// RED today (Task 2b-F fixed point 0da3f1391075e3e77c54b626d5550e3b):
//   error[20]: identifier 'x' is not declared or imported in this module
// (dump rc=2, 0 `.c`; corpus classifier FAIL).
//
// Expected GREEN contract (Task 2c-F): `C` folds to 32; `x.len == 32`; dump
// rc=0, 5 `.c`, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.
//
// Fix locus: the `binary` case in `evalConstU32Full`
// (`sf/src/type_resolver.zig:744`) on top of the existing `field_access` arm
// (`:766`). See report Q3/Q6.
const mid = @import("mid.zig");

const C = mid.leaf.HEADER_SIZE * 2;

pub fn main() void {
    var x: [C]u8 = undefined;
    if (x.len != 32) {
        @panic("const_size_member_xmod: array size mismatch");
    }
}
