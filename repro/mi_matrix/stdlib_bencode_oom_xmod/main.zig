// stdlib_bencode_oom_xmod — STDLIB std_bencode (M0 §4.2) arena-exhaustion
// GREEN fixture.
//
// encode allocates only its output from the caller's arena (R1). A value whose
// canonical encoding needs 204 bytes (`200:` followed by 200 'A' bytes) must
// fail with exactly error.OutOfMemory when handed a 64-byte arena; any other
// error (or success) is a failure.
//
// GREEN: deterministic byte-exact stdout (RUNRC=0):
//   oom ok
const std = @import("std");
const ben = @import("std_bencode.zig");

pub fn main() void {
    var big: [256]u8 = undefined;
    var i: usize = 0;
    while (i < big.len) : (i += 1) {
        big[i] = 'A';
    }
    var bslice: []const u8 = big[0..200];
    var v = ben.Value{ .bytes = bslice };

    var backing: [64]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var got = ben.encode(&ar, v) catch |e| {
        if (e == error.OutOfMemory) {
            std.io.write("oom ok\n");
            return;
        }
        @panic("wrong error");
    };
    _ = got;
    @panic("expected OutOfMemory");
}
