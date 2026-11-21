// print_fmt_ptrarray_guard_reject_xmod — Task 9 (z98-print-formatting
// Amendment 1, B4) guard probe: the pointer-to-array arm of `printFmtCheck`
// (`sf/src/lower.zig`) reads the array payload's element type to decide
// `*[N]u8 {s}`/`{x}` (3063, the Q3 bounded residual) vs `*[N]T {s}`/`{x}`/`{}`
// (3013). Task 9 range-guards the payload index like every sibling payload read
// in the validator family. No source program can drive the index out of range
// (the registry appends the payload before the type record), so the guard is
// behavior-neutral for every well-formed registry entry; this fixture pins the
// reachable decision path byte-for-byte.
//
// CENSUS: dump rc=2, 0 `.c`, exactly 6 diagnostics:
//   2 x error[3063] — `*const [2]u8` `{s}` / `{x}` (the `p_arr_u8` branch)
//   4 x error[3013] — `*const [2]u8` `{}`, `*const [3]i32` `{s}`/`{x}`/`{}`
//
// ORACLE (official Zig 0.15.2): `{}` on a pointer-to-array rejects ("cannot
// format slice without a specifier"); `{s}`/`{x}` on `*[N]i32` reject (child
// `i32` cannot cast into `u8`); `{s}`/`{x}` on `*[N]u8` are accepted and print
// the byte string / hex bytes — the two 3063 rows are the documented Q3
// divergence (Zig accepts; Z98 clean-rejects).
const std = @import("std");

pub fn main() void {
    var mbu = [_]u8{ 'h', 'i' };
    const pbu: *const [2]u8 = &mbu;
    std.io.print("{s}", .{pbu});
    std.io.print("{x}", .{pbu});
    std.io.print("{}", .{pbu});
    var ma = [3]i32{ 1, 2, 3 };
    const pa: *const [3]i32 = &ma;
    std.io.print("{s}", .{pa});
    std.io.print("{x}", .{pa});
    std.io.print("{}", .{pa});
}
