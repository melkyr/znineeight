// stdlib_method_syntax_ok_xmod — Task 13 (S1) positive runtime control.
//
// The Task 13 rejection must leave every VALID Z98 form unchanged. Z98 has no
// method syntax (`struct.func()` is forbidden), but the sanctioned equivalents
// are: a free function that takes the struct value, and ordinary field access.
//
// Covers: the free-function call `square(nine)`; real field access on a value,
// through a pointer, on a nested struct field, and on a function-call result;
// union field access; tagged-union field access and `.tag`; an enum member
// reference; and an error-set member reference. Every observation is
// `@panic`-guarded.
//
// Contract: stdout `free=9 x=3 px=3 nested=7 callx=5 union=11 tu=13 tag=0
// enum=2\n`, rc 0, byte-exact 3x, Zig-0.15.2-twin-matched.
const std = @import("std");

const Point = struct {
    x: i32,
    y: i32,
};

const Inner = struct {
    v: i32,
};

const Outer = struct {
    inner: Inner,
    tag: u8,
};

const U = union {
    a: i32,
    b: f32,
};

const TU = union(enum) {
    num: i32,
    flag: bool,
};

const E = enum(u8) { A = 1, B = 2 };

const Err = error{ Bad, Worse };

fn square(p: Point) i32 {
    return p.x * p.x;
}

fn makePoint() Point {
    return Point{ .x = 5, .y = 6 };
}

fn area(i: Inner) i32 {
    return i.v * i.v;
}

pub fn main() void {
    const nine = Point{ .x = 3, .y = 4 };
    const p: *const Point = &nine;
    const inner = Inner{ .v = 7 };
    const outer = Outer{ .inner = inner, .tag = 9 };
    var u = U{ .a = 11 };
    var tu = TU{ .num = 13 };
    const e = E.B;
    const es = Err.Bad;

    var free_call: i32 = square(nine);
    if (free_call != 9) {
        @panic("free-function call failed");
    }
    if (area(inner) != 49) {
        @panic("free-function call on nested value failed");
    }

    if (nine.x != 3 or nine.y != 4) {
        @panic("struct field access failed");
    }
    if (p.x != 3) {
        @panic("pointer field access failed");
    }
    if (outer.inner.v != 7 or outer.tag != 9) {
        @panic("nested field access failed");
    }
    if (makePoint().x != 5 or makePoint().y != 6) {
        @panic("call-result field access failed");
    }
    if (u.a != 11) {
        @panic("union field access failed");
    }
    if (tu.num != 13) {
        @panic("tagged-union field access failed");
    }
    if (@intCast(u32, tu.tag) != 0) {
        @panic("tagged-union .tag failed");
    }
    if (@intCast(u32, e) != 2) {
        @panic("enum member reference failed");
    }
    if (es != Err.Bad) {
        @panic("error-set member reference failed");
    }

    std.io.print("free={} x={} px={} nested={} callx={} union={} tu={} tag={} enum={}\n", .{ free_call, nine.x, p.x, outer.inner.v, makePoint().x, u.a, tu.num, @intCast(u32, tu.tag), @intCast(u32, e) });
}
