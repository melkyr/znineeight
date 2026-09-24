// slice_runtime_end_xmod — Task 17 fix round (review Important 1) regression
// fixture for a CLOSED slice range with a comptime start beyond the array
// length and a RUNTIME end.
//
// DEFECT (Task 17 base): `semanticAnalyzerCheckComptimeSliceBounds` fell back
// to `end_eff = len` even for a present-but-unfoldable end, so `scores[7..ri]`
// (ri runtime) was rejected `error[3062]: start index 7 is larger than end
// index 5`. Official Zig 0.15.2 ACCEPTS this shape (the out-of-range start is a
// runtime condition, not a compile-time one) — `build-exe -fno-emit-bin` compiles
// it with no diagnostics — and the pristine compiler compiled it (the bad
// runtime length then flows into the ordinary `-fsafe` runtime guards).
//
// FIX (Task 17 fix round): the start check uses `alen` as the effective end
// ONLY for the open form (`scores[7..]`, `child_2 == 0`); when a present end
// does not fold there is no comptime end to compare against, so the start
// check is skipped and the shape keeps its pre-Task-17 runtime behavior.
//
// Contract (verified identical to the pristine compiler, emitted C
// byte-identical in both modes):
//   * `-fsafe`: compile rc 0; the resulting bad length trips the runtime
//     `@intCast` overflow guard -> rc 133 (SIGTRAP).
//   * `-ffast`: compile rc 0; `len=-4` (3 - 7), rc 0.
// The closed/known rejects (`scores[6..]`, `scores[1..10]`, `scores[3..1]`)
// and the in-range controls stay pinned in `slice_range_oob_reject_xmod` /
// `stdlib_comptime_index_ok_xmod`.
const std = @import("std");

pub fn main() void {
    var scores: [5]i32 = .{ 10, 20, 30, 40, 50 };
    var ri: usize = 3;
    var s: []i32 = scores[7..ri];
    std.io.writeStr("len=");
    std.io.printInt(@intCast(i32, s.len));
    std.io.writeByte('\n');
}
