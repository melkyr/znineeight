// piece_test.zig — deterministic unit harness for piece.zig block accounting.
//
// No wall clock, no randomness: synthetic one-piece torrents over temporary
// files under /tmp exercise the O(1) `received_count`/`outstanding_count`
// counters against the real `pieceInit`/`nextRequests`/`onBlock` path (including
// the write-through and SHA-1 verify-on-complete).
//
// Asserts:
//   (a) out-of-order blocks then the rest report `Complete` exactly once;
//   (b) a duplicate block leaves the counters unchanged;
//   (c) a malformed/short block is rejected and leaves the counters unchanged;
//   (d) `nextRequests` returns the expected request set for an in-progress piece;
//   (e) a corrupt-piece requeue resets both counters consistently;
//   (f) a piece longer than 1 MiB verifies through the bounded chunk path.
//
// Build (binding recipe), entry is this file:
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -fsafe -o out tests/piece_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog
//
// Exits 0 on success; on the first failure prints a `piece_test: FAIL: ...`
// line and exits 1.

const std = @import("std");
const piece = @import("../piece.zig");
const disk = @import("../disk.zig");
const torrent = @import("../torrent.zig");
const crypto = @import("std_crypto");

const BLOCK = piece.BLOCK_SIZE;

var g_state_buf: [1048576]u8;
var g_io_buf: [1048576]u8;
var g_data: [96 * 16384]u8;
var g_hash: [20]u8;
var g_zero_alist: [8][]const u8;

fn fail(msg: []const u8) void {
    var p: []const u8 = "piece_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn checkU32(got: u32, want: u32, label: []const u8) void {
    if (got != want) fail(label);
}

fn fillData(total: u32) void {
    var i: usize = 0;
    var n: usize = @intCast(usize, total);
    while (i < n) : (i += 1) {
        g_data[i] = @intCast(u8, (@intCast(u32, i) * 37 + 11) % 251);
    }
}

fn blockData(begin: u32, len: u32) []const u8 {
    var b: usize = @intCast(usize, begin);
    var e: usize = @intCast(usize, begin + len);
    return g_data[b..e];
}

fn hashPiece(data: []const u8) void {
    var hs = crypto.sha1Init();
    crypto.sha1Update(&hs, data);
    crypto.sha1Final(&hs, &g_hash);
}

fn makeTorrent(name: []const u8, nblocks: u32) torrent.Torrent {
    var ih: [20]u8 = [20]u8{0};
    var z: usize = 0;
    while (z < 20) : (z += 1) ih[z] = 0;
    var alist: [8][]const u8 = g_zero_alist;
    var e: []const u8 = "";
    z = 0;
    while (z < 8) : (z += 1) alist[z] = e;
    var total: u32 = nblocks * BLOCK;
    return torrent.Torrent{
        .announce = e,
        .announce_list = alist,
        .announce_count = 0,
        .info_hash = ih,
        .name = name,
        .piece_length = total,
        .piece_hashes = g_hash[0..],
        .total_length = @intCast(u64, total),
    };
}

fn checkBegin(q: *piece.RequestQueue, i: u32, begin: u32, label: []const u8) void {
    if (q.in_flight[@intCast(usize, i)].begin != begin) fail(label);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    var state_arena: std.arena.Arena = std.arena.init(g_state_buf[0..]);
    var io_arena: std.arena.Arena = std.arena.init(g_io_buf[0..]);

    // --- (a) out-of-order blocks, then the rest -> Complete exactly once ----
    var total_a: u32 = 3 * BLOCK;
    fillData(total_a);
    hashPiece(g_data[0..@intCast(usize, total_a)]);
    var ta = makeTorrent("/tmp/z9torr_piece_a.bin", 3);
    var fa = disk.openTarget(&io_arena, ta) catch {
        fail("(a) open target");
        return;
    };
    var ioa = piece.PieceIO{ .arena = &io_arena, .t = ta, .f = &fa };
    var pa: piece.PieceState = piece.zeroPieceState();
    piece.pieceInit(&state_arena, ta, &pa, 0) catch {
        fail("(a) pieceInit");
        return;
    };
    checkU32(pa.received_count, 0, "(a) init received_count != 0");
    checkU32(pa.outstanding_count, 0, "(a) init outstanding_count != 0");
    checkU32(pa.nblocks, 3, "(a) nblocks != 3");

    var completes: u32 = 0;
    var ra = piece.onBlock(&pa, 2 * BLOCK, blockData(2 * BLOCK, BLOCK), &ioa) catch {
        fail("(a) onBlock 2 error");
        return;
    };
    if (ra == piece.BlockResult.Complete) completes += 1;
    if (ra != piece.BlockResult.Continue) fail("(a) block 2 was not Continue");
    checkU32(pa.received_count, 1, "(a) received_count after block 2");
    checkU32(pa.outstanding_count, 0, "(a) outstanding_count after block 2");

    ra = piece.onBlock(&pa, 0, blockData(0, BLOCK), &ioa) catch {
        fail("(a) onBlock 0 error");
        return;
    };
    if (ra == piece.BlockResult.Complete) completes += 1;
    if (ra != piece.BlockResult.Continue) fail("(a) block 0 was not Continue");
    checkU32(pa.received_count, 2, "(a) received_count after block 0");

    ra = piece.onBlock(&pa, BLOCK, blockData(BLOCK, BLOCK), &ioa) catch {
        fail("(a) onBlock 1 error");
        return;
    };
    if (ra == piece.BlockResult.Complete) completes += 1;
    if (ra != piece.BlockResult.Complete) fail("(a) final block was not Complete");
    checkU32(completes, 1, "(a) Complete was not reported exactly once");
    checkU32(pa.received_count, 3, "(a) received_count after Complete");
    checkU32(pa.outstanding_count, 0, "(a) outstanding_count after Complete");
    if (pa.state != piece.BlockState.verified) fail("(a) piece not verified");

    // --- (b) duplicate block leaves the counters unchanged ------------------
    var total_b: u32 = 2 * BLOCK;
    fillData(total_b);
    hashPiece(g_data[0..@intCast(usize, total_b)]);
    var tb = makeTorrent("/tmp/z9torr_piece_b.bin", 2);
    var fb = disk.openTarget(&io_arena, tb) catch {
        fail("(b) open target");
        return;
    };
    var iob = piece.PieceIO{ .arena = &io_arena, .t = tb, .f = &fb };
    var pb: piece.PieceState = piece.zeroPieceState();
    piece.pieceInit(&state_arena, tb, &pb, 0) catch {
        fail("(b) pieceInit");
        return;
    };
    var rb = piece.onBlock(&pb, 0, blockData(0, BLOCK), &iob) catch {
        fail("(b) first onBlock error");
        return;
    };
    if (rb != piece.BlockResult.Continue) fail("(b) first block was not Continue");
    checkU32(pb.received_count, 1, "(b) received_count after first block");
    checkU32(pb.outstanding_count, 0, "(b) outstanding_count after first block");
    rb = piece.onBlock(&pb, 0, blockData(0, BLOCK), &iob) catch {
        fail("(b) duplicate onBlock error");
        return;
    };
    if (rb != piece.BlockResult.Continue) fail("(b) duplicate block was not Continue");
    checkU32(pb.received_count, 1, "(b) duplicate changed received_count");
    checkU32(pb.outstanding_count, 0, "(b) duplicate changed outstanding_count");

    // --- (c) malformed/short block rejected, counters unchanged -------------
    var total_c: u32 = 2 * BLOCK;
    fillData(total_c);
    hashPiece(g_data[0..@intCast(usize, total_c)]);
    var tc = makeTorrent("/tmp/z9torr_piece_c.bin", 2);
    var fc = disk.openTarget(&io_arena, tc) catch {
        fail("(c) open target");
        return;
    };
    var ioc = piece.PieceIO{ .arena = &io_arena, .t = tc, .f = &fc };
    var pc: piece.PieceState = piece.zeroPieceState();
    piece.pieceInit(&state_arena, tc, &pc, 0) catch {
        fail("(c) pieceInit");
        return;
    };
    var rc = piece.onBlock(&pc, 0, blockData(0, 100), &ioc) catch {
        fail("(c) short block returned an error");
        return;
    };
    if (rc != piece.BlockResult.Corrupt) fail("(c) short block was not Corrupt");
    checkU32(pc.received_count, 0, "(c) short block changed received_count");
    checkU32(pc.outstanding_count, 0, "(c) short block changed outstanding_count");
    checkU32(pc.received_bytes, 0, "(c) short block changed received_bytes");
    if (pc.blocks[0] != piece.BlockState.missing) fail("(c) short block changed block state");
    rc = piece.onBlock(&pc, 1, blockData(0, BLOCK), &ioc) catch {
        fail("(c) unaligned block returned an error");
        return;
    };
    if (rc != piece.BlockResult.Corrupt) fail("(c) unaligned block was not Corrupt");
    checkU32(pc.received_count, 0, "(c) unaligned block changed received_count");
    rc = piece.onBlock(&pc, 2 * BLOCK, blockData(0, BLOCK), &ioc) catch {
        fail("(c) out-of-range block returned an error");
        return;
    };
    if (rc != piece.BlockResult.Corrupt) fail("(c) out-of-range block was not Corrupt");
    checkU32(pc.received_count, 0, "(c) out-of-range block changed received_count");
    checkU32(pc.outstanding_count, 0, "(c) out-of-range block changed outstanding_count");

    // --- (d) nextRequests expected set for an in-progress piece -------------
    var total_d: u32 = 5 * BLOCK;
    fillData(total_d);
    hashPiece(g_data[0..@intCast(usize, total_d)]);
    var td = makeTorrent("/tmp/z9torr_piece_d.bin", 5);
    var fd = disk.openTarget(&io_arena, td) catch {
        fail("(d) open target");
        return;
    };
    var iod = piece.PieceIO{ .arena = &io_arena, .t = td, .f = &fd };
    var pd: piece.PieceState = piece.zeroPieceState();
    piece.pieceInit(&state_arena, td, &pd, 0) catch {
        fail("(d) pieceInit");
        return;
    };
    var q: piece.RequestQueue = piece.zeroRequestQueue();
    piece.nextRequests(&pd, &q);
    checkU32(q.head, 0, "(d) head != 0");
    checkU32(q.tail, 4, "(d) first window tail != 4");
    checkU32(pd.outstanding_count, 4, "(d) first window outstanding_count != 4");
    checkBegin(&q, 0, 0, "(d) request 0 begin");
    checkBegin(&q, 1, BLOCK, "(d) request 1 begin");
    checkBegin(&q, 2, 2 * BLOCK, "(d) request 2 begin");
    checkBegin(&q, 3, 3 * BLOCK, "(d) request 3 begin");

    var rd = piece.onBlock(&pd, BLOCK, blockData(BLOCK, BLOCK), &iod) catch {
        fail("(d) onBlock error");
        return;
    };
    if (rd != piece.BlockResult.Continue) fail("(d) block 1 was not Continue");
    checkU32(pd.received_count, 1, "(d) received_count after block 1");
    checkU32(pd.outstanding_count, 3, "(d) outstanding_count after block 1");

    piece.nextRequests(&pd, &q);
    checkU32(q.tail, 1, "(d) refill tail != 1");
    checkBegin(&q, 0, 4 * BLOCK, "(d) refill begin != block 4");
    checkU32(pd.outstanding_count, 4, "(d) refill outstanding_count != 4");

    // --- (e) corrupt-piece requeue resets the counters ----------------------
    var total_e: u32 = 2 * BLOCK;
    fillData(total_e);
    var z: usize = 0;
    while (z < 20) : (z += 1) g_hash[z] = @intCast(u8, 90);
    var te = makeTorrent("/tmp/z9torr_piece_e.bin", 2);
    var fe = disk.openTarget(&io_arena, te) catch {
        fail("(e) open target");
        return;
    };
    var ioe = piece.PieceIO{ .arena = &io_arena, .t = te, .f = &fe };
    var pe: piece.PieceState = piece.zeroPieceState();
    piece.pieceInit(&state_arena, te, &pe, 0) catch {
        fail("(e) pieceInit");
        return;
    };
    var re = piece.onBlock(&pe, 0, blockData(0, BLOCK), &ioe) catch {
        fail("(e) onBlock 0 error");
        return;
    };
    if (re != piece.BlockResult.Continue) fail("(e) block 0 was not Continue");
    checkU32(pe.received_count, 1, "(e) received_count before corrupt");
    re = piece.onBlock(&pe, BLOCK, blockData(BLOCK, BLOCK), &ioe) catch {
        fail("(e) onBlock 1 error");
        return;
    };
    if (re != piece.BlockResult.Corrupt) fail("(e) final block was not Corrupt");
    checkU32(pe.received_count, 0, "(e) requeue did not reset received_count");
    checkU32(pe.outstanding_count, 0, "(e) requeue did not reset outstanding_count");
    checkU32(pe.received_bytes, 0, "(e) requeue did not reset received_bytes");
    if (pe.state != piece.BlockState.failed) fail("(e) piece state not failed");
    if (pe.blocks[0] != piece.BlockState.missing) fail("(e) block 0 not missing");
    if (pe.blocks[1] != piece.BlockState.missing) fail("(e) block 1 not missing");
    piece.nextRequests(&pe, &q);
    checkU32(q.tail, 2, "(e) requeue nextRequests tail != 2");
    checkU32(pe.outstanding_count, 2, "(e) requeue nextRequests outstanding != 2");

    // --- (f) >1 MiB piece verifies without a whole-piece work-arena alloc ----
    // 96 * 16 KiB = 1.5 MiB, larger than the 1 MiB `g_io_buf` work arena.
    var nf: u32 = 96;
    var total_f: u32 = nf * BLOCK;
    fillData(total_f);
    hashPiece(g_data[0..@intCast(usize, total_f)]);
    var tf = makeTorrent("/tmp/z9torr_piece_f.bin", nf);
    var ff = disk.openTarget(&io_arena, tf) catch {
        fail("(f) open target");
        return;
    };
    var iof = piece.PieceIO{ .arena = &io_arena, .t = tf, .f = &ff };
    var pf: piece.PieceState = piece.zeroPieceState();
    piece.pieceInit(&state_arena, tf, &pf, 0) catch {
        fail("(f) pieceInit");
        return;
    };
    var completes_f: u32 = 0;
    var bf: u32 = 0;
    while (bf < nf) : (bf += 1) {
        var rf = piece.onBlock(&pf, bf * BLOCK, blockData(bf * BLOCK, BLOCK), &iof) catch {
            fail("(f) onBlock error");
            return;
        };
        if (rf == piece.BlockResult.Complete) completes_f += 1;
        if (bf + 1 < nf and rf != piece.BlockResult.Continue) fail("(f) early non-Continue");
    }
    checkU32(completes_f, 1, "(f) Complete was not reported exactly once");
    checkU32(pf.received_count, nf, "(f) received_count after Complete");
    if (pf.state != piece.BlockState.verified) fail("(f) >1 MiB piece not verified");

    var p: []const u8 = "piece_test: PASS (a) complete-once (b) duplicate (c) malformed (d) requests (e) requeue (f) >1MiB\n";
    std.io.write(p);
    std.os.exit(0);
}
