// undefined_slice_array_xmod — Plan A Task 6b-I pin: `-ffast` `undefined`
// initialization of a 1-D array of slices mis-emits.
//
// `var arr: [3][]const u8 = undefined;` lowers, under `-ffast`, to a
// `LirStmt.undefined_const` whose element kind is a slice (neither
// `array_type` / `struct_type` / `tagged_union_type`), so the emitter's
// scalar else-arm (`sf/src/c89_emit.zig:7308-7311`) renders
//
//     zT_1[_i] = 0;            /* int -> slice struct: illegal C89 */
//
// and gcc rejects the emitted C ("incompatible types when assigning to type
// 'Slice...' from type 'int'"). Under `-fsafe`/default, lowering routes
// `undefined` through `poison_init` (`zig_poison_fill`,
// `sf/src/c89_emit.zig:7329`), so the same program builds and runs clean
// (control: `known_excluded/undefined_slice_array_safe_xmod`).
//
// The corpus classifier (`scripts/corpus/classify`) runs `-ffast`, so this
// dir classifies FAIL pre-fix and OK once Task 6b-F adds a slice element arm.
//
// GREEN contract: stdout `alpha|gamma|5\n` (rc=0).
const std = @import("std");

pub fn main() void {
    var arr: [3][]const u8 = undefined;
    arr[0] = "alpha";
    arr[2] = "gamma";
    std.io.write(arr[0]);
    std.io.writeByte('|');
    std.io.write(arr[2]);
    std.io.writeByte('|');
    std.io.printInt(@intCast(i32, arr[0].len));
    std.io.writeByte('\n');
}
