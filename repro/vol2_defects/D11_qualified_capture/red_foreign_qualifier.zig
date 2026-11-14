// D11 validation (FX4): a qualified prong whose qualifier denotes a type
// other than the switch condition's enum/tagged-union type now rejects
// level-0 `error[3071]` (before FX4 `B.x` dispatched as `A.x` and `B.z` was
// silently dead). The mismatch wins over a missing member (`B.z`).
//
// Contract with the current compiler: compile rc 2, 0 `.c`, 4 x `error[3071]`
// + 1 x `error[20]` (the captured `B.x` prong's unbound-capture cascade stays
// visible — no suppression).
const A = union(enum) { x: i32, y: i32 };
const B = union(enum) { x: i32, z: i32 };
const C1 = enum { a, b };
const C2 = enum { b, a };

fn f1(v: A) i32 { return switch (v) { B.x => 100, else => 0 }; }
fn f2(c: C1) i32 { return switch (c) { C2.b => 100, else => 0 }; }
fn f3(v: A) i32 { return switch (v) { B.z => 100, else => 0 }; }
fn f4(v: A) i32 { return switch (v) { B.x => |r| r, else => 0 }; }

pub fn main() void {
    _ = f1;
    _ = f2;
    _ = f3;
    _ = f4;
}
