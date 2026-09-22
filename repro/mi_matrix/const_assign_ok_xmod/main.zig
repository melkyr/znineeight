// const_assign_ok_xmod — Task 7B positive runtime control (no over-rejection).
//
// The const-assignment check must reject ONLY writes to immutable l-values.
// Every write below is legal Zig and must keep compiling and running:
//   * `var` reassignment (plain + compound)
//   * a `const` binding with a MUTABLE pointee (`const p: *T`) deref write
//   * a `const` binding with a MUTABLE slice (`const s: []T`) element write
//   * a `var` fixed-array element write and a `var` struct field write
//   * `_ = expr;` discard (explicit, exempt)
//   * a read-only `for` capture
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
const std = @import("std");

const S = struct { x: u32, y: u32 };

pub fn main() void {
    var v: u32 = 1;
    v = 2;
    v += 1;
    std.io.printInt(v);
    std.io.print("\n"); // 3

    var arr: [3]u32 = .{ 10, 20, 30 };
    const p: *u32 = &arr[0];
    p.* = 5;
    std.io.printInt(arr[0]);
    std.io.print("\n"); // 5

    const s: []u32 = &arr;
    s[1] = 7;
    std.io.printInt(arr[1]);
    std.io.print("\n"); // 7

    var b: [3]u32 = .{ 1, 2, 3 };
    b[0] = 8;
    std.io.printInt(b[0]);
    std.io.print("\n"); // 8

    var st: S = .{ .x = 1, .y = 2 };
    st.x = 9;
    std.io.printInt(st.x);
    std.io.print("\n"); // 9

    s[2] = 11;
    std.io.printInt(arr[2]);
    std.io.print("\n"); // 11

    const unused: u32 = 42;
    _ = unused;

    var total: u32 = 0;
    for (arr) |it| {
        total += it;
    }
    std.io.printInt(total);
    std.io.print("\n"); // 23
}
