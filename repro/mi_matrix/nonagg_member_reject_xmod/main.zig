// nonagg_member_reject_xmod — Task 13 fix round (I1) reject fixture.
//
// A member access/call on a NON-AGGREGATE value (`x.foo()`, `x.foo`, `b.foo`,
// `s.foo`, `arr.foo`, `e.nope`, `es.nope`, `fl.nope`) is invalid Z98 and was
// still silently accepted before the fix: `semanticAnalyzerResolveFieldAccess`
// returned `TYPE_VOID` with no diagnostic, so `const x: i32 = 5; x.foo();`
// compiled rc=0 and emitted `(void)zT_3();` — a call to an undeclared temp
// (the original Task 13 failure class). The enum / error-set / non-aggregate
// `else` arms now emit the same dedicated level-0 `error[3060]` the aggregate
// unknown-member reject uses (message tail names the base kind, ASCII-only).
//
// Sites (every one independently rejected by official Zig 0.15.2):
//   * `x.foo();`         i32 method-call shape  (Zig: no field or member
//                        function named 'foo' in 'i32')
//   * `_ = x.bar;`       i32 member read       (Zig: type 'i32' does not
//                        support field access)
//   * `_ = b.foo;`       bool member read
//   * `_ = s.foo;`       slice member read     (Zig: no member named 'foo'
//                        in '[]const u8')
//   * `_ = arr.foo;`     array member read     (Zig: no member named 'foo'
//                        in '[3]u8')
//   * `_ = e.nope;`      enum value member     (Zig: type 'E' does not
//                        support field access)
//   * `_ = es.nope;`     error-set value member
//   * `_ = fl.nope;`     f64 member read
//
// Valid shapes (enum/error-set members, module access, slice/array `.len` and
// `.ptr`, tagged-union `.tag`/`.payload`, real aggregate fields, free-function
// calls) stay accepted — see `stdlib_method_syntax_ok_xmod`.
//
// EXPECTED: dump rc=2, 0 `.c`, exactly one `error[3060]` per site.
const E = enum(u8) { A = 1, B = 2 };

const Err = error{ Bad, Worse };

pub fn main() void {
    const x: i32 = 5;
    const b: bool = true;
    var s: []u8 = undefined;
    var arr: [3]u8 = [3]u8{ 1, 2, 3 };
    const e = E.B;
    const es = Err.Bad;
    const fl: f64 = 1.0;

    x.foo();
    _ = x.bar;
    _ = b.foo;
    _ = s.foo;
    _ = arr.foo;
    _ = e.nope;
    _ = es.nope;
    _ = fl.nope;
}
