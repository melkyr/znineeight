// store_dedup_assign_xmod — EMISSION-CORE compaction RED fixture (Part 1: plain-assign 2x shape).
//
// Bug: a plain named-local store `x = expr;` (lowerAssignLValue ident arm) is emitted as TWO
// identical consecutive C statements `x = zT_N;` (store_local + assign backing-reg), when
// every later reader consumes the C variable `x` so one of the two writes is a pure dead
// store. This fixture pins the "proper emission" invariant: ONE C store per logical
// named-local store.
//
// GREEN (contract): deterministic stdout below (byte-exact, RUNRC=0). This fixture only
// exercises plain reassignments of locals from runtime arithmetic, so any correct compiler
// prints identical output.
// PROPER EMISSION (invariant this fixture guards): the emitted C of this program contains NO
// pair of consecutive identical `name = …;` lines — the duplicate named-local store must be
// collapsed at the lowering source.
const std = @import("std");

fn bump(v: i32) i32 {
    var x: i32 = 0;
    x = v;
    x = x + 1;
    return x;
}

pub fn main() void {
    std.io.printInt(bump(4));
    std.io.writeByte('\n');
    std.io.printInt(bump(40));
    std.io.writeByte('\n');
    std.io.printInt(bump(400));
    std.io.writeByte('\n');
}
