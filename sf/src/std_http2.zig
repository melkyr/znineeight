// std_http2.zig — Z98 std lib: HTTP/2 frame codec (RFC 7540 §4/§6).
//
// Scope: the frame layer only. Header parse, a sliding-window reader whose
// payloads are in-place slices of the caller's read buffer, an append writer
// that coalesces frames for one transport write per pump, and SETTINGS
// parse/encode. No allocation anywhere.
//
// Bounds are checked once per frame, never per byte. Malformed lengths,
// stream ids, SETTINGS values, zero WINDOW_UPDATE increments, and bad
// HEADERS/CONTINUATION ordering fail closed. Unknown SETTINGS ids are ignored.
//
// Task 6 consumes FrameType/Frame/FrameHeader/Settings/FrameReader/FrameWriter.

const arena_mod = @import("std_arena.zig");
const buf_mod = @import("std_buf.zig");
const hpack_mod = @import("std_hpack.zig");
const http = @import("std_http.zig");

pub const FrameType = enum(u8) {
    data = 0,
    headers = 1,
    priority = 2,
    rst_stream = 3,
    settings = 4,
    push_promise = 5,
    ping = 6,
    goaway = 7,
    window_update = 8,
    continuation = 9,
    // Concrete sentinel for an extension frame type (Z98 has no
    // non-exhaustive enums). `raw_type` carries the exact wire byte.
    unknown = 255,
};

pub const Http2Error = error{
    NotHttp2,
    BadConfig,
    TooLarge,
    Protocol,
    Corrupt,
    Closed,
    Io,
    OutOfMemory,
    StreamClosed,
    StreamReset,
    GoAway,
    NoStream,
    Busy,
};

pub const FRAME_HEADER_LEN: usize = 9;
pub const MAX_WIRE_LENGTH: u32 = 0xFFFFFF;
pub const MAX_PARSE_FRAME: u32 = 16 * 1024 * 1024; // 16 MiB hard parse bound
pub const DEFAULT_MAX_FRAME_SIZE: u32 = 16384;
pub const MIN_MAX_FRAME_SIZE: u32 = 16384;
pub const MAX_MAX_FRAME_SIZE: u32 = 16777215;
pub const MAX_INITIAL_WINDOW: u32 = 0x7FFFFFFF;
pub const SETTINGS_ENTRY_LEN: usize = 6;
pub const SETTINGS_COUNT: usize = 6;

pub const FrameHeader = struct {
    length: u32,
    typ: FrameType,
    flags: u8,
    stream_id: u32,
    raw_type: u8,
};

pub const Frame = struct {
    typ: FrameType,
    flags: u8,
    stream_id: u32,
    payload: []const u8,
    raw_type: u8,
};

pub const Settings = struct {
    header_table_size: u32,
    enable_push: bool,
    max_concurrent_streams: u32,
    initial_window_size: u32,
    max_frame_size: u32,
    max_header_list_size: u32,
};

fn loadU32be(raw: []const u8, off: usize) u32 {
    return (@intCast(u32, raw[off]) << 24) |
        (@intCast(u32, raw[off + 1]) << 16) |
        (@intCast(u32, raw[off + 2]) << 8) |
        @intCast(u32, raw[off + 3]);
}

fn settingsDefaults(s: *Settings) void {
    s.header_table_size = 4096;
    s.enable_push = true;
    s.max_concurrent_streams = 0xFFFFFFFF;
    s.initial_window_size = 65535;
    s.max_frame_size = DEFAULT_MAX_FRAME_SIZE;
    s.max_header_list_size = 0xFFFFFFFF;
}

pub fn settingsParse(raw: []const u8, out: *Settings) Http2Error!void {
    if ((raw.len % SETTINGS_ENTRY_LEN) != 0) return error.Corrupt;
    settingsDefaults(out);
    var i: usize = 0;
    while (i < raw.len) : (i += SETTINGS_ENTRY_LEN) {
        const id: u32 = (@intCast(u32, raw[i]) << 8) | @intCast(u32, raw[i + 1]);
        const val: u32 = loadU32be(raw, i + 2);
        if (id == 0x1) {
            out.header_table_size = val;
        } else if (id == 0x2) {
            if (val > 1) return error.Protocol;
            out.enable_push = (val == 1);
        } else if (id == 0x3) {
            out.max_concurrent_streams = val;
        } else if (id == 0x4) {
            if (val > MAX_INITIAL_WINDOW) return error.Protocol;
            out.initial_window_size = val;
        } else if (id == 0x5) {
            if (val < MIN_MAX_FRAME_SIZE or val > MAX_MAX_FRAME_SIZE) return error.Protocol;
            out.max_frame_size = val;
        } else if (id == 0x6) {
            out.max_header_list_size = val;
        }
        // Unknown ids are ignored (RFC 7540 §6.5.2).
    }
}

fn storeSetting(out: []u8, off: usize, id: u32, val: u32) usize {
    out[off] = @intCast(u8, (id >> 8) & 0xFF);
    out[off + 1] = @intCast(u8, id & 0xFF);
    out[off + 2] = @intCast(u8, (val >> 24) & 0xFF);
    out[off + 3] = @intCast(u8, (val >> 16) & 0xFF);
    out[off + 4] = @intCast(u8, (val >> 8) & 0xFF);
    out[off + 5] = @intCast(u8, val & 0xFF);
    return off + SETTINGS_ENTRY_LEN;
}

pub fn settingsEncode(out: []u8, s: Settings) Http2Error!usize {
    if (s.initial_window_size > MAX_INITIAL_WINDOW) return error.Protocol;
    if (s.max_frame_size < MIN_MAX_FRAME_SIZE or s.max_frame_size > MAX_MAX_FRAME_SIZE) return error.Protocol;
    if (out.len < SETTINGS_ENTRY_LEN * SETTINGS_COUNT) return error.TooLarge;
    var push: u32 = 0;
    if (s.enable_push) push = 1;
    var p: usize = 0;
    p = storeSetting(out, p, 0x1, s.header_table_size);
    p = storeSetting(out, p, 0x2, push);
    p = storeSetting(out, p, 0x3, s.max_concurrent_streams);
    p = storeSetting(out, p, 0x4, s.initial_window_size);
    p = storeSetting(out, p, 0x5, s.max_frame_size);
    p = storeSetting(out, p, 0x6, s.max_header_list_size);
    return p;
}

// Unknown wire types are not an error (RFC 7540 §4.1); they map to the
// concrete `.unknown` variant and keep the raw byte in `raw_type`.
pub fn frameTypeFromRaw(raw: u8) FrameType {
    if (raw > 9) return FrameType.unknown;
    return @intToEnum(FrameType, raw);
}

pub fn frameParseHeader(raw: []const u8) Http2Error!FrameHeader {
    if (raw.len < FRAME_HEADER_LEN) return error.Corrupt;
    const length: u32 = (@intCast(u32, raw[0]) << 16) |
        (@intCast(u32, raw[1]) << 8) |
        @intCast(u32, raw[2]);
    if (length > MAX_PARSE_FRAME) return error.TooLarge;
    const tv: u8 = raw[3];
    const flags: u8 = raw[4];
    const stream_id: u32 = (@intCast(u32, raw[5] & 0x7F) << 24) |
        (@intCast(u32, raw[6]) << 16) |
        (@intCast(u32, raw[7]) << 8) |
        @intCast(u32, raw[8]);
    return FrameHeader{
        .length = length,
        .typ = frameTypeFromRaw(tv),
        .flags = flags,
        .stream_id = stream_id,
        .raw_type = tv,
    };
}

fn validatePayload(typ: FrameType, flags: u8, stream_id: u32, payload: []const u8) Http2Error!void {
    switch (typ) {
        .data => {
            if (stream_id == 0) return error.Protocol;
            if ((flags & 0x8) != 0) {
                if (payload.len < 1) return error.Protocol;
                const pad: usize = @intCast(usize, payload[0]);
                if (pad > payload.len - 1) return error.Protocol;
            }
        },
        .headers => {
            if (stream_id == 0) return error.Protocol;
            var pos: usize = 0;
            if ((flags & 0x8) != 0) {
                if (payload.len < 1) return error.Protocol;
                pos = 1;
            }
            if ((flags & 0x20) != 0) {
                if (pos + 5 > payload.len) return error.Protocol;
                pos += 5;
            }
            if ((flags & 0x8) != 0) {
                const pad: usize = @intCast(usize, payload[0]);
                if (pad > payload.len - pos) return error.Protocol;
            }
        },
        .priority => {
            if (stream_id == 0) return error.Protocol;
            if (payload.len != 5) return error.Protocol;
        },
        .rst_stream => {
            if (stream_id == 0) return error.Protocol;
            if (payload.len != 4) return error.Protocol;
        },
        .settings => {
            if (stream_id != 0) return error.Protocol;
            if ((flags & 0x1) != 0) {
                if (payload.len != 0) return error.Protocol;
            } else {
                if ((payload.len % SETTINGS_ENTRY_LEN) != 0) return error.Protocol;
                var s: Settings = undefined;
                try settingsParse(payload, &s);
            }
        },
        .push_promise => {
            if (stream_id == 0) return error.Protocol;
            var pos: usize = 0;
            if ((flags & 0x8) != 0) {
                if (payload.len < 1) return error.Protocol;
                pos = 1;
            }
            if (payload.len < pos + 4) return error.Protocol;
            const promised: u32 = (@intCast(u32, payload[pos] & 0x7F) << 24) |
                (@intCast(u32, payload[pos + 1]) << 16) |
                (@intCast(u32, payload[pos + 2]) << 8) |
                @intCast(u32, payload[pos + 3]);
            if (promised == 0) return error.Protocol;
            pos += 4;
            if ((flags & 0x8) != 0) {
                const pad: usize = @intCast(usize, payload[0]);
                if (pad > payload.len - pos) return error.Protocol;
            }
        },
        .ping => {
            if (stream_id != 0) return error.Protocol;
            if (payload.len != 8) return error.Protocol;
        },
        .goaway => {
            if (stream_id != 0) return error.Protocol;
            if (payload.len < 8) return error.Protocol;
        },
        .window_update => {
            if (payload.len != 4) return error.Protocol;
            const inc: u32 = loadU32be(payload, 0) & 0x7FFFFFFF;
            if (inc == 0) return error.Protocol;
        },
        .continuation => {
            if (stream_id == 0) return error.Protocol;
        },
        else => return error.Protocol,
    }
}

// Sliding-window frame reader. `buf` is caller-owned (64 KiB in the connection
// layer). `start`/`end` delimit unconsumed bytes; appends use the free tail.
// The buffer is compacted only once the consumed prefix is past half. A
// returned payload is an in-place slice valid until the next append/read.
pub const FrameReader = struct {
    buf: []u8,
    start: usize,
    end: usize,
    expect_continuation: bool,
    continuation_stream: u32,
};

pub fn frameReaderInit(r: *FrameReader, buf: []u8) void {
    r.buf = buf;
    r.start = 0;
    r.end = 0;
    r.expect_continuation = false;
    r.continuation_stream = 0;
}

pub fn frameReaderBuffered(r: *const FrameReader) usize {
    return r.end - r.start;
}

fn frameReaderCompact(r: *FrameReader) void {
    if (r.start == 0) return;
    const n = r.end - r.start;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        r.buf[i] = r.buf[r.start + i];
    }
    r.start = 0;
    r.end = n;
}

pub fn frameReaderFree(r: *FrameReader) []u8 {
    if (r.start == r.end) {
        r.start = 0;
        r.end = 0;
    } else if (r.start > (r.buf.len / 2)) {
        frameReaderCompact(r);
    }
    return r.buf[r.end..];
}

pub fn frameReaderAdvance(r: *FrameReader, n: usize) void {
    if (n > r.buf.len - r.end) {
        r.end = r.buf.len;
        return;
    }
    r.end += n;
}

pub fn frameReaderAppend(r: *FrameReader, src: []const u8) usize {
    const free = frameReaderFree(r);
    var n: usize = src.len;
    if (n > free.len) n = free.len;
    var i: usize = 0;
    while (i < n) : (i += 1) free[i] = src[i];
    r.end += n;
    return n;
}

pub fn frameNext(r: *FrameReader, out: *Frame) Http2Error!bool {
    while (true) {
        const avail = r.end - r.start;
        if (avail < FRAME_HEADER_LEN) return false;
        const hdr = try frameParseHeader(r.buf[r.start .. r.start + FRAME_HEADER_LEN]);
        const need: usize = FRAME_HEADER_LEN + @intCast(usize, hdr.length);
        // A declared length that cannot fit this reader's buffer must fail
        // closed; waiting for impossible bytes would wedge forever.
        if (need > r.buf.len) return error.TooLarge;
        if (avail < need) return false;

        // RFC 7540 §4.1: ignore and discard frames with an unknown type.
        if (hdr.typ == .unknown) {
            r.start += need;
            if (r.start == r.end) {
                r.start = 0;
                r.end = 0;
            }
            continue;
        }

        if (r.expect_continuation) {
            if (hdr.typ != .continuation) return error.Protocol;
            if (hdr.stream_id != r.continuation_stream) return error.Protocol;
        } else if (hdr.typ == .continuation) {
            return error.Protocol;
        }
        const pstart: usize = r.start + FRAME_HEADER_LEN;
        const pend: usize = pstart + @intCast(usize, hdr.length);
        const payload: []const u8 = r.buf[pstart..pend];
        try validatePayload(hdr.typ, hdr.flags, hdr.stream_id, payload);

        if (hdr.typ == .headers or hdr.typ == .push_promise or hdr.typ == .continuation) {
            if ((hdr.flags & 0x4) == 0) {
                r.expect_continuation = true;
                r.continuation_stream = hdr.stream_id;
            } else {
                r.expect_continuation = false;
            }
        }

        out.typ = hdr.typ;
        out.flags = hdr.flags;
        out.stream_id = hdr.stream_id;
        out.payload = payload;
        out.raw_type = hdr.raw_type;
        r.start = pend;
        if (r.start == r.end) {
            r.start = 0;
            r.end = 0;
        }
        return true;
    }
    return false;
}

// Append writer. `buf` is caller-owned (64 KiB in the connection layer) and
// holds whole frames for one transport write per pump. `max_frame_size` is the
// locally advertised setting: payloads above it are refused.
pub const FrameWriter = struct {
    buf: []u8,
    len: usize,
    max_frame_size: u32,
};

pub fn frameWriterInit(w: *FrameWriter, buf: []u8, max_frame_size: u32) void {
    w.buf = buf;
    w.len = 0;
    w.max_frame_size = max_frame_size;
}

pub fn frameWriterClear(w: *FrameWriter) void {
    w.len = 0;
}

pub fn frameWriterSlice(w: *const FrameWriter) []const u8 {
    return w.buf[0..w.len];
}

pub fn frameAppend(w: *FrameWriter, typ: FrameType, flags: u8, stream_id: u32, payload: []const u8) Http2Error!void {
    if (payload.len > @intCast(usize, w.max_frame_size)) return error.TooLarge;
    if (payload.len > @intCast(usize, MAX_WIRE_LENGTH)) return error.TooLarge;
    const need: usize = FRAME_HEADER_LEN + payload.len;
    if (w.len > w.buf.len) return error.TooLarge;
    if (need > w.buf.len - w.len) return error.TooLarge;

    const len32: u32 = @intCast(u32, payload.len);
    const off: usize = w.len;
    w.buf[off] = @intCast(u8, (len32 >> 16) & 0xFF);
    w.buf[off + 1] = @intCast(u8, (len32 >> 8) & 0xFF);
    w.buf[off + 2] = @intCast(u8, len32 & 0xFF);
    w.buf[off + 3] = @intCast(u8, @enumToInt(typ));
    w.buf[off + 4] = flags;
    const sid: u32 = stream_id & 0x7FFFFFFF;
    w.buf[off + 5] = @intCast(u8, (sid >> 24) & 0x7F);
    w.buf[off + 6] = @intCast(u8, (sid >> 16) & 0xFF);
    w.buf[off + 7] = @intCast(u8, (sid >> 8) & 0xFF);
    w.buf[off + 8] = @intCast(u8, sid & 0xFF);
    var i: usize = 0;
    while (i < payload.len) : (i += 1) {
        w.buf[off + FRAME_HEADER_LEN + i] = payload[i];
    }
    w.len = off + need;
}

// ===== Connection, streams, and flow control (Task 6) =====

pub const DEFAULT_INITIAL_WINDOW: i32 = 65535;
pub const READ_BUF_LEN: usize = 65536;
pub const WRITE_BUF_LEN: usize = 65536;
pub const MAX_BUFFERED_BODY: usize = 1024 * 1024;
pub const MAX_HEADER_FIELDS: usize = 128;

const I32_MAX_I64: i64 = 2147483647;
const I32_MIN_I64: i64 = -2147483647 - 1;

const CLIENT_PREFACE = [_]u8{
    'P', 'R', 'I', ' ', '*', ' ', 'H', 'T', 'T', 'P', '/', '2', '.', '0',
    '\r', '\n', '\r', '\n', 'S', 'M', '\r', '\n', '\r', '\n',
};

pub const TransportError = error{ WouldBlock, Closed, Io };

pub const Transport = struct {
    state: *void,
    read_fn: fn (*void, []u8) TransportError!usize,
    write_fn: fn (*void, []const u8) TransportError!usize,
    close_fn: fn (*void) void,
};

pub const Http2Config = struct {
    max_streams: u32,
    max_header_list: usize,
    initial_window: u32,
    max_frame_size: u32,
    header_table_size: u32,
};

pub const PumpStatus = enum(u8) { progress = 0, would_block = 1, closed = 2 };

pub const StreamState = enum(u8) {
    idle = 0,
    open = 1,
    half_closed_local = 2,
    half_closed_remote = 3,
    closed = 4,
    reset = 5,
};

pub const Http2Request = struct {
    method: []const u8,
    scheme: []const u8,
    authority: []const u8,
    path: []const u8,
    headers: []const http.Header,
    body: []const u8,
    body_len: usize,
    body_source: ?*http.RequestSource,
    sink: ?*http.ResponseSink,
    out: *http.Response,
    stream_id: u32,
    done: bool,
    failed: bool,
};

pub const Stream = struct {
    id: u32,
    state: StreamState,
    req: *Http2Request,
    send_window: i32,
    recv_window: i32,
    recv_pending: i32,
    body_off: usize,
    src_sent: usize,
    headers_received: bool,
    resp_body: buf_mod.Buf,
    hdr_arena_buf: []u8,
    hdr_slots: []hpack_mod.HpackHeader,
    hdr_out: []http.Header,
};

pub const Http2Conn = struct {
    arena: *arena_mod.Arena,
    transport: *const Transport,
    cfg: Http2Config,
    rbuf: []u8,
    reader: FrameReader,
    wbuf: []u8,
    writer: FrameWriter,
    write_off: usize,
    preface_off: usize,
    preface_sent: bool,
    peer_preface_done: bool,
    hpack: hpack_mod.Hpack,
    hpack_storage: []u8,
    enc_storage: []u8,
    hscratch: []u8,
    hscratch_len: usize,
    cont_pending: bool,
    cont_discard: bool,
    cont_end_stream: bool,
    cont_stream: u32,
    remote: Settings,
    local: Settings,
    conn_send_window: i32,
    conn_recv_window: i32,
    conn_recv_pending: i32,
    streams: []Stream,
    hdr_slots: []hpack_mod.HpackHeader,
    hdr_out: []http.Header,
    fields_per_stream: usize,
    send_scratch: []u8,
    next_stream_id: u32,
    last_peer_stream: u32,
    goaway: bool,
    goaway_last_stream_id: u32,
    closed: bool,
    close_called: bool,
    peer_closed: bool,
    settings_ack_count: u32,
    ping_ack_count: u32,
    goaway_count: u32,
    rst_count: u32,
    empty_bytes: [1]u8,
    empty_headers: [1]http.Header,
};

pub fn http2DefaultConfig() Http2Config {
    return Http2Config{
        .max_streams = 16,
        .max_header_list = 65536,
        .initial_window = 65535,
        .max_frame_size = DEFAULT_MAX_FRAME_SIZE,
        .header_table_size = 4096,
    };
}

fn validateConfig(cfg: Http2Config) Http2Error!void {
    if (cfg.max_streams == 0 or cfg.max_streams > 65535) return error.BadConfig;
    if (cfg.max_header_list == 0) return error.BadConfig;
    if (cfg.max_header_list > 0xFFFFFFFF) return error.BadConfig;
    if (cfg.initial_window > MAX_INITIAL_WINDOW) return error.BadConfig;
    if (cfg.max_frame_size < MIN_MAX_FRAME_SIZE or cfg.max_frame_size > MAX_MAX_FRAME_SIZE) return error.BadConfig;
}

fn allocBytes(a: *arena_mod.Arena, n: usize) Http2Error![]u8 {
    const raw = arena_mod.alloc(a, n) catch return error.OutOfMemory;
    return raw[0..n];
}

fn allocStreams(a: *arena_mod.Arena, n: usize) Http2Error![]Stream {
    const total: u64 = @intCast(u64, n) * @intCast(u64, @sizeOf(Stream));
    if (total > 0xFFFFFFFF) return error.BadConfig;
    const raw = arena_mod.alloc(a, @intCast(usize, total)) catch return error.OutOfMemory;
    const p: [*]Stream = @ptrCast([*]Stream, raw);
    return p[0..n];
}

fn allocHpackSlots(a: *arena_mod.Arena, n: usize) Http2Error![]hpack_mod.HpackHeader {
    const total: u64 = @intCast(u64, n) * @intCast(u64, @sizeOf(hpack_mod.HpackHeader));
    if (total > 0xFFFFFFFF) return error.BadConfig;
    const raw = arena_mod.alloc(a, @intCast(usize, total)) catch return error.OutOfMemory;
    const p: [*]hpack_mod.HpackHeader = @ptrCast([*]hpack_mod.HpackHeader, raw);
    return p[0..n];
}

fn allocHttpHeaders(a: *arena_mod.Arena, n: usize) Http2Error![]http.Header {
    const total: u64 = @intCast(u64, n) * @intCast(u64, @sizeOf(http.Header));
    if (total > 0xFFFFFFFF) return error.BadConfig;
    const raw = arena_mod.alloc(a, @intCast(usize, total)) catch return error.OutOfMemory;
    const p: [*]http.Header = @ptrCast([*]http.Header, raw);
    return p[0..n];
}

fn defaultRemoteSettings() Settings {
    return Settings{
        .header_table_size = 4096,
        .enable_push = true,
        .max_concurrent_streams = 0xFFFFFFFF,
        .initial_window_size = 65535,
        .max_frame_size = DEFAULT_MAX_FRAME_SIZE,
        .max_header_list_size = 0xFFFFFFFF,
    };
}

fn fieldsFor(max_header_list: usize) usize {
    var f: usize = max_header_list / 2;
    if (f > MAX_HEADER_FIELDS) f = MAX_HEADER_FIELDS;
    if (f < 4) f = 4;
    return f;
}

pub fn http2OpenTransport(arena: *arena_mod.Arena, t: *const Transport, cfg: Http2Config) Http2Error!*Http2Conn {
    try validateConfig(cfg);
    const c_raw = arena_mod.alloc(arena, @sizeOf(Http2Conn)) catch return error.OutOfMemory;
    const c: *Http2Conn = @ptrCast(*Http2Conn, c_raw);
    c.arena = arena;
    c.transport = t;
    c.cfg = cfg;

    c.rbuf = try allocBytes(arena, READ_BUF_LEN);
    frameReaderInit(&c.reader, c.rbuf);
    c.wbuf = try allocBytes(arena, WRITE_BUF_LEN);
    frameWriterInit(&c.writer, c.wbuf, DEFAULT_MAX_FRAME_SIZE);
    c.write_off = 0;
    c.preface_off = 0;
    c.preface_sent = false;
    c.peer_preface_done = false;

    c.hpack_storage = try allocBytes(arena, @intCast(usize, cfg.header_table_size));
    hpack_mod.hpackInit(&c.hpack, c.hpack_storage);
    c.enc_storage = try allocBytes(arena, cfg.max_header_list);
    c.hscratch = try allocBytes(arena, cfg.max_header_list);
    c.hscratch_len = 0;
    c.cont_pending = false;
    c.cont_discard = false;
    c.cont_end_stream = false;
    c.cont_stream = 0;

    c.remote = defaultRemoteSettings();
    c.local = Settings{
        .header_table_size = cfg.header_table_size,
        .enable_push = false,
        .max_concurrent_streams = cfg.max_streams,
        .initial_window_size = cfg.initial_window,
        .max_frame_size = cfg.max_frame_size,
        .max_header_list_size = @intCast(u32, cfg.max_header_list),
    };

    c.conn_send_window = DEFAULT_INITIAL_WINDOW;
    c.conn_recv_window = @intCast(i32, cfg.initial_window);
    c.conn_recv_pending = 0;

    c.streams = try allocStreams(arena, @intCast(usize, cfg.max_streams));
    c.fields_per_stream = fieldsFor(cfg.max_header_list);
    const slot_count: usize = @intCast(usize, cfg.max_streams) * c.fields_per_stream;
    c.hdr_slots = try allocHpackSlots(arena, slot_count);
    c.hdr_out = try allocHttpHeaders(arena, slot_count);
    c.send_scratch = try allocBytes(arena, @intCast(usize, cfg.max_frame_size));
    var i: usize = 0;
    while (i < c.streams.len) : (i += 1) {
        const st = &c.streams[i];
        st.id = 0;
        st.state = StreamState.idle;
        st.req = undefined;
        st.send_window = 0;
        st.recv_window = 0;
        st.recv_pending = 0;
        st.body_off = 0;
        st.src_sent = 0;
        st.headers_received = false;
        st.resp_body = buf_mod.init(arena);
        st.hdr_arena_buf = try allocBytes(arena, cfg.max_header_list);
        const base: usize = i * c.fields_per_stream;
        st.hdr_slots = c.hdr_slots[base .. base + c.fields_per_stream];
        st.hdr_out = c.hdr_out[base .. base + c.fields_per_stream];
    }

    c.next_stream_id = 1;
    c.last_peer_stream = 0;
    c.goaway = false;
    c.goaway_last_stream_id = 0;
    c.closed = false;
    c.close_called = false;
    c.peer_closed = false;
    c.settings_ack_count = 0;
    c.ping_ack_count = 0;
    c.goaway_count = 0;
    c.rst_count = 0;

    try queueClientSettings(c);
    return c;
}

fn queueClientSettings(c: *Http2Conn) Http2Error!void {
    var raw: [SETTINGS_ENTRY_LEN * SETTINGS_COUNT]u8 = undefined;
    const n = try settingsEncode(raw[0..], c.local);
    try frameAppend(&c.writer, FrameType.settings, 0, 0, raw[0..n]);
}

fn findStream(c: *Http2Conn, id: u32) ?*Stream {
    var i: usize = 0;
    while (i < c.streams.len) : (i += 1) {
        const st = &c.streams[i];
        if (st.state != StreamState.idle and st.id == id) return st;
    }
    return null;
}

fn findFreeStream(c: *Http2Conn) ?*Stream {
    var i: usize = 0;
    while (i < c.streams.len) : (i += 1) {
        const st = &c.streams[i];
        if (st.state == StreamState.idle or st.state == StreamState.closed or st.state == StreamState.reset) return st;
    }
    return null;
}

fn activeStreams(c: *const Http2Conn) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < c.streams.len) : (i += 1) {
        const st = &c.streams[i];
        if (st.state == StreamState.open or st.state == StreamState.half_closed_local or st.state == StreamState.half_closed_remote) n += 1;
    }
    return n;
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn parseStatus(v: []const u8) Http2Error!u16 {
    if (v.len != 3) return error.Protocol;
    var x: u32 = 0;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (v[i] < '0' or v[i] > '9') return error.Protocol;
        x = x * 10 + @intCast(u32, v[i] - 48);
    }
    if (x < 100 or x > 999) return error.Protocol;
    return @intCast(u16, x);
}

fn resetStream(c: *Http2Conn, st: *Stream, id: u32, req: *Http2Request) void {
    st.id = id;
    st.state = StreamState.open;
    st.req = req;
    st.send_window = @intCast(i32, c.remote.initial_window_size);
    st.recv_window = @intCast(i32, c.cfg.initial_window);
    st.recv_pending = 0;
    st.body_off = 0;
    st.src_sent = 0;
    st.headers_received = false;
    buf_mod.clear(&st.resp_body);
    req.stream_id = id;
    req.done = false;
    req.failed = false;
    req.out.status = 0;
    req.out.headers = c.empty_headers[0..0];
    req.out.body = c.empty_bytes[0..0];
}

fn encodeRequestHeaders(c: *Http2Conn, st: *Stream) Http2Error!void {
    const req = st.req;
    if (req.headers.len > 60) return error.TooLarge;
    var hs: [64]hpack_mod.HpackHeader = undefined;
    var n: usize = 0;
    hs[n] = hpack_mod.HpackHeader{ .name = ":method", .value = req.method };
    n += 1;
    hs[n] = hpack_mod.HpackHeader{ .name = ":scheme", .value = req.scheme };
    n += 1;
    hs[n] = hpack_mod.HpackHeader{ .name = ":authority", .value = req.authority };
    n += 1;
    hs[n] = hpack_mod.HpackHeader{ .name = ":path", .value = req.path };
    n += 1;
    var i: usize = 0;
    while (i < req.headers.len) : (i += 1) {
        hs[n] = hpack_mod.HpackHeader{ .name = req.headers[i].name, .value = req.headers[i].value };
        n += 1;
    }

    var ea = arena_mod.init(c.enc_storage);
    var bb = buf_mod.init(&ea);
    hpack_mod.hpackEncode(hs[0..n], &bb) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Corrupt;
    };
    const block = buf_mod.slice(&bb);
    const has_body: bool = (req.body.len > 0) or (req.body_len > 0) or (req.body_source != null);
    var off: usize = 0;
    var first: bool = true;
    var first_max: usize = @intCast(usize, c.remote.max_frame_size);
    if (first_max == 0) first_max = @intCast(usize, DEFAULT_MAX_FRAME_SIZE);
    while (true) {
        var chunk: usize = block.len - off;
        if (chunk > first_max) chunk = first_max;
        const last: bool = (off + chunk == block.len);
        var flags: u8 = 0;
        if (last) flags = flags | 0x4;
        if (first and !has_body) flags = flags | 0x1;
        var typ: FrameType = FrameType.continuation;
        if (first) typ = FrameType.headers;
        try frameAppend(&c.writer, typ, flags, st.id, block[off .. off + chunk]);
        off += chunk;
        if (first) first = false;
        if (last) break;
    }
    if (!has_body) st.state = StreamState.half_closed_local;
}

pub fn http2Submit(c: *Http2Conn, req: *Http2Request) Http2Error!u32 {
    if (c.closed or c.goaway) return error.GoAway;
    const active = activeStreams(c);
    if (active >= @intCast(usize, c.cfg.max_streams)) return error.Busy;
    if (c.remote.max_concurrent_streams != 0xFFFFFFFF) {
        if (active >= @intCast(usize, c.remote.max_concurrent_streams)) return error.Busy;
    }
    const st = findFreeStream(c) orelse return error.Busy;
    if (c.next_stream_id > 0x7FFFFFFF) return error.GoAway;
    const id = c.next_stream_id;
    c.next_stream_id += 2;
    resetStream(c, st, id, req);
    try encodeRequestHeaders(c, st);
    return id;
}

pub fn http2StreamState(c: *Http2Conn, stream_id: u32) Http2Error!StreamState {
    const st = findStream(c, stream_id) orelse return error.NoStream;
    return st.state;
}

pub fn http2StreamSendWindow(c: *Http2Conn, stream_id: u32) Http2Error!i32 {
    const st = findStream(c, stream_id) orelse return error.NoStream;
    return st.send_window;
}

pub fn http2StreamRecvWindow(c: *Http2Conn, stream_id: u32) Http2Error!i32 {
    const st = findStream(c, stream_id) orelse return error.NoStream;
    return st.recv_window;
}

pub fn http2ActiveStreams(c: *const Http2Conn) usize {
    return activeStreams(c);
}

pub fn http2PendingOutput(c: *const Http2Conn) usize {
    var n: usize = c.writer.len - c.write_off;
    if (!c.preface_sent) n += CLIENT_PREFACE.len - c.preface_off;
    return n;
}

fn flushOutput(c: *Http2Conn) Http2Error!bool {
    while (!c.preface_sent) {
        const n = c.transport.write_fn(c.transport.state, CLIENT_PREFACE[c.preface_off..]) catch |e| {
            if (e == error.WouldBlock) return true;
            if (e == error.Closed) {
                c.closed = true;
                return false;
            }
            return error.Io;
        };
        if (n == 0) return true;
        c.preface_off += n;
        if (c.preface_off >= CLIENT_PREFACE.len) c.preface_sent = true;
    }
    while (c.write_off < c.writer.len) {
        const n = c.transport.write_fn(c.transport.state, c.writer.buf[c.write_off..c.writer.len]) catch |e| {
            if (e == error.WouldBlock) return true;
            if (e == error.Closed) {
                c.closed = true;
                return false;
            }
            return error.Io;
        };
        if (n == 0) return true;
        c.write_off += n;
    }
    if (c.write_off >= c.writer.len) {
        c.write_off = 0;
        c.writer.len = 0;
    }
    return false;
}

fn copyInto(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[i] = src[i];
}

fn processBuffered(c: *Http2Conn) Http2Error!bool {
    var progressed: bool = false;
    if (!c.peer_preface_done) {
        const avail = frameReaderBuffered(&c.reader);
        if (avail < CLIENT_PREFACE.len) return false;
        var i: usize = 0;
        while (i < CLIENT_PREFACE.len) : (i += 1) {
            if (c.reader.buf[c.reader.start + i] != CLIENT_PREFACE[i]) return error.NotHttp2;
        }
        c.reader.start += CLIENT_PREFACE.len;
        if (c.reader.start == c.reader.end) {
            c.reader.start = 0;
            c.reader.end = 0;
        }
        c.peer_preface_done = true;
        progressed = true;
    }
    var f: Frame = undefined;
    while (true) {
        const got = try frameNext(&c.reader, &f);
        if (!got) break;
        try dispatchFrame(c, &f);
        progressed = true;
    }
    return progressed;
}

fn dispatchFrame(c: *Http2Conn, f: *Frame) Http2Error!void {
    if (f.typ == FrameType.data) {
        try dispatchData(c, f);
        return;
    }
    if (f.typ == FrameType.headers) {
        try dispatchHeaders(c, f);
        return;
    }
    if (f.typ == FrameType.continuation) {
        try dispatchContinuation(c, f);
        return;
    }
    if (f.typ == FrameType.settings) {
        try dispatchSettings(c, f);
        return;
    }
    if (f.typ == FrameType.ping) {
        try dispatchPing(c, f);
        return;
    }
    if (f.typ == FrameType.window_update) {
        try dispatchWindowUpdate(c, f);
        return;
    }
    if (f.typ == FrameType.goaway) {
        try dispatchGoaway(c, f);
        return;
    }
    if (f.typ == FrameType.rst_stream) {
        try dispatchRst(c, f);
        return;
    }
    if (f.typ == FrameType.priority) return;
    if (f.typ == FrameType.push_promise) return error.Protocol;
    return;
}

fn headerBlockSlice(f: *Frame) Http2Error![]const u8 {
    var start: usize = 0;
    var pad: usize = 0;
    if ((f.flags & 0x8) != 0) {
        pad = @intCast(usize, f.payload[0]);
        start = 1;
    }
    if ((f.flags & 0x20) != 0) start += 5;
    if (start > f.payload.len) return error.Protocol;
    if (pad > f.payload.len - start) return error.Protocol;
    return f.payload[start .. f.payload.len - pad];
}

fn decodeHeaderBlock(c: *Http2Conn, st: *Stream, block: []const u8) Http2Error!void {
    var ar = arena_mod.init(st.hdr_arena_buf);
    const n = hpack_mod.hpackDecode(&c.hpack, block, st.hdr_slots, &ar) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Corrupt;
    };
    var outn: usize = 0;
    var status: u16 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const hh = st.hdr_slots[i];
        if (hh.name.len > 0 and hh.name[0] == ':') {
            if (eqBytes(hh.name, ":status")) {
                status = try parseStatus(hh.value);
            } else {
                return error.Protocol;
            }
        } else {
            if (outn >= st.hdr_out.len) return error.TooLarge;
            st.hdr_out[outn] = http.Header{ .name = hh.name, .value = hh.value };
            outn += 1;
        }
    }
    st.req.out.status = status;
    st.req.out.headers = st.hdr_out[0..outn];
}

fn dispatchHeaders(c: *Http2Conn, f: *Frame) Http2Error!void {
    const st = findStream(c, f.stream_id) orelse return error.Protocol;
    if (st.state == StreamState.reset or st.state == StreamState.closed or st.state == StreamState.idle) return error.StreamClosed;
    const block = try headerBlockSlice(f);
    if (st.headers_received) {
        if ((f.flags & 0x4) == 0) {
            c.hscratch_len = 0;
            c.cont_pending = true;
            c.cont_discard = true;
            c.cont_end_stream = (f.flags & 0x1) != 0;
            c.cont_stream = f.stream_id;
        } else {
            if ((f.flags & 0x1) != 0) try finishStream(c, st);
        }
        return;
    }
    if ((f.flags & 0x4) != 0) {
        try decodeHeaderBlock(c, st, block);
        st.headers_received = true;
        if ((f.flags & 0x1) != 0) try finishStream(c, st);
    } else {
        if (block.len > c.hscratch.len) return error.TooLarge;
        copyInto(c.hscratch[0..block.len], block);
        c.hscratch_len = block.len;
        c.cont_pending = true;
        c.cont_discard = false;
        c.cont_end_stream = (f.flags & 0x1) != 0;
        c.cont_stream = f.stream_id;
    }
}

fn dispatchContinuation(c: *Http2Conn, f: *Frame) Http2Error!void {
    if (!c.cont_pending) return error.Protocol;
    if (f.stream_id != c.cont_stream) return error.Protocol;
    if (!c.cont_discard) {
        if (c.hscratch_len + f.payload.len > c.hscratch.len) return error.TooLarge;
        copyInto(c.hscratch[c.hscratch_len .. c.hscratch_len + f.payload.len], f.payload);
        c.hscratch_len += f.payload.len;
    }
    if ((f.flags & 0x4) != 0) {
        const st = findStream(c, f.stream_id) orelse return error.Protocol;
        if (!c.cont_discard and !st.headers_received) {
            try decodeHeaderBlock(c, st, c.hscratch[0..c.hscratch_len]);
            st.headers_received = true;
        }
        const finish = c.cont_end_stream;
        c.cont_pending = false;
        c.cont_discard = false;
        c.cont_end_stream = false;
        c.hscratch_len = 0;
        if (finish) try finishStream(c, st);
    }
}

fn sendWindowUpdate(c: *Http2Conn, stream_id: u32, inc: i32) Http2Error!void {
    if (inc <= 0) return;
    var p: [4]u8 = undefined;
    const v: u32 = @intCast(u32, inc);
    p[0] = @intCast(u8, (v >> 24) & 0xFF);
    p[1] = @intCast(u8, (v >> 16) & 0xFF);
    p[2] = @intCast(u8, (v >> 8) & 0xFF);
    p[3] = @intCast(u8, v & 0xFF);
    try frameAppend(&c.writer, FrameType.window_update, 0, stream_id, p[0..4]);
    if (stream_id == 0) {
        const nv: i64 = @intCast(i64, c.conn_recv_window) + @intCast(i64, inc);
        if (nv > @intCast(i64, MAX_INITIAL_WINDOW)) return error.Protocol;
        c.conn_recv_window = @intCast(i32, nv);
    } else {
        const st = findStream(c, stream_id) orelse return;
        const nv2: i64 = @intCast(i64, st.recv_window) + @intCast(i64, inc);
        if (nv2 > @intCast(i64, MAX_INITIAL_WINDOW)) return error.Protocol;
        st.recv_window = @intCast(i32, nv2);
    }
}

fn maybeWindowUpdate(c: *Http2Conn, st: *Stream) Http2Error!void {
    const half: i32 = @intCast(i32, c.cfg.initial_window / 2);
    if (c.conn_recv_pending > 0 and (c.conn_recv_pending >= half or c.conn_recv_window <= 0)) {
        try sendWindowUpdate(c, 0, c.conn_recv_pending);
        c.conn_recv_pending = 0;
    }
    if (st.recv_pending > 0 and (st.recv_pending >= half or st.recv_window <= 0)) {
        try sendWindowUpdate(c, st.id, st.recv_pending);
        st.recv_pending = 0;
    }
}

fn finishStream(c: *Http2Conn, st: *Stream) Http2Error!void {
    if (st.recv_pending > 0) {
        try sendWindowUpdate(c, st.id, st.recv_pending);
        st.recv_pending = 0;
    }
    if (!st.req.done) {
        st.req.done = true;
        if (st.req.sink == null) {
            st.req.out.body = buf_mod.slice(&st.resp_body);
        }
    }
    st.state = StreamState.closed;
    if (c.goaway and activeStreams(c) == 0) c.closed = true;
}

fn dispatchData(c: *Http2Conn, f: *Frame) Http2Error!void {
    const st = findStream(c, f.stream_id) orelse return error.StreamClosed;
    if (st.state == StreamState.reset or st.state == StreamState.closed or st.state == StreamState.idle) return error.StreamClosed;
    const wire: i32 = @intCast(i32, f.payload.len);
    if (wire > st.recv_window or wire > c.conn_recv_window) return error.Protocol;
    var body: []const u8 = f.payload;
    if ((f.flags & 0x8) != 0) {
        const pad: usize = @intCast(usize, f.payload[0]);
        if (pad > f.payload.len - 1) return error.Protocol;
        body = f.payload[1 .. f.payload.len - pad];
    }
    st.recv_window -= wire;
    st.recv_pending += wire;
    c.conn_recv_window -= wire;
    c.conn_recv_pending += wire;

    if (st.req.sink) |snk| {
        snk.write_fn(snk.state, body) catch return error.Io;
    } else {
        if (st.resp_body.len + body.len > MAX_BUFFERED_BODY) return error.TooLarge;
        buf_mod.append(&st.resp_body, body) catch return error.OutOfMemory;
    }
    try maybeWindowUpdate(c, st);
    if ((f.flags & 0x1) != 0) try finishStream(c, st);
}

fn dispatchSettings(c: *Http2Conn, f: *Frame) Http2Error!void {
    if ((f.flags & 0x1) != 0) return;
    var tmp: Settings = undefined;
    try settingsParse(f.payload, &tmp);
    const old_initial: u32 = c.remote.initial_window_size;
    var i: usize = 0;
    while (i < f.payload.len) : (i += SETTINGS_ENTRY_LEN) {
        const id: u32 = (@intCast(u32, f.payload[i]) << 8) | @intCast(u32, f.payload[i + 1]);
        const val: u32 = loadU32be(f.payload, i + 2);
        if (id == 0x1) {
            c.remote.header_table_size = val;
        } else if (id == 0x2) {
            c.remote.enable_push = (val == 1);
        } else if (id == 0x3) {
            c.remote.max_concurrent_streams = val;
        } else if (id == 0x4) {
            c.remote.initial_window_size = val;
        } else if (id == 0x5) {
            c.remote.max_frame_size = val;
        } else if (id == 0x6) {
            c.remote.max_header_list_size = val;
        }
    }
    if (c.remote.initial_window_size != old_initial) {
        const delta: i64 = @intCast(i64, c.remote.initial_window_size) - @intCast(i64, old_initial);
        try adjustInitialWindow(c, delta);
    }
    c.writer.max_frame_size = c.remote.max_frame_size;
    try frameAppend(&c.writer, FrameType.settings, 0x1, 0, f.payload[0..0]);
    c.settings_ack_count += 1;
}

fn adjustInitialWindow(c: *Http2Conn, delta: i64) Http2Error!void {
    var i: usize = 0;
    while (i < c.streams.len) : (i += 1) {
        const st = &c.streams[i];
        if (st.state == StreamState.open or st.state == StreamState.half_closed_local or st.state == StreamState.half_closed_remote) {
            const nv: i64 = @intCast(i64, st.send_window) + delta;
            if (nv < I32_MIN_I64 or nv > I32_MAX_I64) return error.Protocol;
            st.send_window = @intCast(i32, nv);
        }
    }
}

fn dispatchPing(c: *Http2Conn, f: *Frame) Http2Error!void {
    if ((f.flags & 0x1) != 0) return;
    try frameAppend(&c.writer, FrameType.ping, 0x1, 0, f.payload);
    c.ping_ack_count += 1;
}

fn dispatchWindowUpdate(c: *Http2Conn, f: *Frame) Http2Error!void {
    const inc: u32 = loadU32be(f.payload, 0) & 0x7FFFFFFF;
    if (inc == 0) return error.Protocol;
    if (f.stream_id == 0) {
        const nv: i64 = @intCast(i64, c.conn_send_window) + @intCast(i64, inc);
        if (nv > I32_MAX_I64) return error.Protocol;
        c.conn_send_window = @intCast(i32, nv);
    } else {
        const st = findStream(c, f.stream_id) orelse return;
        if (st.state == StreamState.reset) return;
        const nv2: i64 = @intCast(i64, st.send_window) + @intCast(i64, inc);
        if (nv2 > I32_MAX_I64) return error.Protocol;
        st.send_window = @intCast(i32, nv2);
    }
}

fn dispatchGoaway(c: *Http2Conn, f: *Frame) Http2Error!void {
    c.goaway = true;
    c.goaway_count += 1;
    const last: u32 = loadU32be(f.payload, 0) & 0x7FFFFFFF;
    c.last_peer_stream = last;
    c.goaway_last_stream_id = last;
    var i: usize = 0;
    while (i < c.streams.len) : (i += 1) {
        const st = &c.streams[i];
        if (st.state == StreamState.idle) continue;
        if (st.id > last) {
            st.state = StreamState.reset;
            st.req.failed = true;
        }
    }
    if (activeStreams(c) == 0) c.closed = true;
}

fn dispatchRst(c: *Http2Conn, f: *Frame) Http2Error!void {
    c.rst_count += 1;
    const st = findStream(c, f.stream_id) orelse return;
    st.state = StreamState.reset;
    st.req.failed = true;
}

fn sendOneData(c: *Http2Conn, st: *Stream) Http2Error!bool {
    if (st.state != StreamState.open) return false;
    if (c.conn_send_window <= 0 or st.send_window <= 0) return false;
    const req = st.req;
    if (req.body_source) |src0| {
        if (st.src_sent >= req.body_len) {
            try frameAppend(&c.writer, FrameType.data, 0x1, st.id, req.body[0..0]);
            st.state = StreamState.half_closed_local;
            return true;
        }
        var want: usize = req.body_len - st.src_sent;
        const cw: usize = @intCast(usize, c.conn_send_window);
        if (want > cw) want = cw;
        const sw: usize = @intCast(usize, st.send_window);
        if (want > sw) want = sw;
        if (want > @intCast(usize, c.remote.max_frame_size)) want = @intCast(usize, c.remote.max_frame_size);
        if (want > c.send_scratch.len) want = c.send_scratch.len;
        if (want == 0) return false;
        const got = src0.read_fn(src0.state, c.send_scratch[0..want]) catch return error.Io;
        if (got == 0) return error.Io;
        var flags: u8 = 0;
        if (st.src_sent + got >= req.body_len) flags = 0x1;
        try frameAppend(&c.writer, FrameType.data, flags, st.id, c.send_scratch[0..got]);
        c.conn_send_window -= @intCast(i32, got);
        st.send_window -= @intCast(i32, got);
        st.src_sent += got;
        if ((flags & 0x1) != 0) st.state = StreamState.half_closed_local;
        return true;
    }
    if (st.body_off >= req.body.len) return false;
    var want: usize = req.body.len - st.body_off;
    const cw2: usize = @intCast(usize, c.conn_send_window);
    if (want > cw2) want = cw2;
    const sw2: usize = @intCast(usize, st.send_window);
    if (want > sw2) want = sw2;
    if (want > @intCast(usize, c.remote.max_frame_size)) want = @intCast(usize, c.remote.max_frame_size);
    const free: usize = c.writer.buf.len - c.writer.len;
    if (free <= FRAME_HEADER_LEN) return false;
    const cap: usize = free - FRAME_HEADER_LEN;
    if (want > cap) want = cap;
    if (want == 0) return false;
    var flags2: u8 = 0;
    if (st.body_off + want >= req.body.len) flags2 = 0x1;
    try frameAppend(&c.writer, FrameType.data, flags2, st.id, req.body[st.body_off .. st.body_off + want]);
    st.body_off += want;
    c.conn_send_window -= @intCast(i32, want);
    st.send_window -= @intCast(i32, want);
    if ((flags2 & 0x1) != 0) st.state = StreamState.half_closed_local;
    return true;
}

fn queueRequestData(c: *Http2Conn) Http2Error!bool {
    var progressed: bool = false;
    while (true) {
        var any: bool = false;
        var i: usize = 0;
        while (i < c.streams.len) : (i += 1) {
            if (try sendOneData(c, &c.streams[i])) {
                any = true;
                progressed = true;
            }
        }
        if (!any) break;
    }
    return progressed;
}

pub fn http2Pump(c: *Http2Conn) Http2Error!PumpStatus {
    if (c.closed) return PumpStatus.closed;
    if (try flushOutput(c)) return PumpStatus.would_block;
    var progressed: bool = false;
    var would_block: bool = false;
    while (true) {
        if (try processBuffered(c)) progressed = true;
        if (try queueRequestData(c)) progressed = true;
        if (try flushOutput(c)) return PumpStatus.would_block;
        const free = frameReaderFree(&c.reader);
        if (free.len == 0) return error.TooLarge;
        const n = c.transport.read_fn(c.transport.state, free) catch |e| {
            if (e == error.WouldBlock) {
                would_block = true;
                break;
            }
            if (e == error.Closed) {
                c.peer_closed = true;
                break;
            }
            return error.Io;
        };
        if (n == 0) {
            c.peer_closed = true;
            break;
        }
        frameReaderAdvance(&c.reader, n);
        progressed = true;
    }
    if (try flushOutput(c)) return PumpStatus.would_block;
    if (c.closed) return PumpStatus.closed;
    if (progressed or !would_block) return PumpStatus.progress;
    return PumpStatus.would_block;
}

pub fn http2Wait(c: *Http2Conn, stream_id: u32) Http2Error!void {
    while (true) {
        const st = findStream(c, stream_id) orelse return error.NoStream;
        if (st.req.failed) {
            if (st.state == StreamState.reset) {
                if (c.goaway) return error.GoAway;
                return error.StreamReset;
            }
            return error.GoAway;
        }
        if (st.req.done) return;
        _ = @asyncSuspend(null);
    }
}

pub fn http2Close(c: *Http2Conn) void {
    if (c.close_called) return;
    _ = flushOutput(c) catch {};
    c.closed = true;
    c.close_called = true;
    c.transport.close_fn(c.transport.state);
}
