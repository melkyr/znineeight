// trap_arena_exhaustion_xmod — RED->GREEN trap fixture (A2F). An exhausted
// arena alloc returns null; `orelse unreachable` MUST terminate via pal_trap()
// rather than producing a null pointer that is then dereferenced.
//
// RED (seed v9): the null payload (address 0) reaches the store, SIGSEGV;
// stdout `before\n`, rc 139. GREEN: pal_trap() fires before the store; stdout
// `before\n`, rc != 0 (SIGTRAP / 133).
const std = @import("std");

var buf: [16]u8 = undefined;
var arena = std.arena.init(buf[0..]);

pub fn main() void {
    std.io.writeStr("before\n");
    var p = std.arena.alloc(&arena, 32) orelse unreachable;
    p[0] = 1;
}
