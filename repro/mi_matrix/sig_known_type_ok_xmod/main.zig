// sig_known_type_ok_xmod — FX13-F (Volume II ch12) positive control.
//
// Every valid function-signature type form must keep resolving after FX13-F
// (no over-rejection):
//   * forward alias (`Later` declared after `fwdAlias`), forward struct
//     (`Node` before its decl) and self-referential struct (`?*Node`);
//   * alias chain A -> B -> C;
//   * `error{...}` set parameter and `E!i32` error-union return;
//   * arbitrary widths `u4`/`u7`;
//   * builtin scalars `c_char` / `bool`;
//   * named fn-pointer parameter (`fn (i32) i32`);
//   * cross-module `helper.Good` member;
//   * a BARE cross-module name `T` (declared only in helper.zig) resolved by
//     the global name-cache scan;
//   * implicit-void return;
//   * `anytype` parameter (node 0, never resolved, never diagnosed);
//   * the operator-ruled `noreturn` exemption (no registry name exists; it
//     stays degraded to void in signatures and is NOT diagnosed).
//
// Contract: rc 0, RUNRC 0, deterministic stdout below, 3x byte-exact.
const std = @import("std");
const helper = @import("helper.zig");

fn fwdAlias(x: Later) Later {
    return x;
}
const Later = i32;

fn fwdStruct(n: *Node) i32 {
    return n.v;
}
const Node = struct { v: i32, next: ?*Node };

const A = B;
const B = C;
const C = i32;
fn chain(x: A) A {
    return x;
}

fn eset(e: error{Foo, Bar}) void {
    if (e == error.Foo) {
        std.io.print("foo\n");
    }
}

const E = error{Foo};
fn errunion() E!i32 {
    return 7;
}

fn width4(x: u4) u4 {
    return x;
}
fn width7(x: u7) u7 {
    return x;
}

fn scalars(c: c_char, b: bool) void {
    _ = c;
    _ = b;
}

fn implicit() void {}

fn apply(cb: fn (i32) i32, x: i32) i32 {
    return cb(x);
}
fn inc(v: i32) i32 {
    return v + 1;
}

fn xmod(g: helper.Good) helper.Good {
    return g;
}

fn xbare(t: T) T {
    return t;
}

fn anyf(x: anytype) void {}

extern "c" fn trap() noreturn;

pub fn main() void {
    var n = Node{ .v = 5, .next = null };
    std.io.printInt(fwdAlias(1));
    std.io.print("\n");
    std.io.printInt(fwdStruct(&n));
    std.io.print("\n");
    std.io.printInt(chain(2));
    std.io.print("\n");
    eset(error.Foo);
    const eu = errunion() catch 0;
    std.io.printInt(eu);
    std.io.print("\n");
    std.io.printInt(@intCast(i32, width4(3)));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, width7(4)));
    std.io.print("\n");
    scalars('x', true);
    implicit();
    std.io.printInt(apply(inc, 6));
    std.io.print("\n");
    var g = helper.Good{ .g = 7 };
    std.io.printInt(xmod(g).g);
    std.io.print("\n");
    std.io.printInt(xbare(8));
    std.io.print("\n");
    _ = anyf;
}
