# G1: Cross-Module Struct Literal + Field-Store (Slice Field)

**Pattern:** Import struct S from another module, create literal `S{ .key = "ok", .val = 42 }`, then field-store `s.key = "hello"`. ICEs with error[3043] on the struct literal.

**RED (main.zig + types.zig):** S imported, literal + field-store. error[3043] unsupported field-store base (node 15).
**GREEN (main_green.zig):** Same struct locally defined. Works.

**Category:** G1 — cross-module struct literal with slice field
