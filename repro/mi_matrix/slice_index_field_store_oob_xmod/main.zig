// slice_index_field_store_oob_xmod — D5/F6: the chain ROOT index of a
// slice-index aggregate lvalue store must be bounds-checked under -fsafe.
// See NOTES.md.
//
// `peers[i].peer_id[0] = 1` with `i = 5` on a length-2 slice is an
// out-of-bounds root index. In Zig a `[]T` index is bounds-checked in a safe
// build, so -fsafe must trap (pal_trap -> SIGTRAP, rc 133). Pre-fix the D5
// address-taking path bypassed the by-value element read (which used to carry
// the `-fsafe` length check), so the store silently succeeded (rc 0).
//
// Under -ffast the index is unchecked and the store runs (rc 0).
const std = @import("std");

const Peer = struct {
    peer_id: [4]u8,
    score: u32,
};

var backing: [4]Peer = undefined;

pub fn main() void {
    var peers: []Peer = backing[0..2];
    var i: usize = 5;
    peers[i].peer_id[0] = 1;
    std.io.write("no trap\n");
}
