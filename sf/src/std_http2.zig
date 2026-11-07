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
};

pub const Frame = struct {
    typ: FrameType,
    flags: u8,
    stream_id: u32,
    payload: []const u8,
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

pub fn frameParseHeader(raw: []const u8) Http2Error!FrameHeader {
    if (raw.len < FRAME_HEADER_LEN) return error.Corrupt;
    const length: u32 = (@intCast(u32, raw[0]) << 16) |
        (@intCast(u32, raw[1]) << 8) |
        @intCast(u32, raw[2]);
    if (length > MAX_PARSE_FRAME) return error.TooLarge;
    const tv: u8 = raw[3];
    if (tv > 9) return error.Protocol;
    const flags: u8 = raw[4];
    const stream_id: u32 = (@intCast(u32, raw[5] & 0x7F) << 24) |
        (@intCast(u32, raw[6]) << 16) |
        (@intCast(u32, raw[7]) << 8) |
        @intCast(u32, raw[8]);
    return FrameHeader{
        .length = length,
        .typ = @intToEnum(FrameType, tv),
        .flags = flags,
        .stream_id = stream_id,
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
    const avail = r.end - r.start;
    if (avail < FRAME_HEADER_LEN) return false;
    const hdr = try frameParseHeader(r.buf[r.start .. r.start + FRAME_HEADER_LEN]);
    if (r.expect_continuation) {
        if (hdr.typ != .continuation) return error.Protocol;
        if (hdr.stream_id != r.continuation_stream) return error.Protocol;
    } else if (hdr.typ == .continuation) {
        return error.Protocol;
    }
    const need: usize = FRAME_HEADER_LEN + @intCast(usize, hdr.length);
    if (avail < need) return false;
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
    r.start = pend;
    if (r.start == r.end) {
        r.start = 0;
        r.end = 0;
    }
    return true;
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
