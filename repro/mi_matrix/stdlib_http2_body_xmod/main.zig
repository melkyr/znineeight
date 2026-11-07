// stdlib_http2_body_xmod — HTTP/2 body API and streaming (Phase 3.3 Task 7).
//
// Drives `std_http2` through `http2OpenTransport` with a scripted,
// non-suspending `Transport`. The script supplies the server preface/SETTINGS,
// HEADERS/DATA responses, and gated WINDOW_UPDATE stages.
//
// Scenarios:
//   body     http2Get + http2Post: pseudo-headers from the URL, lowercased
//            request header names, status/body mapping. Prints body=<g>/<p>.
//   sink     http2GetStream: response DATA flows to a ResponseSink; custom
//            header name is lowercased; a Connection header is rejected.
//            Prints sink=<n>.
//   source   http2PostStream: a RequestSource body larger than the initial
//            send window stops at the window, then finishes after server
//            WINDOW_UPDATE. Prints source=<n>.
//   large    buffered response over 1 MiB is rejected with TooLarge.
//            Prints large=too_large.
//   error    one stream's sink error fails only that stream; the other stream
//            completes normally.
//   slow     a streaming sink on stream 1 queues WINDOW_UPDATE while the
//            transport write side is blocked; stream 3 still completes, and
//            the deferred update is emitted once writes resume. Prints
//            slow_ok=1.
//
// Argless and deterministic. GREEN: exact stdout, exit 0.

const std = @import("std");
const h2 = @import("std_http2.zig");
const http = @import("std_http.zig");

const PREFACE_BYTES = [_]u8{
    'P', 'R', 'I', ' ', '*', ' ', 'H', 'T', 'T', 'P', '/', '2', '.', '0',
    '\r', '\n', '\r', '\n', 'S', 'M', '\r', '\n', '\r', '\n',
};

const SLOW_BODY_LEN: usize = 40000;
const SOURCE_BODY_LEN: usize = 70000;
const LARGE_CHUNK: usize = 16384;
const LARGE_CHUNKS: usize = 65;
const TOO_CHUNK_LEN: usize = 16384;
const NORMAL_BODY_LEN: usize = 33000;

const Script = struct {
    rbuf: [1200000]u8,
    rlen: usize,
    rpos: usize,
    wbuf: [262144]u8,
    wlen: usize,
    chunk: usize,
    base: usize,
    fw: h2.FrameWriter,
    block_writes: bool,
    close_called: bool,
    dynamic: bool,
    dyn_kind: u8,
    cycles_ready: usize,
    cycles_served: usize,
    emit_preface: bool,
};

const Ctx = struct { used: u32, capacity: u32, oom: u8 };

var g_script: Script = undefined;
var g_out_headers: [1]http.Header = undefined;
var g_empty_body: [1]u8 = undefined;
var g_arena_backing: [4200000]u8 = undefined;

var g_slow_body: [SLOW_BODY_LEN]u8 = undefined;
var g_source_body: [SOURCE_BODY_LEN]u8 = undefined;
var g_large_body: [LARGE_CHUNK]u8 = undefined;

var g_sink_buf: [64]u8 = undefined;
var g_slow_sink_buf: [SLOW_BODY_LEN]u8 = undefined;
var g_cycle_out: http.Response = undefined;
var g_body_get: [16]u8 = undefined;
var g_body_post: [16]u8 = undefined;
var g_body_again: [16]u8 = undefined;
var g_cycle_body: [16]u8 = undefined;
var g_good_out_buf: [16]u8 = undefined;
var g_slow_out_buf: [16]u8 = undefined;
var g_small_out_buf: [4]u8 = undefined;
var g_large_out_buf: [1048576 + 16384]u8 = undefined;
var g_fail_body: [16]u8 = undefined;
var g_fail_reuse: [16]u8 = undefined;
var g_too_chunk: [TOO_CHUNK_LEN]u8 = undefined;
var g_normal_body: [NORMAL_BODY_LEN]u8 = undefined;
var g_rej_out_buf: [100]u8 = undefined;
var g_normal_out_buf: [40000]u8 = undefined;
var g_stream_body: [3]u8 = undefined;

const SinkState = struct {
    buf: []u8,
    len: usize,
    fail: bool,
};

fn sinkWrite(state: *void, data: []const u8) http.HttpError!void {
    const ss: *SinkState = @ptrCast(*SinkState, state);
    if (ss.fail) return error.BadResponse;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        if (ss.len + i < ss.buf.len) ss.buf[ss.len + i] = data[i];
    }
    ss.len += data.len;
}

const SourceState = struct {
    body: []const u8,
    pos: usize,
    reads: usize,
};

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

fn scriptReset(s: *Script) void {
    s.rlen = 0;
    s.rpos = 0;
    s.wlen = 0;
    s.chunk = 13;
    s.base = 0;
    s.block_writes = false;
    s.close_called = false;
    s.dynamic = false;
    s.dyn_kind = 0;
    s.cycles_ready = 0;
    s.cycles_served = 0;
    s.emit_preface = true;
}

fn scriptBegin(s: *Script) void {
    var base: usize = 0;
    if (s.emit_preface) {
        var i: usize = 0;
        while (i < 24) : (i += 1) s.rbuf[i] = PREFACE_BYTES[i];
        s.emit_preface = false;
        base = 24;
    }
    s.base = base;
    h2.frameWriterInit(&s.fw, s.rbuf[base..], 16384);
}

fn scriptEmit(s: *Script, t: h2.FrameType, flags: u8, sid: u32, payload: []const u8) void {
    h2.frameAppend(&s.fw, t, flags, sid, payload) catch @panic("fixture: script frame overflow");
}

fn scriptEnd(s: *Script) void {
    s.rlen = s.base + s.fw.len;
    s.rpos = 0;
}

fn buildStage(s: *Script, stage: usize) void {
    scriptBegin(s);
    if (s.dyn_kind == 1) {
        if (stage == 0) {
            var empty = [_]u8{0};
            scriptEmit(s, h2.FrameType.settings, 0, 0, empty[0..0]);
        } else if (stage == 1) {
            emitStatus(s, 1);
            emitBodyChunks(s, 1, g_slow_body[0..]);
        } else if (stage == 2) {
            emitStatus(s, 3);
            emitData(s, 3, 0x1, "ok");
        }
    } else if (s.dyn_kind == 2) {
        if (stage == 0) {
            var empty = [_]u8{0};
            scriptEmit(s, h2.FrameType.settings, 0, 0, empty[0..0]);
            emitStatus(s, 1);
            emitData(s, 1, 0x1, "ok");
        } else if (stage == 1) {
            emitWindowUpdate(s, 0, 200000);
            emitWindowUpdate(s, 1, 200000);
        }
    } else if (s.dyn_kind == 3) {
        if (stage == 0) {
            var empty = [_]u8{0};
            scriptEmit(s, h2.FrameType.settings, 0, 0, empty[0..0]);
        }
        const id: u32 = @intCast(u32, stage * 2 + 1);
        emitStatus(s, id);
        emitData(s, id, 0x1, "z");
    } else if (s.dyn_kind == 4) {
        if (stage == 0) {
            var empty = [_]u8{0};
            scriptEmit(s, h2.FrameType.settings, 0, 0, empty[0..0]);
            emitStatus(s, 1);
            emitData(s, 1, 0, g_too_chunk[0..]);
        } else if (stage == 1) {
            emitStatus(s, 3);
            emitData(s, 3, 0, g_too_chunk[0..]);
        } else if (stage == 2) {
            emitStatus(s, 5);
            emitData(s, 5, 0, g_normal_body[0..16384]);
            emitData(s, 5, 0, g_normal_body[16384..32768]);
            emitData(s, 5, 0x1, g_normal_body[32768..NORMAL_BODY_LEN]);
        }
    }
    scriptEnd(s);
}

fn scriptRead(state: *void, dst: []u8) h2.TransportError!usize {
    const s: *Script = @ptrCast(*Script, state);
    if (s.rpos >= s.rlen) {
        if (s.dynamic and s.cycles_served < s.cycles_ready) {
            buildStage(s, s.cycles_served);
            s.cycles_served += 1;
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

fn makeTransport(s: *Script) h2.Transport {
    return h2.Transport{
        .state = @ptrCast(*void, s),
        .read_fn = scriptRead,
        .write_fn = scriptWrite,
        .close_fn = scriptClose,
    };
}

fn emitSettingsEmpty(s: *Script) void {
    var empty = [_]u8{0};
    scriptEmit(s, h2.FrameType.settings, 0, 0, empty[0..0]);
}

fn emitStatus(s: *Script, sid: u32) void {
    var block = [_]u8{0x88};
    scriptEmit(s, h2.FrameType.headers, 0x4, sid, block[0..1]);
}

fn emitData(s: *Script, sid: u32, flags: u8, body: []const u8) void {
    scriptEmit(s, h2.FrameType.data, flags, sid, body);
}

fn emitBodyChunks(s: *Script, sid: u32, body: []const u8) void {
    var off: usize = 0;
    while (off < body.len) {
        var n: usize = body.len - off;
        if (n > 16000) n = 16000;
        emitData(s, sid, 0, body[off .. off + n]);
        off += n;
    }
}

fn emitWindowUpdate(s: *Script, sid: u32, inc: u32) void {
    var p = [_]u8{ 0, 0, 0, 0 };
    p[0] = @intCast(u8, (inc >> 24) & 0xFF);
    p[1] = @intCast(u8, (inc >> 16) & 0xFF);
    p[2] = @intCast(u8, (inc >> 8) & 0xFF);
    p[3] = @intCast(u8, inc & 0xFF);
    scriptEmit(s, h2.FrameType.window_update, 0, sid, p[0..4]);
}

fn emitRst(s: *Script, sid: u32) void {
    var p = [_]u8{ 0, 0, 0, 0x08 };
    scriptEmit(s, h2.FrameType.rst_stream, 0, sid, p[0..4]);
}

fn emptyResponse(out: *http.Response) void {
    out.status = 0;
    out.headers = g_out_headers[0..0];
    out.body = g_empty_body[0..0];
}

fn makeGet(out: *http.Response) h2.Http2Request {
    emptyResponse(out);
    return h2.Http2Request{
        .method = "GET",
        .scheme = "https",
        .authority = "example.com",
        .path = "/x",
        .headers = g_out_headers[0..0],
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

fn makeGetSink(out: *http.Response, sink: *http.ResponseSink) h2.Http2Request {
    var r = makeGet(out);
    r.sink = sink;
    return r;
}

fn defaultConfig() h2.Http2Config {
    return h2.Http2Config{
        .max_streams = 4,
        .max_header_list = 4096,
        .initial_window = 65535,
        .max_frame_size = 16384,
        .header_table_size = 4096,
    };
}

fn fillPattern(buf: []u8, seed: u8) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = @intCast(u8, (@intCast(u32, seed) + @intCast(u32, i % 89)) & 0xFF);
    }
}

fn containsBytes(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (hay[i + j] != needle[j]) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

fn frameLength(bytes: []const u8, pos: usize) usize {
    return (@intCast(usize, bytes[pos]) << 16) |
        (@intCast(usize, bytes[pos + 1]) << 8) |
        @intCast(usize, bytes[pos + 2]);
}

fn frameStreamId(bytes: []const u8, pos: usize) u32 {
    return (@intCast(u32, bytes[pos + 5] & 0x7F) << 24) |
        (@intCast(u32, bytes[pos + 6]) << 16) |
        (@intCast(u32, bytes[pos + 7]) << 8) |
        @intCast(u32, bytes[pos + 8]);
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

fn dataBytesAndEnd(bytes: []const u8, start: usize, want_sid: u32, sum_out: *usize, end_out: *bool) void {
    var pos: usize = start;
    sum_out.* = 0;
    end_out.* = false;
    while (pos + 9 <= bytes.len) {
        const len = frameLength(bytes, pos);
        if (pos + 9 + len > bytes.len) break;
        const typ: u8 = bytes[pos + 3];
        const flags: u8 = bytes[pos + 4];
        if (typ == 0 and frameStreamId(bytes, pos) == want_sid) {
            sum_out.* += len;
            if ((flags & 0x1) != 0) end_out.* = true;
        }
        pos += 9 + len;
    }
}

const ApiArgs = struct {
    c: *h2.Http2Conn,
    out: *http.Response,
    body: []const u8,
    ct: []const u8,
    accept: []const u8,
    kind: u8,
    ok: u8,
    id: u32,
};

fn apiWorker(args: *ApiArgs) void {
    if (args.kind == 0) {
        h2.http2Get(args.c, "https://example.com/get", args.out, &args.id) catch {
            args.ok = 0;
            return;
        };
    } else {
        h2.http2Post(args.c, "https://example.com/post?x=1", args.body, args.ct, args.accept, args.out, &args.id) catch {
            args.ok = 0;
            return;
        };
    }
    args.ok = 1;
}

const StreamArgs = struct {
    c: *h2.Http2Conn,
    url: []const u8,
    headers: []const http.Header,
    sink: *http.ResponseSink,
    out: *http.Response,
    ok: u8,
    id: u32,
};

fn getStreamWorker(args: *StreamArgs) void {
    h2.http2GetStream(args.c, args.url, args.headers, args.sink, args.out, &args.id) catch {
        args.ok = 0;
        return;
    };
    args.ok = 1;
}

const RejectArgs = struct {
    c: *h2.Http2Conn,
    url: []const u8,
    headers: []const http.Header,
    sink: *http.ResponseSink,
    out: *http.Response,
    ok: u8,
};

fn rejectWorker(args: *RejectArgs) void {
    var id: u32 = 0;
    h2.http2GetStream(args.c, args.url, args.headers, args.sink, args.out, &id) catch |e| {
        if (e == error.Protocol) args.ok = 1;
        return;
    };
    h2.http2Release(args.c, id) catch {};
    args.ok = 0;
}

const PostStreamArgs = struct {
    c: *h2.Http2Conn,
    url: []const u8,
    body_len: usize,
    ct: []const u8,
    accept: []const u8,
    src: *http.RequestSource,
    sink: *http.ResponseSink,
    out: *http.Response,
    ok: u8,
    id: u32,
};

fn postStreamWorker(args: *PostStreamArgs) void {
    h2.http2PostStream(args.c, args.url, args.body_len, args.ct, args.accept, args.src, args.sink, args.out, &args.id) catch {
        args.ok = 0;
        return;
    };
    args.ok = 1;
}

const FailArgs = struct {
    c: *h2.Http2Conn,
    out: *http.Response,
    id: u32,
    got_error: u8,
};

fn failWorker(args: *FailArgs) void {
    h2.http2Get(args.c, "https://example.com/f", args.out, &args.id) catch |e| {
        if (e == error.StreamReset) args.got_error = 1;
        return;
    };
    args.got_error = 0;
}

fn initContext(buf: []u8) *void {
    const cv: *Ctx = @ptrCast(*Ctx, buf.ptr);
    cv.used = 0;
    cv.capacity = @intCast(u32, buf.len);
    cv.oom = 0;
    return @ptrCast(*void, buf.ptr);
}

fn scenarioBody() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0x1, "hello");
    emitStatus(s, 3);
    emitData(s, 3, 0x1, "world");
    scriptEnd(s);

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var cfg = defaultConfig();
    cfg.max_streams = 2;
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch @panic("body: open");

    var out1: http.Response = undefined;
    var out2: http.Response = undefined;
    out1.body = g_body_get[0..];
    out2.body = g_body_post[0..];
    var a1 = ApiArgs{ .c = c, .out = &out1, .body = "", .ct = "", .accept = "", .kind = 0, .ok = 0, .id = 0 };
    var a2 = ApiArgs{ .c = c, .out = &out2, .body = "payload", .ct = "text/plain", .accept = "*/*", .kind = 1, .ok = 0, .id = 0 };

    var c1buf: [32768]u8 = undefined;
    var c2buf: [32768]u8 = undefined;
    var f1buf: [8192]u8 = undefined;
    var f2buf: [8192]u8 = undefined;
    var ctx1 = initContext(c1buf[0..]);
    var ctx2 = initContext(c2buf[0..]);
    var a1p: *ApiArgs = &a1;
    var a2p: *ApiArgs = &a2;
    var args1: *const void = @ptrCast(*const void, &a1p);
    var args2: *const void = @ptrCast(*const void, &a2p);
    var f1: *void = @asyncInit(ctx1, &f1buf, apiWorker, args1);
    var f2: *void = @asyncInit(ctx2, &f2buf, apiWorker, args2);

    var m1: ?*void = @asyncResume(f1, null);
    var m2: ?*void = @asyncResume(f2, null);
    var it: usize = 0;
    while ((m1 != null or m2 != null) and it < 8000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("body: pump");
        if (m1 != null) m1 = @asyncResume(f1, null);
        if (m2 != null) m2 = @asyncResume(f2, null);
    }
    if (m1 != null or m2 != null) @panic("body: worker stuck");
    if (a1.ok != 1 or a2.ok != 1) @panic("body: api failed");
    if (out1.status != 200 or out2.status != 200) @panic("body: status");
    if (!containsBytes(out1.body, "hello")) @panic("body: get body");
    if (!containsBytes(out2.body, "world")) @panic("body: post body");
    if (out1.body.len != 5 or out2.body.len != 5) @panic("body: convenience did not wait");

    const wire = s.wbuf[0..s.wlen];
    if (!containsBytes(wire, "example.com")) @panic("body: authority");
    if (!containsBytes(wire, "/get")) @panic("body: get path");
    if (!containsBytes(wire, "/post?x=1")) @panic("body: post path");
    if (!containsBytes(wire, "payload")) @panic("body: post data");
    if (!containsBytes(wire, "text/plain")) @panic("body: content-type");
    if (!containsBytes(wire, "*/*")) @panic("body: accept");

    std.io.write("body=");
    std.io.write(out1.body);
    std.io.writeByte('/');
    std.io.write(out2.body);
    std.io.writeByte('\n');

    h2.http2Release(c, a1.id) catch @panic("body: release get");
    h2.http2Release(c, a2.id) catch @panic("body: release post");
    var gone1: bool = false;
    var gone2: bool = false;
    _ = h2.http2StreamState(c, a1.id) catch |e| {
        gone1 = (e == error.NoStream);
    };
    _ = h2.http2StreamState(c, a2.id) catch |e| {
        gone2 = (e == error.NoStream);
    };
    var again: bool = false;
    h2.http2Release(c, a1.id) catch |e| {
        again = (e == error.NoStream);
    };
    if (!gone1 or !gone2 or !again) @panic("body: released id not NoStream");

    var out3: http.Response = undefined;
    var r3 = makeGet(&out3);
    out3.body = g_body_again[0..];
    const id5 = h2.http2Submit(c, &r3) catch @panic("body: slot not reusable");
    if (id5 != 5) @panic("body: reuse id");
    std.io.write("release=1\n");
    h2.http2Close(c);
}

fn scenarioSink() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0, "abc");
    emitData(s, 1, 0x1, "def");
    scriptEnd(s);

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch @panic("sink: open");

    var ss = SinkState{ .buf = g_sink_buf[0..], .len = 0, .fail = false };
    var sink = http.ResponseSink{ .state = @ptrCast(*void, &ss), .write_fn = sinkWrite };
    // Streaming mode must not read or write out.body; use a sentinel slice.
    g_stream_body[0] = 's';
    g_stream_body[1] = 'b';
    g_stream_body[2] = 'k';
    var out: http.Response = undefined;
    out.body = g_stream_body[0..];
    var hs = [1]http.Header{http.Header{ .name = "X-Custom", .value = "Value" }};
    var args = StreamArgs{ .c = c, .url = "https://example.com/s", .headers = hs[0..], .sink = &sink, .out = &out, .ok = 0, .id = 0 };

    var cbuf: [32768]u8 = undefined;
    var fbuf: [8192]u8 = undefined;
    var ctx = initContext(cbuf[0..]);
    var argsp: *StreamArgs = &args;
    var args_ptr: *const void = @ptrCast(*const void, &argsp);
    var f: *void = @asyncInit(ctx, &fbuf, getStreamWorker, args_ptr);

    var more: ?*void = @asyncResume(f, null);
    var it: usize = 0;
    while (more != null and it < 8000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("sink: pump");
        more = @asyncResume(f, null);
    }
    if (more != null or args.ok != 1) @panic("sink: api failed");
    if (out.status != 200) @panic("sink: status");
    if (ss.len != 6) @panic("sink: length");
    const stream_body_kept: bool = (out.body.len == 3 and out.body[0] == 's' and out.body[1] == 'b' and out.body[2] == 'k');
    if (!containsBytes(ss.buf[0..6], "abcdef")) @panic("sink: bytes");

    const wire = s.wbuf[0..s.wlen];
    if (!containsBytes(wire, "x-custom")) @panic("sink: header not lowercased");
    if (containsBytes(wire, "X-Custom")) @panic("sink: uppercase header leaked");
    if (!containsBytes(wire, "Value")) @panic("sink: header value");

    var bad = [1]http.Header{http.Header{ .name = "Connection", .value = "close" }};
    var out2: http.Response = undefined;
    out2.body = g_empty_body[0..0];
    var ra = RejectArgs{ .c = c, .url = "https://example.com/r", .headers = bad[0..], .sink = &sink, .out = &out2, .ok = 0 };

    var rcbuf: [32768]u8 = undefined;
    var rfbuf: [8192]u8 = undefined;
    var rctx = initContext(rcbuf[0..]);
    var rap: *RejectArgs = &ra;
    var rargs: *const void = @ptrCast(*const void, &rap);
    var rf: *void = @asyncInit(rctx, &rfbuf, rejectWorker, rargs);
    var rmore: ?*void = @asyncResume(rf, null);
    var rit: usize = 0;
    while (rmore != null and rit < 64) : (rit += 1) {
        _ = h2.http2Pump(c) catch @panic("sink: reject pump");
        rmore = @asyncResume(rf, null);
    }
    if (rmore != null or ra.ok != 1) @panic("sink: connection header not rejected");

    h2.http2Release(c, args.id) catch @panic("sink: release");
    std.io.write("sink=");
    std.io.printInt(@intCast(i32, ss.len));
    std.io.writeByte('\n');
    printFlag("stream_body_kept", stream_body_kept);
    h2.http2Close(c);
}

fn scenarioSource() void {
    const s = &g_script;
    scriptReset(s);
    s.dynamic = true;
    s.dyn_kind = 2;
    s.cycles_ready = 1;

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch @panic("source: open");

    var ss = SinkState{ .buf = g_sink_buf[0..], .len = 0, .fail = false };
    var sink = http.ResponseSink{ .state = @ptrCast(*void, &ss), .write_fn = sinkWrite };
    var src_state = SourceState{ .body = g_source_body[0..], .pos = 0, .reads = 0 };
    var src = http.RequestSource{ .state = @ptrCast(*void, &src_state), .read_fn = sourceRead };
    // Streaming mode must not read out.body; leave it undefined on purpose.
    var out: http.Response = undefined;
    var args = PostStreamArgs{
        .c = c,
        .url = "https://example.com/post",
        .body_len = SOURCE_BODY_LEN,
        .ct = "application/octet-stream",
        .accept = "*/*",
        .src = &src,
        .sink = &sink,
        .out = &out,
        .ok = 0,
        .id = 0,
    };

    var cbuf: [32768]u8 = undefined;
    var fbuf: [8192]u8 = undefined;
    var ctx = initContext(cbuf[0..]);
    var argsp: *PostStreamArgs = &args;
    var args_ptr: *const void = @ptrCast(*const void, &argsp);
    var f: *void = @asyncInit(ctx, &fbuf, postStreamWorker, args_ptr);

    var more: ?*void = @asyncResume(f, null);
    var it: usize = 0;
    while (more != null and it < 400) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("source: pump stage0");
        more = @asyncResume(f, null);
    }
    if (src_state.pos != 65535) @panic("source: did not stop at send window");
    if (more == null) @panic("source: finished before window update");

    s.cycles_ready = 2;
    it = 0;
    while (more != null and it < 8000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("source: pump stage1");
        more = @asyncResume(f, null);
    }
    if (more != null or args.ok != 1) @panic("source: api failed");
    if (src_state.pos != SOURCE_BODY_LEN) @panic("source: short read");

    var sent: usize = 0;
    var ended: bool = false;
    dataBytesAndEnd(s.wbuf[0..s.wlen], 24, 1, &sent, &ended);
    if (sent != SOURCE_BODY_LEN) @panic("source: DATA length");
    if (!ended) @panic("source: missing END_STREAM");

    h2.http2Release(c, args.id) catch @panic("source: release");
    std.io.write("source=");
    std.io.printInt(@intCast(i32, src_state.pos));
    std.io.writeByte('\n');
    h2.http2Close(c);
}

fn scenarioLarge() void {
    const s = &g_script;
    scriptReset(s);
    s.chunk = 0;
    scriptBegin(s);
    emitSettingsEmpty(s);
    var i: usize = 0;
    while (i < LARGE_CHUNKS) : (i += 1) {
        emitData(s, 1, 0, g_large_body[0..]);
    }
    scriptEnd(s);

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var cfg = defaultConfig();
    cfg.initial_window = 1200000;
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch @panic("large: open");

    var out: http.Response = undefined;
    var r = makeGet(&out);
    out.body = g_large_out_buf[0..];
    _ = h2.http2Submit(c, &r) catch @panic("large: submit");

    var too_large: bool = false;
    var it: usize = 0;
    while (it < 200000) : (it += 1) {
        _ = h2.http2Pump(c) catch |e| {
            if (e == error.TooLarge) too_large = true;
            break;
        };
        if (r.done or r.failed) break;
    }
    if (!too_large) @panic("large: not rejected");
    std.io.write("large=too_large\n");
    h2.http2Close(c);
}

fn scenarioSmallBuf() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0x1, "12345678");
    scriptEnd(s);

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch @panic("small: open");

    var out: http.Response = undefined;
    var r = makeGet(&out);
    out.body = g_small_out_buf[0..];
    _ = h2.http2Submit(c, &r) catch @panic("small: submit");

    var too_large: bool = false;
    var it: usize = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch |e| {
            if (e == error.TooLarge) too_large = true;
            break;
        };
        if (r.done or r.failed) break;
    }
    if (!too_large) @panic("small: not rejected");
    std.io.write("small_buf=too_large\n");
    h2.http2Close(c);
}

fn scenarioTooLargeFlush() void {
    const s = &g_script;
    scriptReset(s);
    s.dynamic = true;
    s.dyn_kind = 4;
    s.cycles_ready = 0;

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch @panic("too_large_flush: open");

    var got1: bool = false;
    var out1: http.Response = undefined;
    var r1 = makeGet(&out1);
    out1.body = g_rej_out_buf[0..];
    const id1 = h2.http2Submit(c, &r1) catch @panic("too_large_flush: submit1");
    s.cycles_ready = 1;
    var it: usize = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch |e| {
            if (e == error.TooLarge) got1 = true;
            break;
        };
        if (r1.done or r1.failed) break;
    }
    h2.http2Release(c, id1) catch {
        got1 = false;
    };
    const credit1: bool = (c.conn_recv_pending == 0 and c.conn_recv_window == 65535);

    var got2: bool = false;
    var out2: http.Response = undefined;
    var r2 = makeGet(&out2);
    out2.body = g_rej_out_buf[0..];
    const id2 = h2.http2Submit(c, &r2) catch @panic("too_large_flush: submit2");
    s.cycles_ready = 2;
    it = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch |e| {
            if (e == error.TooLarge) got2 = true;
            break;
        };
        if (r2.done or r2.failed) break;
    }
    h2.http2Release(c, id2) catch {
        got2 = false;
    };
    const credit2: bool = (c.conn_recv_pending == 0 and c.conn_recv_window == 65535);

    var out3: http.Response = undefined;
    var r3 = makeGet(&out3);
    out3.body = g_normal_out_buf[0..];
    const id3 = h2.http2Submit(c, &r3) catch @panic("too_large_flush: submit3");
    s.cycles_ready = 3;
    var normal_ok: bool = false;
    it = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch break;
        if (r3.done or r3.failed) break;
    }
    if (r3.done and out3.status == 200 and out3.body.len == NORMAL_BODY_LEN) normal_ok = true;
    h2.http2Release(c, id3) catch {
        normal_ok = false;
    };

    printFlag("too_large_flush", got1 and got2 and credit1 and credit2 and normal_ok);
    h2.http2Close(c);
}

fn scenarioSinkError() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitStatus(s, 1);
    emitData(s, 1, 0x1, "bad");
    emitData(s, 1, 0, "ignored");
    emitStatus(s, 3);
    emitData(s, 3, 0x1, "good");
    scriptEnd(s);

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch @panic("error: open");

    var bad_state = SinkState{ .buf = g_sink_buf[0..], .len = 0, .fail = true };
    var bad_sink = http.ResponseSink{ .state = @ptrCast(*void, &bad_state), .write_fn = sinkWrite };
    var out1: http.Response = undefined;
    var out2: http.Response = undefined;
    var r1 = makeGetSink(&out1, &bad_sink);
    var r2 = makeGet(&out2);
    out2.body = g_good_out_buf[0..];
    const id1 = h2.http2Submit(c, &r1) catch @panic("error: submit1");
    const id2 = h2.http2Submit(c, &r2) catch @panic("error: submit2");

    var it: usize = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("error: pump aborted");
        if (r2.done) break;
    }
    if (!r1.failed) @panic("error: failing stream not marked failed");
    if (!r2.done or out2.status != 200) @panic("error: good stream incomplete");
    if (!containsBytes(out2.body, "good")) @panic("error: good body corrupted");
    h2.http2Release(c, id1) catch @panic("error: release failed stream");
    h2.http2Release(c, id2) catch @panic("error: release good stream");
    h2.http2Close(c);
}

fn scenarioFailIdRelease() void {
    const s = &g_script;
    scriptReset(s);
    scriptBegin(s);
    emitSettingsEmpty(s);
    emitRst(s, 1);
    scriptEnd(s);

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var cfg = defaultConfig();
    cfg.max_streams = 1;
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch @panic("fail: open");

    var out: http.Response = undefined;
    out.body = g_fail_body[0..];
    var args = FailArgs{ .c = c, .out = &out, .id = 0, .got_error = 0 };

    var cbuf: [32768]u8 = undefined;
    var fbuf: [8192]u8 = undefined;
    var ctx = initContext(cbuf[0..]);
    var ap: *FailArgs = &args;
    var args_ptr: *const void = @ptrCast(*const void, &ap);
    var f: *void = @asyncInit(ctx, &fbuf, failWorker, args_ptr);

    var more: ?*void = @asyncResume(f, null);
    var it: usize = 0;
    while (more != null and it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("fail: pump");
        more = @asyncResume(f, null);
    }
    if (more != null) @panic("fail: worker stuck");

    var good: bool = (args.got_error == 1 and args.id == 1);
    if (args.id == 0) good = false;
    if (good) {
        h2.http2Release(c, args.id) catch {
            good = false;
        };
        var gone: bool = false;
        _ = h2.http2StreamState(c, args.id) catch |e| {
            gone = (e == error.NoStream);
        };
        if (!gone) good = false;
        var out3: http.Response = undefined;
        var r3 = makeGet(&out3);
        out3.body = g_fail_reuse[0..];
        const id3 = h2.http2Submit(c, &r3) catch @panic("fail: reuse submit");
        if (id3 != 3) good = false;
    }
    printFlag("fail_id_release", good);
    h2.http2Close(c);
}

fn scenarioSlow() void {
    const s = &g_script;
    scriptReset(s);
    s.dynamic = true;
    s.dyn_kind = 1;
    s.cycles_ready = 1;

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var c = h2.http2OpenTransport(&ar, &t, defaultConfig()) catch @panic("slow: open");

    var sink_state = SinkState{ .buf = g_slow_sink_buf[0..], .len = 0, .fail = false };
    var sink = http.ResponseSink{ .state = @ptrCast(*void, &sink_state), .write_fn = sinkWrite };
    var out1: http.Response = undefined;
    var out2: http.Response = undefined;
    var r1 = makeGetSink(&out1, &sink);
    var r2 = makeGet(&out2);
    out2.body = g_slow_out_buf[0..];
    const id1 = h2.http2Submit(c, &r1) catch @panic("slow: submit1");
    const id2 = h2.http2Submit(c, &r2) catch @panic("slow: submit2");
    if (id1 != 1 or id2 != 3) @panic("slow: stream ids");

    var it: usize = 0;
    while (it < 40) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("slow: flush");
    }
    if (h2.http2PendingOutput(c) != 0) @panic("slow: pending output before block");

    s.block_writes = true;
    s.cycles_ready = 3;
    it = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("slow: blocked pump");
        if (r2.done) break;
    }
    const deferred = windowIncrementSum(s.wbuf[0..s.wlen], 24, 1) == 0;
    if (!r2.done or out2.status != 200) @panic("slow: second stream stalled");
    if (!containsBytes(out2.body, "ok")) @panic("slow: second stream body");
    if (sink_state.len != SLOW_BODY_LEN) @panic("slow: sink length");
    if (!deferred) @panic("slow: window update not deferred");
    if (r1.done) @panic("slow: first stream unexpectedly done");

    s.block_writes = false;
    it = 0;
    while (it < 4000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("slow: resume pump");
        if (h2.http2PendingOutput(c) == 0) break;
    }
    const delivered = windowIncrementSum(s.wbuf[0..s.wlen], 24, 1);
    if (delivered < @intCast(i64, SLOW_BODY_LEN)) @panic("slow: deferred window update lost");

    h2.http2Release(c, id2) catch @panic("slow: release second stream");
    std.io.write("slow_ok=1\n");
    h2.http2Close(c);
}

fn printFlag(label: []const u8, ok: bool) void {
    std.io.write(label);
    if (ok) {
        std.io.write("=1\n");
    } else {
        std.io.write("=0\n");
    }
}

const CyclesArgs = struct {
    c: *h2.Http2Conn,
    s: *Script,
    ar: *std.arena.Arena,
    ok: u8,
    used2: usize,
    peak: usize,
    final_used: usize,
};

fn cyclesWorker(args: *CyclesArgs) void {
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        args.s.cycles_ready = i + 1;
        g_cycle_out.body = g_cycle_body[0..];
        var id: u32 = 0;
        if ((i % 2) == 0) {
            h2.http2Get(args.c, "https://example.com/c", &g_cycle_out, &id) catch {
                args.ok = 0;
                return;
            };
        } else {
            h2.http2Post(args.c, "https://example.com/c", "p", "text/plain", "*/*", &g_cycle_out, &id) catch {
                args.ok = 0;
                return;
            };
        }
        if (g_cycle_out.status != 200) {
            args.ok = 0;
            return;
        }
        h2.http2Release(args.c, id) catch {
            args.ok = 0;
            return;
        };
        const used = args.ar.used;
        if (used > args.peak) args.peak = used;
        if (i == 1) args.used2 = used;
    }
    args.final_used = args.ar.used;
    args.ok = 1;
}

fn scenarioArenaCycles() void {
    const s = &g_script;
    scriptReset(s);
    s.dynamic = true;
    s.dyn_kind = 3;
    s.cycles_ready = 0;

    var ar = std.arena.init(g_arena_backing[0..]);
    var t = makeTransport(s);
    var cfg = defaultConfig();
    cfg.max_streams = 2;
    var c = h2.http2OpenTransport(&ar, &t, cfg) catch @panic("cycles: open");

    var ca = CyclesArgs{ .c = c, .s = s, .ar = &ar, .ok = 0, .used2 = 0, .peak = 0, .final_used = 0 };
    var cbuf: [32768]u8 = undefined;
    var fbuf: [8192]u8 = undefined;
    var ctx = initContext(cbuf[0..]);
    var cap: *CyclesArgs = &ca;
    var args_ptr: *const void = @ptrCast(*const void, &cap);
    var f: *void = @asyncInit(ctx, &fbuf, cyclesWorker, args_ptr);

    var more: ?*void = @asyncResume(f, null);
    var it: usize = 0;
    while (more != null and it < 20000) : (it += 1) {
        _ = h2.http2Pump(c) catch @panic("cycles: pump");
        more = @asyncResume(f, null);
    }
    if (more != null or ca.ok != 1) @panic("cycles: worker failed");
    const stable: bool = (ca.used2 > 0 and ca.final_used == ca.used2 and ca.peak <= ca.used2);
    printFlag("arena_ok", stable);
    h2.http2Close(c);
}

pub fn main() void {
    fillPattern(g_slow_body[0..], 17);
    fillPattern(g_source_body[0..], 43);
    fillPattern(g_large_body[0..], 91);
    fillPattern(g_too_chunk[0..], 53);
    fillPattern(g_normal_body[0..], 67);
    scenarioBody();
    scenarioSink();
    scenarioSource();
    scenarioLarge();
    scenarioSmallBuf();
    scenarioTooLargeFlush();
    scenarioSinkError();
    scenarioFailIdRelease();
    scenarioSlow();
    scenarioArenaCycles();
}
