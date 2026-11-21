// stdlib_bits_insert_trap_xmod — STDLIB std_bits (L0) insert out-of-range
// expected-failure probe (Plan A hardening Task 3).
//
// Contract (sf/src/std_bits.zig:125-141): insert traps via `unreachable` when
//   off >= 32, or len > 32, or off + len > 32.
// This probe drives the third guard with runtime (non-comptime) operands:
// argc is 1, so off = 1 + 27 = 28 and len = 8, giving off + len = 36 > 32.
// The out-of-range call MUST terminate the process at the trap (SIGTRAP,
// rc 133) before any stdout is produced.
//
// Expected-failure contract: empty stdout, rc 133. The trailing write is only
// reached if the guard is silently dropped, which makes the probe FAIL visibly
// with rc 0 and non-empty stdout.
//
// NOTE: extract and insert live in separate probe dirs because each process
// traps at most once (the harness asserts a single expected.rc per dir).
const std = @import("std");
const bits = @import("std_bits.zig");

pub fn main(argc: i32, argv: [*]*const u8) void {
    _ = argv;
    var off: u32 = @intCast(u32, argc) + 27;
    var len: u32 = 8;
    var r = bits.insert(@intCast(u32, 0), @intCast(u32, 0), off, len);
    _ = r;
    std.io.write("bits insert no-trap FAIL\n");
}
