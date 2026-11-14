// stdlib_switch_enum_range_xmod — FA-a runtime fixture for D2 enum switch
// range prongs (with the strict mandatory `else`; no switch here omits it).
//
// DEFECT pinned (D2, repro/vol2_defects/D02_enum_switch_ranges): enum-typed
// range prong endpoints were accepted only as int/char literals in
// `lowerAppendSwitchCaseItem`'s range branch, so `Color.Red...Color.Green` /
// `.Red... .Blue` appended ZERO C `case` labels and every value silently took
// `else` (wrong stdout, rc 0).
// FIX (FA-a): the range branch resolves its endpoints through the shared
// `lowerSwitchCaseItemValue` helper — `enum_literal` / `field_access` resolved
// by member name against the condition enum via `member.value` (so `enum(uN)`
// gaps are exact), exactly like the exact-case tail; the integer/char literal
// path and the >16384 / hi<lo / empty-exclusive caps are unchanged.
//
// Contract: stdout rows below, rc 0, byte-exact 3x. The int/char range rows
// are byte-identical to the official Zig 0.15.2 twin; enum ranges are a Z98
// extension (Zig 0.15.2 rejects "ranges not allowed when switching on type
// 'Color'").
//   incl 10 10 20
//   excl 30 30 40
//   mixed 60 60 50
//   shorthand 80 80 80
//   halfsh 81 81 81
//   gaps 100 100 100
//   gapsx 120 120 130
//   xmod 140 140 150
//   xmodsh 160 160 160
//   stmt 180 180 190
//   ints 200 210 220
//   chars 230 240
//   nomatch 250 260
const std = @import("std");
const colors = @import("colors.zig");

const Color = enum { Red, Green, Blue };
const Code = enum(u8) { A = 1, B = 5, C = 9 };

fn incl(c: Color) i32 {
    return switch (c) {
        Color.Red...Color.Green => 10,
        else => 20,
    };
}

fn excl(c: Color) i32 {
    return switch (c) {
        Color.Red..Color.Blue => 30,
        else => 40,
    };
}

fn mixed(c: Color) i32 {
    return switch (c) {
        Color.Blue => 50,
        Color.Red...Color.Green => 60,
        else => 70,
    };
}

fn shorthand(c: Color) i32 {
    return switch (c) {
        .Red... .Blue => 80,
        else => 90,
    };
}

fn halfsh(c: Color) i32 {
    return switch (c) {
        .Red...Color.Blue => 81,
        else => 91,
    };
}

fn gaps(c: Code) i32 {
    return switch (c) {
        Code.A...Code.C => 100,
        else => 110,
    };
}

fn gapsx(c: Code) i32 {
    return switch (c) {
        Code.A..Code.C => 120,
        else => 130,
    };
}

fn xmod(c: colors.Color) i32 {
    return switch (c) {
        colors.Color.Red...colors.Color.Green => 140,
        else => 150,
    };
}

fn xmodsh(c: colors.Color) i32 {
    return switch (c) {
        .Red... .Blue => 160,
        else => 170,
    };
}

fn stmt(c: Color) i32 {
    var r: i32 = 0;
    switch (c) {
        Color.Red...Color.Green => { r = 180; },
        else => { r = 190; },
    }
    return r;
}

fn ints(x: i32) i32 {
    return switch (x) {
        1...5 => 200,
        7..9 => 210,
        else => 220,
    };
}

fn chars(c: u8) i32 {
    return switch (c) {
        'a'...'c' => 230,
        else => 240,
    };
}

fn nomatch(c: Color) i32 {
    return switch (c) {
        Color.Red...Color.Green => 250,
        else => 260,
    };
}

pub fn main() void {
    if (incl(Color.Red) != 10) { @panic("incl-red"); }
    if (incl(Color.Green) != 10) { @panic("incl-green"); }
    if (incl(Color.Blue) != 20) { @panic("incl-blue"); }
    std.io.print("incl {} {} {}\n", .{ incl(Color.Red), incl(Color.Green), incl(Color.Blue) });

    if (excl(Color.Red) != 30) { @panic("excl-red"); }
    if (excl(Color.Green) != 30) { @panic("excl-green"); }
    if (excl(Color.Blue) != 40) { @panic("excl-blue"); }
    std.io.print("excl {} {} {}\n", .{ excl(Color.Red), excl(Color.Green), excl(Color.Blue) });

    if (mixed(Color.Red) != 60) { @panic("mixed-red"); }
    if (mixed(Color.Green) != 60) { @panic("mixed-green"); }
    if (mixed(Color.Blue) != 50) { @panic("mixed-blue"); }
    std.io.print("mixed {} {} {}\n", .{ mixed(Color.Red), mixed(Color.Green), mixed(Color.Blue) });

    if (shorthand(Color.Red) != 80) { @panic("sh-red"); }
    if (shorthand(Color.Green) != 80) { @panic("sh-green"); }
    if (shorthand(Color.Blue) != 80) { @panic("sh-blue"); }
    std.io.print("shorthand {} {} {}\n", .{ shorthand(Color.Red), shorthand(Color.Green), shorthand(Color.Blue) });

    if (halfsh(Color.Red) != 81) { @panic("halfsh-red"); }
    if (halfsh(Color.Green) != 81) { @panic("halfsh-green"); }
    if (halfsh(Color.Blue) != 81) { @panic("halfsh-blue"); }
    std.io.print("halfsh {} {} {}\n", .{ halfsh(Color.Red), halfsh(Color.Green), halfsh(Color.Blue) });

    if (gaps(Code.A) != 100) { @panic("gaps-a"); }
    if (gaps(Code.B) != 100) { @panic("gaps-b"); }
    if (gaps(Code.C) != 100) { @panic("gaps-c"); }
    std.io.print("gaps {} {} {}\n", .{ gaps(Code.A), gaps(Code.B), gaps(Code.C) });

    if (gapsx(Code.A) != 120) { @panic("gapsx-a"); }
    if (gapsx(Code.B) != 120) { @panic("gapsx-b"); }
    if (gapsx(Code.C) != 130) { @panic("gapsx-c"); }
    std.io.print("gapsx {} {} {}\n", .{ gapsx(Code.A), gapsx(Code.B), gapsx(Code.C) });

    if (xmod(colors.Color.Red) != 140) { @panic("xmod-red"); }
    if (xmod(colors.Color.Green) != 140) { @panic("xmod-green"); }
    if (xmod(colors.Color.Blue) != 150) { @panic("xmod-blue"); }
    std.io.print("xmod {} {} {}\n", .{ xmod(colors.Color.Red), xmod(colors.Color.Green), xmod(colors.Color.Blue) });

    if (xmodsh(colors.Color.Red) != 160) { @panic("xmodsh-red"); }
    if (xmodsh(colors.Color.Green) != 160) { @panic("xmodsh-green"); }
    if (xmodsh(colors.Color.Blue) != 160) { @panic("xmodsh-blue"); }
    std.io.print("xmodsh {} {} {}\n", .{ xmodsh(colors.Color.Red), xmodsh(colors.Color.Green), xmodsh(colors.Color.Blue) });

    if (stmt(Color.Red) != 180) { @panic("stmt-red"); }
    if (stmt(Color.Green) != 180) { @panic("stmt-green"); }
    if (stmt(Color.Blue) != 190) { @panic("stmt-blue"); }
    std.io.print("stmt {} {} {}\n", .{ stmt(Color.Red), stmt(Color.Green), stmt(Color.Blue) });

    if (ints(3) != 200) { @panic("ints-3"); }
    if (ints(8) != 210) { @panic("ints-8"); }
    if (ints(6) != 220) { @panic("ints-6"); }
    std.io.print("ints {} {} {}\n", .{ ints(3), ints(8), ints(6) });

    if (chars('a') != 230) { @panic("chars-a"); }
    if (chars('z') != 240) { @panic("chars-z"); }
    std.io.print("chars {} {}\n", .{ chars('a'), chars('z') });

    if (nomatch(Color.Red) != 250) { @panic("nomatch-red"); }
    if (nomatch(Color.Blue) != 260) { @panic("nomatch-blue"); }
    std.io.print("nomatch {} {}\n", .{ nomatch(Color.Red), nomatch(Color.Blue) });
}
