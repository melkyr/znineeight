# E: Module-Level Mutable var

**Pattern:** Module-level `var x: i32 = 0;` mutated by multiple functions.

**GREEN (main_green.zig):** Uses `const x` (immutable). Works.
**RED (main.zig):** Uses `var x` (mutable) shared between functions. Fails with undeclared 'x' in C output.

**Category:** E — global mutable `var`
