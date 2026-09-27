// stdlib_print_tuple_var_ok_xmod — FD2 (Volume II print tuple variables)
// positive runtime fixture.
//
// The Language Spec section 4 promises `print(fmt, args)` for a tuple literal
// OR a tuple variable. FD1 validated the container and clean-rejected
// non-tuples (error[3065]); FD2 lowers a tuple-variable container through the
// FB tuple model: the container is lowered once (lazily, on the first
// placeholder) and each placeholder reads its element through the shared
// tuple `load_field` mechanism. This fixture pins the accepted shapes at
// runtime:
//   basic   bare inferred tuple variable (`{} {}`)
//   specs   typed int tuple with explicit `{d}` / `{x}`
//   char    typed u8 tuple with explicit `{c}`
//   slice   slice element with explicit `{s}`
//   float   f64 elements (`{}`)
//   bool    bool elements (`{}`)
//   enm     enum element (`{}`) + integer element
//   agg     nested tuple element (aggregate printer)
//   stct    struct element inside the tuple (aggregate printer)
//   call    tuple-returning call as the container
//   field   tuple-typed struct field as the container
//   alias   aliased `print` callee
//   xmod    cross-module tuple parameter printed by the helper
//   big     FB2 value-chosen u32/i64 carriers (`3000000000`, `-3000000000`)
//   u32b    u32/i64 boundary (`4294967295`, `4294967296`)
//   u64b    u64 window (`9223372036854775808`, `18446744073709551615`)
//   i64b    i64 window (`9223372036854775807`, `-9223372036854775808`)
//   hexb    `{x}` on u32/u64 elements
//   negb    `{x}` on i64 negative elements
//   arithb  literal-only arithmetic elements (`2000000000 + 2000000000`)
//   refb    element reads (`w32[0]`/`w32[1]`) re-tupled and printed
//   litc    literal-container aggregate print of a big-element tuple
//   free    placeholder-free fmt (container is not evaluated)
//
// Contract: stdout (expected.txt), rc 0, byte-exact 3x. The Zig-0.15.2 twin
// (`std.debug.print`) prints every line byte-for-byte; for `free` the twin
// passes an empty tuple literal because Zig rejects unused arguments.
const std = @import("std");
const helper = @import("helper.zig");

const Color = enum { red, green };
const Pair = struct { i32, i32 };
const Bytes = struct { u8, u8 };
const S2 = struct { a: i32, b: i32 };
const Holder = struct { p: Pair };

fn mk() Pair {
    return .{ 4, 5 };
}

pub fn main() void {
    const t = .{ 7, 8 };
    std.io.print("basic={} {}\n", t);

    const ti = .{ 10, 255 };
    std.io.print("specs={d} {x}\n", ti);

    const ch: Bytes = .{ 65, 66 };
    std.io.print("char={c}{c}\n", ch);

    const s: []const u8 = "hi";
    const sl = .{ s, 3 };
    std.io.print("slice={s} n={}\n", sl);

    const fl = .{ 1.5, 2.5 };
    std.io.print("float={} {}\n", fl);

    const bo = .{ true, false };
    std.io.print("bool={} {}\n", bo);

    const en = .{ Color.green, 9 };
    std.io.print("enm={} {}\n", en);

    const agg = .{ .{ 1, 2 }, 3 };
    std.io.print("agg={} {}\n", agg);

    const st = .{ S2{ .a = 1, .b = 2 }, 7 };
    std.io.print("stct={} {}\n", st);

    std.io.print("call={} {}\n", mk());

    const h = Holder{ .p = .{ 11, 12 } };
    std.io.print("field={} {}\n", h.p);

    const pr = std.io.print;
    pr("alias={} {}\n", t);

    helper.logPair(.{ 12, 34 });

    // FB2 (Volume II): inferred tuple elements type by value. Every in-i32
    // element above keeps its legacy lowering (emitted C byte-identical);
    // these rows pin the value-chosen u32/i64/u64 carriers and the exact
    // `{x}` routes through the tuple-variable print path.
    const w32 = .{ 3000000000, -3000000000 };
    std.io.print("big={} {}\n", w32);

    const wu32 = .{ 4294967295, 4294967296 };
    std.io.print("u32b={} {}\n", wu32);

    const widest = .{ 9223372036854775808, 18446744073709551615 };
    std.io.print("u64b={} {}\n", widest);

    const wi64 = .{ 9223372036854775807, -9223372036854775808 };
    std.io.print("i64b={} {}\n", wi64);

    const whex = .{ 3000000000, 18446744073709551615 };
    std.io.print("hexb={x} {x}\n", whex);

    const wneg = .{ -3000000000, -9223372036854775808 };
    std.io.print("negb={x} {x}\n", wneg);

    const warith = .{ 2000000000 + 2000000000, 0 - 3000000000 };
    std.io.print("arithb={} {}\n", warith);

    const wref = .{ w32[0], w32[1] };
    std.io.print("refb={} {}\n", wref);

    std.io.print("litc={}\n", .{ w32 });

    std.io.print("free\n", t);
}
