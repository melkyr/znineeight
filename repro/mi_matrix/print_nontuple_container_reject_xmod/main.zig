// print_nontuple_container_reject_xmod — FD1 (Volume II D7 + D13) reject
// fixture for the print argument-container gate.
//
// Language Spec §4: the `print` arguments must be a tuple literal (a tuple
// VARIABLE is spec-legal but is an interim reject until FD2 implements its
// element reads). Pre-FD1 the print arm passed the LAST call argument to
// `lowerPrintFmt` without a kind test; the container walk read that node's
// payload as an `extra_ranges` index, so the same source shape could silently
// drop the placeholder (D7), print an unrelated value, misattribute
// error[3013], or SIGSEGV through unbounded `lowerPrintFmt` re-entry
// (D13 / S01). FD1 gates the container kind BEFORE the first extra-child read
// (level-0 `error[3065]` at the container node, deduped per node) and requires
// exactly two arguments (more -> the existing level-0 `error[3061]` at the
// call span). No shape may SIGSEGV.
//
// Exact diagnostic census: 13 x error[3065] + 1 x error[3061]
//   1. bare int literal container            (bareLit)
//   2. two bare literal calls                (twoLits -> 2 x 3065)
//   3. bare variable container               (bareVar, a parameter)
//   4. two bare variable calls               (twoVars -> 2 x 3065)
//   5. expression container (v + 1)          (exprArg)
//   6. nested call container (id(7))         (nestedCall)
//   7. typed struct-init container           (typedInit, P{ .a = 1 })
//   7b. anonymous field-init container       (anonInit, .{ .b = 2 })
//   8. array-literal container               (arrayLit, [2]i32{...})
//   9. tuple-variable container (interim)    (tupleVar)
//  10. cross-module container                (helper.zig: 1 x 3065)
//  11. arity > 2                             (tooManyArgs -> 1 x 3061)
// Controls that must NOT be diagnosed: the empty tuple literal `.{}`
// (emptyFmt) and the tuple literal `. { 7, 8 }` (tupleFmt). rc 2 / 0 `.c`.
const std = @import("std");
const helper = @import("helper.zig");

const P = struct { a: i32 };

fn id(x: i32) i32 {
    return x;
}

fn bareLit() void {
    std.io.print("{}\n", 5);
}

fn twoLits() void {
    std.io.print("one={}\n", 1);
    std.io.print("two={}\n", 2);
}

fn bareVar(v: i32) void {
    std.io.print("v={}\n", v);
}

fn twoVars(a: i32, b: i32) void {
    std.io.print("a={}\n", a);
    std.io.print("b={}\n", b);
}

fn exprArg(v: i32) void {
    std.io.print("e={}\n", v + 1);
}

fn nestedCall() void {
    std.io.print("n={}\n", id(7));
}

fn typedInit() void {
    std.io.print("s={}\n", P{ .a = 1 });
}

fn anonInit() void {
    std.io.print("a={}\n", .{ .b = 2 });
}

fn arrayLit() void {
    std.io.print("arr={}\n", [2]i32{ 1, 2 });
}

fn tupleVar() void {
    const t = .{ 7, 8 };
    std.io.print("t={} {}\n", t);
}

fn tooManyArgs() void {
    std.io.print("{} {}\n", .{ 1, 2 }, .{ 3 });
}

fn emptyFmt() void {
    std.io.print("empty-tuple\n", .{});
}

fn tupleFmt() void {
    std.io.print("tuple={} {}\n", .{ 7, 8 });
}

pub fn main() void {
    bareLit();
    twoLits();
    bareVar(1);
    twoVars(1, 2);
    exprArg(1);
    nestedCall();
    typedInit();
    anonInit();
    arrayLit();
    tupleVar();
    tooManyArgs();
    helper.logVar(3);
    emptyFmt();
    tupleFmt();
}
