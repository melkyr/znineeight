// w3000fp_errset_subset_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// `var y: A!i32 = fromB();` where `fromB() B!i32` and `B = error{Bad}` is a
// SUBSET of `A = error{Other, Bad}`. Zig/Z98 permit an error set to coerce to a
// superset. `typeRegistryIsAssignable` (`sf/src/type_registry.zig:1193-1199`)
// requires `eu_src.error_set == eu_tgt.error_set` (exact equality) before it
// recurses, so the var-decl warns `source: error-union / target: error-union`.
// (The same holds for an inferred anonymous error set, see
// `errset_cross_set_compare`.)
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file.
//
// Runtime (today): prints `9` (the `catch` fallback); the error is stored.
const std = @import("std");
const A = error{ Other, Bad };
const B = error{ Bad };

fn fromB() B!i32 { return error.Bad; }

pub fn main() void {
    var y: A!i32 = fromB();
    var s: i32 = y catch 9;
    std.io.printInt(s);
    std.io.writeByte('\n');
}
