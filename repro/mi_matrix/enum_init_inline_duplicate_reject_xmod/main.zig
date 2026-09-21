// enum_init_inline_duplicate_reject_xmod — Task B2 fix round 1 (Important 2)
// negative control: duplicate tags in an INLINE enum are a clean reject.
//
// Official Zig rejects `enum(u8){ A = 1, B = 1 }` wherever it appears. Before
// fix round 1 only the binding form and the expression arm ran the strict
// local-enum check; an inline annotation (`var e: enum(u8){...}`) went through
// `resolveTypeExprFull` -> `registerContainerType` -> `populateTypePayload`,
// which walked the members leniently and discarded the result — so the invalid
// enum was silently accepted (dump rc=0) and the duplicate tag collapsed.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: duplicate enum tag value (tag values must be unique).
fn f() u8 {
    var e: enum(u8) { A = 1, B = 1 } = .A;
    return @enumToInt(e);
}

pub fn main() void {
    _ = f();
}
