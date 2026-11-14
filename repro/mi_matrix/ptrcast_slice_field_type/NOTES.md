# G3: Cross-Module Struct Literal — No Field-Store (Undeclared Var)

**Pattern:** Import struct S with slice field, create literal `S{ .key = "ok", .val = 42 }`, no field-store. zig1 emits C but the `s` variable declaration is MISSING — gcc fails with `'s' undeclared`. Same behavior with scalar-only types.

**RED (main.zig + types.zig):** Cross-module literal, no field-store. FAIL (gcc undeclared var).
**GREEN (main_green.zig):** Locally defined. Works.

**Category:** G3 — cross-module struct literal (no field-store, undeclared var)
