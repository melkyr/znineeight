// shadow_ok_xmod — Task 7D positive runtime control (no over-rejection).
//
// These sibling-scope patterns are accepted by Z98 and must keep compiling:
//   * sibling blocks reuse the same identifier (separate scopes)
//   * an inner block uses a name before the enclosing scope declares it
//   * sibling `if`/`for` constructs use distinct capture names
//   * `_` (the discard) is re-bound freely — it is not an identifier
//   * a read-only `for` capture
//
// NOTE: this is a Z98 acceptance control, NOT a claim that the file is
// oracle-legal Zig. Official Zig 0.15.2 additionally rejects an unmutated `var`
// ("local variable is never mutated") and the Z98-specific `const _ = 1;`
// discard binding, so it does not accept this file verbatim; what must not be
// over-rejected is the sibling-scope REUSE exercised here (the Zig-matching
// boundary is proven by shadow_reject_xmod, whose shapes the oracle rejects).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
const std = @import("std");

const G: i32 = 7;

fn siblingBlocks() void {
    {
        const x: i32 = 1;
        std.io.printInt(x);
    }
    {
        const x: i32 = 2;
        std.io.printInt(x);
    }
}

fn innerBeforeOuter() void {
    {
        const y: i32 = 3;
        std.io.printInt(y);
    }
    const y: i32 = 4;
    std.io.printInt(y);
}

fn siblingCaptures(opt: ?i32) void {
    var arr: [2]i32 = .{ 5, 6 };
    if (opt) |a| {
        std.io.printInt(a);
    }
    if (opt) |b| {
        std.io.printInt(b);
    }
    for (arr) |c| {
        std.io.printInt(c);
    }
    for (arr) |d| {
        std.io.printInt(d);
    }
    var total: i32 = 0;
    for (arr) |e| {
        total += e;
    }
    std.io.printInt(total);
}

fn discardRebind() void {
    const _ = 1;
    const _ = 2;
    _ = 3;
}

fn distinctNames() void {
    var v: i32 = 5;
    std.io.printInt(v);
    {
        var v2: i32 = 6;
        std.io.printInt(v2);
    }
}

pub fn main() void {
    siblingBlocks();
    innerBeforeOuter();
    siblingCaptures(9);
    discardRebind();
    distinctNames();
    std.io.printInt(G);
    std.io.print("\n");
}
