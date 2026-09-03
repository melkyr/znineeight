// packed_l3_nested_xmod — FEATURE-GAP RED fixture (packed struct, L3: nested
//   packed struct field, bit-contiguous). Nested-packable is a FEASIBILITY probe:
//   if zig1 must restrict fields to int/bool/enum only, this contract re-baselines
//   with the operator at the gate.
// GREEN (contract): "2 5 6 3 3\n" — 2+6+2 = 10 bits => size 2; reads back.
const std = @import("std");

const Inner = packed struct { a: u3, b: u3 };
const Outer = packed struct { head: u2, inner: Inner, tail: u2 };

pub fn main() void {
    var o: Outer = undefined;
    o.head = 3;
    o.inner.a = 5;
    o.inner.b = 6;
    o.tail = 3;
    std.io.printInt(@intCast(i32, @sizeOf(Outer)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.inner.a));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.inner.b));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.head));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, o.tail));
    std.io.writeByte('\n');
}
