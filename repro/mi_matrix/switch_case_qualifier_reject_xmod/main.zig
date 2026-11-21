// switch_case_qualifier_reject_xmod — FX4 (Volume II D11 extras) reject
// fixture: a qualified switch prong whose qualifier does not denote the
// switch condition's enum/tagged-union type (foreign qualifier) and a
// qualified or shorthand prong whose member does not exist on the condition
// type (bogus member) are level-0 `error[3071]` rejects.
//
// Before FX4 the qualified member was silently name-matched against the
// condition (a foreign `B.x` dispatched as `A.x`) and an unknown member
// silently emitted no `case` label (dead prong). Zig 0.15.2 rejects every
// shape. The foreign qualifier wins over a missing member (`B.z`), matching
// Zig's mismatch-before-member order.
//
// Contract: compile rc 2, no `.c` emitted, no signal; the exact census is
// pinned in `expected_error.txt` (`3071 12` primary sites + the two cascading
// `error[20]` unbound-capture diagnostics, which are deliberately NOT
// suppressed).
const helper = @import("helper.zig");

const Shape = union(enum) { circle: i32, rect: i32, empty };
const Color = enum { red, green, blue };
const B = union(enum) { x: i32, z: i32 };
const C1 = enum { a, b };
const C2 = enum { b, a };

// 1. qualified bogus member (tagged union)
fn q1(s: Shape) i32 { return switch (s) { Shape.bogus => 1, else => 0 }; }

// 2. qualified bogus member (enum)
fn q2(c: Color) i32 { return switch (c) { Color.bogus => 1, else => 0 }; }

// 3. shorthand bogus member (tagged union)
fn q3(s: Shape) i32 { return switch (s) { .bogus => 1, else => 0 }; }

// 4. shorthand bogus member (enum)
fn q4(c: Color) i32 { return switch (c) { .bogus => 1, else => 0 }; }

// 5. foreign qualifier (tagged union)
fn q5(a: Shape) i32 { return switch (a) { B.x => 1, else => 0 }; }

// 6. foreign qualifier whose member is ALSO missing (mismatch wins)
fn q6(a: Shape) i32 { return switch (a) { B.z => 1, else => 0 }; }

// 7. foreign qualifier (enum)
fn q7(c: C1) i32 { return switch (c) { C2.b => 1, else => 0 }; }

// 8. bogus member + capture: 3071 AND the unbound-capture error[20] cascade
fn q8(s: Shape) i32 { return switch (s) { Shape.nope => |r| r, else => 0 }; }

// 9. foreign qualifier + capture: 3071 AND the error[20] cascade
fn q9(a: Shape) i32 { return switch (a) { B.x => |r| r, else => 0 }; }

// 10. cross-module qualified bogus member
fn q10(s: helper.Shape) i32 { return switch (s) { helper.Shape.bogus => 1, else => 0 }; }

// 11. cross-module foreign qualifier
fn q11(a: helper.Other) i32 { return switch (a) { helper.Shape.circle => 1, else => 0 }; }

// 12. value qualifier with a bogus member (`s.bogus`)
fn q12(s: Shape) i32 { return switch (s) { s.bogus => 1, else => 0 }; }

pub fn main() void {
    _ = q1;
    _ = q2;
    _ = q3;
    _ = q4;
    _ = q5;
    _ = q6;
    _ = q7;
    _ = q8;
    _ = q9;
    _ = q10;
    _ = q11;
    _ = q12;
}
