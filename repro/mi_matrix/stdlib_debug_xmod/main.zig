// stdlib_debug_xmod — STDLIB std_debug logging GREEN fixture.
//
// std_debug.zig is re-exported from std.zig as `debug`; this fixture imports
// it via a BARE `@import("std")` (lib search path binds the canonical
// <exe>/lib std module) and exercises log / logInt / passing assert.
//
// PANIC MECHANISM: assert(false)/panic() print a message then enter a
// non-returning while-true trap (AMENDMENT 1 — @panic/unreachable are no-ops
// in user programs). Those paths HANG and are deliberately NOT exercised here;
// the failing path is proven by a separate scratch probe. This fixture only
// calls passing asserts.
//
// SHIPPED COMPILER FEATURES pinned alongside the module:
//   - optional return `?usize` from findByte + `orelse` fallback
//   - `for` loop over a []const u8 slice with element payload capture
//   - u32 unsigned comparison (`4000000000 > 100` is true only if the compare
//     is unsigned — a signed i32 interpretation would be negative)
//   - i32 negative literal formatting in logInt
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0):
//   debug-ok
//   pos: 42
//   neg: -7
//   zero: 0
//   idx: 6
//   dash: 1
//   wide: 1
const std = @import("std");

fn findByte(s: []const u8, c: u8) ?usize {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == c) return i;
    }
    return null;
}

pub fn main() void {
    var msg: []const u8 = "debug-ok\n";
    std.debug.log(msg);

    std.debug.assert(1 == 1);
    std.debug.assert(2 > 1);

    std.debug.logInt("pos", 42);
    std.debug.logInt("neg", -7);
    std.debug.logInt("zero", 0);

    var idx = findByte(msg, 'o') orelse 99;
    std.debug.logInt("idx", @intCast(i32, idx));

    var dash: i32 = 0;
    for (msg) |ch| {
        if (ch == '-') dash += 1;
    }
    std.debug.logInt("dash", dash);

    var w: u32 = 4000000000;
    if (w > 100) {
        std.debug.logInt("wide", 1);
    } else {
        std.debug.logInt("wide", 0);
    }
}
