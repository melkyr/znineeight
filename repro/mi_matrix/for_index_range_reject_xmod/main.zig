// for_index_range_reject_xmod — Task 11 (Part II) reject fixture for the
// explicit index-range form. Every site is invalid in official Zig 0.15.2 and
// must be a clean Z98 reject: rc 2, 0 `.c`, `error[3000]` (the canonical
// green-guard).
//
// Sites (all Zig-0.15.2-oracle-checked):
//   * `for (arr, 1..4)`      — span 3 != array length 5 (Zig: "non-matching
//                              for loop lengths");
//   * `for (arr, 0 - 1..)`   — comptime negative bound does not fit `usize`
//                              (Zig: "overflow of integer type 'usize' with
//                              value '-1'");
//   * `for (arr, i32var..)`  — signed bound (Zig: "expected type 'usize',
//                              found 'i32'");
//   * `for (arr, 1..) |x|`   — explicit index range without an index capture
//                              (Zig: "for input is not captured");
//   * `for (arr, 2..2)`      — empty span on a non-empty array (same
//                              non-matching-lengths reject);
//   * `for (arr, 9..4)`      — end before start (Zig: "overflow of integer
//                              type 'usize' with value '-5'").
pub fn main() void {
    const arr = [_]u8{ 10, 11, 12, 13, 14 };
    for (arr, 1..4) |x, i| {
        _ = x; _ = i;
    }
    for (arr, 0 - 1..) |x, i| {
        _ = x; _ = i;
    }
    var n: i32 = 1;
    for (arr, n..) |x, i| {
        _ = x; _ = i;
    }
    for (arr, 2..2) |x, i| {
        _ = x; _ = i;
    }
    for (arr, 9..4) |x, i| {
        _ = x; _ = i;
    }
    for (arr, 1..) |x| {
        _ = x;
    }
}
