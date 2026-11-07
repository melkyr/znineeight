// stdlib_http2_state_xmod — HTTP/2 connection, streams, and flow control.
//
// Drives `std_http2` through `http2OpenTransport` with a scripted, entirely
// non-suspending `Transport`. The script supplies literal server frames
// (SETTINGS, PING, HEADERS/DATA, GOAWAY, RST_STREAM, WINDOW_UPDATE); the
// transport write side records client output and can stall after a chosen byte
// offset to model a partial `WouldBlock` write. The scripted server data never
// includes the client PRI preface: the server connection preface is SETTINGS.

//
// Scenarios (one connection each):
//   basic     two GETs, response bodies "a" and "b", status 200, odd ids 1/3,
//             SETTINGS ACK and PING ACK.
//   goaway    GOAWAY(last=0) fails the in-flight stream.
//   rst       RST_STREAM(8) fails the in-flight stream.
//   wb        a write stalls mid-SETTINGS frame; resumed pumps emit the exact
//             same byte stream with no loss or duplication.
//   zero      WINDOW_UPDATE increment 0 -> error.Protocol.
//   win       SETTINGS_INITIAL_WINDOW_SIZE changes apply signed deltas to an
//             already-open stream.
//   arena     100 submit/complete cycles with a fixed arena; peak usage stays
//             under a fixed cap.
//
// GREEN (contract): deterministic byte-exact stdout, exit code 0.

const std = @import("std");
const h2 = @import("std_http2.zig");
const http = @import("std_http.zig");

const PREFACE_BYTES = [_]u8{
    'P', 'R', 'I', ' ', '*', ' ', 'H', 'T', 'T', 'P', '/', '2', '.', '0',
    '\r', '\n', '\r', '\n', 'S', 'M', '\r', '\n', '\r', '\n',
};

const Script = struct {
    rbuf: [131072]u8,
    rlen: usize,
    rpos: usize,
    wbuf: [262144]u8,
    wlen: usize,
    chunk: usize,

    fw: h2.FrameWriter,
    stall_at: usize,
    stall_accepted: usize,
    stall_delivered: bool,
    close_called: bool,
    peer_eof: bool,
    block_writes: bool,
    close_pending_flag: bool,
    dynamic: bool,
    dyn_kind: u8,
    cycles_ready: usize,
    cycles_served: usize,

};

const Ctx = struct { used: u32, capacity: u32, oom: u8 };
const WaitArgs = struct { c: *h2.Http2Conn, id: u32, ok: *bool };
const WaitErrArgs = struct { c: *h2.Http2Conn, id: u32, err: u8, done: bool };

fn waitWorker(args: *WaitArgs) void {
    h2.http2Wait(args.c, args.id) catch {
        args.ok.* = false;
        return;
    };
    args.ok.* = true;
}

fn waitErrWorker(args: *WaitErrArgs) void {
    h2.http2Wait(args.c, args.id) catch |e| {
        if (e == error.Closed) {
            args.err = 1;
        } else if (e == error.Io) {
            args.err = 2;
        } else if (e == error.TooLarge) {
            args.err = 3;
        } else if (e == error.GoAway) {
            args.err = 4;
        } else if (e == error.StreamReset) {
            args.err = 5;
        } else {
            args.err = 9;
        }
        args.done = true;
        return;
    };
    args.err = 0;
    args.done = true;
}

var g_script: Script = undefined;
var g_headers: [1]http.Header = undefined;
var g_out_headers: [1]http.Header = undefined;
var g_out_body: [16000]u8 = undefined;
var g_out_body2: [16000]u8 = undefined;
var g_win_small: [16000]u8 = undefined;
var g_early_body: [100000]u8 = undefined;
var g_src1_body: [70000]u8 = undefined;
var g_src2_body: [20000]u8 = undefined;

fn scriptReset(s: *Script) void {
    s.rlen = 0;
    s.rpos = 0;
    s.wlen = 0;
    s.chunk = 7;

    s.stall_at = 0;
    s.stall_accepted = 0;
    s.stall_delivered = false;
    s.close_called = false;
    s.peer_eof = false;
    s.block_writes = false;
    s.close_pending_flag = false;
    s.dynamic = false;
    s.dyn_kind = 0;
    s.cycles_ready = 0;
    s.cycles_served = 0;

}

fn scriptBegin(s: *Script) void {
    h2.frameWriterInit(&s.fw, s.rbuf[0..], 16384);
}

fn scriptEmit(s: *Script, t: h2.FrameType, flags: u8, sid: u32, payload: []const u8) void {
    h2.frameAppend(&s.fw, t, flags, sid, payload) catch @panic("fixture: script frame overflow");
}

fn scriptEnd(s: *Script) void {
    s.rlen = s.fw.len;
    s.rpos = 0;
}

fn scriptRead(state: *void, dst: []u8) h2.TransportError!usize {
    const s: *Script = @ptrCast(*Script, state);
    if (s.rpos >= s.rlen) {
        if (s.dynamic and s.cycles_served < s.cycles_ready) {
            if (s.dyn_kind == 1) {
                buildEarlyStage(s, s.cycles_served);
            } else {
                buildCycle(s, s.cycles_served);
            }
            s.cycles_served += 1;
        } else if (s.peer_eof) {
            return 0;
        } else {
            return error.WouldBlock;
        }
    }
    var n: usize = s.rlen - s.rpos;
    if (s.chunk > 0 and n > s.chunk) n = s.chunk;
    if (n > dst.len) n = dst.len;
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = s.rbuf[s.rpos + i];
    s.rpos += n;
    return n;
}

fn scriptWrite(state: *void, data: []const u8) h2.TransportError!usize {
    const s: *Script = @ptrCast(*Script, state);
    if (s.block_writes) return error.WouldBlock;
    if (s.stall_at > 0 and !s.stall_delivered) {
        if (s.stall_accepted >= s.stall_at) {
            s.stall_delivered = true;
            return error.WouldBlock;
        }
        var allow: usize = s.stall_at - s.stall_accepted;
        var n: usize = data.len;
        if (n > allow) n = allow;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (s.wlen >= s.wbuf.len) @panic("fixture: write capture overflow");
            s.wbuf[s.wlen] = data[i];
            s.wlen += 1;
        }
        s.stall_accepted += n;
        return n;
    }
    var j: usize = 0;
    while (j < data.len) : (j += 1) {
        if (s.wlen >= s.wbuf.len) @panic("fixture: write capture overflow");
        s.wbuf[s.wlen] = data[j];
        s.wlen += 1;
    }
    return data.len;
}

fn scriptClose(state: *void) void {
    const s: *Script = @ptrCast(*Script, state);
    s.close_called = true;
}

fn scriptPending(state: *void) bool {
    const s: *Script = @ptrCast(*Script, state);
    return s.close_pending_flag;
}

fn makeTransport(s: *Script) h2.Transport {
    return h2.Transport{
        .state = @ptrCast(*void, s),
        .read_fn = scriptRead,
        .write_fn = scriptWrite,
        .pending_fn = scriptPending,
        .close_fn = scriptClose,
    };
}

fn emitSettingsEmpty(s: *Script) void {
    var empty = [_]u8{0};
    scriptEmit(s, h2.FrameType.settings, 0, 0, empty[0..0]);
}

fn emitSettingsWindow(s: *Script, value: u32) void {
    var p = [_]u8{ 0x00, 0x04, 0x00, 0x00, 0x00, 0x00 };
    p[2] = @intCast(u8, (value >> 24) & 0xFF);
    p[3] = @intCast(u8, (value >> 16) & 0xFF);
    p[4] = @intCast(u8, (value >> 8) & 0xFF);
    p[5] = @intCast(u8, value & 0xFF);
    scriptEmit(s, h2.FrameType.settings, 0, 0, p[0..6]);
}

fn emitStatus(s: *Script, sid: u32) void {
    var block = [_]u8{0x88}; // HPACK static index 8: ":status: 200"
    scriptEmit(s, h2.FrameType.headers, 0x4, sid, block[0..1]);
}

fn emitStatusSplit(s: *Script, sid: u32) void {
    // ":status: 200" plus a literal "x-test: v", split across HEADERS and
    // CONTINUATION so the joined scratch path decodes with one HPACK pass.
    var block = [_]u8{ 0x88, 0x00, 0x06, 'x', '-', 't', 'e', 's', 't', 0x01, 'v' };
    scriptEmit(s, h2.FrameType.headers, 0, sid, block[0..4]);
    scriptEmit(s, h2.FrameType.continuation, 0x4, sid, block[4..11]);
}

fn emitData(s: *Script, sid: u32, flags: u8, body: []const u8) void {
    scriptEmit(s, h2.FrameType.data, flags, sid, body);
}

fn emitGoaway(s: *Script, last_sid: u32) void {
    var p = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
    p[0] = @intCast(u8, (last_sid >> 24) & 0x7F);
    p[1] = @intCast(u8, (last_sid >> 16) & 0xFF);
    p[2] = @intCast(u8, (last_sid >> 8) & 0xFF);
    p[3] = @intCast(u8, last_sid & 0xFF);
    scriptEmit(s, h2.FrameType.goaway, 0, 0, p[0..8]);
}

fn emitRst(s: *Script, sid: u32) void {
    var p = [_]u8{ 0, 0, 0, 0x08 };
    scriptEmit(s, h2.FrameType.rst_stream, 0, sid, p[0..4]);
}

fn emitZeroWindow(s: *Script) void {
    var p = [_]u8{ 0, 0, 0, 0 };
    scriptEmit(s, h2.FrameType.window_update, 0, 0, p[0..4]);
}

fn emitPing(s: *Script) void {
    var p = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
    scriptEmit(s, h2.FrameType.ping, 0, 0, p[0..8]);
}

fn emitWindowUpdate(s: *Script, sid: u32, inc: u32) void {
    var p = [_]u8{ 0, 0, 0, 0 };
    p[0] = @intCast(u8, (inc >> 24) & 0xFF);
    p[1] = @intCast(u8, (inc >> 16) & 0xFF);
    p[2] = @intCast(u8, (inc >> 8) & 0xFF);
    p[3] = @intCast(u8, inc & 0xFF);
    scriptEmit(s, h2.FrameType.window_update, 0, sid, p[0..4]);
}

fn emptyResponse(out: *http.Response) void {
    out.status = 0;
    out.headers = g_out_headers[0..0];
    out.body = g_out_body[0..];
}

fn makeRequest(out: *http.Response) h2.Http2Request {
    emptyResponse(out);
    return h2.Http2Request{
        .method = "GET",
        .scheme = "https",
        .authority = "example.com",
        .path = "/",
        .headers = g_headers[0..0],
        .body = "",
        .body_len = 0,
        .body_source = null,
        .sink = null,
        .out = out,
        .stream_id = 0,
        .done = false,
        .failed = false,
    };
}

fn makePost(out: *http.Response) h2.Http2Request {
    emptyResponse(out);
    out.body = g_out_body2[0..];
    return h2.Http2Request{
        .method = "POST",
        .scheme = "https",
        .authority = "example.com",
        .path = "/p",
        .headers = g_headers[0..0],
        .body = "q",
        .body_len = 1,
        .body_source = null,
        .sink = null,
        .out = out,
        .stream_id = 0,
        .done = false,
        .failed = false,
    };
}

const SourceState = struct { body: []const u8, pos: usize, reads: usize };

fn sourceRead(state: *void, dst: []u8) http.HttpError!usize {
    const ss: *SourceState = @ptrCast(*SourceState, state);
    var n: usize = ss.body.len - ss.pos;
    if (n > dst.len) n = dst.len;
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = ss.body[ss.pos + i];
    ss.pos += n;
    ss.reads += 1;
    return n;
}

fn makeBodyRequest(out: *http.Response, body: []const u8) h2.Http2Request {
    emptyResponse(out);
    return h2.Http2Request{
        .method = "POST",
        .scheme = "https",
        .authority = "example.com",
        .path = "/b",
        .headers = g_headers[0..0],
        .body = body,
        .body_len = body.len,
        .body_source = null,
        .sink = null,
        .out = out,
        .stream_id = 0,
        .done = false,
        .failed = false,
    };
}

fn makeStreamRequest(out: *http.Response, src: *http.RequestSource, body_len: usize) h2.Http2Request {
    emptyResponse(out);
    return h2.Http2Request{
        .method = "POST",
        .scheme = "https",
        .authority = "example.com",
        .path = "/s",
        .headers = g_headers[0..0],
        .body = "",
        .body_len = body_len,
        .body_source = src,
        .sink = null,
        .out = out,
        .stream_id = 0,
        .done = false,
        .failed = false,
    };
}

fn fillPattern(buf: []u8, seed: u8) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = @intCast(u8, (@intCast(u32, seed) + @intCast(u32, i % 97)) & 0xFF);
    }
}

fn frameStreamId(bytes: []const u8, pos: usize) u32 {
    return (@intCast(u32, bytes[pos + 5] & 0x7F) << 24) |
        (@intCast(u32, bytes[pos + 6]) << 16) |
        (@intCast(u32, bytes[pos + 7]) << 8) |
        @intCast(u32, bytes[pos + 8]);
}

fn frameLength(bytes: []const u8, pos: usize) usize {
    return (@intCast(usize, bytes[pos]) << 16) |
        (@intCast(usize, bytes[pos + 1]) << 8) |
        @intCast(usize, bytes[pos + 2]);
}

fn windowIncrementSum(bytes: []const u8, start: usize, want_sid: u32) i64 {
    var pos: usize = start;
    var sum: i64 = 0;
    while (pos + 9 <= bytes.len) {
        const len = frameLength(bytes, pos);
        if (pos + 9 + len > bytes.len) break;
        const typ: u8 = bytes[pos + 3];
        if (typ == 8 and frameStreamId(bytes, pos) == want_sid and len == 4) {
            const inc: u32 = (@intCast(u32, bytes[pos + 9]) << 24) |
                (@intCast(u32, bytes[pos + 10]) << 16) |
                (@intCast(u32, bytes[pos + 11]) << 8) |
                @intCast(u32, bytes[pos + 12]);
            sum += @intCast(i64, inc & 0x7FFFFFFF);
        }
        pos += 9 + len;
    }
    return sum;
}

fn verifyDataBody(bytes: []const u8, start: usize, sid: u32, body: []const u8) bool {
    var pos: usize = start;
    var off: usize = 0;
    var ended: bool = false;
    while (pos + 9 <= bytes.len) {
        const len = frameLength(bytes, pos);
        if (pos + 9 + len > bytes.len) return false;
        const typ: u8 = bytes[pos + 3];
        const flags: u8 = bytes[pos + 4];
        if (typ == 0 and frameStreamId(bytes, pos) == sid) {
            if (off + len > body.len) return false;
            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (bytes[pos + 9 + i] != body[off + i]) return false;
            }
            off += len;
            if ((flags & 0x1) != 0) ended = true;
        }
        pos += 9 + len;
    }
    return off == body.len and ended;
}

fn defaultConfig() h2.Http2Config {
    return h2.Http2Config{
        .max_streams = 4,
        .max_header_list = 1024,
        .initial_window = 65535,
        .max_frame_size = 16384,
        .header_table_size = 4096,
    };
}

fn printCounter(label: []const u8, v: u32) void {
    std.io.write(label);
    std.io.printInt(@intCast(i32, v));
    std.io.writeByte('\n');
}

fn printFlag(label: []const u8, ok: bool) void {
    std.io.write(label);
    if (ok) {
        std.io.write("=1\n");
    } else {
        std.io.write("=0\n");
    }
}

fn printOk(label: []const u8, ok: bool) void {
    std.io.write(label);
    if (ok) {
        std.io.write("=ok\n");
    } else {
        std.io.write("=fail\n");
    }
}

fn scenarioBasic() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitPing(s);
    emitStatusSplit(s, 1);
    emitData(s, 1, 0x1, "a");
    emitStatus(s, 3);
    emitData(s, 3, 0x1, "b");
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("open-error\n");
        return;
    };

    var out1: http.Response = undefined;
    var out2: http.Response = undefined;
    var r1 = makeRequest(&out1);
    var r2 = makePost(&out2);
    const id1 = h2.http2Submit(c, &r1) catch {
        std.io.write("submit-error\n");
        return;
    };
    const id2 = h2.http2Submit(c, &r2) catch {
        std.io.write("submit-error\n");
        return;
    };

    var it: usize = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch {
            std.io.write("pump-error\n");
            return;
        };
        if (r1.done and r2.done) break;
    }

    // The send side must have emitted request DATA plus one stream
    // WINDOW_UPDATE at each close (both bodies are below the half threshold).
    if (countType(s.wbuf[0..s.wlen], 24, 8) < 2) @panic("fixture: missing stream WINDOW_UPDATE");
    if (countType(s.wbuf[0..s.wlen], 24, 0) < 1) @panic("fixture: missing request DATA");

    var count: i32 = 0;
    if (r1.done and id1 == 1) count += 1;
    if (r2.done and id2 == 3) count += 1;
    std.io.write("streams=");
    std.io.printInt(count);
    std.io.writeByte('\n');

    var status_ok: bool = false;
    if (r1.done and r2.done and out1.status == 200 and out2.status == 200) status_ok = true;
    if (status_ok) {
        std.io.write("status=200\n");
    } else {
        std.io.write("status=0\n");
    }

    std.io.write("body=");
    std.io.write(out1.body);
    std.io.writeByte('/');
    std.io.write(out2.body);
    std.io.writeByte('\n');

    h2.http2Release(c, id1) catch @panic("fixture: release id1");
    h2.http2Release(c, id2) catch @panic("fixture: release id2");

    printCounter("settings_ack=", c.settings_ack_count);
    printCounter("ping_ack=", c.ping_ack_count);

    h2.http2Close(c);
}

fn scenarioGoaway() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitGoaway(s, 0);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("goaway=0\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    const id = h2.http2Submit(c, &r) catch {
        std.io.write("goaway=0\n");
        return;
    };
    var it: usize = 0;
    while (it < 2000) : (it += 1) {
        _ = h2.http2Pump(c) catch break;
        if (r.failed) break;
    }
    h2.http2Release(c, id) catch @panic("fixture: release goaway");
    printFlag("goaway", r.failed and c.goaway_count == 1);
}

fn scenarioRst() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitRst(s, 1);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("rst=0\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    const id = h2.http2Submit(c, &r) catch {
        std.io.write("rst=0\n");
        return;
    };
    var it: usize = 0;
    while (it < 2000) : (it += 1) {
        _ = h2.http2Pump(c) catch break;
        if (r.failed) break;
    }
    h2.http2Release(c, id) catch @panic("fixture: release rst");
    printFlag("rst", r.failed and c.rst_count == 1);
}

fn countType(bytes: []const u8, start: usize, typ: u8) i32 {
    var pos: usize = start;
    var n: i32 = 0;
    while (pos + 9 <= bytes.len) {
        const len: usize = (@intCast(usize, bytes[pos]) << 16) |
            (@intCast(usize, bytes[pos + 1]) << 8) |
            @intCast(usize, bytes[pos + 2]);
        if (pos + 9 + len > bytes.len) break;
        if (bytes[pos + 3] == typ) n += 1;
        pos += 9 + len;
    }
    return n;
}

fn frameTypesWellFormed(bytes: []const u8, start: usize) bool {
    var pos: usize = start;
    var saw_headers: bool = false;
    while (pos < bytes.len) {
        if (bytes.len - pos < 9) return false;
        const len: usize = (@intCast(usize, bytes[pos]) << 16) |
            (@intCast(usize, bytes[pos + 1]) << 8) |
            @intCast(usize, bytes[pos + 2]);
        const typ: u8 = bytes[pos + 3];
        if (typ > 9) return false;
        if (len > bytes.len - pos - 9) return false;
        if (typ == 1) saw_headers = true;
        pos += 9 + len;
    }
    return pos == bytes.len and saw_headers;
}

fn scenarioWouldBlock() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    scriptEnd(s);
    // 24-byte preface + 5 bytes of the 45-byte client SETTINGS frame.
    s.stall_at = 29;

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("wb_resume=0\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    _ = h2.http2Submit(c, &r) catch {
        std.io.write("wb_resume=0\n");
        return;
    };

    var saw_wb: bool = false;
    var it: usize = 0;
    while (it < 2000) : (it += 1) {
        const st = h2.http2Pump(c) catch {
            std.io.write("wb_resume=0\n");
            return;
        };
        if (st == h2.PumpStatus.would_block) saw_wb = true;
        if (h2.http2PendingOutput(c) == 0 and c.preface_sent) break;
    }

    // Literal client wire vector: the client must emit the 24-byte PRI
    // preface exactly once, then literal SETTINGS/frames. PREFACE_BYTES is a
    // local literal here (not imported from the production code).
    var preface_ok: bool = s.wlen >= 24;
    var i: usize = 0;
    if (preface_ok) {
        while (i < 24) : (i += 1) {
            if (s.wbuf[i] != PREFACE_BYTES[i]) preface_ok = false;
        }
    }
    var preface_count: usize = 0;
    var p: usize = 0;
    while (p + 24 <= s.wlen) : (p += 1) {
        var match: bool = true;
        var k: usize = 0;
        while (k < 24) : (k += 1) {
            if (s.wbuf[p + k] != PREFACE_BYTES[k]) match = false;
        }
        if (match) preface_count += 1;
    }
    const frames_ok = frameTypesWellFormed(s.wbuf[0..s.wlen], 24);
    const ok = saw_wb and s.stall_delivered and preface_ok and preface_count == 1 and frames_ok and (h2.http2PendingOutput(c) == 0);

    printFlag("wb_resume", ok);
}

fn scenarioZeroWindow() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitZeroWindow(s);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("zero_wu=fail\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    _ = h2.http2Submit(c, &r) catch {
        std.io.write("zero_wu=fail\n");
        return;
    };
    var it: usize = 0;
    while (it < 2000) : (it += 1) {
        _ = h2.http2Pump(c) catch |e| {
            if (e == error.Protocol) {
                std.io.write("zero_wu=protocol\n");
                return;
            }
            std.io.write("zero_wu=fail\n");
            return;
        };
    }
    std.io.write("zero_wu=fail\n");
}

fn scenarioWindowDelta() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsWindow(s, 1000);
    emitSettingsWindow(s, 70000);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("win_delta=fail\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    var id: u32 = 0;
    id = h2.http2Submit(c, &r) catch {
        std.io.write("win_delta=fail\n");
        return;
    };
    var it: usize = 0;
    while (it < 1000) : (it += 1) {
        _ = h2.http2Pump(c) catch break;
    }
    const w = h2.http2StreamSendWindow(c, id) catch {
        std.io.write("win_delta=fail\n");
        return;
    };
    if (w == 70000) {
        std.io.write("win_delta=ok\n");
    } else {
        std.io.write("win_delta=fail\n");
    }
}

fn connWindowSmall() bool {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0x1, g_win_small[0..900]);
    emitStatus(s, 3);
    emitData(s, 3, 0x1, g_win_small[0..900]);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var cfg = defaultConfig();
    cfg.initial_window = 1000;
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch return false;
    var out1: http.Response = undefined;
    var out2: http.Response = undefined;
    var r1 = makeRequest(&out1);
    var r2 = makeRequest(&out2);
    const id1 = h2.http2Submit(c, &r1) catch return false;
    const id2 = h2.http2Submit(c, &r2) catch return false;
    var it: usize = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch return false;
        if (r1.done and r2.done) break;
    }
    const ok = r1.done and r2.done and out1.status == 200 and out2.status == 200 and
        windowIncrementSum(s.wbuf[0..s.wlen], 24, 0) == 0;
    h2.http2Release(c, id1) catch return false;
    h2.http2Release(c, id2) catch return false;
    h2.http2Close(c);
    return ok;
}

fn connWindowLarge() bool {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0x1, g_win_small[0..16000]);
    emitStatus(s, 3);
    emitData(s, 3, 0x1, g_win_small[0..16000]);
    emitStatus(s, 5);
    emitData(s, 5, 0x1, g_win_small[0..16000]);
    emitStatus(s, 7);
    emitData(s, 7, 0x1, g_win_small[0..16000]);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var cfg = defaultConfig();
    cfg.initial_window = 200000;
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch return false;

    var o1: http.Response = undefined;
    var o2: http.Response = undefined;
    var o3: http.Response = undefined;
    var o4: http.Response = undefined;
    var r1 = makeRequest(&o1);
    var r2 = makeRequest(&o2);
    var r3 = makeRequest(&o3);
    var r4 = makeRequest(&o4);
    const id1 = h2.http2Submit(c, &r1) catch return false;
    const id2 = h2.http2Submit(c, &r2) catch return false;
    const id3 = h2.http2Submit(c, &r3) catch return false;
    const id4 = h2.http2Submit(c, &r4) catch return false;

    var it: usize = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch return false;
        if (r1.done and r2.done and r3.done and r4.done) break;
    }
    const all_done = r1.done and r2.done and r3.done and r4.done;
    const ok = all_done and o1.status == 200 and o2.status == 200 and o3.status == 200 and
        o4.status == 200 and windowIncrementSum(s.wbuf[0..s.wlen], 24, 0) > 0;
    h2.http2Release(c, id1) catch return false;
    h2.http2Release(c, id2) catch return false;
    h2.http2Release(c, id3) catch return false;
    h2.http2Release(c, id4) catch return false;
    h2.http2Close(c);
    return ok;
}

fn scenarioConnWindow() void {
    printOk("conn_win", connWindowSmall() and connWindowLarge());
}

fn buildEarlyStage(s: *Script, stage: usize) void {
    scriptBegin(s);
    if (stage == 0) {
        emitSettingsEmpty(s);
        emitStatus(s, 1);
        emitData(s, 1, 0x1, "z");
    } else if (stage == 1) {
        emitWindowUpdate(s, 0, 65535);
        emitWindowUpdate(s, 1, 65535);
    }
    scriptEnd(s);
}

fn scenarioEarlyEnd() void {
    const s = &g_script;
    scriptReset(s);
    s.dynamic = true;
    s.dyn_kind = 1;

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("early_end=0\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeBodyRequest(&out, g_early_body[0..]);
    const id = h2.http2Submit(c, &r) catch {
        std.io.write("early_end=0\n");
        return;
    };

    s.cycles_ready = 1;
    _ = h2.http2Pump(c) catch {
        std.io.write("early_end=0\n");
        return;
    };
    var state_ok: bool = false;
    const st0 = h2.http2StreamState(c, id) catch h2.StreamState.closed;
    if (st0 == h2.StreamState.half_closed_remote) state_ok = true;
    const not_done = !r.done;

    s.cycles_ready = 2;
    var it: usize = 0;
    while (it < 8000) : (it += 1) {
        _ = h2.http2Pump(c) catch {
            std.io.write("early_end=0\n");
            return;
        };
        if (r.done) break;
    }
    const sent_ok = verifyDataBody(s.wbuf[0..s.wlen], 24, id, g_early_body[0..]);
    const resp_ok = out.status == 200 and out.body.len == 1 and out.body[0] == 'z';
    h2.http2Release(c, id) catch @panic("fixture: release early_end");
    printOk("early_end", state_ok and not_done and r.done and sent_ok and resp_ok);
    h2.http2Close(c);
}

fn scenarioStreamFull() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitWindowUpdate(s, 0, 200000);
    emitWindowUpdate(s, 1, 200000);
    emitWindowUpdate(s, 3, 200000);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("stream_full=0\n");
        return;
    };
    var ss1 = SourceState{ .body = g_src1_body[0..], .pos = 0, .reads = 0 };
    var ss2 = SourceState{ .body = g_src2_body[0..], .pos = 0, .reads = 0 };
    var src1 = http.RequestSource{ .state = @ptrCast(*void, &ss1), .read_fn = sourceRead };
    var src2 = http.RequestSource{ .state = @ptrCast(*void, &ss2), .read_fn = sourceRead };
    var o1: http.Response = undefined;
    var o2: http.Response = undefined;
    var r1 = makeStreamRequest(&o1, &src1, g_src1_body.len);
    var r2 = makeStreamRequest(&o2, &src2, g_src2_body.len);
    const id1 = h2.http2Submit(c, &r1) catch {
        std.io.write("stream_full=0\n");
        return;
    };
    const id2 = h2.http2Submit(c, &r2) catch {
        std.io.write("stream_full=0\n");
        return;
    };

    var it: usize = 0;
    while (it < 8) : (it += 1) {
        _ = h2.http2Pump(c) catch {
            std.io.write("stream_full=0\n");
            return;
        };
    }
    const consumed = ss1.pos == g_src1_body.len and ss2.pos == g_src2_body.len;
    const body_ok = verifyDataBody(s.wbuf[0..s.wlen], 24, id1, g_src1_body[0..]) and
        verifyDataBody(s.wbuf[0..s.wlen], 24, id2, g_src2_body[0..]);

    printOk("stream_full", consumed and body_ok and ss1.reads > 0 and ss2.reads > 0);
    h2.http2Close(c);
}

fn buildCycle(s: *Script, cycle: usize) void {
    scriptBegin(s);
    if (cycle == 0) emitSettingsEmpty(s);
    const base: u32 = @intCast(u32, cycle * 4 + 1);
    emitStatus(s, base);
    emitData(s, base, 0x1, "x");
    emitStatus(s, base + 2);
    emitData(s, base + 2, 0x1, "y");
    scriptEnd(s);
}

fn scenarioArena() void {
    const s = &g_script;
    scriptReset(s);
    s.dynamic = true;


    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var cfg = h2.Http2Config{
        .max_streams = 2,
        .max_header_list = 512,
        .initial_window = 65535,
        .max_frame_size = 16384,
        .header_table_size = 4096,
    };
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch {
        std.io.write("arena_ok=0\n");
        return;
    };

    var peak: usize = 0;
    var used_after_two: usize = 0;
    var cycle: usize = 0;
    while (cycle < 100) : (cycle += 1) {
        var out1: http.Response = undefined;
        var out2: http.Response = undefined;
        var r1 = makeRequest(&out1);
        var r2 = makeRequest(&out2);
        const id1 = h2.http2Submit(c, &r1) catch {
            std.io.write("arena_ok=0\n");
            return;
        };
        const id2 = h2.http2Submit(c, &r2) catch {
            std.io.write("arena_ok=0\n");
            return;
        };
        s.cycles_ready += 1;
        var it: usize = 0;
        while (it < 4000) : (it += 1) {
            _ = h2.http2Pump(c) catch {
                std.io.write("arena_ok=0\n");
                return;
            };
            if (r1.done and r2.done) break;
        }
        if (!r1.done or !r2.done) {
            std.io.write("arena_ok=0\n");
            return;
        }
        h2.http2Release(c, id1) catch {
            std.io.write("arena_ok=0\n");
            return;
        };
        h2.http2Release(c, id2) catch {
            std.io.write("arena_ok=0\n");
            return;
        };
        if (ar.used > peak) peak = ar.used;
        if (cycle == 1) used_after_two = ar.used;
    }
    const stable: bool = (used_after_two > 0 and ar.used == used_after_two);
    if (peak <= 200000 and stable) {
        std.io.write("arena_ok=1\n");
    } else {
        std.io.write("arena_ok=0\n");
    }
}

fn scenarioPeerEof() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    scriptEnd(s);
    s.peer_eof = true;

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("peer_eof=fail\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    const id = h2.http2Submit(c, &r) catch {
        std.io.write("peer_eof=fail\n");
        return;
    };

    var wa = WaitErrArgs{ .c = c, .id = id, .err = 0, .done = false };
    var cbuf: [1024]u8 = undefined;
    var fbuf: [512]u8 = undefined;
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 1024;
    var wap: *WaitErrArgs = &wa;
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var args: *const void = @ptrCast(*const void, &wap);
    var frame: *void = @asyncInit(ctxp, &fbuf, waitErrWorker, args);
    var more: ?*void = @asyncResume(frame, null);

    var saw_closed: bool = false;
    var it: usize = 0;
    while (more != null and it < 4000) : (it += 1) {
        const st = h2.http2Pump(c) catch {
            std.io.write("peer_eof=fail\n");
            return;
        };
        if (st == h2.PumpStatus.closed) saw_closed = true;
        more = @asyncResume(frame, null);
    }
    const ok = (more == null) and wa.done and wa.err == 1 and r.failed and saw_closed;
    if (ok) {
        std.io.write("peer_eof=ok\n");
    } else {
        std.io.write("peer_eof=fail\n");
    }
    h2.http2Release(c, id) catch {};
    h2.http2Close(c);
}

fn scenarioLateFrames() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0x1, "a");
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("late_frames=fail\n");
        return;
    };
    var out1: http.Response = undefined;
    var r1 = makeRequest(&out1);
    const id1 = h2.http2Submit(c, &r1) catch {
        std.io.write("late_frames=fail\n");
        return;
    };
    var it: usize = 0;
    while (it < 2000) : (it += 1) {
        _ = h2.http2Pump(c) catch {
            std.io.write("late_frames=fail\n");
            return;
        };
        if (r1.done) break;
    }
    if (!r1.done) {
        std.io.write("late_frames=fail\n");
        return;
    }
    h2.http2Release(c, id1) catch {
        std.io.write("late_frames=fail\n");
        return;
    };

    // A released id is stale: late DATA and a split HEADERS/CONTINUATION must
    // be ignored/accounted, not abort the connection for the next stream.
    scriptBegin(s);
    emitData(s, id1, 0, "late");
    emitStatusSplit(s, id1);
    emitStatus(s, 3);
    emitData(s, 3, 0x1, "b");
    scriptEnd(s);

    var body3: [16]u8 = undefined;
    var out3: http.Response = undefined;
    var r3 = makeRequest(&out3);
    out3.body = body3[0..];
    const id3 = h2.http2Submit(c, &r3) catch {
        std.io.write("late_frames=fail\n");
        return;
    };
    var pump_ok: bool = true;
    it = 0;
    while (it < 2000) : (it += 1) {
        _ = h2.http2Pump(c) catch {
            pump_ok = false;
            break;
        };
        if (r3.done) break;
    }
    const ok = pump_ok and r3.done and out3.status == 200 and out3.body.len == 1 and out3.body[0] == 'b';
    if (ok) {
        std.io.write("late_frames=ok\n");
    } else {
        std.io.write("late_frames=fail\n");
    }
    h2.http2Release(c, id3) catch {};
    h2.http2Close(c);
}

fn headerRejected(block: []const u8) bool {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    scriptEmit(s, h2.FrameType.headers, 0x4, 1, block);
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch return false;
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    _ = h2.http2Submit(c, &r) catch {
        h2.http2Close(c);
        return false;
    };
    var it: usize = 0;
    while (it < 400) : (it += 1) {
        _ = h2.http2Pump(c) catch |e| {
            h2.http2Close(c);
            return e == error.Protocol or e == error.Corrupt;
        };
        if (r.failed) break;
    }
    h2.http2Close(c);
    return false;
}

fn scenarioHeaderValidation() void {
    // Indexed :status 200 + literal x-test with a Huffman-free CRLF value.
    var crlf = [_]u8{ 0x88, 0x00, 0x06, 'x', '-', 't', 'e', 's', 't', 0x04, 'a', '\r', '\n', 'b' };
    // Uppercase response field name.
    var upper = [_]u8{ 0x88, 0x00, 0x06, 'X', '-', 'T', 'e', 's', 't', 0x01, 'v' };
    // No :status at all.
    var nostatus = [_]u8{ 0x00, 0x06, 'x', '-', 't', 'e', 's', 't', 0x01, 'v' };
    // :status after a regular field (also a duplicate pseudo-header).
    var pseudo = [_]u8{ 0x88, 0x00, 0x06, 'x', '-', 't', 'e', 's', 't', 0x01, 'v', 0x88 };
    printFlag("hdr_crlf", headerRejected(crlf[0..]));
    printFlag("hdr_upper", headerRejected(upper[0..]));
    printFlag("hdr_nostatus", headerRejected(nostatus[0..]));
    printFlag("hdr_pseudo", headerRejected(pseudo[0..]));
}

fn configRejected(cfg: h2.Http2Config) bool {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    scriptEnd(s);
    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    _ = h2.http2OpenTransport(&ar, &t, cfg) catch |e| {
        return e == error.BadConfig;
    };
    return false;
}

fn configAccepted(cfg: h2.Http2Config) bool {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    scriptEnd(s);
    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch return false;
    h2.http2Close(c);
    return true;
}

fn scenarioConfig() void {
    var a_cfg = defaultConfig();
    a_cfg.max_frame_size = @intCast(u32, h2.READ_BUF_LEN - h2.FRAME_HEADER_LEN) + 1;
    const a = configRejected(a_cfg);

    var b_cfg = defaultConfig();
    b_cfg.max_frame_size = h2.MAX_MAX_FRAME_SIZE;
    const b = configRejected(b_cfg);

    var c_cfg = defaultConfig();
    c_cfg.initial_window = 0;
    const c = configRejected(c_cfg);

    var d_cfg = defaultConfig();
    d_cfg.max_frame_size = @intCast(u32, h2.READ_BUF_LEN - h2.FRAME_HEADER_LEN);
    const d = configAccepted(d_cfg);

    printFlag("config", a and b and c and d);
}

fn scenarioClose() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    scriptEnd(s);
    s.block_writes = true;

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch {
        std.io.write("close_pending=fail\n");
        return;
    };
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    _ = h2.http2Submit(c, &r) catch {
        std.io.write("close_pending=fail\n");
        return;
    };

    // HTTP output (preface/SETTINGS/HEADERS) is pending: the close must not
    // finalize or call the transport close.
    h2.http2Close(c);
    const first_pending = h2.http2ClosePending(c) and !s.close_called and !c.close_called;

    // Output can now flush, but the transport reports its own pending close
    // bytes (the TLS close_pending case): still not finalized.
    s.block_writes = false;
    s.close_pending_flag = true;
    h2.http2Close(c);
    const second_pending = h2.http2ClosePending(c) and !s.close_called;

    // Transport pending clears; the retry completes the close exactly once.
    s.close_pending_flag = false;
    h2.http2Close(c);
    const done = s.close_called and !h2.http2ClosePending(c) and c.close_called;
    printFlag("close_pending", first_pending and second_pending and done);
}

fn scenarioWait() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0x1, "w");
    scriptEnd(s);

    var backing: [262144]u8 = undefined;
    var ar = std.arena.init(backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch return;
    var out: http.Response = undefined;
    var r = makeRequest(&out);
    const id = h2.http2Submit(c, &r) catch return;

    var ok: bool = false;
    var wa = WaitArgs{ .c = c, .id = id, .ok = &ok };
    var cbuf: [1024]u8 = undefined;
    var ctxv: *Ctx = @ptrCast(*Ctx, &cbuf);
    ctxv.capacity = 1024;
    var fbuf: [512]u8 = undefined;
    var wap: *WaitArgs = &wa;
    var ctxp: *void = @ptrCast(*void, &cbuf);
    var args: *const void = @ptrCast(*const void, &wap);
    var frame: *void = @asyncInit(ctxp, &fbuf, waitWorker, args);
    var more: ?*void = @asyncResume(frame, null);

    var it: usize = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch break;
        if (r.done) break;
    }
    while (more != null) {
        more = @asyncResume(frame, null);
    }
    if (!ok or !r.done) @panic("fixture: http2Wait did not complete");
    h2.http2Release(c, id) catch @panic("fixture: release wait");
    h2.http2Close(c);
}

pub fn main() void {
    fillPattern(g_win_small[0..], 11);
    fillPattern(g_early_body[0..], 21);
    fillPattern(g_src1_body[0..], 31);
    fillPattern(g_src2_body[0..], 71);
    scenarioBasic();
    scenarioGoaway();
    scenarioRst();
    scenarioWouldBlock();
    scenarioZeroWindow();
    scenarioWindowDelta();
    scenarioConnWindow();
    scenarioEarlyEnd();
    scenarioStreamFull();
    scenarioPeerEof();
    scenarioLateFrames();
    scenarioHeaderValidation();
    scenarioConfig();
    scenarioClose();
    scenarioWait();
    scenarioArena();
}
