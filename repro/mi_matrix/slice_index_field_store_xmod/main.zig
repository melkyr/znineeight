// slice_index_field_store_xmod — D5: a store through a slice-index aggregate
// lvalue (`s[i].field[j] = x`) is silently lost. See NOTES.md.
//
// This is a RUNTIME reproducer: the store compiles and links cleanly both
// before and after the fix, so the compile-only corpus classify cannot detect
// it. In Zig `s[i].field[j]` is an lvalue and `s[i].field[j] = x` writes
// through `&s[i].field[j]`. Pre-fix the backend lowers the base by VALUE and
// the emitter stores into a by-value struct copy:
//
//   zT = backing[i];      /* Peer copied BY VALUE into a local temp */
//   p  = zT.peer_id;      /* pointer into the LOCAL copy */
//   p[j] = x;             /* the store lands in the temp, not backing[i] */
//
// Expected stdout (post-fix): `9\n11\n22\nslice_index_field_store ok\n`.
// Pre-fix stdout is `9\n0\n0\nslice_index_field_store FAIL\n` (write lost).
const std = @import("std");

const Peer = struct {
    peer_id: [4]u8,
    score: u32,
};

var backing: [4]Peer = undefined;

fn line(v: u32) void {
    std.io.printInt(@intCast(i32, v));
    std.io.writeByte('\n');
}

pub fn main() void {
    // Control: a plain local struct field-index store is addressed correctly
    // today (`p.peer_id` decays to a pointer into the real `p`).
    var p: Peer = undefined;
    p.peer_id[0] = 9;
    p.score = 3;

    // Fixed-array element: `backing[1].peer_id[1] = 11`. Lowering reads
    // `backing[1]` by value into a temp, so the store is lost.
    backing[1].peer_id[1] = 11;

    // Slice element (the z9torr `g_sched.peers[slot].peer_id[pid_i]` shape):
    // the same lost store.
    var peers: []Peer = backing[0..2];
    peers[1].peer_id[2] = 22;

    line(p.peer_id[0]);
    line(backing[1].peer_id[1]);
    line(peers[1].peer_id[2]);

    var bad: u32 = 0;
    if (p.peer_id[0] != 9) bad += 1;
    if (backing[1].peer_id[1] != 11) bad += 1;
    if (peers[1].peer_id[2] != 22) bad += 1;
    if (bad == 0) {
        std.io.write("slice_index_field_store ok\n");
    } else {
        std.io.write("slice_index_field_store FAIL\n");
    }
}
