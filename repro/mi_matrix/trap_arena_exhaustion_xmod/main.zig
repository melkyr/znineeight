// trap_arena_exhaustion_xmod — RED->GREEN trap fixture (A2F; A8F migrated).
// Since A8F `std.arena.alloc` returns `std.arena.ArenaError![*]u8`; an
// exhausted arena yields `error.OutOfMemory`, and `catch unreachable` MUST
// terminate via pal_trap() rather than producing a null pointer that is then
// dereferenced. (A2F's old optional-null-unwrap trap no longer type-checks on
// the error union — `catch unreachable` is the error-union spelling of it.)
//
// RED (seed v9, optional API): the null payload (address 0) reaches the store,
// SIGSEGV; stdout empty (the block buffer is never flushed before the fault),
// rc 139. GREEN: pal_trap() fires before the store; stdout empty, rc 133
// (SIGTRAP) — the observable is the rc/signal, not stdout.
const std = @import("std");

var buf: [16]u8 = undefined;
var arena = std.arena.init(buf[0..]);

pub fn main() void {
    std.io.writeStr("before\n");
    var p = std.arena.alloc(&arena, 32) catch unreachable;
    p[0] = 1;
}
