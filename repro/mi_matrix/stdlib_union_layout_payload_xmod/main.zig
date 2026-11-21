// stdlib_union_layout_payload_xmod — FF (Volume II D6 + D9) positive runtime
// fixture.
//
// D9: `@sizeOf`/`@alignOf`/`@bitSizeOf` keep their unchanged Z98 C-model
// values on every union kind — bare 4/4/32, tagged 8/4/64, two-u8 tagged
// 8/4/64, u8/u64 bare 8/8/64, u8/u64 tagged 16/8/128, packed 1/1/4 — and a
// struct that CONTAINS a union keeps its layout (`@offsetOf` on the struct is
// unchanged and still accepted).
// D6: an f64 float LITERAL assigned to an f32 tagged-union payload is narrowed
// to f32 before the payload store, so the emitter's exact type-id variant
// match selects the real variant (`zT.payload.circle._0 = ...`) instead of the
// gcc-invalid whole-union `payload = double`, and instead of silently writing
// an f64 SIBLING while the tag named the f32 field. Wrapped literal forms
// (`-2.0`, `(2.5)`) narrow too; the typed-f64-variable shape is the documented
// FX3 residual (not pinned here).
//
// Contract: stdout below, rc 0, byte-exact 3x. The payload rows are
// Zig-0.15.2-oracle-equal; the layout rows pin the Z98 C model (FF-I table).
const std = @import("std");
const helper = @import("helper.zig");

const Raw = union { i: i32, u: u32 };
const T = union(enum) { i: i32, u: u32 };
const T88 = union(enum) { a: u8, b: u8 };
const MU = union { a: u8, b: u64 };
const MT = union(enum) { a: u8, b: u64 };
const PU = packed union { a: u4, b: u4 };
const SQ = struct { a: u8, r: Raw };

const ShapeF = union(enum) { circle: f32, empty };
const Sib = union(enum) { a: f32, b: f64 };

pub fn main() void {
    if (@sizeOf(Raw) != 4) @panic("raw-size");
    if (@alignOf(Raw) != 4) @panic("raw-align");
    if (@bitSizeOf(Raw) != 32) @panic("raw-bits");
    std.io.print("raw={} {} {}\n", .{ @intCast(i32, @sizeOf(Raw)), @intCast(i32, @alignOf(Raw)), @intCast(i32, @bitSizeOf(Raw)) });

    if (@sizeOf(T) != 8) @panic("tag-size");
    if (@alignOf(T) != 4) @panic("tag-align");
    if (@bitSizeOf(T) != 64) @panic("tag-bits");
    std.io.print("tag={} {} {}\n", .{ @intCast(i32, @sizeOf(T)), @intCast(i32, @alignOf(T)), @intCast(i32, @bitSizeOf(T)) });

    if (@sizeOf(T88) != 8) @panic("t88-size");
    if (@alignOf(T88) != 4) @panic("t88-align");
    if (@bitSizeOf(T88) != 64) @panic("t88-bits");
    std.io.print("t88={} {} {}\n", .{ @intCast(i32, @sizeOf(T88)), @intCast(i32, @alignOf(T88)), @intCast(i32, @bitSizeOf(T88)) });

    if (@sizeOf(MU) != 8) @panic("mu-size");
    if (@alignOf(MU) != 8) @panic("mu-align");
    if (@bitSizeOf(MU) != 64) @panic("mu-bits");
    std.io.print("mu={} {} {}\n", .{ @intCast(i32, @sizeOf(MU)), @intCast(i32, @alignOf(MU)), @intCast(i32, @bitSizeOf(MU)) });

    if (@sizeOf(MT) != 16) @panic("mt-size");
    if (@alignOf(MT) != 8) @panic("mt-align");
    if (@bitSizeOf(MT) != 128) @panic("mt-bits");
    std.io.print("mt={} {} {}\n", .{ @intCast(i32, @sizeOf(MT)), @intCast(i32, @alignOf(MT)), @intCast(i32, @bitSizeOf(MT)) });

    if (@sizeOf(PU) != 1) @panic("pu-size");
    if (@alignOf(PU) != 1) @panic("pu-align");
    if (@bitSizeOf(PU) != 4) @panic("pu-bits");
    std.io.print("pu={} {} {}\n", .{ @intCast(i32, @sizeOf(PU)), @intCast(i32, @alignOf(PU)), @intCast(i32, @bitSizeOf(PU)) });

    if (@sizeOf(SQ) != 8) @panic("sq-size");
    if (@offsetOf(SQ, "a") != 0) @panic("sq-offa");
    if (@offsetOf(SQ, "r") != 4) @panic("sq-offr");
    std.io.print("sq={} {} {}\n", .{ @intCast(i32, @sizeOf(SQ)), @intCast(i32, @offsetOf(SQ, "a")), @intCast(i32, @offsetOf(SQ, "r")) });

    var a: ShapeF = ShapeF{ .circle = 2.0 };
    if (a.circle != @as(f32, 2.0)) @panic("shape-circle");
    std.io.print("shape={}\n", .{a.circle});

    var b: ShapeF = .{ .circle = 3.0 };
    if (b.circle != @as(f32, 3.0)) @panic("shape-anon");
    std.io.print("shape2={}\n", .{b.circle});

    var c = helper.ShapeF{ .circle = 4.0 };
    if (c.circle != @as(f32, 4.0)) @panic("shape-xmod");
    std.io.print("shape3={}\n", .{c.circle});

    var s1: Sib = Sib{ .a = 2.0 };
    var s2: Sib = Sib{ .b = 2.5 };
    if (s1.a != @as(f32, 2.0)) @panic("sib-a");
    if (s2.b != @as(f64, 2.5)) @panic("sib-b");
    std.io.print("sib={} {}\n", .{ s1.a, s2.b });

    var n: Sib = Sib{ .a = -2.0 };
    if (n.a != @as(f32, -2.0)) @panic("sib-neg");
    std.io.print("sibneg={}\n", .{n.a});

    var p: Sib = Sib{ .a = (2.5) };
    if (p.a != @as(f32, 2.5)) @panic("sib-paren");
    std.io.print("sibparen={}\n", .{p.a});

    std.io.print("done\n", .{});
}
