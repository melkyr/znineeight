// volatile_mmio_xmod — GREEN (A10F). Zig-style pointer-pointee `volatile`
// qualifier (`*volatile u32`, `[*]volatile u32`, `*volatile *u32`) with
// `@volatileCast` and implicit add-volatile coercion, across modules.
//
// RED baseline: `*volatile` is not parseable (`volatile` lexes as an
// identifier -> `error[2000]`); `@volatileCast` is `error[3000] unsupported
// builtin function`.
// GREEN contract: compile/link/run clean, prints "4660\n85\n" byte-exact.
const mod = @import("mod.zig");
const std = @import("std");

pub fn main() void {
    var reg: u32 = 0;

    const mmio: *volatile u32 = @ptrCast(*volatile u32, &reg); // explicit add
    mod.poke(mmio, 0x1234);
    std.io.printInt(@intCast(i32, mod.peek(mmio)));
    std.io.writeByte('\n');

    const plain: *u32 = @volatileCast(*u32, mmio); // sanctioned volatile removal
    plain.* = 0x55;
    std.io.printInt(@intCast(i32, mmio.*));
    std.io.writeByte('\n');

    const q: *volatile u32 = &reg; // implicit add-volatile coercion
    _ = q;

    const r: mod.Reg = mmio; // cross-module pointer alias
    _ = r;

    var inner: *u32 = &reg;
    var vpp: *volatile *u32 = &inner; // append rule: unsigned int* volatile*
    vpp.*.* = 1;
}
