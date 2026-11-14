# H1: Cross-Module &extern_var + @ptrCast + Union Field-Store

**Pattern:** Full json_parser_workaround chain:
1. `const arena = &zig_default_arena;` — address of extern var (void** → void* mismatch)
2. `arena_alloc_default` — extern fn for allocation
3. `@ptrCast(*S, arena_alloc_default(...))` — cross-module pointer to hand-rolled tagged union
4. `ptr.data.x = 42` — field-store to union member through @ptrCast pointer

**RED (main.zig):** Complete json_parser_workaround pattern. Expected: ICE(3043).
**GREEN (main_green.zig):** Uses union(enum) + ptr.* = S2{...} full copy. Works.

**Category:** H1 — cross-module &extern var + extern alloc + union field-store
