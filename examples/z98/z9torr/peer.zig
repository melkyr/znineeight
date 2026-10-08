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
// (directly, or through `std_stream.readMsgAsync`). All coroutine-live state
// lives in file-scope globals or the caller-owned `Peer`/`RunCtx` (spec §12
// risk 1: keep large state out of coroutine locals).
//
// NOTE (documented deviation): `wire.readHandshake` is blocking (`recvAll` ->
// `std_net.recv`), but `connectToIp` leaves the socket O_NONBLOCK, so calling
// it would race on a not-yet-arrived handshake. `readHandshakeAsync` below
// therefore re-reads the 68-byte record in the coroutine with the same
// validation rules as `wire.readHandshake`. `writeHandshake`/`writeInterested`/
// `writeRequest`/`writeKeepAlive` are used unchanged (small sends on loopback).
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

// Parse a raw 68-byte handshake record with the same rules as
// `wire.readHandshake`. `expected` is the 20-byte info_hash.
fn parseHandshake(h: []const u8, expected: []const u8, out: *wire.Handshake) PeerError!void {
    if (h.len != HANDSHAKE_LEN or expected.len != 20) return error.HandshakeFailed;
    if (h[0] != @intCast(u8, 19)) return error.HandshakeFailed;

    var pstr: []const u8 = "BitTorrent protocol";
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        if (h[1 + i] != pstr[i]) return error.HandshakeFailed;
    }
    i = 0;
    while (i < 8) : (i += 1) {
        if (h[20 + i] != 0) return error.HandshakeFailed;
    }
    i = 0;
    while (i < 20) : (i += 1) {
        if (h[28 + i] != expected[i]) return error.InfoHashMismatch;
    }

    i = 0;
    while (i < 19) : (i += 1) {
        out.pstr[i] = h[1 + i];
    }
    i = 0;
    while (i < 8) : (i += 1) {
        out.reserved[i] = h[20 + i];
    }
    i = 0;
    while (i < 20) : (i += 1) {
        out.info_hash[i] = h[28 + i];
        out.peer_id[i] = h[48 + i];
    }
}

// One non-blocking receive attempt. Returns 1 with the byte count in `out_n`
// (0 = EOF) on success, 0 when the socket would block (caller yields).
fn tryRecv(sock: *std_net.Socket, buf: []u8, out_n: *usize) PeerError!u8 {
    const got = std_net.recvNonBlocking(sock, buf) catch |e| {
        if (e == error.WouldBlock) return 0;
        return error.NetFailed;
    };
    out_n.* = got;
    return 1;
}

// Cooperative-yield exact read: suspend on WouldBlock until `buf` is full.
fn recvExactAsync(sock: *std_net.Socket, buf: []u8) PeerError!void {
    var off: usize = 0;
    while (off < buf.len) {
        var n: usize = 0;
        const st = try tryRecv(sock, buf[off..], &n);
        if (st == 0) {
            _ = @asyncSuspend(null);
        } else {
            if (n == 0) return error.PeerClosed;
            off += n;
        }
    }
}

fn readHandshakeAsync(peer: *Peer, expected: []const u8, out: *wire.Handshake) PeerError!void {
    try recvExactAsync(&peer.sock, peer.read_buf[0..HANDSHAKE_LEN]);
    try parseHandshake(peer.read_buf[0..HANDSHAKE_LEN], expected, out);
}

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

// Re-encode + write the resume sidecar from the shared verified bitset.
fn saveResume(ctx: *RunCtx) void {
    std.arena.reset(ctx.save_arena);
    var empty: [1]resumemod.PartialPiece = undefined;
    var st = resumemod.ResumeState{ .completed_bits = ctx.verified_bits, .partial = empty[0..0] };
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

    readHandshakeAsync(peer, ctx.t.info_hash[0..], &g_rhs) catch {
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
                .piece => {
                    if (!have_piece) {
                        // no piece requested yet; ignore
                    } else if (msg.payload.len < 8) {
                        stop = true;
                    } else {
                        var idx: u32 = wire.readU32BE(msg.payload[0..4]);
                        var begin: u32 = wire.readU32BE(msg.payload[4..8]);
                        var data: []const u8 = msg.payload[8..];
                        if (idx != g_ps.index) {
                            // foreign piece; ignore
                        } else {
                            std.arena.reset(ctx.work_arena);
                            var r = piece.onBlock(&g_ps, begin, data, &g_io) catch piece.BlockResult.Corrupt;
                            switch (r) {
                                .Continue => {
                                    sendRequests(peer, &g_ps);
                                },
                                .Complete => {
                                    piece.bitSet(ctx.verified_bits, idx);
                                    ctx.verified_count += 1;
                                    saveResume(ctx);
                                    cur = nextMissing(ctx);
                                    if (cur >= ctx.n_pieces) {
                                        ctx.ok = true;
                                    } else {
                                        piece.pieceInit(ctx.arena, ctx.t, &g_ps, cur) catch {
                                            ctx.exit_class = 5;
                                            stop = true;
                                        };
                                        sendRequests(peer, &g_ps);
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
