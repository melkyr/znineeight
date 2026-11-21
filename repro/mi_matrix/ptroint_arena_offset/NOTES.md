# D: @ptrToInt Pointer Arithmetic (Arena Offset)

**Pattern:** Arena allocator using `@ptrToInt` + `@intToPtr` for pointer arithmetic.

**GREEN (main_green.zig):** Uses `usize` index field for arena position. Works.
**RED (main.zig):** Uses `@intToPtr`/`@ptrToInt` pointer arithmetic. Fails with undeclared C temp.

**Category:** D — @ptrToInt arena arithmetic
