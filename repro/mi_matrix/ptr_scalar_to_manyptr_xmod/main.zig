// ptr_scalar_to_manyptr_xmod — GREEN diagnostic guard (A9F-a review fix).
// A scalar `*T` must NOT implicitly broaden to a many-pointer `[*]T`: the
// spec coercion table (Language_Spec_Z98.md:362-365) permits only slice->ptr
// and array->ptr.
//
// RED baseline (A9F-a fixed point `dcc89404`): `typeRegistryIsAssignable`
// / `classifyCoercion` accepted `*T -> [*]T` on a bare `sp.base == tp.base`
// match, so `var p: [*]u8 = &x` silently dropped the mismatch.
// GREEN: exactly ONE `warning[3000]` (source: pointer / target:
// many-pointer); dump rc0 and run still print 7\n (the pointer value is
// carried through unchanged). The `&array -> [*]` positive case is pinned by
// `typealias_mptr_xmod`.
// Fix (A9F-a review): restrict the ptr->many-ptr branch to an array pointee.
const std = @import("std");

pub fn main() void {
    var x: u8 = 7;
    var p: [*]u8 = &x;
    std.io.printInt(@intCast(i32, p[0]));
    std.io.writeByte('\n');
}
