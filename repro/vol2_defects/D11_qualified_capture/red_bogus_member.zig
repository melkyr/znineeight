// D11 validation (FX4): a qualified or shorthand switch prong naming a
// non-existent member of the switch condition type now rejects level-0
// `error[3071]` (before FX4 all four compiled rc 0; `Shape.bogus`/`.bogus`
// emitted no `case` label — a dead prong).
//
// Contract with the current compiler: compile rc 2, 0 `.c`, 4 x `error[3071]`
// + 1 x `error[20]` (the captured `Shape.nope` prong's unbound-capture
// cascade stays visible — no suppression).
const Shape = union(enum) { circle: i32, rect: i32, empty };
const Color = enum { red, green, blue };

fn qUnion(s: Shape) i32 { return switch (s) { Shape.bogus => 1, else => 0 }; }
fn qEnum(c: Color) i32 { return switch (c) { Color.bogus => 1, else => 0 }; }
fn qShort(s: Shape) i32 { return switch (s) { .bogus => 1, else => 0 }; }
fn qCap(s: Shape) i32 { return switch (s) { Shape.nope => |r| r, else => 0 }; }

pub fn main() void {
    _ = qUnion;
    _ = qEnum;
    _ = qShort;
    _ = qCap;
}
