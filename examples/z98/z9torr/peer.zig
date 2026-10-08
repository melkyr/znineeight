// peer.zig — z9torr: one peer's connection state machine (coroutine).
//
// Spec 2026-10-08 §3/§6/§7/§8, blueprint `peer` section. `peerRun` is a
// suspending function driven by the caller's `std.async` scheduler. It:
//   1. connects (`std_net.connectToIp`, which leaves the socket non-blocking);
//   2. writes our handshake and reads/validates the peer's (info_hash must
//      match — `PeerError.InfoHashMismatch`);
//   3. sends `interested`, then reads `bitfield`/`have`, and waits for
//      `unchoke`;
//   4. pumps depth-4 `request`s and feeds each `piece` to `piece.onBlock`
//      (write-through + SHA-1 verify) until every piece is verified.
//
// The socket is non-blocking, so every wait yields via `@asyncSuspend(null)`
// (directly in `wire.recvExactAsync`, or through `std_stream.readMsgAsync`).
// All coroutine-live state lives in file-scope globals or the caller-owned
// `Peer`/`RunCtx` (spec §12 risk 1: keep large state out of coroutine locals).
//
// The handshake is read with `wire.readHandshakeAsync` (the non-blocking
// counterpart of `wire.readHandshake` added under D-c).
//
// `peerRun` returns `void`, not `!void`: the landed `std.async` drive loop
// consumes only `@asyncResume`'s `?*void` step status, so a coroutine cannot
// surface an error to its caller (the same reason `std_stream`'s async readers
// split their work into scalar-status helpers). The outcome is therefore
// reported through `RunCtx`:
//   * `ok == true`                 -> every piece is verified;
//   * `ok == false`                -> failure, with `exit_class` set to the
//     spec §8 class (`4` peer/protocol, including a bad handshake or a SHA-1
//     mismatch; `5` disk). `peerRun` handles every `PeerError` internally and
//     never lets it escape the frame.
//
// Z98 rules: free functions only, no generics, strict `@intCast`, `switch`
// needs `else`. D2: `[]u8`/`[]const u8` plus `[]piece.PieceState` (named).

const std = @import("std");
const std_net = @import("std_net");
const std_stream = @import("std_stream.zig");
const wire = @import("wire.zig");
const piece = @import("piece.zig");
const torrent = @import("torrent.zig");
const tracker = @import("tracker.zig");
const resumemod = @import("resume.zig");
const filemod = @import("std_file.zig");

pub const PeerError = wire.PeerError;

const HANDSHAKE_LEN: usize = 68;
const KEEPALIVE_MS: u32 = 120000;
const CONNECT_TIMEOUT_MS: u32 = 10000;

pub const Peer = struct {
    addr: tracker.PeerAddr,
    sock: std_net.Socket,
    peer_id: [20]u8,
    am_choking: bool,
    am_interested: bool,
    peer_choking: bool,
    peer_interested: bool,
    last_recv_ms: u32,
    last_send_ms: u32,
    down_bytes: u64,
    up_bytes: u64,
    read_buf: [65536]u8,
};

// Caller-owned download context. `arena` holds durable piece state (block
// vectors); `work_arena` is reset per `onBlock` for the read-back scratch;
// `save_arena` is reset per resume save. `verified_bits` is the completed-piece
// bitset (shared with `resume`). `ok`/`exit_class` carry the outcome back.
pub const RunCtx = struct {
    arena: *std.arena.Arena,
    work_arena: *std.arena.Arena,
    save_arena: *std.arena.Arena,
    t: torrent.Torrent,
    f: *filemod.File,
    verified_bits: []u8,
    partial: []resumemod.PartialPiece,
    n_pieces: u32,
    verified_count: u32,
    ok: bool,
    exit_class: u8,
};

// Coroutine-live scratch state kept at file scope (see header note).
var g_ps: piece.PieceState = undefined;
var g_io: piece.PieceIO = undefined;
var g_hs: wire.Handshake = undefined;
var g_rhs: wire.Handshake = undefined;

fn makeHandshake(t: torrent.Torrent, peer_id: [20]u8, out: *wire.Handshake) void {
    var pstr: []const u8 = "BitTorrent protocol";
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        out.pstr[i] = pstr[i];
    }
    i = 0;
    while (i < 8) : (i += 1) {
        out.reserved[i] = 0;
    }
    i = 0;
    while (i < 20) : (i += 1) {
        out.info_hash[i] = t.info_hash[i];
        out.peer_id[i] = peer_id[i];
    }
}

// The handshake read/validation now lives in `wire.readHandshakeAsync` (D-c);
// this module no longer carries a private copy.


// Fill the request window from `ps` and send the requests (no-op while the
// peer is choking). Small messages go through the blocking wire writers.
fn sendRequests(peer: *Peer, ps: *piece.PieceState) void {
    if (peer.peer_choking) return;
    var q: piece.RequestQueue = undefined;
    piece.nextRequests(ps, &q);
    var i: u32 = 0;
    while (i < q.tail) : (i += 1) {
        var r = q.in_flight[@intCast(usize, i)];
        wire.writeRequest(peer.sock, r.index, r.begin, r.length) catch return;
        peer.last_send_ms = std.time.ticksMs();
        peer.up_bytes += 13;
    }
}

fn nextMissing(ctx: *RunCtx) u32 {
    var i: u32 = 0;
    while (i < ctx.n_pieces) : (i += 1) {
        if (!piece.bitGet(ctx.verified_bits, i)) return i;
    }
    return ctx.n_pieces;
}

// Seed `ps`'s block states from the loaded sidecar's partial mask for this
// piece: blocks the previous run wrote through are already on disk, so mark
// them `received` and let `nextRequests` request only the missing 16 KB blocks
// (B2=A — half-downloaded piece resume). A mask mismatch simply re-requests.
fn seedPartial(ctx: *RunCtx, ps: *piece.PieceState) void {
    var i: usize = 0;
    while (i < ctx.partial.len) : (i += 1) {
        var pp = ctx.partial[i];
        if (pp.index == ps.index) {
            var b: u32 = 0;
            while (b < ps.nblocks) : (b += 1) {
                var byte: usize = @intCast(usize, b / 8);
                var sh: u8 = @intCast(u8, b % 8);
                if (byte < pp.block_mask.len) {
                    var bit: u8 = (pp.block_mask[byte] >> sh) & @intCast(u8, 1);
                    if (bit == @intCast(u8, 1)) {
                        ps.blocks[@intCast(usize, b)] = piece.BlockState.received;
                    }
                }
            }
            return;
        }
    }
}

// Re-encode + write the resume sidecar: the shared verified bitset plus, if
// `ps` is a half-downloaded piece, its received-block mask. Called after each
// verified piece, after every block written to a still-incomplete piece (so
// the recorded mtime stays current across write-through, spec §7), and on
// clean completion.
fn saveResume(ctx: *RunCtx, ps: *piece.PieceState) void {
    std.arena.reset(ctx.save_arena);
    var empty: [1]resumemod.PartialPiece = undefined;
    var partial_arr: []resumemod.PartialPiece = empty[0..0];
    if (ps.state != piece.BlockState.verified) {
        var any: bool = false;
        var i: u32 = 0;
        while (i < ps.nblocks) : (i += 1) {
            if (ps.blocks[@intCast(usize, i)] == piece.BlockState.received) any = true;
        }
        if (any) {
            var mbytes: usize = (@intCast(usize, ps.nblocks) + 7) / 8;
            var mraw = std.arena.alloc(ctx.save_arena, mbytes) catch return;
            var mask: []u8 = mraw[0..mbytes];
            var z: usize = 0;
            while (z < mbytes) : (z += 1) {
                mask[z] = 0;
            }
            i = 0;
            while (i < ps.nblocks) : (i += 1) {
                if (ps.blocks[@intCast(usize, i)] == piece.BlockState.received) {
                    var byte: usize = @intCast(usize, i / 8);
                    var sh: u8 = @intCast(u8, i % 8);
                    var bit: u8 = @intCast(u8, 1) << sh;
                    mask[byte] = mask[byte] | bit;
                }
            }
            var praw = std.arena.alloc(ctx.save_arena, @sizeOf(resumemod.PartialPiece)) catch return;
            var pp: []resumemod.PartialPiece = @ptrCast([*]resumemod.PartialPiece, praw)[0..1];
            pp[0] = resumemod.PartialPiece{ .index = ps.index, .block_mask = mask };
            partial_arr = pp;
        }
    }
    var st = resumemod.ResumeState{ .completed_bits = ctx.verified_bits, .partial = partial_arr };
    resumemod.save(ctx.save_arena, ctx.t, st) catch {};
}

// The coroutine. `ctx`/`peer` come from the caller's args record via
// `@asyncInit`. Returns to the scheduler when every piece is verified (`ctx.ok`)
// or on any failure (`ctx.exit_class` = 4 peer, 5 disk).
pub fn peerRun(ctx: *RunCtx, peer: *Peer) void {
    ctx.ok = false;
    ctx.exit_class = 4;

    peer.sock = std_net.tcpSocket() catch return;
    std_net.connectToIp(peer.sock, peer.addr.ip_be, peer.addr.port, CONNECT_TIMEOUT_MS) catch {
        std_net.close(peer.sock);
        return;
    };

    makeHandshake(ctx.t, peer.peer_id, &g_hs);
    wire.writeHandshake(peer.sock, &g_hs) catch {
        std_net.close(peer.sock);
        return;
    };

    wire.readHandshakeAsync(peer.sock, ctx.t.info_hash[0..], &g_rhs) catch {
        std_net.close(peer.sock);
        return;
    };

    wire.writeInterested(peer.sock) catch {
        std_net.close(peer.sock);
        return;
    };

    var reader: std_stream.MsgReader = undefined;
    reader.src = &peer.sock;
    reader.buf = peer.read_buf[0..];
    reader.pending = peer.read_buf[0..0];

    var now: u32 = std.time.ticksMs();
    peer.last_recv_ms = now;
    peer.last_send_ms = now;

    g_io.arena = ctx.work_arena;
    g_io.t = ctx.t;
    g_io.f = ctx.f;

    var have_piece: bool = false;
    var cur: u32 = nextMissing(ctx);
    if (cur < ctx.n_pieces) {
        piece.pieceInit(ctx.arena, ctx.t, &g_ps, cur) catch {
            std_net.close(peer.sock);
            return;
        };
        seedPartial(ctx, &g_ps);
        have_piece = true;
        sendRequests(peer, &g_ps);
    } else {
        ctx.ok = true;
    }

    while (!ctx.ok) {
        now = std.time.ticksMs();
        if (now - peer.last_recv_ms > KEEPALIVE_MS) break; // idle: disconnect
        if (now - peer.last_send_ms > KEEPALIVE_MS) {
            wire.writeKeepAlive(peer.sock) catch break;
            peer.last_send_ms = now;
        }

        var msg: wire.Message = undefined;
        wire.readMessageAsync(&reader, &msg) catch break;
        peer.last_recv_ms = std.time.ticksMs();

        var stop: bool = false;

        if (!msg.is_keep_alive) {
            switch (msg.id) {
                .unchoke => {
                    peer.peer_choking = false;
                    if (have_piece) sendRequests(peer, &g_ps);
                },
                .choke => {
                    peer.peer_choking = true;
                },
                .bitfield => {
                    // B1=A: the peer's bitfield body must be exactly
                    // ceil(n_pieces/8) bytes; otherwise the peer is malformed
                    // and the run fails (spec §8 exit 4).
                    var need: usize = (@intCast(usize, ctx.n_pieces) + 7) / 8;
                    if (msg.payload.len != need) {
                        ctx.exit_class = 4;
                        stop = true;
                    }
                },
                .piece => {
                    if (!have_piece) {
                        // no piece requested yet; ignore
                    } else if (msg.payload.len < 8) {
                        stop = true;
                    } else {
                        var idx: u32 = wire.readU32BE(msg.payload[0..4]);
                        var begin: u32 = wire.readU32BE(msg.payload[4..8]);
                        var data: []const u8 = msg.payload[8..];
                        peer.down_bytes += @intCast(u64, data.len);
                        if (idx != g_ps.index) {
                            // foreign piece; ignore
                        } else {
                            std.arena.reset(ctx.work_arena);
                            var r = piece.onBlock(&g_ps, begin, data, &g_io) catch piece.BlockResult.Corrupt;
                            switch (r) {
                                .Continue => {
                                    saveResume(ctx, &g_ps);
                                    sendRequests(peer, &g_ps);
                                },
                                .Complete => {
                                    piece.bitSet(ctx.verified_bits, idx);
                                    ctx.verified_count += 1;
                                    saveResume(ctx, &g_ps);
                                    cur = nextMissing(ctx);
                                    if (cur >= ctx.n_pieces) {
                                        ctx.ok = true;
                                    } else {
                                        piece.pieceInit(ctx.arena, ctx.t, &g_ps, cur) catch {
                                            ctx.exit_class = 5;
                                            stop = true;
                                        };
                                        if (!stop) {
                                            seedPartial(ctx, &g_ps);
                                            sendRequests(peer, &g_ps);
                                        }
                                    }
                                },
                                .Corrupt => {
                                    ctx.exit_class = 4;
                                    stop = true;
                                },
                                else => {},
                            }
                        }
                    }
                },
                else => {},
            }
        }

        if (stop) break;
    }

    std_net.close(peer.sock);
}
