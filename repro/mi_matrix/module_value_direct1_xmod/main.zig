// module_value_direct1_xmod — GREEN control: 1-level DIRECT module import.
//
// `leaf.HEADER_SIZE` (a fixture-local module) and
// `@import("std_async.zig").HEADER_SIZE` (the real std module) are both DIRECT
// module bases, not nested aliases. These already work: the lowerer's
// field_access path recognizes a direct module ident and resolves the member
// (`sf/src/lower.zig:3400-3416`, `:3311-3348`; sema
// `sf/src/semantic_analyzer.zig:498-553`).
//
// GREEN (current, fixed point 286c9011691ccd39403534019baa12c6): dump rc=0,
// gcc clean, link+run rc=0, no stdout. This control proves the gap is the
// NESTED alias, not module-member access per se.
const leaf = @import("leaf.zig");
const sa = @import("std_async.zig");

pub fn main() void {
    var n: usize = leaf.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_direct1_xmod: local direct import");
    }
    var h: usize = sa.HEADER_SIZE;
    if (h != 16) {
        @panic("module_value_direct1_xmod: std_async direct import");
    }
}
