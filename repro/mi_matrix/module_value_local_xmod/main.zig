// module_value_local_xmod — GREEN control: module-LOCAL `pub const`.
//
// Reading a `pub const` declared in the SAME module needs no module base at
// all, so it is unaffected by the nested-module value-position gap.
//
// GREEN (current, fixed point 286c9011691ccd39403534019baa12c6): dump rc=0,
// gcc clean, link+run rc=0, no stdout. This control proves the const value
// itself is fine and isolates the defect to the nested module base.
pub const K: usize = 16;

pub fn main() void {
    var n: usize = K;
    if (n != 16) {
        @panic("module_value_local_xmod: K mismatch");
    }
}
