// bare_enum_literal_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Task 0c-reported residual gap (declared here per the standing declare-every-gap rule):
// a BARE plain-enum literal in VALUE position is mis-lowered. `var c: C = .A;` followed by
// `@enumToInt(c)` yields a garbage tag (Task 0c probe p16 printed 2 for .A and 8 for .B;
// passing .A/.B as arguments printed 8/10), and a switch over a global initialized with a
// bare literal takes the wrong prong (p20 printed 20 for .A). `@intToEnum(C, 0/1)` is
// correct, which is why every S19/S20 fixture drives tags through @intToEnum.
//
// RED today: dump rc=0 / gcc-clean / link rc=0 / run rc=133 (assert trap). GREEN when the
// bare-enum-literal value-position lowering is fixed (out of Task 0f's S20/S21 scope).
//
// This is a DISTINCT defect from the string->slice gaps; it is declared (not fixed) here.
const std = @import("std");

const C = enum { A, B };

var g: C = .A;

pub fn main() void {
    var c: C = .A;
    if (@intCast(i32, @enumToInt(c)) != 0) { @panic("bare_enum_literal_xmod: c = .A mis-lowered"); }
    c = .B;
    if (@intCast(i32, @enumToInt(c)) != 1) { @panic("bare_enum_literal_xmod: c = .B mis-lowered"); }

    var v: i32 = switch (g) {
        .A => @intCast(i32, 10),
        .B => @intCast(i32, 20),
        else => @intCast(i32, 99),
    };
    if (v != 10) { @panic("bare_enum_literal_xmod: global .A switch mis-lowered"); }

    std.io.writeByte('O');
    std.io.writeByte('\n');
}
