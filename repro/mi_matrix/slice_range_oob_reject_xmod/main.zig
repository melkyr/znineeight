// slice_range_oob_reject_xmod — Task 17 (F) constant-slice-range reject
// fixture (the fixed-array analogue of the index check).
//
// DEFECT (before the fix): a constant slice range beyond a fixed array's
// bounds compiled rc=0 with no diagnostic and produced a wrong slice length at
// runtime (`scores[1..10]` gave len 9); official Zig 0.15.2 rejects each shape
// at compile time.
//
// FIX (Task 17): `semanticAnalyzerResolveSliceExpr` runs
// `semanticAnalyzerCheckComptimeSliceBounds` when the sliced base is a
// fixed-size array and a bound is comptime-known. Zig's order: a negative
// bound is the `usize` coercion reject; then an end beyond the length; then a
// start after the effective end (the open-ended `a[s..]` end is the length).
// All four messages are Zig 0.15.2's exact ASCII wording, emitted as the new
// level-0 `error[3062]` (ERR_3062_INDEX_OUT_OF_BOUNDS) — rc=2, 0 `.c`.
//
// Sites (every one independently rejected by official Zig 0.15.2):
//   * `scores[1..10]`        end index 10 out of bounds for array of length 5
//   * `scores[10..12]`       end index 12 out of bounds for array of length 5
//   * `scores[3..1]`         start index 3 is larger than end index 1
//   * `scores[6..]`          start index 6 is larger than end index 5
//   * `scores[-1..2]`        type 'usize' cannot represent integer value '-1'
//   * `p[1..10]` (`*[5]i32`) end index 10 out of bounds for array of length 5
//   * `st.arr[1..4]` (field) end index 4 out of bounds for array of length 3
//
// EXPECTED: dump rc=2, 0 `.c`, exactly one `error[3062]` per site (7 total);
// no `error[3000]`, so this dir buckets as FAIL under the corpus classifier.
// Legal boundaries (`scores[5..]`, `scores[5..5]`, in-range ranges) stay
// accepted — see `stdlib_comptime_index_ok_xmod`.
const S = struct { arr: [3]i32 };

pub fn main() void {
    var scores: [5]i32 = .{ 10, 20, 30, 40, 50 };
    var p: *[5]i32 = &scores;
    var st: S = S{ .arr = .{ 1, 2, 3 } };
    var a: []i32 = scores[1..10];
    _ = a;
    var b: []i32 = scores[10..12];
    _ = b;
    var c: []i32 = scores[3..1];
    _ = c;
    var d: []i32 = scores[6..];
    _ = d;
    var e: []i32 = scores[-1..2];
    _ = e;
    var f: []i32 = p[1..10];
    _ = f;
    var g: []i32 = st.arr[1..4];
    _ = g;
}
