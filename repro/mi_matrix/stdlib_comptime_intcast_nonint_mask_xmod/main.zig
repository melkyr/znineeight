// stdlib_comptime_intcast_nonint_mask_xmod — Task 4 fix-round coverage pin for
// the non-integer `@intCast` target masking carry-item.
//
// Z98 accepts a non-integer `@intCast` target (`@intCast(f32, v)`) and, before
// Task 2, masked the folded bits to the target's byte size. Task 2's exact
// representation dropped the mask (the raw exact value survived, which made the
// outer `@intCast(i32, ...)` reject where it previously fit); the Task 4 carry
// item restored the masking: the folded bits are reduced to the target's
// `size * 8` low bits of the two's-complement pattern. `@intCast(f32,
// 4294967596)` therefore folds to 300 (0x12C), not 4294967596, so the outer
// `@intCast(i32, ...)` fits and the program prints 300.
//
// This shape is a Z98-only extension: official Zig 0.15.2 rejects a
// non-integer `@intCast` target (`expected integer type, found 'f32'`) and has
// no 2-argument `@intCast`, so there is no oracle twin; the golden pins the
// restored pre-Task-2 semantics (see doc 04 §Task 4 and Known Issues).
//
// Contract: stdout `masked=300`, rc 0, byte-exact 3x.
const std = @import("std");

const MASKED = @intCast(i32, @intCast(f32, 4294967596));

pub fn main() void {
    if (MASKED != 300) { @panic("masked"); }
    std.io.print("masked={}\n", .{MASKED});
}
