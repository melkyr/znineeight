# B2: Cross-Module Bare ! Error Set

**Pattern:** Module A exports `fn do_thing() !i32`, Module B imports and calls via `try`. zig1 produces error[3011].

**GREEN (main_green.zig + lib_green.zig):** Uses explicit `E = error{Bad}` error set. Works.
**RED (main.zig + lib.zig):** Uses bare `!i32` return type in lib module. Fails with error[3011].

**Category:** B2 — cross-module bare error inference
