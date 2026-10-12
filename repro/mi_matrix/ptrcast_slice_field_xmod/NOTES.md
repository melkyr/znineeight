# G2: Cross-Module Struct Literal — Scalar Fields + Field-Store

**Pattern:** Import struct S with scalar fields only, create literal `S{ .a = 1, .b = 2 }`, then field-store `s.a = 5`. ICEs with error[3043] — same as G1, proving the bug is NOT slice-specific.

**RED (main.zig + types.zig):** Scalar-only fields, literal + field-store. ICE(3043).
**GREEN (main_green.zig):** Locally defined. Works.

**Category:** G2 — cross-module struct literal (scalar fields) + field-store
