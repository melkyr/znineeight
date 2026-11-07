// stdlib_http2_state_xmod — HTTP/2 connection, streams, and flow control.
//
// Drives `std_http2` through `http2OpenTransport` with a scripted, entirely
// non-suspending `Transport`. The script supplies the server preface, SETTINGS,
// PING, HEADERS/DATA responses, GOAWAY, RST_STREAM, WINDOW_UPDATE, and
// SETTINGS frames; the transport write side records client output and can
// stall after a chosen byte offset to model a partial `WouldBlock` write.
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
    rbuf: [8192]u8,
    rlen: usize,
    rpos: usize,
    wbuf: [65536]u8,
    wlen: usize,
    chunk: usize,
    base: usize,
    fw: h2.FrameWriter,
    stall_at: usize,
    stall_accepted: usize,
    stall_delivered: bool,
    close_called: bool,
    dynamic: bool,
    cycles_ready: usize,
    cycles_served: usize,
    emit_preface: bool,
};

const Ctx = struct { used: u32, capacity: u32, oom: u8 };
const WaitArgs = struct { c: *h2.Http2Conn, id: u32, ok: *bool };

fn waitWorker(args: *WaitArgs) void {
    h2.http2Wait(args.c, args.id) catch {
        args.ok.* = false;
        return;
    };
    args.ok.* = true;
}

var g_script: Script = undefined;
var g_headers: [1]http.Header = undefined;
var g_out_headers: [1]http.Header = undefined;
var g_out_body: [1]u8 = undefined;

fn scriptReset(s: *Script) void {
    s.rlen = 0;
    s.rpos = 0;
    s.wlen = 0;
    s.chunk = 7;
    s.base = 0;
    s.stall_at = 0;
    s.stall_accepted = 0;
    s.stall_delivered = false;
    s.close_called = false;
    s.dynamic = false;
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

fn scriptRead(state: *void, dst: []u8) h2.TransportError!usize {
    const s: *Script = @ptrCast(*Script, state);
    if (s.rpos >= s.rlen) {
        if (s.dynamic and s.cycles_served < s.cycles_ready) {
            buildCycle(s, s.cycles_served);
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

fn emptyResponse(out: *http.Response) void {
    out.status = 0;
    out.headers = g_out_headers[0..0];
    out.body = g_out_body[0..0];
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
    _ = h2.http2Submit(c, &r) catch {
        std.io.write("goaway=0\n");
        return;
    };
    var it: usize = 0;
    while (it < 2000) : (it += 1) {
        _ = h2.http2Pump(c) catch break;
        if (r.failed) break;
    }
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
    _ = h2.http2Submit(c, &r) catch {
        std.io.write("rst=0\n");
        return;
    };
    var it: usize = 0;
    while (it < 2000) : (it += 1) {
        _ = h2.http2Pump(c) catch break;
        if (r.failed) break;
    }
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

    var preface_ok: bool = true;
    var i: usize = 0;
    while (i < 24) : (i += 1) {
        if (s.wbuf[i] != PREFACE_BYTES[i]) preface_ok = false;
    }
    const frames_ok = frameTypesWellFormed(s.wbuf[0..s.wlen], 24);
    const ok = saw_wb and s.stall_delivered and preface_ok and frames_ok and (h2.http2PendingOutput(c) == 0);
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
    s.emit_preface = true;

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
        _ = h2.http2Submit(c, &r1) catch {
            std.io.write("arena_ok=0\n");
            return;
        };
        _ = h2.http2Submit(c, &r2) catch {
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
    h2.http2Close(c);
}

pub fn main() void {
    scenarioBasic();
    scenarioGoaway();
    scenarioRst();
    scenarioWouldBlock();
    scenarioZeroWindow();
    scenarioWindowDelta();
    scenarioWait();
    scenarioArena();
}
