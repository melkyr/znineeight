// index_oob_reject_xmod — Task 17 (F) comptime-known out-of-bounds index
// reject fixture.
//
// DEFECT (before the fix): a comptime-known out-of-bounds array index compiled
// rc=0 with no diagnostic. Under the default `-fsafe` it trapped at runtime
// (rc 133) through the A5F `check_trap{kind=5}` guard, but under `-ffast` the
// guard is not emitted and the program silently read the wrong value; official
// Zig 0.15.2 rejects the same programs at compile time.
//
// FIX (Task 17): `semanticAnalyzerResolveIndexAccess` runs
// `semanticAnalyzerCheckComptimeIndexOob` when the indexed base is a fixed-size
// array (`[N]T`, `*[N]T`, or a struct/union array field) and the index is
// comptime-known (a literal, a `const` chain, constant arithmetic, or `.len`
// of a fixed array). It emits the new level-0 `error[3062]`
// (ERR_3062_INDEX_OUT_OF_BOUNDS) with Zig 0.15.2's exact ASCII wording — rc=2,
// 0 emitted `.c`. The runtime-index `-fsafe` trap is untouched.
//
// Sites (every one independently rejected by official Zig 0.15.2):
//   * `scores[5]`             index 5 outside array of length 5
//   * `scores[scores.len]`    index 5 outside array of length 5
//   * `scores[ci]` (const)    index 5 outside array of length 5
//   * `scores[-1]`            type 'usize' cannot represent integer value '-1'
//   * `p[5]` (`*[5]i32`)      index 5 outside array of length 5
//   * `st.arr[5]` ([3]field)  index 5 outside array of length 3
//   * `st.arr[st.arr.len]`    index 3 outside array of length 3
//   * `scores[4294967296]`    index 4294967296 outside array of length 5
//
// EXPECTED: dump rc=2, 0 `.c`, exactly one `error[3062]` per site (8 total);
// no `error[3000]`, so this dir buckets as FAIL under the corpus classifier.
// Valid forms stay accepted — see `stdlib_comptime_index_ok_xmod` and the
// standalone `repro/comptime_index_oob.z98`.
const S = struct { arr: [3]i32 };

pub fn main() void {
    var scores: [5]i32 = .{ 10, 20, 30, 40, 50 };
    var p: *[5]i32 = &scores;
    var st: S = S{ .arr = .{ 1, 2, 3 } };
    const ci: u32 = 5;
    var a: i32 = scores[5];
    _ = a;
    var b: i32 = scores[scores.len];
    _ = b;
    var c: i32 = scores[ci];
    _ = c;
    var d: i32 = scores[-1];
    _ = d;
    var e: i32 = p[5];
    _ = e;
    var f: i32 = st.arr[5];
    _ = f;
    var g: i32 = st.arr[st.arr.len];
    _ = g;
    var h: i32 = scores[4294967296];
    _ = h;
}
