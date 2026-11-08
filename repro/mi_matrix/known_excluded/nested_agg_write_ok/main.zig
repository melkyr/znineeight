// nested_agg_write_ok — Phase 3.5 D7.3 repro.
//
// A slice taken from an aggregate field reached through an indexed base
// (`peers[i].field[0..]`) must point into `peers[i]`'s storage, not into a
// by-value temporary of `peers[i]`. This is the wireguard demo shape
// (`copyBytes(g_peers[0].static_priv[0..], src)`) that forced the
// `var pp: *wg.WgPeer = &g_peers[0]` workaround.
//
// RED (pre-fix): the program compiles and links (compile-only classify is OK)
// but the callee writes into a temporary; the read-backs print the pre-write
// values (`0 0 0 0`).
//
// GREEN (post-fix) contract: stdout `77 88 77 88\n`, rc 0.
const std = @import("std");

const Peer = struct {
    field: [4]u8,
    score: u32,
};

var peers: [2]Peer = undefined;

fn fill(dst: []u8) void {
    dst[0] = 77;
    dst[1] = 88;
}

pub fn main() void {
    // Lost store: the slice base `peers[1]` is materialised by value.
    fill(peers[1].field[0..]);

    // Second indexed base at a non-zero field offset.
    fill(peers[0].field[2..]);

    // Control: pointer-to-aggregate (the demo workaround) must keep working.
    var pp: *Peer = &peers[0];
    pp.score = 9;

    std.io.printInt(@intCast(i32, peers[1].field[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, peers[1].field[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, peers[0].field[2]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, peers[0].field[3]));
    std.io.writeByte('\n');
}
