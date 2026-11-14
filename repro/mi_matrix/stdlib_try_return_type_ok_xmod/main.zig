// stdlib_try_return_type_ok_xmod — FX12 (Volume II ch12) positive runtime
// fixture.
//
// Every LEGAL `try` enclosing-return shape must stay accepted (the 3075
// enforcement is a reject-only addition), run correctly and deterministically:
//   * `main() !void` with `try`;
//   * `E!T` function with an `E!void` operand (set-only comparison: payload
//     equality is NOT required);
//   * anonymous `!T` signature and anonymous `!T` operand;
//   * superset enclosing set (`E subset F`) and same-set cross-module operand;
//   * `try` in an if-VALUE and in a switch-VALUE inside an error-union
//     function;
//   * `try` inside a nested block;
//   * a local error-union variable operand;
//   * `!void` fall-off with `try` (implicit success).
//
// Contract: stdout `expected.txt` byte-exact 3x, rc 0; every observed value is
// `@panic`-guarded so a mis-typed `try` traps instead of passing silently.
const std = @import("std");
const helper = @import("helper.zig");

const E = error{Boom};
const F = error{Boom, Other};

fn p(v: i32) void {
    std.io.print("{}\n", .{v});
}

// `E!void` operand consumed by an `E!i32` function (payload need not match).
fn voidOperand() E!void {
    return;
}

fn emptyOk() E!i32 {
    try voidOperand();
    return 41;
}

// Anonymous `!T` operand.
fn anonOk() !i32 {
    return 11;
}

fn anonCaller() !i32 {
    const a = try anonOk();
    return a + 1;
}

// Superset enclosing set (`E subset F`).
fn subOperand() E!void {
    return;
}

fn supersetCaller() F!void {
    try subOperand();
}

// `try` in an if-VALUE inside an error-union function.
fn ifValue(c: bool) !i32 {
    const x = if (c) try anonOk() else 0;
    return x;
}

// `try` in a switch-VALUE inside an error-union function.
fn switchValue(c: i32) !i32 {
    const x = switch (c) {
        1 => try anonOk(),
        else => 0,
    };
    return x;
}

// `try` inside a nested block.
fn nestedBlock() !i32 {
    {
        const a = try anonOk();
        return a + 2;
    }
}

// Local error-union variable operand.
fn localVarOperand() !i32 {
    const eu: E!i32 = 33;
    return try eu;
}

// Same named set, cross-module.
fn xmodCaller() E!i32 {
    return try helper.gOk();
}

// `!void` fall-off with `try` (implicit success).
fn fallOff() !void {
    try voidOperand();
}

pub fn main() !void {
    const v1: i32 = try emptyOk();
    if (v1 != 41) @panic("emptyOk");
    p(v1);

    const v2 = try anonCaller();
    if (v2 != 12) @panic("anonCaller");
    p(v2);

    try supersetCaller();

    const v3 = try ifValue(true);
    if (v3 != 11) @panic("ifValue");
    p(v3);

    const v4 = try switchValue(1);
    if (v4 != 11) @panic("switchValue");
    p(v4);

    const v5 = try nestedBlock();
    if (v5 != 13) @panic("nestedBlock");
    p(v5);

    const v6 = try localVarOperand();
    if (v6 != 33) @panic("localVarOperand");
    p(v6);

    const v7 = try xmodCaller();
    if (v7 != 77) @panic("xmodCaller");
    p(v7);

    try fallOff();

    std.io.print("ok\n", .{});
}
