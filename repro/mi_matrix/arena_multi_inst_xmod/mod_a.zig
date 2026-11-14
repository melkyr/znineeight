const arena_mod = @import("a/std_arena.zig");

pub fn makeA() arena_mod.Arena {
    return arena_mod.create();
}
