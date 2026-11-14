// method_syntax_reject_xmod — Task 13 (S1) reject fixture.
// Task 18 fix round: every `error[3060]` also renders Zig's aggregate
// declaration note (`main.zig:40/45: note: struct declared here`;
// `:54`/`:59: note: union declared here`).
//
// Z98 forbids method syntax: `struct.func()` is not supported; use
// `func(struct)` (docs/reference/Language_Spec_Z98.md, "No Method Syntax";
// docs/sf/AGENTS.md). Because Z98 structs cannot contain function
// declarations, a member call on a struct value is ALWAYS an unknown member.
//
// DEFECT (before the fix): `nine.square()` (a member call on a struct value)
// compiled rc=0 with NO error diagnostic and emitted `zT_8 = zT_7();` where
// `zT_7` was never declared; the C89 build "succeeded" via an implicit
// function declaration and the LINK failed (`undefined reference to 'zT_7'`).
// A plain unknown member (`nine.nope`) was silently typed `void` too.
//
// FIX (Task 13): `semanticAnalyzerResolveFieldAccess` emits the new level-0
// `error[3060]: no field or member function named '<name>' in
// struct/union type` when a struct/union/tagged-union value's member is not
// found, so the program rejects with rc=2 and 0 emitted `.c`.
//
// Sites (every one independently rejected by official Zig 0.15.2):
//   * `nine.square();`            method call on a struct value
//                                 (Zig: no field or member function named
//                                 'square' in 'Point')
//   * `_ = nine.nope;`            unknown struct member
//                                 (Zig: no field named 'nope' in struct)
//   * `p.square();`               method call through a pointer
//   * `outer.inner.area();`       method call on a nested struct field
//   * `_ = makePoint().square;`   unknown member on a call result
//   * `_ = u.nope;`               unknown union member
//   * `_ = tu.nope;`              unknown tagged-union member
//   * `_ = Point.square;`         member on the struct TYPE name
//
// EXPECTED: dump rc=2, 0 `.c`, exactly one `error[3060]` per site.
// Valid free-function calls and real field accesses stay accepted — see the
// positive control `stdlib_method_syntax_ok_xmod` and the standalone
// `repro/method_syntax.z98`.

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
    var p: *const Point = &nine;
    const inner = Inner{ .v = 7 };
    const outer = Outer{ .inner = inner, .tag = 9 };
    var u = U{ .a = 11 };
    var tu = TU{ .num = 13 };

    nine.square();
    _ = nine.nope;
    p.square();
    outer.inner.area();
    _ = makePoint().square;
    _ = u.nope;
    _ = tu.nope;
    _ = Point.square;
}
