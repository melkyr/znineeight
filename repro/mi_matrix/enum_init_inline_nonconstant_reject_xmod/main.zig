// enum_init_inline_nonconstant_reject_xmod — Task B2 fix round 1 (Important 2)
// negative control: an INLINE enum with a non-comptime integer tag is a clean
// reject.
//
// Official Zig rejects `enum(u8){ A = @intToFloat(f32, 1) }`. Before fix round
// 1 only the binding form and the expression arm ran the strict local-enum
// check; an inline annotation went through `registerContainerType` ->
// `populateTypePayload` (lenient member walk, result discarded), so the
// unfoldable tag silently became the auto-increment ordinal `A = 0`.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: enum member value is not a comptime-known integer expression.
fn f() u8 {
    var e: enum(u8) { A = @intToFloat(f32, 1) } = .A;
    return @enumToInt(e);
}

pub fn main() void {
    _ = f();
}
