// wire.zig — z9torr: BitTorrent peer wire protocol (handshake + message framing).
//
// Blueprint §3/§6, spec 2026-10-08 §3/§6/§8. All multi-byte integers on the
// wire are big-endian. The handshake is a fixed 68-byte record:
//
//   offset 0      : pstrlen = 19 (single byte)
//   offset 1..20  : pstr    = "BitTorrent protocol" (19 bytes)
//   offset 20..28 : reserved (8 bytes; MUST be zero for v1 — BEP 10 signalling)
//   offset 28..48 : info_hash (20 bytes)
//   offset 48..68 : peer_id   (20 bytes)
//
// Messages are framed as a 4-byte big-endian length prefix (which excludes
// itself), an optional 1-byte id, then the payload. A length of 0 is a
// keep-alive: no id, no payload. The cap is MAX_MESSAGE_SIZE (64 KiB).
//
// The reader is `std_stream.MsgReader` (`readMsgSync`/`readMsgAsync`): it
// decodes the u32-BE prefix and returns the frame body (id + payload) or a
// zero-length frame for a keep-alive. The caller-owned `MsgReader.buf` MUST be
// at least MAX_MESSAGE_SIZE (64 KiB): `readMsgSync`/`readMsgAsync` return
// FrameTooLarge when the declared length exceeds `buf.len`, and even a plain
// 16 KiB block `piece` body is 9 + 16384 = 16393 bytes, well over 16 KiB.
//
// Z98 rules (spec §5): no method syntax (free functions taking self), no
// generics, strict `@intCast`, `switch` needs `else`, string literals via
// `var s: []const u8 = "...";`. D2: every slice here is `[]u8`/`[]const u8`
// (primitive element) or a pointer to a named struct — no `[]synthetic`.

const std = @import("std");
const std_net = @import("std_net");
const std_stream = @import("std_stream.zig");
const logmod = @import("log.zig");

pub const MsgReader = std_stream.MsgReader;

// Message framing cap (blueprint §6): 64 KiB. A length prefix larger than this
// is a protocol error (`PeerError.BadMessage`).
pub const MAX_MESSAGE_SIZE: usize = 65536;

// Wire message ids (spec §6). This enum is EXACTLY 0..8; a keep-alive (a
// length-0 frame with no id) is not an id and is surfaced via
// `Message.is_keep_alive` instead.
pub const MsgType = enum(u8) {
    choke = 0,
    unchoke = 1,
    interested = 2,
    not_interested = 3,
    have = 4,
    bitfield = 5,
    request = 6,
    piece = 7,
    cancel = 8,
};

pub const Handshake = struct {
    pstr: [19]u8,
    reserved: [8]u8,
    info_hash: [20]u8,
    peer_id: [20]u8,
};

pub const Message = struct {
    id: MsgType,
    payload: []const u8,
    is_keep_alive: bool,
};

// Spec §8 error taxonomy, kept small and concrete. `PeerClosed`/`NetFailed`
// are the transport members (a peer close, or a socket send/recv error); the
// rest are protocol members.
pub const PeerError = error{
    HandshakeFailed,
    InfoHashMismatch,
    BadMessage,
    Timeout,
    BadHash,
    PeerClosed,
    NetFailed,
};

pub const HANDSHAKE_LEN: usize = 68;
// Absolute deadline (ms) for the async handshake exchange: a peer that TCP
// connects but never sends its 68-byte record fails as `PeerError.Timeout`
// instead of parking the coroutine until the 60 s stall watchdog. Handshake
// path only; the shared message framing/blocking read are untouched.
const HANDSHAKE_DEADLINE_MS: u32 = 3000;
const PSTR_LEN: usize = 19;
const RESERVED_LEN: usize = 8;
const HASH_LEN: usize = 20;

// --- big-endian integer helpers (blueprint §3) ------------------------------

pub fn readU32BE(b: []const u8) u32 {
    return (@intCast(u32, b[0]) << 24) | (@intCast(u32, b[1]) << 16) |
        (@intCast(u32, b[2]) << 8) | @intCast(u32, b[3]);
}

pub fn writeU32BE(b: []u8, v: u32) void {
    b[0] = @intCast(u8, (v >> 24) & @intCast(u32, 0xFF));
    b[1] = @intCast(u8, (v >> 16) & @intCast(u32, 0xFF));
    b[2] = @intCast(u8, (v >> 8) & @intCast(u32, 0xFF));
    b[3] = @intCast(u8, v & @intCast(u32, 0xFF));
}

pub fn readU16BE(b: []const u8) u16 {
    return (@intCast(u16, b[0]) << 8) | @intCast(u16, b[1]);
}

pub fn writeU16BE(b: []u8, v: u16) void {
    b[0] = @intCast(u8, (v >> 8) & @intCast(u16, 0xFF));
    b[1] = @intCast(u8, v & @intCast(u16, 0xFF));
}

// --- transport helpers ------------------------------------------------------

fn sendAll(sock: std_net.Socket, data: []const u8) PeerError!void {
    var off: usize = 0;
    while (off < data.len) {
        var chunk: []const u8 = data[off..];
        const n = std_net.send(sock, chunk.ptr, @intCast(i32, chunk.len));
        if (n <= 0) return error.NetFailed;
        off += @intCast(usize, n);
    }
}

fn recvAll(sock: std_net.Socket, buf: []u8) PeerError!void {
    var off: usize = 0;
    while (off < buf.len) {
        var chunk: []u8 = buf[off..];
        const n = std_net.recv(sock, chunk.ptr, @intCast(i32, chunk.len));
        if (n == 0) return error.PeerClosed;
        if (n < 0) return error.NetFailed;
        off += @intCast(usize, n);
    }
}

// --- env-gated handshake trace (Z9TORR_LOG) ---------------------------------

// Name for a `PeerError` in the handshake trace. `readHandshakeAsync` collapses
// transport and protocol failures, so the log records which concrete member
// fired. Strictly a formatter; safe to call when logging is off.
pub fn peerErrorName(e: PeerError) []const u8 {
    if (e == error.HandshakeFailed) return "HandshakeFailed";
    if (e == error.InfoHashMismatch) return "InfoHashMismatch";
    if (e == error.BadMessage) return "BadMessage";
    if (e == error.Timeout) return "Timeout";
    if (e == error.BadHash) return "BadHash";
    if (e == error.PeerClosed) return "PeerClosed";
    if (e == error.NetFailed) return "NetFailed";
    return "Unknown";
}

// `hs fd=<n> stage=<name> recv=<hex>` — the bytes received for one handshake
// stage. The fd ties the line back to the owning `peer slot=`/`fd=` line.
fn hsLogRecv(fd: std_net.Socket, stage: []const u8, data: []const u8) void {
    logmod.s("hs fd=");
    logmod.i32v(fd);
    logmod.s(" stage=");
    logmod.s(stage);
    logmod.s(" recv=");
    logmod.hex(data);
    logmod.nl();
}

// `hs fd=<n> stage=<name> err=<PeerError>` — a handshake stage failure.
fn hsLogFail(fd: std_net.Socket, stage: []const u8, e: PeerError) void {
    logmod.s("hs fd=");
    logmod.i32v(fd);
    logmod.s(" stage=");
    logmod.s(stage);
    logmod.s(" err=");
    logmod.s(peerErrorName(e));
    logmod.nl();
}

// --- handshake --------------------------------------------------------------

pub fn writeHandshake(sock: std_net.Socket, hs: *const Handshake) PeerError!void {
    var h: [HANDSHAKE_LEN]u8 = undefined;
    h[0] = @intCast(u8, PSTR_LEN);
    var i: usize = 0;
    while (i < PSTR_LEN) : (i += 1) {
        h[1 + i] = hs.pstr[i];
    }
    i = 0;
    while (i < RESERVED_LEN) : (i += 1) {
        h[20 + i] = hs.reserved[i];
    }
    i = 0;
    while (i < HASH_LEN) : (i += 1) {
        h[28 + i] = hs.info_hash[i];
    }
    i = 0;
    while (i < HASH_LEN) : (i += 1) {
        h[48 + i] = hs.peer_id[i];
    }
    logmod.s("hs fd=");
    logmod.i32v(sock);
    logmod.s(" sent=");
    logmod.hex(h[0..]);
    logmod.nl();
    try sendAll(sock, h[0..]);
}

// Read and validate a peer handshake. `expected_info_hash` is the caller's
// 20-byte info_hash (a `[]const u8` of length 20, D2-safe). Rejects a bad
// pstrlen/pstr (`HandshakeFailed`), a non-zero reserved field
// (`HandshakeFailed`) and a mismatching info_hash (`InfoHashMismatch`).
pub fn readHandshake(sock: std_net.Socket, expected_info_hash: []const u8, out: *Handshake) PeerError!void {
    if (expected_info_hash.len != HASH_LEN) return error.HandshakeFailed;

    var h: [HANDSHAKE_LEN]u8 = undefined;
    try recvAll(sock, h[0..]);

    if (h[0] != @intCast(u8, PSTR_LEN)) return error.HandshakeFailed;

    var pstr: []const u8 = "BitTorrent protocol";
    var i: usize = 0;
    while (i < PSTR_LEN) : (i += 1) {
        if (h[1 + i] != pstr[i]) return error.HandshakeFailed;
    }
    i = 0;
    while (i < RESERVED_LEN) : (i += 1) {
        if (h[20 + i] != 0) return error.HandshakeFailed;
    }
    i = 0;
    while (i < HASH_LEN) : (i += 1) {
        if (h[28 + i] != expected_info_hash[i]) return error.InfoHashMismatch;
    }

    i = 0;
    while (i < PSTR_LEN) : (i += 1) {
        out.pstr[i] = h[1 + i];
    }
    i = 0;
    while (i < RESERVED_LEN) : (i += 1) {
        out.reserved[i] = h[20 + i];
    }
    i = 0;
    while (i < HASH_LEN) : (i += 1) {
        out.info_hash[i] = h[28 + i];
    }
    i = 0;
    while (i < HASH_LEN) : (i += 1) {
        out.peer_id[i] = h[48 + i];
    }
}

// --- async handshake (non-blocking, for the peer coroutine) -----------------

// One non-blocking receive attempt. Returns 1 with the byte count in `out_n`
// (0 = EOF) on success, 0 when the socket would block (caller yields).
fn tryRecvAsync(sock: *std_net.Socket, buf: []u8, out_n: *usize) PeerError!u8 {
    const got = std_net.recvNonBlocking(sock, buf) catch |e| {
        if (e == error.WouldBlock) return 0;
        return error.NetFailed;
    };
    out_n.* = got;
    return 1;
}

// Cooperative-yield exact read: suspend on WouldBlock until `buf` is full.
// `buf` aliases caller (not local-array) memory so nothing large spans a
// suspension. `start_ms` is the `ticksMs` value captured at the start of the
// handshake; the read fails as `PeerError.Timeout` once the absolute
// `HANDSHAKE_DEADLINE_MS` budget elapses (a silent peer must not park the
// coroutine until the stall watchdog).
fn recvExactAsync(sock: std_net.Socket, buf: []u8, start_ms: u32) PeerError!void {
    var s: std_net.Socket = sock;
    var off: usize = 0;
    while (off < buf.len) {
        if (std.time.ticksMs() - start_ms >= HANDSHAKE_DEADLINE_MS) return error.Timeout;
        var n: usize = 0;
        const st = try tryRecvAsync(&s, buf[off..], &n);
        if (st == 0) {
            _ = @asyncSuspend(null);
        } else {
            if (n == 0) return error.PeerClosed;
            off += n;
        }
    }
}

// Read and validate a peer handshake WITHOUT blocking: the counterpart of
// `readHandshake` for `peer.zig`'s non-blocking socket. The 68-byte record is
// read straight into `out`'s fields (no local array spans a suspend). Same
// rules as `readHandshake`: pstrlen == 19, pstr match, zero reserved, and
// `info_hash` match else `PeerError.InfoHashMismatch`.
//
// NOTE: `expected_info_hash` is `[]const u8` (length 20), matching the ratified
// blocking `readHandshake` (Task-1 ruling A). A by-value `[20]u8` parameter is
// un-emittable here: this is a suspending (cross-module coroutine) callee, and
// the emitter copies the array argument into the child frame with a C array
// assignment, which C89 rejects (`assignment to expression with array type`).
pub fn readHandshakeAsync(sock: std_net.Socket, expected_info_hash: []const u8, out: *Handshake) PeerError!void {
    if (expected_info_hash.len != HASH_LEN) return error.HandshakeFailed;
    var start_ms: u32 = std.time.ticksMs();
    // The leading pstrlen byte has no `Handshake` field; land it in
    // `out.info_hash[0]` as scratch (that field is fully overwritten below).
    recvExactAsync(sock, out.info_hash[0..1], start_ms) catch |e| {
        hsLogFail(sock, "pstrlen", e);
        return e;
    };
    hsLogRecv(sock, "pstrlen", out.info_hash[0..1]);
    if (out.info_hash[0] != @intCast(u8, PSTR_LEN)) {
        hsLogFail(sock, "pstrlen", error.HandshakeFailed);
        return error.HandshakeFailed;
    }

    recvExactAsync(sock, out.pstr[0..], start_ms) catch |e| {
        hsLogFail(sock, "pstr", e);
        return e;
    };
    hsLogRecv(sock, "pstr", out.pstr[0..]);

    recvExactAsync(sock, out.reserved[0..], start_ms) catch |e| {
        hsLogFail(sock, "reserved", e);
        return e;
    };
    hsLogRecv(sock, "reserved", out.reserved[0..]);

    recvExactAsync(sock, out.info_hash[0..], start_ms) catch |e| {
        hsLogFail(sock, "info_hash", e);
        return e;
    };
    hsLogRecv(sock, "info_hash", out.info_hash[0..]);

    recvExactAsync(sock, out.peer_id[0..], start_ms) catch |e| {
        hsLogFail(sock, "peer_id", e);
        return e;
    };
    hsLogRecv(sock, "peer_id", out.peer_id[0..]);

    var pstr: []const u8 = "BitTorrent protocol";
    var i: usize = 0;
    while (i < PSTR_LEN) : (i += 1) {
        if (out.pstr[i] != pstr[i]) {
            hsLogFail(sock, "pstr", error.HandshakeFailed);
            return error.HandshakeFailed;
        }
    }
    i = 0;
    while (i < RESERVED_LEN) : (i += 1) {
        if (out.reserved[i] != 0) {
            hsLogFail(sock, "reserved", error.HandshakeFailed);
            return error.HandshakeFailed;
        }
    }
    i = 0;
    while (i < HASH_LEN) : (i += 1) {
        if (out.info_hash[i] != expected_info_hash[i]) {
            hsLogFail(sock, "info_hash", error.InfoHashMismatch);
            return error.InfoHashMismatch;
        }
    }
    logmod.s("hs fd=");
    logmod.i32v(sock);
    logmod.s(" ok");
    logmod.nl();
}

// --- message framing --------------------------------------------------------
fn decodeMsgType(id: u8, out: *MsgType) bool {
    switch (id) {
        0 => {
            out.* = MsgType.choke;
            return true;
        },
        1 => {
            out.* = MsgType.unchoke;
            return true;
        },
        2 => {
            out.* = MsgType.interested;
            return true;
        },
        3 => {
            out.* = MsgType.not_interested;
            return true;
        },
        4 => {
            out.* = MsgType.have;
            return true;
        },
        5 => {
            out.* = MsgType.bitfield;
            return true;
        },
        6 => {
            out.* = MsgType.request;
            return true;
        },
        7 => {
            out.* = MsgType.piece;
            return true;
        },
        8 => {
            out.* = MsgType.cancel;
            return true;
        },
        else => return false,
    }
}

// Decode one frame body (id + payload) into `out`. A zero-length frame is a
// keep-alive: `is_keep_alive = true`, empty payload, unused `id` set to .choke.
fn decodeFrame(frame: []u8, out: *Message) PeerError!void {
    if (frame.len == 0) {
        out.id = MsgType.choke;
        out.payload = frame[0..0];
        out.is_keep_alive = true;
        return;
    }
    var t: MsgType = undefined;
    if (!decodeMsgType(frame[0], &t)) return error.BadMessage;
    out.id = t;
    out.payload = frame[1..];
    out.is_keep_alive = false;
}

// Read one framed message into `out` (blocking). A zero-length frame is a
// keep-alive (`is_keep_alive = true`). An oversize frame (length > 64 KiB) or
// an unknown id is `PeerError.BadMessage`; EOF is `PeerError.PeerClosed`.
// `out.payload` aliases the reader buffer and is valid until the next read.
pub fn readMessage(mr: *MsgReader, out: *Message) PeerError!void {
    var frame_opt: ?[]u8 = std_stream.readMsgSync(mr) catch |e| {
        if (e == error.FrameTooLarge) return error.BadMessage;
        return error.NetFailed;
    };
    if (frame_opt) |frame| {
        try decodeFrame(frame, out);
        return;
    }
    return error.PeerClosed;
}

// Cooperative-yield counterpart of `readMessage` for a non-blocking socket:
// `readMsgAsync` suspends on WouldBlock internally (std_stream.zig) and is
// re-driven on the next tick. Same error/keep-alive semantics.
pub fn readMessageAsync(mr: *MsgReader, out: *Message) PeerError!void {
    var frame_opt: ?[]u8 = std_stream.readMsgAsync(mr) catch |e| {
        if (e == error.FrameTooLarge) return error.BadMessage;
        return error.NetFailed;
    };
    if (frame_opt) |frame| {
        try decodeFrame(frame, out);
        return;
    }
    return error.PeerClosed;
}

// --- message writers --------------------------------------------------------

fn checkLen(total: usize) PeerError!void {
    if (total == 0 or total > MAX_MESSAGE_SIZE) return error.BadMessage;
}

// A message with an id and no payload (choke/unchoke/interested/...).
pub fn writeSimple(sock: std_net.Socket, id: MsgType) PeerError!void {
    var b: [5]u8 = undefined;
    writeU32BE(b[0..4], @intCast(u32, 1));
    b[4] = @intCast(u8, @enumToInt(id));
    try sendAll(sock, b[0..]);
}

pub fn writeChoke(sock: std_net.Socket) PeerError!void {
    try writeSimple(sock, MsgType.choke);
}

pub fn writeUnchoke(sock: std_net.Socket) PeerError!void {
    try writeSimple(sock, MsgType.unchoke);
}

pub fn writeInterested(sock: std_net.Socket) PeerError!void {
    try writeSimple(sock, MsgType.interested);
}

pub fn writeNotInterested(sock: std_net.Socket) PeerError!void {
    try writeSimple(sock, MsgType.not_interested);
}

// Zero-length frame: 4-byte length prefix 0, no id, no payload.
pub fn writeKeepAlive(sock: std_net.Socket) PeerError!void {
    var b: [4]u8 = undefined;
    writeU32BE(b[0..4], @intCast(u32, 0));
    try sendAll(sock, b[0..]);
}

// have{index}: payload is a 4-byte BE piece index.
pub fn writeHave(sock: std_net.Socket, index: u32) PeerError!void {
    var b: [9]u8 = undefined;
    writeU32BE(b[0..4], @intCast(u32, 5));
    b[4] = @intCast(u8, @enumToInt(MsgType.have));
    writeU32BE(b[5..9], index);
    try sendAll(sock, b[0..]);
}

// bitfield{bits}: payload is the raw bitfield bytes.
pub fn writeBitfield(sock: std_net.Socket, bits: []const u8) PeerError!void {
    const total: usize = 1 + bits.len;
    try checkLen(total);
    var hdr: [5]u8 = undefined;
    writeU32BE(hdr[0..4], @intCast(u32, total));
    hdr[4] = @intCast(u8, @enumToInt(MsgType.bitfield));
    try sendAll(sock, hdr[0..]);
    try sendAll(sock, bits);
}

// request{index, begin, length} / cancel{...}: 12-byte payload, all BE u32.
fn writeBlockReq(sock: std_net.Socket, id: MsgType, index: u32, begin: u32, length: u32) PeerError!void {
    var b: [17]u8 = undefined;
    writeU32BE(b[0..4], @intCast(u32, 13));
    b[4] = @intCast(u8, @enumToInt(id));
    writeU32BE(b[5..9], index);
    writeU32BE(b[9..13], begin);
    writeU32BE(b[13..17], length);
    try sendAll(sock, b[0..]);
}

pub fn writeRequest(sock: std_net.Socket, index: u32, begin: u32, length: u32) PeerError!void {
    try writeBlockReq(sock, MsgType.request, index, begin, length);
}

pub fn writeCancel(sock: std_net.Socket, index: u32, begin: u32, length: u32) PeerError!void {
    try writeBlockReq(sock, MsgType.cancel, index, begin, length);
}

// piece{index, begin, data}: 4+4 BE header then the block bytes.
pub fn writePiece(sock: std_net.Socket, index: u32, begin: u32, data: []const u8) PeerError!void {
    const total: usize = 9 + data.len;
    try checkLen(total);
    var hdr: [13]u8 = undefined;
    writeU32BE(hdr[0..4], @intCast(u32, total));
    hdr[4] = @intCast(u8, @enumToInt(MsgType.piece));
    writeU32BE(hdr[5..9], index);
    writeU32BE(hdr[9..13], begin);
    try sendAll(sock, hdr[0..]);
    try sendAll(sock, data);
}
