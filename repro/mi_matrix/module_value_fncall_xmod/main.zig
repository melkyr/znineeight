// module_value_fncall_xmod — GREEN control: function called through a 2-level
// module alias.
//
// `mid.leaf.add(2, 3)`: the call-expression lowering walks the module-alias
// chain to the owning module before dispatching (sf/src/lower.zig:3787-3813),
// so a nested-alias FUNCTION call already works — unlike a nested-alias VALUE
// access. This control pins the contrast asserted in the Task 2a-I report (Q4):
// functions work, values do not. The real-std instance is
// `std.async.contextInit(...)` (also exercised by stdlib_async_headerexact_xmod).
//
// GREEN (current, fixed point 286c9011691ccd39403534019baa12c6; tested binary
// md5 8c4900dc8980c00c085049970246500d): dump rc=0, gcc clean, link+run rc=0,
// no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    var n: i32 = mid.leaf.add(2, 3);
    if (n != 5) {
        @panic("module_value_fncall_xmod: add mismatch");
    }
}
