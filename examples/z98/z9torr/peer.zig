// peer.zig — z9torr: one peer's connection state machine (coroutine).
//
// Spec 2026-10-08 §3/§6/§7/§8, blueprint `peer` section. `peerRun` is a
// suspending function driven by the caller's `std.async` scheduler. It:
//   1. connects with `connectAsync` — a non-blocking `connect(2)` that yields on
//      WouldBlock (M4.1 Task 4), so a dead peer cannot freeze the scheduler;
//   2. runs the MSE/PE probe (`mse.mseConnectAsync`, also coroutine-aware),
//      then writes our handshake and reads/validates the peer's (info_hash must
//      match — `PeerError.InfoHashMismatch`), falling back to a fresh plaintext
//      connection if the probe fails;
//   3. sends `interested`, then reads `bitfield`/`have`, and waits for
//      `unchoke`;
//   4. pumps depth-4 `request`s and feeds each `piece` to `piece.onBlock`
//      (write-through + SHA-1 verify) until every piece is verified.
//
// The socket is non-blocking, so every wait yields via `@asyncSuspend(null)`
// (directly in `wire.recvExactAsync`, in `connectAsync`/`mse`, or through
// `std_stream.readMsgAsync`). All coroutine-live state lives in file-scope
// globals or the caller-owned `Peer`/`RunCtx` (spec §12 risk 1: keep large
// state out of coroutine locals — e.g. the MSE scratch is `peer.msesc`).
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
const mse = @import("mse.zig");
const pex = @import("pex.zig");
const piece = @import("piece.zig");
const scheduler = @import("scheduler.zig");
const torrent = @import("torrent.zig");
const tracker = @import("tracker.zig");
const resumemod = @import("resume.zig");
const filemod = @import("std_file.zig");
const ratelimit = @import("ratelimit.zig");
const logmod = @import("log.zig");

pub const PeerError = wire.PeerError;

const HANDSHAKE_LEN: usize = 68;
const KEEPALIVE_MS: u32 = 120000;
// Per-peer connect budget. `connectAsync` issues a non-blocking connect and
// yields via `@asyncSuspend` until the socket reports writable (or this deadline
// elapses), so a dead/unresponsive peer costs the scheduler only a tick per
// retry instead of freezing `tick` inside a blocking `select(2)`. Because the
// connect no longer serializes the single-threaded scheduler (M4.1 Task 4), the
// budget does not need to be tiny: the old 1 s value spuriously dropped
// reachable-but-slow peers (7/16 connect timeouts in the live run), so this is
// raised to a realistic 10 s while staying well under `STALL_MS` (60 s) so dead
// peers cannot by themselves trip the stall detector (spec §7/§8; M3
// final-review fix 3; CP P2).
const CONNECT_TIMEOUT_MS: u32 = 10000;

// Plaintext-fallback reconnect budget + retry cadence. After an MSE probe
// fails, `plainReconnect` retries a fresh plaintext connect for the WHOLE
// `FALLBACK_WINDOW_MS`; the retry is cooperatively throttled to one attempt per
// `FALLBACK_RETRY_MS` (no blocking `sleepMs` — M4.1 Task 4), so a fast-failing
// connect neither spins thousands of syscalls nor exhausts a fixed attempt count
// before the window elapses. This is the M4.1 Task 5 fix: Task 4 replaced the
// old 20 ms `sleepMs` pause with `@asyncSuspend`, which (with the then-100
// attempt cap) made the fallback give up in microseconds — a plaintext peer
// that only became reachable shortly after the MSE probe never got a second
// connection.
const FALLBACK_WINDOW_MS: u32 = 3000;
const FALLBACK_RETRY_MS: u32 = 20;

// IPv4 sockaddr for the raw `connect(2)`. Same layout std_net uses internally
// (`SockAddrIn` is private there), so the example can issue the non-blocking
// connect without an sf/src change (post-D1–D5 freeze).
const SockAddrIn = struct {
    sin_family: u16,
    sin_port: u16,
    sin_addr: u32,
    sin_zero: [8]u8,
};

// net_prelude.h aliases `connect_os` to the OS `connect`, matching std_net's own
// extern; `peer`'s generated TU sees that prelude through std_net.h.
extern "stdcall" fn connect_os(s: i32, name: *const void, namelen: i32) i32;

// Debug switch (wired by main from Z9TORR_CLAIM_LOG): when set, each scheduler
// claim prints one `claim slot=.. piece=..` line so a test can assert no two
// peers are asked for the same piece.
pub var log_claims: bool = false;

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
    // --- M3 Task 2: per-peer coroutine state (moved from file scope) ---------
    // The M2 file-scope scratch (`g_ps`/`g_io`/`g_hs`/`g_rhs`) lived in one
    // copy, so N concurrent peers would clobber each other; M3 moves it into
    // the caller-owned `Peer` (spec §6 M3 amendment / §12 risk 1).
    ps: piece.PieceState,
    io: piece.PieceIO,
    hs: wire.Handshake,
    rhs: wire.Handshake,
    // --- M4: per-peer MSE/PE state (D3/D4: caller-owned, stable address) -----
    // `enc` holds the two RC4 contexts (out = keyA, in = keyB) once the MSE
    // handshake has succeeded; `encrypted` selects the encrypted framing. Both
    // are overwritten in `peerRun` before use, so an uninitialised slot is safe.
    enc: mse.Rc4Pair,
    encrypted: bool,
    // CP P1: monotonic per-slot MSE attempt counter. Mixed into the ephemeral
    // seed so a re-dialed (slot, address) pair still derives a fresh `Xa`; it is
    // initialised once by `schedulerInit` and never reset on slot reuse.
    mse_attempts: u32,
    // M4.1 Task 4: caller-owned MSE handshake scratch (fixed arrays cannot live
    // in the coroutine frame across a suspension — see `mse.MseScratch`).
    msesc: mse.MseScratch,
    // M4: per-peer BEP 10/11 peer-exchange negotiation state (ut_pex id). Set by
    // `pexInit` at the top of `peerRun` before any extended message is parsed.
    pex: pex.PexState,
    // Peer availability bitfield (ceil(n_pieces/8) bytes; filled by the peer
    // loop from `bitfield`/`have`).
    bitfield: []u8,
    // Alias into the owning `Scheduler.piece_rarest` (empty when no scheduler).
    rarest: []u32,
    // Owning scheduler (null in the M2 single-peer path).
    sched: ?*scheduler.Scheduler,
    // Slot index within the scheduler's peer array.
    slot: u32,
    // True while this peer holds a claimed piece.
    have_piece: bool,
    // True while this slot is in use by the scheduler.
    active: bool,
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
    // Global token buckets shared by every peer (spec §6/§9 M3). `rate == 0`
    // means unlimited; main owns the buckets and rewires `last_refill_ms` to the
    // start time so the first refill does not credit a startup burst.
    down_bucket: *ratelimit.TokenBucket,
    up_bucket: *ratelimit.TokenBucket,
    // Live scheduler peer slots (set in `main.zig`). `saveResume` walks these so
    // the sidecar's `partial[]` lists every in-flight partial piece across all
    // peers, not just the calling one (spec §7).
    peers: []Peer,
    // M4: deterministic ephemeral MSE key material (Z9TORR_SEED or the clock).
    mse_seed: u32,
    // M4: scratch arena for decoding BEP 10/11 extended messages. Reset before
    // each extended message; owned by main (never a module global, D3/D4).
    pex_arena: *std.arena.Arena,
};
// Severity order (most-severe-wins): 5 disk > 4 peer > 3 tracker > 2 parse > 1 usage.
fn raiseExit(ctx: *RunCtx, c: u8) void {
    if (c > ctx.exit_class) ctx.exit_class = c;
}

// Diagnostic helpers for the `Z9TORR_LOG` peer trace. `logPeerIp` renders the
// network-order IPv4 in `PeerAddr.ip_be` (b0 in the low byte) as a dotted quad
// after the caller's `ip=` prefix. `logPeerEnd` writes the end-of-peer line.
fn logPeerIp(ip_be: u32) void {
    var m: u32 = @intCast(u32, 255);
    logmod.u32v(ip_be & m);
    logmod.s(".");
    logmod.u32v((ip_be >> 8) & m);
    logmod.s(".");
    logmod.u32v((ip_be >> 16) & m);
    logmod.s(".");
    logmod.u32v((ip_be >> 24) & m);
}

fn logPeerEnd(peer: *Peer) void {
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" end down=");
    logmod.u64v(peer.down_bytes);
    logmod.nl();
}
// M4 CP P3: env-gated per-peer wire-frame trace (Z9TORR_LOG). `id` is the
// `wire.MsgType` id and `body_len` the frame body length (id byte + payload);
// keep-alives carry no id and are rendered explicitly. These attribute a
// post-handshake close to the exact sent/received frame and peer slot. Every
// helper is a strict no-op when `Z9TORR_LOG` is unset (log.zig gates on
// `g_enabled`); free functions, no generics (Z98), caller-owned `Peer`/`Message`
// (D3/D4).
fn logFrameTx(peer: *Peer, id: u8, body_len: u32) void {
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" frame tx id=");
    logmod.u32v(@intCast(u32, id));
    logmod.s(" len=");
    logmod.u32v(body_len);
    logmod.nl();
}

fn logFrameTxFail(peer: *Peer, id: u8) void {
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" frame tx-fail id=");
    logmod.u32v(@intCast(u32, id));
    logmod.nl();
}

fn logFrameTxKeepalive(peer: *Peer) void {
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" frame tx keepalive len=0");
    logmod.nl();
}

fn logFrameRx(peer: *Peer, msg: *const wire.Message) void {
    if (msg.is_keep_alive) {
        logmod.s("peer slot=");
        logmod.u32v(peer.slot);
        logmod.s(" frame rx keepalive len=0");
        logmod.nl();
        return;
    }
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" frame rx id=");
    logmod.u32v(@intCast(u32, @enumToInt(msg.id)));
    logmod.s(" len=");
    logmod.u32v(@intCast(u32, msg.payload.len + 1));
    logmod.nl();
}

fn logFrameRxErr(peer: *Peer, e: wire.PeerError) void {
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" frame rx error=");
    logmod.s(wire.peerErrorName(e));
    logmod.nl();
}


// Zero-length slices returned to callers that need a valid-but-empty slice
// (the M2 single-peer path has no scheduler, so `rarest`/`bitfield` start
// empty). D2: `[]u8`/`[]u32` are primitive-element slices.
var g_empty_u8: [1]u8 = undefined;
var g_empty_u32: [1]u32 = undefined;
var g_empty_blockstate: [1]piece.BlockState = undefined;

pub fn emptyU8() []u8 {
    return g_empty_u8[0..0];
}

pub fn emptyU32() []u32 {
    return g_empty_u32[0..0];
}

fn emptyBlockStates() []piece.BlockState {
    return g_empty_blockstate[0..0];
}

// Zero-value constructors for the nested named-struct `Peer` fields. A struct
// literal field of a nested named-struct type cannot be `undefined` in Z98
// emission (it lowers to `0`, a C type error). `-fsafe` poisons `undefined`
// with 0xAA, so these fully initialise every field (never `return undefined`)
// and no poisoned field is ever read; callers still overwrite the fields before
// use (`makeHandshake`, `readHandshakeAsync`, `pieceInit`, the explicit `io`
// assignments).
pub fn zeroPieceState() piece.PieceState {
    var x: piece.PieceState = undefined;
    x.index = 0;
    x.state = piece.BlockState.missing;
    x.blocks = emptyBlockStates();
    x.received_bytes = 0;
    x.length = 0;
    x.nblocks = 0;
    return x;
}

// All-zero `torrent.Torrent` for `zeroPieceIO` (its slices/arrays must be
// written, not left `undefined`, so no poisoned field is ever read).
fn zeroTorrent() torrent.Torrent {
    var ih: [20]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        ih[i] = 0;
    }
    var alist: [8][]const u8 = undefined;
    var e: []const u8 = "";
    i = 0;
    while (i < 8) : (i += 1) {
        alist[i] = e;
    }
    return torrent.Torrent{
        .announce = e,
        .announce_list = alist,
        .announce_count = 0,
        .info_hash = ih,
        .name = e,
        .piece_length = 0,
        .piece_hashes = e,
        .total_length = 0,
    };
}

pub fn zeroPieceIO() piece.PieceIO {
    var x: piece.PieceIO = undefined;
    x.arena = @ptrFromInt(0);
    x.t = zeroTorrent();
    x.f = @ptrFromInt(0);
    return x;
}

pub fn zeroHandshake() wire.Handshake {
    var x: wire.Handshake = undefined;
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        x.pstr[i] = 0;
    }
    i = 0;
    while (i < 8) : (i += 1) {
        x.reserved[i] = 0;
    }
    i = 0;
    while (i < 20) : (i += 1) {
        x.info_hash[i] = 0;
        x.peer_id[i] = 0;
    }
    return x;
}

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
    // Advertise the two reserved bits we understand: BEP 10 extension protocol
    // (reserved[5] bit 0x10) and BEP 5 DHT (reserved[7] bit 0x01).
    out.reserved[5] = @intCast(u8, 0x10);
    out.reserved[7] = @intCast(u8, 0x01);
    i = 0;
    while (i < 20) : (i += 1) {
        out.info_hash[i] = t.info_hash[i];
        out.peer_id[i] = peer_id[i];
    }
}

// Name for an `mse.MseError` in the peer trace.
fn mseErrorName(e: mse.MseError) []const u8 {
    if (e == error.MseFailed) return "MseFailed";
    if (e == error.BadMethod) return "BadMethod";
    if (e == error.Timeout) return "Timeout";
    if (e == error.PeerClosed) return "PeerClosed";
    if (e == error.NetFailed) return "NetFailed";
    return "Unknown";
}

// Coroutine-aware non-blocking connect. Issues `connect(2)` on the already
// non-blocking socket, then yields until the socket reports writable; a real
// failure surfaces through `checkSoError` (SO_ERROR), a still-in-progress one
// keeps yielding until `deadline_ms` elapses (`error.Timeout`). No blocking
// `select(2)` timeout, so the scheduler keeps running other peers.
fn connectAsync(sock: std_net.Socket, ip_be: u32, port: u16, deadline_ms: u32) std_net.NetError!void {
    var s: std_net.Socket = sock;
    try std_net.setNonBlocking(&s);
    var addr = SockAddrIn{
        .sin_family = @intCast(u16, 2),
        .sin_port = std_net.htons(port),
        .sin_addr = ip_be,
        .sin_zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    // Non-blocking: 0 = connected immediately, -1 = in progress (or a real
    // error the SO_ERROR poll reports). errno is private to std_net, so the
    // outcome is read from the socket with `select` + `checkSoError`.
    _ = connect_os(s, @ptrCast(*const void, &addr), @intCast(i32, 16));
    var start: u32 = std.time.ticksMs();
    var done: bool = false;
    while (!done) {
        var wfds: std_net.fd_set = undefined;
        std_net.fdZero(@ptrCast(*u8, &wfds));
        std_net.fdSet(s, @ptrCast(*u8, &wfds));
        const sr = std_net.select(s + 1, null, @ptrCast(*u8, &wfds), null, @intCast(i32, 0));
        if (sr > 0) {
            try std_net.checkSoError(s);
            done = true;
        } else if (sr < 0) {
            return error.Io;
        } else if (std.time.ticksMs() - start >= deadline_ms) {
            return error.Timeout;
        } else {
            _ = @asyncSuspend(null);
        }
    }
}

// Socket + initial connect for one peer, with the peer trace. Void return
// (success in `ok_out`) so `peerRun` sees only void implicit awaits from the
// connect path and keeps one common parent_result type for the async transform.
fn connectPeer(peer: *Peer, deadline_ms: u32, ok_out: *bool) void {
    peer.sock = std_net.tcpSocket() catch {
        logmod.s("peer slot=");
        logmod.u32v(peer.slot);
        logmod.s(" socket-fail");
        logmod.nl();
        ok_out.* = false;
        return;
    };
    connectAsync(peer.sock, peer.addr.ip_be, peer.addr.port, deadline_ms) catch |e| {
        var nm: []const u8 = "other";
        if (e == error.Timeout) nm = "timeout";
        if (e == error.ConnRefused) nm = "refused";
        if (e == error.ConnReset) nm = "reset";
        if (e == error.NotConnected) nm = "notconnected";
        if (e == error.WouldBlock) nm = "wouldblock";
        if (e == error.ResolveFailed) nm = "resolvefailed";
        if (e == error.InvalidAddr) nm = "invalidaddr";
        if (e == error.Io) nm = "io";
        logmod.s("peer slot=");
        logmod.u32v(peer.slot);
        logmod.s(" connect-fail err=");
        logmod.s(nm);
        logmod.nl();
        std_net.close(peer.sock);
        ok_out.* = false;
        return;
    };
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" fd=");
    logmod.i32v(peer.sock);
    logmod.nl();
    ok_out.* = true;
}

// Encrypted-first step: run the outbound MSE/PE handshake into `peer.enc`.
// Success is written to `ok_out` (false on any failure, logged); the caller then
// falls back to a fresh plaintext connection. Coroutine-aware: `mseConnectAsync`
// yields on WouldBlock. Void return for the same async parent_result reason.
fn mseHandshake(ctx: *RunCtx, peer: *Peer, ok_out: *bool) void {
    // CP P1: derive a per-connection seed from the run base seed + this peer's
    // slot/address + a monotonic per-slot attempt counter, so each connection
    // sends a distinct `Ya` (independent `Xa`) — including a re-dialed
    // (slot, address) pair. Same inputs -> same secret: hermetic `Z9TORR_SEED`
    // runs stay deterministic.
    peer.mse_attempts = peer.mse_attempts +% 1;
    var pseed: u32 = mse.mixPeerSeed(ctx.mse_seed, peer.slot, peer.addr.ip_be, @intCast(u32, peer.addr.port), peer.mse_attempts);
    mse.mseConnectAsync(peer.sock, ctx.t.info_hash[0..], pseed, &peer.enc, &peer.msesc) catch |me| {
        logmod.s("peer slot=");
        logmod.u32v(peer.slot);
        logmod.s(" mse-fail err=");
        logmod.s(mseErrorName(me));
        logmod.nl();
        ok_out.* = false;
        return;
    };
    ok_out.* = true;
}

// Bounded plaintext fallback: close the (now unusable) MSE socket and open a
// fresh one, retrying for the WHOLE `FALLBACK_WINDOW_MS` while the peer (or the
// tier's one-shot plaintext mock) becomes reachable again. Coroutine-aware
// (M4.1 Task 4): `connectAsync` yields, and the inter-attempt pause is a
// cooperative `@asyncSuspend` rather than a blocking `sleepMs`, so it never
// freezes the scheduler. The retry is wall-clock throttled to one connect per
// `FALLBACK_RETRY_MS` (M4.1 Task 5) instead of a fixed attempt count, so the
// full budget is honored even when connects fail instantly. Void return (success
// in `ok_out`) so `peerRun`'s implicit awaits keep one common parent_result type
// (zig1 async P2/P4 order).
fn plainReconnect(ctx: *RunCtx, peer: *Peer, ok_out: *bool) void {
    _ = ctx;
    ok_out.* = false;
    std_net.close(peer.sock);
    peer.sock = @intCast(i32, -1);
    var start: u32 = std.time.ticksMs();
    var next_try: u32 = start;
    while (true) {
        var elapsed: u32 = std.time.ticksMs() - start;
        if (elapsed > FALLBACK_WINDOW_MS) return;
        // Cooperative throttle: yield (no blocking sleep) but attempt a connect
        // at most once per retry interval, so an immediate ECONNREFUSED cannot
        // burn the whole budget in a spin.
        if (std.time.ticksMs() < next_try) {
            _ = @asyncSuspend(null);
            continue;
        }
        next_try = std.time.ticksMs() + FALLBACK_RETRY_MS;
        peer.sock = std_net.tcpSocket() catch {
            peer.sock = @intCast(i32, -1);
            continue;
        };
        var rem: u32 = FALLBACK_WINDOW_MS - elapsed;
        if (rem > CONNECT_TIMEOUT_MS) rem = CONNECT_TIMEOUT_MS;
        connectAsync(peer.sock, peer.addr.ip_be, peer.addr.port, rem) catch {
            std_net.close(peer.sock);
            peer.sock = @intCast(i32, -1);
            continue;
        };
        ok_out.* = true;
        return;
    }
}

// The handshake read/validation now lives in `wire.readHandshakeAsync` (D-c);
// this module no longer carries a private copy.


// Return block `begin` of `ps` to `missing` so a later tick can request it.
fn revertBlock(ps: *piece.PieceState, begin: u32) void {
    var bi: u32 = begin / piece.BLOCK_SIZE;
    if (bi < ps.nblocks) ps.blocks[@intCast(usize, bi)] = piece.BlockState.missing;
}

// Fill the request window from `ps` and send the requests (no-op while the
// peer is choking). Small messages go through the blocking wire writers.
//
// M3 rate gate (spec §9): every outbound `request` is charged to the GLOBAL
// token buckets. `--max-up` reserves the 13 request bytes about to be sent;
// `--max-down` reserves the block payload the request will bring back (the
// download-only client throttles by not requesting faster than the down rate).
// `rate == 0` means unlimited. A block that cannot be afforded is returned to
// `missing` (with every later unsent block in this window) and the window stops.
//
// Returns true when the caller may block on the socket read (something was sent,
// nothing was left to send, or the write failed — the read path will surface it).
// Returns false only when the rate gate stopped us before sending anything: the
// caller must yield and retry, because there is no in-flight data to read.
fn sendRequests(ctx: *RunCtx, peer: *Peer, ps: *piece.PieceState) bool {
    if (peer.peer_choking) return true;
    var q: piece.RequestQueue = undefined;
    piece.nextRequests(ps, &q);
    var i: u32 = 0;
    var sent: u32 = 0;
    while (i < q.tail) : (i += 1) {
        var r = q.in_flight[@intCast(usize, i)];

        // Buckets are refilled centrally by the driver every 100 ms (spec §9);
        // here we only charge. A request that cannot be afforded consumes
        // nothing: the up charge is refunded when the down charge then fails.
        var afford: bool = true;
        if (ctx.up_bucket.rate != 0) {
            if (!ratelimit.take(ctx.up_bucket, @intCast(u32, 13))) afford = false;
        }
        if (afford and ctx.down_bucket.rate != 0) {
            if (!ratelimit.take(ctx.down_bucket, r.length)) {
                if (ctx.up_bucket.rate != 0) {
                    ratelimit.refund(ctx.up_bucket, @intCast(u32, 13));
                }
                afford = false;
            }
        }
        if (!afford) {
            var k: u32 = i;
            while (k < q.tail) : (k += 1) {
                revertBlock(ps, q.in_flight[@intCast(usize, k)].begin);
            }
            return sent > 0;
        }

        if (peer.encrypted) {
            wire.writeRequestEnc(peer.sock, &peer.enc.out, r.index, r.begin, r.length) catch return true;
        } else {
            wire.writeRequest(peer.sock, r.index, r.begin, r.length) catch return true;
        }
        logFrameTx(peer, @intCast(u8, 6), 13);
        peer.last_send_ms = std.time.ticksMs();
        peer.up_bytes += 13;
        sent += 1;
    }
    return true;
}

fn nextMissing(ctx: *RunCtx) u32 {
    var i: u32 = 0;
    while (i < ctx.n_pieces) : (i += 1) {
        if (!piece.bitGet(ctx.verified_bits, i)) return i;
    }
    return ctx.n_pieces;
}

// Pick the next piece for `peer`: the shared rarest-first `Scheduler` when one
// is attached (multi-peer), else the M2 lowest-missing-index scan. In the
// scheduler path the piece is immediately claimed (no suspension in between, so
// `pending_owner` recorded by `pickPiece` is this peer's).
fn chooseNext(ctx: *RunCtx, peer: *Peer) ?u32 {
    if (peer.sched) |sc| {
        var picked: ?u32 = scheduler.pickPiece(sc, peer);
        if (picked) |idx| {
            scheduler.claim(sc, idx);
            return idx;
        }
        return null;
    }
    var nxt: u32 = nextMissing(ctx);
    if (nxt >= ctx.n_pieces) return null;
    return nxt;
}

// Acquire + start a piece for `peer`. Returns 0 = have one, 1 = none available
// now, 2 = disk failure initialising the piece.
fn acquirePiece(ctx: *RunCtx, peer: *Peer) u8 {
    if (peer.have_piece) return 0;
    var picked: ?u32 = chooseNext(ctx, peer);
    if (picked) |cur| {
        piece.pieceInit(ctx.arena, ctx.t, &peer.ps, cur) catch return 2;
        seedPartial(ctx, &peer.ps);
        peer.have_piece = true;
        if (log_claims) {
            var c1: []const u8 = "claim slot=";
            std.io.write(c1);
            std.io.printInt(@intCast(i32, peer.slot));
            var c2: []const u8 = " piece=";
            std.io.write(c2);
            std.io.printInt(@intCast(i32, cur));
            var cn: []const u8 = "\n";
            std.io.write(cn);
        }
        _ = sendRequests(ctx, peer, &peer.ps);
        return 0;
    }
    return 1;
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

// True if `ps` holds at least one received (written-through) block.
fn hasReceived(ps: *piece.PieceState) bool {
    var i: u32 = 0;
    while (i < ps.nblocks) : (i += 1) {
        if (ps.blocks[@intCast(usize, i)] == piece.BlockState.received) return true;
    }
    return false;
}

// True if the partial list `pp[0..count]` already holds `index`.
fn indexIn(pp: []resumemod.PartialPiece, count: usize, index: u32) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (pp[i].index == index) return true;
    }
    return false;
}

// Encode `ps`'s received-block mask into the save arena and write the entry
// into `dst`. Returns false on arena exhaustion (caller aborts the save).
fn fillMask(ctx: *RunCtx, ps: *piece.PieceState, dst: *resumemod.PartialPiece) bool {
    var mbytes: usize = (@intCast(usize, ps.nblocks) + 7) / 8;
    var mraw = std.arena.alloc(ctx.save_arena, mbytes) catch return false;
    var mask: []u8 = mraw[0..mbytes];
    var z: usize = 0;
    while (z < mbytes) : (z += 1) {
        mask[z] = 0;
    }
    var i: u32 = 0;
    while (i < ps.nblocks) : (i += 1) {
        if (ps.blocks[@intCast(usize, i)] == piece.BlockState.received) {
            var byte: usize = @intCast(usize, i / 8);
            var sh: u8 = @intCast(u8, i % 8);
            var bit: u8 = @intCast(u8, 1) << sh;
            mask[byte] = mask[byte] | bit;
        }
    }
    dst.index = ps.index;
    dst.block_mask = mask;
    return true;
}

// Re-encode + write the resume sidecar: the shared verified bitset plus a
// `partial[]` entry for EVERY in-flight partial piece across all live peer
// slots, and, for pieces no peer currently holds, the loaded `ctx.partial`. The
// calling peer's `ps` is included even when it is not in `ctx.peers` (the M2
// single-peer path). Live masks take precedence over the loaded sidecar so the
// newer block state wins. Called after each verified piece, after every block
// written to a still-incomplete piece (so the recorded mtime stays current
// across write-through, spec §7), and on clean completion.
fn saveResume(ctx: *RunCtx, ps: *piece.PieceState) void {
    std.arena.reset(ctx.save_arena);
    var cap: usize = ctx.partial.len + ctx.peers.len + 1;
    var praw = std.arena.alloc(ctx.save_arena, cap * @sizeOf(resumemod.PartialPiece)) catch return;
    var pp: []resumemod.PartialPiece = @ptrCast([*]resumemod.PartialPiece, praw)[0..cap];
    var count: usize = 0;

    // 1. Live peers' working pieces (newest masks).
    var pi: usize = 0;
    while (pi < ctx.peers.len) : (pi += 1) {
        var lpe = &ctx.peers[pi];
        if (!lpe.active) continue;
        if (lpe.ps.state == piece.BlockState.verified) continue;
        if (lpe.ps.nblocks == 0) continue;
        if (!hasReceived(&lpe.ps)) continue;
        if (indexIn(pp, count, lpe.ps.index)) continue;
        if (!fillMask(ctx, &lpe.ps, &pp[count])) return;
        count += 1;
    }

    // 2. The calling peer (M2 path where it is not in `ctx.peers`).
    if (ps.state != piece.BlockState.verified and ps.nblocks > 0 and hasReceived(ps)) {
        if (!indexIn(pp, count, ps.index)) {
            if (!fillMask(ctx, ps, &pp[count])) return;
            count += 1;
        }
    }

    // 3. Loaded partials for pieces no live peer is working (older masks).
    var li: usize = 0;
    while (li < ctx.partial.len) : (li += 1) {
        var lp = ctx.partial[li];
        if (indexIn(pp, count, lp.index)) continue;
        pp[count] = lp;
        count += 1;
    }

    var st = resumemod.ResumeState{ .completed_bits = ctx.verified_bits, .partial = pp[0..count] };
    resumemod.save(ctx.save_arena, ctx.t, st) catch {};
}

// True when `sock` has at least one readable byte (a zero-timeout `select`).
// Used by the peer loop as a non-blocking wake gate: a peer with no claimed
// piece must never park in `readMessageAsync`, because `scheduler.corrupt` can
// return a piece to `missing` after this peer went idle, and a parked peer is
// not re-driven into `acquirePiece` until a message arrives. When nothing is
// readable the caller yields and re-checks the scheduler on the next tick.
fn socketReadable(sock: std_net.Socket) bool {
    if (sock < 0) return false;
    var rfds: std_net.fd_set = undefined;
    std_net.fdZero(@ptrCast(*u8, &rfds));
    std_net.fdSet(sock, @ptrCast(*u8, &rfds));
    const sr = std_net.select(sock + 1, @ptrCast(*u8, &rfds), null, null, @intCast(i32, 0));
    return sr > 0;
}

// The coroutine. `ctx`/`peer` come from the caller's args record via
// `@asyncInit`. Returns to the scheduler when every piece is verified (`ctx.ok`)
// or on any failure (`ctx.exit_class` = 4 peer, 5 disk).
pub fn peerRun(ctx: *RunCtx, peer: *Peer) void {
    ctx.ok = false;
    raiseExit(ctx, 4);
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" start ip=");
    logPeerIp(peer.addr.ip_be);
    logmod.s(" port=");
    logmod.u32v(@intCast(u32, peer.addr.port));
    logmod.nl();

    var cok: bool = false;
    connectPeer(peer, CONNECT_TIMEOUT_MS, &cok);
    if (!cok) {
        logPeerEnd(peer);
        return;
    }


    makeHandshake(ctx.t, peer.peer_id, &peer.hs);

    // Encrypted-first (spec §4.2): attempt MSE/PE; on success the rest of the
    // connection is RC4-wrapped. On failure, fall back to a fresh plaintext
    // socket (the MSE probe consumed the one-shot plaintext mock's connection).
    var mse_ok: bool = false;
    mseHandshake(ctx, peer, &mse_ok);
    if (mse_ok) {
        peer.encrypted = true;
        wire.writeHandshakeEnc(peer.sock, &peer.enc.out, &peer.hs) catch {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" handshake-write-fail");
            logmod.nl();
            std_net.close(peer.sock);
            logPeerEnd(peer);
            return;
        };
        wire.readHandshakeAsyncEnc(peer.sock, &peer.enc.in, ctx.t.info_hash[0..], &peer.rhs) catch |e| {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" handshake-fail err=");
            logmod.s(wire.peerErrorName(e));
            logmod.nl();
            std_net.close(peer.sock);
            logPeerEnd(peer);
            return;
        };
    } else {
        peer.encrypted = false;
        var r_ok: bool = false;
        plainReconnect(ctx, peer, &r_ok);
        if (!r_ok) {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" reconnect-fail");
            logmod.nl();
            logPeerEnd(peer);
            return;
        }
        wire.writeHandshake(peer.sock, &peer.hs) catch {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" handshake-write-fail");
            logmod.nl();
            std_net.close(peer.sock);
            logPeerEnd(peer);
            return;
        };
        wire.readHandshakeAsync(peer.sock, ctx.t.info_hash[0..], &peer.rhs) catch |e| {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" handshake-fail err=");
            logmod.s(wire.peerErrorName(e));
            logmod.nl();
            std_net.close(peer.sock);
            logPeerEnd(peer);
            return;
        };
    }
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    if (peer.encrypted) {
        logmod.s(" handshake ok enc");
    } else {
        logmod.s(" handshake ok plain");
    }
    logmod.nl();

    // BEP 10: if the peer advertises the extension protocol, announce `ut_pex`
    // in our extended handshake. A peer that leaves the bit clear gets no
    // extended traffic (the tier2/tier3 mocks advertise none).
    pex.pexInit(&peer.pex);
    if ((peer.rhs.reserved[5] & @intCast(u8, 0x10)) != 0) {
        std.arena.reset(ctx.pex_arena);
        var ext_body: []u8 = pex.pexBuildHandshake(ctx.pex_arena, 0);
        var ext_ok: bool = true;
        if (peer.encrypted) {
            wire.writeExtendedEnc(peer.sock, &peer.enc.out, 0, ext_body) catch { ext_ok = false; };
        } else {
            wire.writeExtended(peer.sock, 0, ext_body) catch { ext_ok = false; };
        }
        if (ext_ok) {
            logFrameTx(peer, @intCast(u8, 20), @intCast(u32, 2 + ext_body.len));
        } else {
            logFrameTxFail(peer, @intCast(u8, 20));
        }
    }

    // M4 test hook (tests/tier_pex.sh): synthesize a received `ut_pex` naming one
    // peer so PEX -> scheduler -> dynamic-spawn can be exercised end-to-end
    // without a purpose-built PEX mock. Gated by Z9TORR_PEX_INJECT=ip[:port].
    if (std.os.env("Z9TORR_PEX_INJECT")) |spec| {
        if (peer.sched) |sc| {
            std.arena.reset(ctx.pex_arena);
            _ = pex.pexInjectPeer(ctx.pex_arena, &peer.pex, sc, spec);
        }
    }

    if (peer.encrypted) {
        wire.writeInterestedEnc(peer.sock, &peer.enc.out) catch {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" interested-write-fail");
            logmod.nl();
            std_net.close(peer.sock);
            logPeerEnd(peer);
            return;
        };
    } else {
        wire.writeInterested(peer.sock) catch {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" interested-write-fail");
            logmod.nl();
            std_net.close(peer.sock);
            logPeerEnd(peer);
            return;
        };
    }
    logFrameTx(peer, @intCast(u8, 2), 1);

    var reader: std_stream.MsgReader = undefined;
    reader.src = &peer.sock;
    reader.buf = peer.read_buf[0..];
    reader.pending = peer.read_buf[0..0];

    var now: u32 = std.time.ticksMs();
    peer.last_recv_ms = now;
    peer.last_send_ms = now;

    peer.io.arena = ctx.work_arena;
    peer.io.t = ctx.t;
    peer.io.f = ctx.f;

    // M3: allocate this peer's availability bitset (zeroed; empty in the M2
    // path where n_pieces is 0).
    var need_bf: usize = (@intCast(usize, ctx.n_pieces) + 7) / 8;
    if (need_bf > 0) {
        var raw_bf = std.arena.alloc(ctx.arena, need_bf) catch {
            logmod.s("peer slot=");
            logmod.u32v(peer.slot);
            logmod.s(" bitfield-alloc-fail");
            logmod.nl();
            std_net.close(peer.sock);
            logPeerEnd(peer);
            return;
        };
        peer.bitfield = raw_bf[0..need_bf];
        var zb: usize = 0;
        while (zb < need_bf) : (zb += 1) {
            peer.bitfield[zb] = 0;
        }
    } else {
        peer.bitfield = emptyU8();
    }

    peer.have_piece = false;
    var st0: u8 = acquirePiece(ctx, peer);
    if (st0 == 2) {
        // Disk failure initialising the first piece: exit 5 (spec §8), matching
        // the loop's later disk paths.
        raiseExit(ctx, 5);
        logmod.s("peer slot=");
        logmod.u32v(peer.slot);
        logmod.s(" disk-piece-alloc");
        logmod.nl();
        std_net.close(peer.sock);
        logPeerEnd(peer);
        return;
    }
    if (st0 == 1 and ctx.verified_count >= ctx.n_pieces) {
        ctx.ok = true;
    }

    var break_reason: []const u8 = "end";
    while (!ctx.ok) {
        now = std.time.ticksMs();
        if (now - peer.last_recv_ms > KEEPALIVE_MS) {
            break_reason = "idle-timeout";
            break;
        }
        if (now - peer.last_send_ms > KEEPALIVE_MS) {
            if (peer.encrypted) {
                wire.writeKeepAliveEnc(peer.sock, &peer.enc.out) catch {
                    break_reason = "keepalive-write-fail";
                    break;
                };
            } else {
                wire.writeKeepAlive(peer.sock) catch {
                    break_reason = "keepalive-write-fail";
                    break;
                };
            }
            logFrameTxKeepalive(peer);
            peer.last_send_ms = now;
        }

        // M3 rate gate: retry any requests an earlier tick could not afford
        // (unlimited buckets make this a no-op once the window is full). If the
        // gate stopped us before sending anything, yield and retry next tick
        // instead of blocking in `readMessageAsync` (nothing is in flight, so it
        // would never wake).
        if (peer.have_piece) {
            if (!sendRequests(ctx, peer, &peer.ps)) {
                _ = @asyncSuspend(null);
                continue;
            }
        }

        // A peer that finished (or could not claim) a piece retries once a new
        // message (`unchoke`/`have`/`bitfield`) may have made a piece eligible.
        if (!peer.have_piece) {
            var st1: u8 = acquirePiece(ctx, peer);
            if (st1 == 2) {
                raiseExit(ctx, 5);
                break_reason = "disk-piece-alloc";
                break;
            }
            if (st1 == 1 and ctx.verified_count >= ctx.n_pieces) {
                ctx.ok = true;
                break_reason = "completion";
                break;
            }
        }

        // Wake gate (corrupt-piece re-queue): a peer with nothing claimed must
        // not park in the blocking message read. When its socket has no pending
        // bytes, yield and re-check `acquirePiece` next tick, so a piece that
        // `scheduler.corrupt` returned to `missing` after this peer went idle
        // is picked up and re-fetched from a good peer. A peer holding a piece
        // still blocks on the read: it has block data to receive.
        if (!peer.have_piece and !socketReadable(peer.sock)) {
            _ = @asyncSuspend(null);
            continue;
        }

        var msg: wire.Message = undefined;
        if (peer.encrypted) {
            wire.readMessageAsyncEnc(&reader, &peer.enc.in, &msg) catch |e| {
                logFrameRxErr(peer, e);
                break_reason = "read-error";
                break;
            };
        } else {
            wire.readMessageAsync(&reader, &msg) catch |e| {
                logFrameRxErr(peer, e);
                break_reason = "read-error";
                break;
            };
        }
        peer.last_recv_ms = std.time.ticksMs();
        logFrameRx(peer, &msg);

        var stop: bool = false;

        if (!msg.is_keep_alive) {
            switch (msg.id) {
                .unchoke => {
                    peer.peer_choking = false;
                    if (peer.have_piece) { _ = sendRequests(ctx, peer, &peer.ps); }
                },
                .choke => {
                    peer.peer_choking = true;
                },
                .bitfield => {
                    // B1=A: the peer's bitfield body must be exactly
                    // ceil(n_pieces/8) bytes; otherwise the peer is malformed
                    // and the run fails (spec §8 exit 4). Valid bits record the
                    // peer's availability and bump the rarest counts.
                    var need: usize = (@intCast(usize, ctx.n_pieces) + 7) / 8;
                    if (msg.payload.len != need) {
                        raiseExit(ctx, 4);
                        break_reason = "bad-bitfield";
                        stop = true;
                    } else {
                        var bi: u32 = 0;
                        while (bi < ctx.n_pieces) : (bi += 1) {
                            if (piece.bitGet(msg.payload, bi)) {
                                // With a scheduler the shared `noteHave` sets
                                // the bit and bumps `piece_rarest`; without one
                                // the M2 path only records the bit locally.
                                if (peer.sched) |sc| {
                                    scheduler.noteHave(sc, peer, bi);
                                } else if (!piece.bitGet(peer.bitfield, bi)) {
                                    piece.bitSet(peer.bitfield, bi);
                                }
                            }
                        }
                    }
                },
                .have => {
                    // M3: a `have` marks one more available piece.
                    if (msg.payload.len < 4) {
                        break_reason = "bad-have-msg";
                        stop = true;
                    } else {
                        var hi: u32 = wire.readU32BE(msg.payload[0..4]);
                        if (hi < ctx.n_pieces) {
                            if (peer.sched) |sc| {
                                scheduler.noteHave(sc, peer, hi);
                            } else if (!piece.bitGet(peer.bitfield, hi)) {
                                piece.bitSet(peer.bitfield, hi);
                            }
                        }
                    }
                },
                .piece => {
                    if (!peer.have_piece) {
                        // no piece requested yet; ignore
                    } else if (msg.payload.len < 8) {
                        break_reason = "bad-piece-msg";
                        stop = true;
                    } else {
                        var idx: u32 = wire.readU32BE(msg.payload[0..4]);
                        var begin: u32 = wire.readU32BE(msg.payload[4..8]);
                        var data: []const u8 = msg.payload[8..];
                        peer.down_bytes += @intCast(u64, data.len);
                        if (idx != peer.ps.index) {
                            // foreign piece; ignore
                        } else {
                            std.arena.reset(ctx.work_arena);
                            var r = piece.onBlock(&peer.ps, begin, data, &peer.io) catch piece.BlockResult.Corrupt;
                            switch (r) {
                                .Continue => {
                                    saveResume(ctx, &peer.ps);
                                    _ = sendRequests(ctx, peer, &peer.ps);
                                },
                                .Complete => {
                                    piece.bitSet(ctx.verified_bits, idx);
                                    ctx.verified_count += 1;
                                    if (peer.sched) |sc| {
                                        scheduler.complete(sc, idx);
                                    }
                                    peer.have_piece = false;
                                    saveResume(ctx, &peer.ps);
                                    if (ctx.verified_count >= ctx.n_pieces) {
                                        ctx.ok = true;
                                    } else {
                                        var stc: u8 = acquirePiece(ctx, peer);
                                        if (stc == 2) {
                                            raiseExit(ctx, 5);
                                            break_reason = "disk-piece-alloc";
                                            stop = true;
                                        }
                                    }
                                },
                                .Corrupt => {
                                    if (peer.sched) |sc| {
                                        // Return the piece to `missing` (blocks
                                        // retained) so another peer can fetch it,
                                        // and drop this peer (spec §7).
                                        scheduler.corrupt(sc, idx);
                                        peer.have_piece = false;
                                        break_reason = "corrupt";
                                        stop = true;
                                    } else {
                                        raiseExit(ctx, 4);
                                        break_reason = "corrupt";
                                        stop = true;
                                    }
                                },
                                else => {},
                            }
                        }
                    }
                },
                .extended => {
                    // BEP 10/11: negotiate ut_pex, then feed `added` peers to
                    // the scheduler. A peer that never negotiates is ignored by
                    // `pexOnExtended` (non-zero ext id with negotiated=false).
                    if (peer.sched) |sc| {
                        std.arena.reset(ctx.pex_arena);
                        _ = pex.pexOnExtended(ctx.pex_arena, &peer.pex, sc, msg.payload);
                    }
                },
                else => {},
            }
        }

        if (stop) break;
    }

    if (ctx.ok) break_reason = "completion";
    logmod.s("peer slot=");
    logmod.u32v(peer.slot);
    logmod.s(" break reason=");
    logmod.s(break_reason);
    logmod.nl();

    // Hand any claimed piece back so other peers may take it.
    if (peer.sched) |sc| {
        scheduler.release(sc, peer);
    }
    std_net.close(peer.sock);
    logPeerEnd(peer);

}
