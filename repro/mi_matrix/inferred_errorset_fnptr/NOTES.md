# B1: @ptrCast with Bare ! (Inferred) Error Set

**Pattern:** Cast `*void` to `fn () !i32` (bare inferred error set in function pointer cast). zig1 produces error[3011].

**GREEN (main_green.zig):** Uses explicit `E = error{Bad}` error set. Works.
**RED (main.zig):** Uses bare `!i32` return type + @ptrCast through *void. Fails with error[3011].

**Category:** B1 — @ptrCast to fn(!T)
