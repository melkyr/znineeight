// stdlib_comptime_constfold_exact_xmod — Task 5 (fold-consumer migration:
// exact array-size / enum-initializer folds) positive runtime fixture.
//
// Pins the exact `ComptimeInt` fold now shared by the type-resolver evaluators
// (`evalConstU32Full` array sizes and `evalConstI64Full` enum initializers, both
// re-pointed at `evalConstIntFull` over the Task-2 `ci*` core). Every shape was
// checked against the official Zig 0.15.2 oracle twin; the committed stdout is
// the oracle's stdout byte-for-byte.
//
// Covered (all previously REJECTED by Z98 — the old u32 evaluator had no
// shift/bitwise/paren arms and the i64 enum evaluator declined a shift count
// >= 64, while Zig folds them exactly):
//   * `[1 << 4]u8` = 16 (shift in a size expression);
//   * `[(2 + 1) * 2]u8` = 6 (parenthesized arithmetic);
//   * `[3 & 3]u8` = 3 (bitwise in a size expression);
//   * `[MSHIFT]u8` = 32 with `const MSHIFT: u64 = 1 << 5;` (ident chain through
//     the exact shift; the module const's initializer recurses);
//   * `[@intCast(u64, 1 << 6)]u8` = 64 (the array-size `@intCast` arm folds its
//     operand exactly, still range-checked against the target);
//   * `[(1 << 200) >> 190]u8` = 1024 (a >64-bit intermediate reduced back into
//     range — the old evaluators declined at the shift);
//   * `enum(u64) { A = (1 << 200) >> 190, B }` -> 1024 / 1025 (same exact
//     intermediate in an enum initializer, auto-increment follower);
//   * `enum(u16) { A = 1 << 12, B }` -> 4096 / 4097;
//   * `enum(u8) { A = 6 & 3, B }` -> 2 / 3.
//
// Oracle output (Zig 0.15.2 twin, `/tmp/task5/oracle/constfold_twin.zig`; the
// twin spells the 2-arg Z98 `@intCast(u64, 1 << 6)` as `@as(u64, 1 << 6)` and
// `@enumToInt` as `@intFromEnum`):
//   16 6 3 32 64 1024
//   1024 1025 4096 4097 2 3
//
// Contract: stdout below, rc 0, byte-exact 3x.
const std = @import("std");

const MSHIFT: u64 = 1 << 5;

const EShift = enum(u64) { A = (1 << 200) >> 190, B };
const EMod = enum(u16) { A = 1 << 12, B };
const EBit = enum(u8) { A = 6 & 3, B };

pub fn main() void {
    var a1: [1 << 4]u8 = undefined;
    var a2: [(2 + 1) * 2]u8 = undefined;
    var a3: [3 & 3]u8 = undefined;
    var a4: [MSHIFT]u8 = undefined;
    var a5: [@intCast(u64, 1 << 6)]u8 = undefined;
    var a6: [(1 << 200) >> 190]u8 = undefined;
    const e1 = @enumToInt(EShift.A);
    const e2 = @enumToInt(EShift.B);
    const e3 = @enumToInt(EMod.A);
    const e4 = @enumToInt(EMod.B);
    const e5 = @enumToInt(EBit.A);
    const e6 = @enumToInt(EBit.B);
    if (a1.len != 16) { @panic("a1"); }
    if (a2.len != 6) { @panic("a2"); }
    if (a3.len != 3) { @panic("a3"); }
    if (a4.len != 32) { @panic("a4"); }
    if (a5.len != 64) { @panic("a5"); }
    if (a6.len != 1024) { @panic("a6"); }
    if (e1 != 1024) { @panic("e1"); }
    if (e2 != 1025) { @panic("e2"); }
    if (e3 != 4096) { @panic("e3"); }
    if (e4 != 4097) { @panic("e4"); }
    if (e5 != 2) { @panic("e5"); }
    if (e6 != 3) { @panic("e6"); }
    std.io.print("{} {} {} {} {} {}\n", .{ a1.len, a2.len, a3.len, a4.len, a5.len, a6.len });
    std.io.print("{} {} {} {} {} {}\n", .{ e1, e2, e3, e4, e5, e6 });
}
