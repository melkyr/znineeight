// undefined_slice_array_safe_xmod — Plan A Task 6b-I `-fsafe`/default control.
//
// The SAME program as `repro/mi_matrix/undefined_slice_array_xmod`, kept
// off-corpus under `known_excluded/` (never enumerated by
// `scripts/corpus/list_corpus_dirs.sh`, so the `-ffast` classifier never runs
// it). Under `-fsafe`/default, lowering routes the array `undefined` through
// `poison_init` (`zig_poison_fill`), which is slice-shape agnostic, so the
// emitted C compiles and runs clean both before and after the Task 6b-F fix.
//
// This control exists to prove the defect is mode-specific (`-ffast` only):
// a `-fsafe`-only defect would be invisible to the `-ffast` corpus
// classifier — this one is not, because it lives in the `-ffast` path.
//
// Contract: stdout `alpha|gamma|5\n` (rc=0).
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
