const arena_mod = @import("b/std_arena.zig");

pub fn makeB() arena_mod.Arena {
    return arena_mod.create();
}
