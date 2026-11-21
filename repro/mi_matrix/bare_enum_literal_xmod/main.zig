// bare_enum_literal_xmod — RUNTIME-GREEN since Task 0m (was a runtime-RED declared gap).
//
// Task 0c-reported residual gap (originally declared here per the standing
// declare-every-gap rule): a BARE plain-enum literal in VALUE position was
// mis-lowered. `var c: C = .A;` followed by `@enumToInt(c)` yielded a garbage tag
// (Task 0c probe p16 printed 2 for .A and 8 for .B; passing .A/.B as arguments
// printed 8/10), and a switch over a global initialized with a bare literal took
// the wrong prong (p20 printed 20 for .A). `@intToEnum(C, 0/1)` was correct, which
// is why every S19/S20 fixture drives tags through @intToEnum.
//
// RESOLVED by Task 0m family D: `semanticAnalyzerResolveEnumLiteral` now honors a
// plain `enum_type` expected type (records the member value in `enum_value_table`
// and resolves the literal to that enum), so the value-position lowering is
// correct. Runtime: dump rc=0 / gcc-clean / link rc=0 / run rc=0 (stdout `O`).
// Previously run rc=133 (assert trap).
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
