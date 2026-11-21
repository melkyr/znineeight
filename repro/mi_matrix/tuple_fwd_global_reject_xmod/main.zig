// tuple_fwd_global_reject_xmod — Task 9 (z98-print-formatting Amendment 1, B5)
// reject fixture, re-scoped by fix round 3 (operator ruling Q7).
//
// Before Q7 this fixture pinned the reject of every forward-referenced
// tuple-global element (composite, out-of-i32, non-literal scalar, same-type
// scalars, cross-module, direct `@import`). Q7 replaced that narrow-reject
// approach with dependency-ordered `__module_init` emission, so all of those
// shapes now COMPILE AND PRINT ZIG-EQUAL — they are pinned as positive rows in
// `stdlib_print_tuple_fwd_ok_xmod` instead.
//
// `error[3064]` (`ERR_3064_CYCLIC_GLOBAL_INIT`) now fires only for the
// genuinely unresolvable shape: a cycle in the global-initializer dependency
// graph, which has no valid emission order. Official Zig 0.15.2 likewise
// rejects a container-level dependency loop ("dependency loop detected").
//
// CENSUS: dump rc=2, 0 `.c`, exactly 1 x error[3064] (one per module; the
// second cycle in this file is covered by the same diagnostic), span on the
// first cycle declaration.
var cyc_a = .{ cyc_b, 1 };
var cyc_b = .{ cyc_a, 2 };

var cyc_c = cyc_d + 1;
var cyc_d = cyc_c + 1;

pub fn main() void {
}
