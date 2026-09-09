// store_dedup_const_xmod — EMISSION-CORE compaction RED fixture (Part 1: decl-init 3x shape).
//
// Bug: a named-local `const x = f()` store (var_decl general init) is emitted as THREE
// identical consecutive C statements `x = zT_N;` (lower.zig decl path trio: store_local +
// assign name_id + assign backing-reg), when every later reader consumes the C variable `x`
// so 2 of the 3 writes are pure dead stores. This fixture pins the "proper emission"
// invariant: ONE C store per logical named-local store.
//
// GREEN (contract): deterministic stdout below (byte-exact, RUNRC=0). This fixture only
// exercises arithmetic over locally-const-declared values derived from runtime fn calls, so
// any correct compiler prints identical output.
// PROPER EMISSION (invariant this fixture guards): the emitted C of this program contains NO
// pair of consecutive identical `name = …;` lines — the duplicate named-local store must be
// collapsed at the lowering source.
const std = @import("std");

fn addThree(v: i32) i32 {
    return v + 3;
}

fn compute(v: i32) i32 {
    const a = addThree(v);
    const b = addThree(a);
    return b;
}

pub fn main() void {
    std.io.printInt(compute(1));
    std.io.writeByte('\n');
    std.io.printInt(compute(10));
    std.io.writeByte('\n');
    std.io.printInt(compute(100));
    std.io.writeByte('\n');
}
