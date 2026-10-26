const colors = @import("colors.zig");

// Task 9 fix round 3 (Q7): a transitive cross-module constant. `aux` depends
// on `colors`; the dependency-ordered `__module_init` calls run colors first,
// then aux, then the root module.
pub const A: i32 = colors.C2;
