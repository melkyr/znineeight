const mod_a = @import("mod_a.zig");
const K = mod_a.K;

pub fn useSw(prefix: []const u8, seed: i32, k: K) ?i32 {
    _ = prefix;
    switch (k) {
        .a => return mod_a.maybe(seed) orelse return null,
        .b => return null,
    }
}
