// stdlib_switch_case_consts_xmod — FX1 runtime fixture for named-constant and
// `bool` switch case items / range bounds (D2 extras).
//
// DEFECT pinned (FX1, D2 extras): `lowerAppendSwitchCaseItem` resolved only
// int/char literals and (after FA-a) enum member endpoints, so named-constant
// case items and range bounds (`LO`, `LO...HI`, `mod.LO`), enum-member consts
// (`const LOMEM = Color.Red;`), unqualified member names (`Blue`) and
// `bool_literal` items appended ZERO C `case` labels — every value silently
// took `else` (wrong stdout, rc 0).
// FIX (FX1): the shared case-item resolver now also resolves
//   - typed/untyped int consts (same module and module-qualified `helper.LO`),
//     including constant arithmetic, through the exact const evaluator;
//   - enum-member consts by walking the constant's initializer chain
//     (`Color.Red` / `.Red` / `Red` / alias consts) to the member name, then
//     resolving it against the condition enum via `member.value` (so
//     `enum(u8)` gaps are exact);
//   - unqualified enum member names and `bool_literal` items (`true`/`false`).
// The int/char literal paths and the >16384 / hi<lo / empty-exclusive caps are
// unchanged; the FA-a enum-range fix is untouched.
//
// Contract: stdout rows below, rc 0, byte-exact 3x. The first 15 rows (through
// `stmt`) are byte-identical to the official Zig 0.15.2 twin
// (/tmp/fx1/oracle/twin.zig, `std.debug.print`); the trailing rows are Z98
// extensions (Zig 0.15.2 rejects ranges on enum conditions and an unreachable
// `else` prong, which Z98's mandatory-`else` rule requires).
//   intrange 10 10 20
//   untyped 12 12 22
//   exact 14 24
//   mixed 16 16 26
//   mixedconst 15 25 15
//   xmod 30 30 40
//   xmodexact 32 42
//   enexact 50 60
//   enalias 52 62
//   entyped 54 64
//   engap 56 66
//   xmodenum 58 68
//   xmodgap 59 69
//   boolp 90 92
//   stmt 100 102
//   enrange 70 70 80
//   enrangemix 72 72 82
//   enrangeident 74 74 74
//   xmodrange 76 76 86
//   boolfull 94 96
const std = @import("std");
const helper = @import("helper.zig");

const Color = enum { Red, Green, Blue };
const Code = enum(u8) { A = 1, B = 5, C = 9 };

const LO: i32 = 1;
const HI: i32 = 5;
const ULO = 2;
const UHI = 4;
const PICK = 3;
const SUM = 1 + 4;
const LOMEM = Color.Red;
const HIMEM = Color.Green;
const LOMEM_T: Color = .Red;
const ALIAS = LOMEM;
const CODE_A: Code = .A;

fn intrange(x: i32) i32 {
    return switch (x) {
        LO...HI => 10,
        else => 20,
    };
}

fn untyped(x: i32) i32 {
    return switch (x) {
        ULO...UHI => 12,
        else => 22,
    };
}

fn exact(x: i32) i32 {
    return switch (x) {
        PICK => 14,
        else => 24,
    };
}

fn mixed(x: i32) i32 {
    return switch (x) {
        LO, 2 => 16,
        else => 26,
    };
}

fn mixedconst(x: i32) i32 {
    return switch (x) {
        PICK, SUM => 15,
        else => 25,
    };
}

fn xmod(x: i32) i32 {
    return switch (x) {
        helper.LO...helper.HI => 30,
        else => 40,
    };
}

fn xmodexact(x: i32) i32 {
    return switch (x) {
        helper.PICK => 32,
        else => 42,
    };
}

fn enexact(c: Color) i32 {
    return switch (c) {
        LOMEM => 50,
        else => 60,
    };
}

fn enalias(c: Color) i32 {
    return switch (c) {
        ALIAS => 52,
        else => 62,
    };
}

fn entyped(c: Color) i32 {
    return switch (c) {
        LOMEM_T => 54,
        else => 64,
    };
}

fn engap(c: Code) i32 {
    return switch (c) {
        CODE_A => 56,
        else => 66,
    };
}

fn xmodenum(c: helper.Color) i32 {
    return switch (c) {
        helper.LOMEM => 58,
        else => 68,
    };
}

fn xmodgap(c: helper.Code) i32 {
    return switch (c) {
        helper.CODE_A => 59,
        else => 69,
    };
}

fn boolp(b: bool) i32 {
    return switch (b) {
        true => 90,
        else => 92,
    };
}

fn stmt(x: i32) i32 {
    var r: i32 = 0;
    switch (x) {
        LO...HI => { r = 100; },
        else => { r = 102; },
    }
    return r;
}

fn enrange(c: Color) i32 {
    return switch (c) {
        LOMEM...HIMEM => 70,
        else => 80,
    };
}

fn enrangemix(c: Color) i32 {
    return switch (c) {
        .Red...HIMEM => 72,
        else => 82,
    };
}

fn enrangeident(c: Color) i32 {
    return switch (c) {
        LOMEM...Blue => 74,
        else => 84,
    };
}

fn xmodrange(c: helper.Color) i32 {
    return switch (c) {
        helper.LOMEM...helper.HIMEM => 76,
        else => 86,
    };
}

fn boolfull(b: bool) i32 {
    return switch (b) {
        true => 94,
        false => 96,
        else => 98,
    };
}

pub fn main() void {
    if (intrange(1) != 10) { @panic("intrange-lo"); }
    if (intrange(5) != 10) { @panic("intrange-hi"); }
    if (intrange(6) != 20) { @panic("intrange-out"); }
    std.io.print("intrange {} {} {}\n", .{ intrange(1), intrange(5), intrange(6) });

    if (untyped(2) != 12) { @panic("untyped-lo"); }
    if (untyped(4) != 12) { @panic("untyped-hi"); }
    if (untyped(5) != 22) { @panic("untyped-out"); }
    std.io.print("untyped {} {} {}\n", .{ untyped(2), untyped(4), untyped(5) });

    if (exact(3) != 14) { @panic("exact-hit"); }
    if (exact(4) != 24) { @panic("exact-miss"); }
    std.io.print("exact {} {}\n", .{ exact(3), exact(4) });

    if (mixed(1) != 16) { @panic("mixed-const"); }
    if (mixed(2) != 16) { @panic("mixed-lit"); }
    if (mixed(3) != 26) { @panic("mixed-miss"); }
    std.io.print("mixed {} {} {}\n", .{ mixed(1), mixed(2), mixed(3) });

    if (mixedconst(3) != 15) { @panic("mixedconst-pick"); }
    if (mixedconst(4) != 25) { @panic("mixedconst-miss"); }
    if (mixedconst(5) != 15) { @panic("mixedconst-sum"); }
    std.io.print("mixedconst {} {} {}\n", .{ mixedconst(3), mixedconst(4), mixedconst(5) });

    if (xmod(1) != 30) { @panic("xmod-lo"); }
    if (xmod(5) != 30) { @panic("xmod-hi"); }
    if (xmod(6) != 40) { @panic("xmod-out"); }
    std.io.print("xmod {} {} {}\n", .{ xmod(1), xmod(5), xmod(6) });

    if (xmodexact(3) != 32) { @panic("xmodexact-hit"); }
    if (xmodexact(4) != 42) { @panic("xmodexact-miss"); }
    std.io.print("xmodexact {} {}\n", .{ xmodexact(3), xmodexact(4) });

    if (enexact(Color.Red) != 50) { @panic("enexact-red"); }
    if (enexact(Color.Green) != 60) { @panic("enexact-green"); }
    std.io.print("enexact {} {}\n", .{ enexact(Color.Red), enexact(Color.Green) });

    if (enalias(Color.Red) != 52) { @panic("enalias-red"); }
    if (enalias(Color.Green) != 62) { @panic("enalias-green"); }
    std.io.print("enalias {} {}\n", .{ enalias(Color.Red), enalias(Color.Green) });

    if (entyped(Color.Red) != 54) { @panic("entyped-red"); }
    if (entyped(Color.Green) != 64) { @panic("entyped-green"); }
    std.io.print("entyped {} {}\n", .{ entyped(Color.Red), entyped(Color.Green) });

    if (engap(Code.A) != 56) { @panic("engap-a"); }
    if (engap(Code.B) != 66) { @panic("engap-b"); }
    std.io.print("engap {} {}\n", .{ engap(Code.A), engap(Code.B) });

    if (xmodenum(helper.Color.Red) != 58) { @panic("xmodenum-red"); }
    if (xmodenum(helper.Color.Green) != 68) { @panic("xmodenum-green"); }
    std.io.print("xmodenum {} {}\n", .{ xmodenum(helper.Color.Red), xmodenum(helper.Color.Green) });

    if (xmodgap(helper.Code.A) != 59) { @panic("xmodgap-a"); }
    if (xmodgap(helper.Code.B) != 69) { @panic("xmodgap-b"); }
    std.io.print("xmodgap {} {}\n", .{ xmodgap(helper.Code.A), xmodgap(helper.Code.B) });

    if (boolp(true) != 90) { @panic("boolp-true"); }
    if (boolp(false) != 92) { @panic("boolp-false"); }
    std.io.print("boolp {} {}\n", .{ boolp(true), boolp(false) });

    if (stmt(2) != 100) { @panic("stmt-hit"); }
    if (stmt(9) != 102) { @panic("stmt-miss"); }
    std.io.print("stmt {} {}\n", .{ stmt(2), stmt(9) });

    if (enrange(Color.Red) != 70) { @panic("enrange-red"); }
    if (enrange(Color.Green) != 70) { @panic("enrange-green"); }
    if (enrange(Color.Blue) != 80) { @panic("enrange-blue"); }
    std.io.print("enrange {} {} {}\n", .{ enrange(Color.Red), enrange(Color.Green), enrange(Color.Blue) });

    if (enrangemix(Color.Red) != 72) { @panic("enrangemix-red"); }
    if (enrangemix(Color.Green) != 72) { @panic("enrangemix-green"); }
    if (enrangemix(Color.Blue) != 82) { @panic("enrangemix-blue"); }
    std.io.print("enrangemix {} {} {}\n", .{ enrangemix(Color.Red), enrangemix(Color.Green), enrangemix(Color.Blue) });

    if (enrangeident(Color.Red) != 74) { @panic("enrangeident-red"); }
    if (enrangeident(Color.Green) != 74) { @panic("enrangeident-green"); }
    if (enrangeident(Color.Blue) != 74) { @panic("enrangeident-blue"); }
    std.io.print("enrangeident {} {} {}\n", .{ enrangeident(Color.Red), enrangeident(Color.Green), enrangeident(Color.Blue) });

    if (xmodrange(helper.Color.Red) != 76) { @panic("xmodrange-red"); }
    if (xmodrange(helper.Color.Green) != 76) { @panic("xmodrange-green"); }
    if (xmodrange(helper.Color.Blue) != 86) { @panic("xmodrange-blue"); }
    std.io.print("xmodrange {} {} {}\n", .{ xmodrange(helper.Color.Red), xmodrange(helper.Color.Green), xmodrange(helper.Color.Blue) });

    if (boolfull(true) != 94) { @panic("boolfull-true"); }
    if (boolfull(false) != 96) { @panic("boolfull-false"); }
    std.io.print("boolfull {} {}\n", .{ boolfull(true), boolfull(false) });
}
