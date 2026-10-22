// std_http.zig — Z98 std lib: minimal HTTP/1.1 client (design spec §4.3).
//
// HTTP/1.1, no TLS. DEFERRED: chunked transfer-encoding and keep-alive are not
// implemented; requires Content-Length or a close-delimited body.
//
// Surface: parseUrl / percentEncode / parseResponse (pure) / get (network).
// parseResponse is the pure seam the fixtures drive; get is proven end-to-end
// in M2 against mock_tracker. Caps: header block 8 KB, body 1 MB.
// Z98: free functions only, no generics, strict @intCast, switch needs else.

const std = @import("std");

pub const Url = struct { host: []const u8, port: u16, path: []const u8, query: []const u8 };
pub const Header = struct { name: []const u8, value: []const u8 };
pub const Response = struct { status: u16, headers: []Header, body: []u8 };

pub const HttpError = error{
    BadUrl,
    DnsFailed,
    ConnectFailed,
    Timeout,
    BadResponse,
    TooLarge,
    OutOfMemory,
};

const MAX_HEADER_BLOCK: usize = 8192;
const MAX_BODY_BYTES: usize = 1048576;
const MAX_RECV: usize = MAX_HEADER_BLOCK + MAX_BODY_BYTES + 4;
const DEFAULT_PORT: u16 = 80;

// --- small byte helpers ------------------------------------------------------

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn lowerByte(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + @intCast(u8, 32);
    return c;
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (lowerByte(a[i]) != lowerByte(b[i])) return false;
    }
    return true;
}

// Index of `needle` in `hay` at/after `from`, or hay.len when absent.
fn findFrom(hay: []const u8, needle: []const u8, from: usize) usize {
    if (needle.len == 0) return from;
    if (from > hay.len) return hay.len;
    var i: usize = from;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (hay[i + j] != needle[j]) break;
        }
        if (j == needle.len) return i;
    }
    return hay.len;
}

fn containsIgnoreCase(hay: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > hay.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (lowerByte(hay[i + j]) != lowerByte(needle[j])) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn trimSpaces(s: []const u8) []const u8 {
    var a: usize = 0;
    while (a < s.len and (s[a] == ' ' or s[a] == '\t')) : (a += 1) {}
    var b: usize = s.len;
    while (b > a and (s[b - 1] == ' ' or s[b - 1] == '\t')) : (b -= 1) {}
    return s[a..b];
}

fn hexUpper(nib: u8) u8 {
    if (nib < 10) return nib + @intCast(u8, 48);
    return nib - @intCast(u8, 10) + @intCast(u8, 65);
}

fn isUnreserved(c: u8) bool {
    if (c >= 'A' and c <= 'Z') return true;
    if (c >= 'a' and c <= 'z') return true;
    if (c >= '0' and c <= '9') return true;
    if (c == '.' or c == '_' or c == '~' or c == '-') return true;
    return false;
}

// --- arena helpers -----------------------------------------------------------

fn allocHeaders(ar: *std.arena.Arena, n: usize) HttpError![]Header {
    const p = std.arena.alloc(ar, n * @sizeOf(Header)) catch return error.OutOfMemory;
    return @ptrCast([*]Header, p)[0..n];
}

fn allocBytes(ar: *std.arena.Arena, n: usize) HttpError![]u8 {
    const p = std.arena.alloc(ar, n) catch return error.OutOfMemory;
    return p[0..n];
}

fn copyBytes(dst: []u8, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[i] = src[i];
    }
}

fn copySlice(ar: *std.arena.Arena, s: []const u8) HttpError![]u8 {
    const p = try allocBytes(ar, s.len);
    copyBytes(p, s);
    return p;
}

// --- parseUrl ----------------------------------------------------------------

fn parsePort(s: []const u8) HttpError!u16 {
    if (s.len == 0) return error.BadUrl;
    var v: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (!isDigit(s[i])) return error.BadUrl;
        v = v * @intCast(u32, 10) + @intCast(u32, s[i] - 48);
        if (v > @intCast(u32, 65535)) return error.BadUrl;
    }
    return @intCast(u16, v);
}

fn parseAuthorityUrl(url: []const u8, sep: usize, default_port: u16) HttpError!Url {
    const auth_start = sep + 3;
    var auth_end: usize = auth_start;
    while (auth_end < url.len and url[auth_end] != '/' and url[auth_end] != '?') : (auth_end += 1) {}
    if (auth_end == auth_start) return error.BadUrl;

    const authority = url[auth_start..auth_end];
    var host: []const u8 = authority;
    var port: u16 = default_port;
    const colon = findFrom(authority, ":", 0);
    if (colon < authority.len) {
        host = authority[0..colon];
        port = try parsePort(authority[colon + 1 ..]);
    }
    if (host.len == 0) return error.BadUrl;

    var path: []const u8 = "/";
    var query: []const u8 = "";
    if (auth_end < url.len) {
        if (url[auth_end] == '/') {
            const qs = findFrom(url, "?", auth_end);
            if (qs < url.len) {
                path = url[auth_end..qs];
                query = url[qs + 1 ..];
            } else {
                path = url[auth_end..];
            }
        } else {
            query = url[auth_end + 1 ..];
        }
    }
    return Url{ .host = host, .port = port, .path = path, .query = query };
}

pub fn parseUrl(url: []const u8) HttpError!Url {
    const sep = findFrom(url, "://", 0);
    if (sep >= url.len) return error.BadUrl;
    if (!eqBytes(url[0..sep], "http")) return error.BadUrl;
    return parseAuthorityUrl(url, sep, DEFAULT_PORT);
}

fn parseTransportUrl(url: []const u8) HttpError!Url {
    const sep = findFrom(url, "://", 0);
    if (sep >= url.len) return error.BadUrl;
    const scheme = url[0..sep];
    if (eqBytes(scheme, "https")) return parseAuthorityUrl(url, sep, 443);
    if (eqBytes(scheme, "http")) return parseAuthorityUrl(url, sep, DEFAULT_PORT);
    return error.BadUrl;
}

// --- percentEncode -----------------------------------------------------------

pub fn percentEncode(arena: *std.arena.Arena, bytes: []const u8) HttpError![]u8 {
    const cap = bytes.len * 3;
    const out = std.arena.alloc(arena, cap) catch return error.OutOfMemory;
    var n: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const c = bytes[i];
        if (isUnreserved(c)) {
            out[n] = c;
            n += 1;
        } else {
            out[n] = '%';
            out[n + 1] = hexUpper(@intCast(u8, c >> 4));
            out[n + 2] = hexUpper(c & @intCast(u8, 15));
            n += 3;
        }
    }
    return out[0..n];
}

// --- parseResponse (pure) ----------------------------------------------------

fn parseStatus(line: []const u8) HttpError!u16 {
    if (line.len < 5) return error.BadResponse;
    if (line[0] != 'H' or line[1] != 'T' or line[2] != 'T' or line[3] != 'P' or line[4] != '/') {
        return error.BadResponse;
    }
    const sp = findFrom(line, " ", 0);
    if (sp >= line.len) return error.BadResponse;
    if (sp + 3 >= line.len) return error.BadResponse;
    const d0 = line[sp + 1];
    const d1 = line[sp + 2];
    const d2 = line[sp + 3];
    if (!isDigit(d0) or !isDigit(d1) or !isDigit(d2)) return error.BadResponse;
    const v: u32 = @intCast(u32, d0 - 48) * @intCast(u32, 100) + @intCast(u32, d1 - 48) * @intCast(u32, 10) + @intCast(u32, d2 - 48);
    return @intCast(u16, v);
}

fn parseSize(s: []const u8) HttpError!usize {
    if (s.len == 0) return error.BadResponse;
    var v: usize = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (!isDigit(s[i])) return error.BadResponse;
        v = v * @intCast(usize, 10) + @intCast(usize, s[i] - 48);
        if (v > MAX_BODY_BYTES) return error.TooLarge;
    }
    return v;
}

pub fn parseResponse(arena: *std.arena.Arena, raw: []const u8) HttpError!Response {
    const sep = findFrom(raw, "\r\n\r\n", 0);
    if (sep >= raw.len) return error.BadResponse;
    const head_end = sep + 2;
    if (head_end > MAX_HEADER_BLOCK) return error.TooLarge;
    const head = raw[0..head_end];
    const body_off = sep + 4;

    const line_end = findFrom(head, "\r\n", 0);
    if (line_end >= head.len) return error.BadResponse;
    const status = try parseStatus(head[0..line_end]);

    var count: usize = 0;
    var pos: usize = line_end + 2;
    while (pos < head.len) {
        const le = findFrom(head, "\r\n", pos);
        if (le >= head.len) return error.BadResponse;
        count += 1;
        pos = le + 2;
    }

    const hdrs = try allocHeaders(arena, count);
    var have_cl: bool = false;
    var clen: usize = 0;
    var idx: usize = 0;
    pos = line_end + 2;
    while (pos < head.len) {
        const le = findFrom(head, "\r\n", pos);
        const line = head[pos..le];
        const colon = findFrom(line, ":", 0);
        if (colon >= line.len) return error.BadResponse;
        const name = line[0..colon];
        const value = trimSpaces(line[colon + 1 ..]);
        hdrs[idx] = Header{ .name = name, .value = value };
        idx += 1;
        if (eqIgnoreCase(name, "content-length")) {
            have_cl = true;
            clen = try parseSize(value);
        } else if (eqIgnoreCase(name, "transfer-encoding")) {
            if (containsIgnoreCase(value, "chunked")) return error.BadResponse;
        }
        pos = le + 2;
    }

    var body: []u8 = undefined;
    if (have_cl) {
        if (body_off + clen > raw.len) return error.BadResponse;
        body = try allocBytes(arena, clen);
        copyBytes(body, raw[body_off .. body_off + clen]);
    } else {
        const blen = raw.len - body_off;
        if (blen > MAX_BODY_BYTES) return error.TooLarge;
        body = try allocBytes(arena, blen);
        copyBytes(body, raw[body_off..]);
    }
    return Response{ .status = status, .headers = hdrs, .body = body };
}

// --- transport vtable + httpGetOver -----------------------------------------

pub const HttpTransport = struct {
    state: *void,
    read_fn: fn (*void, []u8) !usize,
    write_fn: fn (*void, []const u8) !usize,
    close_fn: fn (*void) void,
};

const Conn = struct {
    t: *HttpTransport,
    buf: [4096]u8,
    pos: usize,
    len: usize,
    eof: bool,
};

fn connFill(c: *Conn) !bool {
    if (c.pos < c.len) return true;
    c.pos = 0;
    c.len = 0;
    const n = try c.t.read_fn(c.t.state, c.buf[0..]);
    if (n == 0) {
        c.eof = true;
        return false;
    }
    c.len = n;
    return true;
}

fn connReadSome(c: *Conn, dst: []u8) !usize {
    if (dst.len == 0) return 0;
    if (!try connFill(c)) return 0;
    var n = c.len - c.pos;
    if (n > dst.len) n = dst.len;
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = c.buf[c.pos + i];
    c.pos += n;
    return n;
}

fn connReadExact(c: *Conn, dst: []u8) !void {
    var got: usize = 0;
    while (got < dst.len) {
        const n = try connReadSome(c, dst[got..]);
        if (n == 0) return error.BadResponse;
        got += n;
    }
}

fn connReadByte(c: *Conn, out: *u8) !bool {
    if (!try connFill(c)) return false;
    out.* = c.buf[c.pos];
    c.pos += 1;
    return true;
}

fn connReadLine(c: *Conn, line: []u8) !usize {
    var n: usize = 0;
    while (true) {
        var b: u8 = 0;
        if (!try connReadByte(c, &b)) {
            if (n == 0) return error.BadResponse;
            return error.BadResponse;
        }
        if (b == '\n') {
            if (n > 0 and line[n - 1] == '\r') n -= 1;
            return n;
        }
        if (n >= line.len) return error.TooLarge;
        line[n] = b;
        n += 1;
    }
    return error.BadResponse;
}

fn isHex(c: u8) bool {
    if (c >= '0' and c <= '9') return true;
    if (c >= 'a' and c <= 'f') return true;
    if (c >= 'A' and c <= 'F') return true;
    return false;
}

fn hexVal(c: u8) usize {
    if (c >= '0' and c <= '9') return @intCast(usize, c - 48);
    if (c >= 'a' and c <= 'f') return @intCast(usize, c - 87);
    return @intCast(usize, c - 55);
}

fn parseChunkSize(s: []const u8) HttpError!usize {
    var v: usize = 0;
    var any: bool = false;
    var i: usize = 0;
    while (i < s.len and s[i] != ';') : (i += 1) {
        if (!isHex(s[i])) return error.BadResponse;
        any = true;
        v = v * @intCast(usize, 16) + hexVal(s[i]);
        if (v > MAX_BODY_BYTES) return error.TooLarge;
    }
    if (!any) return error.BadResponse;
    return v;
}

fn readTrailers(c: *Conn) !void {
    var line: [1024]u8 = undefined;
    var count: usize = 0;
    while (count < 64) : (count += 1) {
        const n = try connReadLine(c, line[0..]);
        if (n == 0) return;
    }
    return error.TooLarge;
}

fn readChunked(c: *Conn, body: *std.buf.Buf) !void {
    while (true) {
        var line: [64]u8 = undefined;
        const n = try connReadLine(c, line[0..]);
        const sz = try parseChunkSize(line[0..n]);
        if (sz == 0) {
            try readTrailers(c);
            return;
        }
        if (body.len + sz > MAX_BODY_BYTES) return error.TooLarge;
        try std.buf.reserve(body, sz);
        var got: usize = 0;
        while (got < sz) {
            const part = try connReadSome(c, body.data[body.len + got .. body.len + sz]);
            if (part == 0) return error.BadResponse;
            got += part;
        }
        body.len += sz;
        var crlf: [2]u8 = undefined;
        try connReadExact(c, crlf[0..]);
        if (crlf[0] != '\r' or crlf[1] != '\n') return error.BadResponse;
    }
}

fn transportWriteAll(t: *HttpTransport, data: []const u8) !void {
    var sent: usize = 0;
    while (sent < data.len) {
        const n = try t.write_fn(t.state, data[sent..]);
        if (n == 0) return error.ConnectFailed;
        sent += n;
    }
}

fn appendHead(head: []u8, head_len: *usize, line: []const u8) HttpError!void {
    if (head_len.* + line.len + 2 > head.len) return error.TooLarge;
    copyBytes(head[head_len.* .. head_len.* + line.len], line);
    head_len.* += line.len;
    head[head_len.*] = '\r';
    head[head_len.* + 1] = '\n';
    head_len.* += 2;
}

// GET over any caller-supplied transport (plain TCP, TLS, mock). HTTP/1.1,
// `Connection: close`, identity + chunked bodies. The transport owns the bytes;
// the arena owns the returned headers/body.
pub fn httpGetOver(arena: *std.arena.Arena, t: *HttpTransport, url: []const u8, out: *Response) !void {
    const u = try parseTransportUrl(url);
    const scheme_sep = findFrom(url, "://", 0);
    var default_port: u16 = DEFAULT_PORT;
    if (scheme_sep < url.len and eqBytes(url[0..scheme_sep], "https")) default_port = 443;
    defer t.close_fn(t.state);

    var req = std.buf.init(arena);
    try std.buf.append(&req, "GET ");
    try std.buf.append(&req, u.path);
    if (u.query.len > 0) {
        try std.buf.appendByte(&req, '?');
        try std.buf.append(&req, u.query);
    }
    try std.buf.append(&req, " HTTP/1.1\r\nHost: ");
    try std.buf.append(&req, u.host);
    if (u.port != default_port) {
        try std.buf.appendByte(&req, ':');
        try appendU16(&req, u.port);
    }
    try std.buf.append(&req, "\r\nConnection: close\r\n\r\n");
    try transportWriteAll(t, std.buf.slice(&req));

    var c = Conn{ .t = t, .buf = undefined, .pos = 0, .len = 0, .eof = false };
    var head: [MAX_HEADER_BLOCK]u8 = undefined;
    var head_len: usize = 0;
    var line: [MAX_HEADER_BLOCK]u8 = undefined;

    const status_len = try connReadLine(&c, line[0..]);
    try appendHead(head[0..], &head_len, line[0..status_len]);
    while (true) {
        const n = try connReadLine(&c, line[0..]);
        if (n == 0) break;
        try appendHead(head[0..], &head_len, line[0..n]);
    }
    try appendHead(head[0..], &head_len, line[0..0]);

    const durable = try allocBytes(arena, head_len);
    copyBytes(durable, head[0..head_len]);

    const first_end = findFrom(durable, "\r\n", 0);
    if (first_end >= durable.len) return error.BadResponse;
    const status = try parseStatus(durable[0..first_end]);

    var count: usize = 0;
    var pos: usize = first_end + 2;
    while (true) {
        const le = findFrom(durable, "\r\n", pos);
        if (le >= durable.len) return error.BadResponse;
        if (le == pos) break;
        count += 1;
        pos = le + 2;
    }

    const hdrs = try allocHeaders(arena, count);
    var have_cl: bool = false;
    var have_chunked: bool = false;
    var clen: usize = 0;
    var idx: usize = 0;
    pos = first_end + 2;
    while (true) {
        const le = findFrom(durable, "\r\n", pos);
        if (le >= durable.len) return error.BadResponse;
        if (le == pos) break;
        const hline = durable[pos..le];
        const colon = findFrom(hline, ":", 0);
        if (colon >= hline.len) return error.BadResponse;
        const name = hline[0..colon];
        const value = trimSpaces(hline[colon + 1 ..]);
        hdrs[idx] = Header{ .name = name, .value = value };
        idx += 1;
        if (eqIgnoreCase(name, "content-length")) {
            have_cl = true;
            clen = try parseSize(value);
        } else if (eqIgnoreCase(name, "transfer-encoding")) {
            if (containsIgnoreCase(value, "chunked")) {
                have_chunked = true;
            } else if (!containsIgnoreCase(value, "identity")) {
                return error.BadResponse;
            }
        }
        pos = le + 2;
    }

    var body = std.buf.init(arena);
    if (have_chunked) {
        try readChunked(&c, &body);
    } else if (have_cl) {
        if (clen > MAX_BODY_BYTES) return error.TooLarge;
        try std.buf.reserve(&body, clen);
        var got: usize = 0;
        while (got < clen) {
            const n = try connReadSome(&c, body.data[body.len + got .. body.len + clen]);
            if (n == 0) return error.BadResponse;
            got += n;
        }
        body.len += clen;
    } else {
        var tmp: [4096]u8 = undefined;
        while (true) {
            const n = try connReadSome(&c, tmp[0..]);
            if (n == 0) break;
            if (body.len + n > MAX_BODY_BYTES) return error.TooLarge;
            try std.buf.append(&body, tmp[0..n]);
        }
    }

    out.* = Response{ .status = status, .headers = hdrs, .body = std.buf.slice(&body) };
}

// --- get (network) -----------------------------------------------------------

fn findHeader(resp: Response, name: []const u8) []const u8 {
    var i: usize = 0;
    while (i < resp.headers.len) : (i += 1) {
        if (eqIgnoreCase(resp.headers[i].name, name)) return resp.headers[i].value;
    }
    var empty: []const u8 = "";
    return empty;
}

fn appendU16(b: *std.buf.Buf, v: u16) HttpError!void {
    var tmp: [5]u8 = undefined;
    var n: usize = 0;
    var x: u16 = v;
    if (x == 0) {
        tmp[0] = '0';
        n = 1;
    }
    while (x > 0) : (x = @intCast(u16, x / 10)) {
        tmp[n] = @intCast(u8, x % 10 + @intCast(u16, 48));
        n += 1;
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        try std.buf.appendByte(b, tmp[n - 1 - i]);
    }
}

fn absoluteLocation(arena: *std.arena.Arena, base_url: []const u8, location: []const u8) HttpError![]u8 {
    if (findFrom(location, "://", 0) < location.len) return copySlice(arena, location);
    const base = try parseUrl(base_url);
    var b = std.buf.init(arena);
    try std.buf.append(&b, "http://");
    try std.buf.append(&b, base.host);
    if (base.port != DEFAULT_PORT) {
        try std.buf.appendByte(&b, ':');
        try appendU16(&b, base.port);
    }
    if (location.len > 0 and location[0] == '/') {
        try std.buf.append(&b, location);
    } else {
        try std.buf.appendByte(&b, '/');
        try std.buf.append(&b, location);
    }
    return std.buf.slice(&b);
}

fn sendAll(fd: i32, data: []const u8) HttpError!void {
    var sent: usize = 0;
    while (sent < data.len) {
        const n = std.net.send(fd, data.ptr + sent, @intCast(i32, data.len - sent));
        if (n <= 0) return error.ConnectFailed;
        sent += @intCast(usize, n);
    }
}

fn getOnce(arena: *std.arena.Arena, url: []const u8, timeout_ms: u32) HttpError!Response {
    const u = try parseUrl(url);
    const ip = std.net.resolve(u.host) catch return error.DnsFailed;
    const fd = std.net.tcpSocket() catch return error.ConnectFailed;
    std.net.connectToIp(fd, ip, u.port, timeout_ms) catch |e| {
        std.net.close(fd);
        if (e == error.Timeout) return error.Timeout;
        return error.ConnectFailed;
    };

    var req = std.buf.init(arena);
    try std.buf.append(&req, "GET ");
    try std.buf.append(&req, u.path);
    if (u.query.len > 0) {
        try std.buf.appendByte(&req, '?');
        try std.buf.append(&req, u.query);
    }
    try std.buf.append(&req, " HTTP/1.1\r\nHost: ");
    try std.buf.append(&req, u.host);
    try std.buf.append(&req, "\r\nConnection: close\r\n\r\n");
    var req_slice: []const u8 = std.buf.slice(&req);
    try sendAll(fd, req_slice);

    const rbuf = std.arena.alloc(arena, MAX_RECV) catch {
        std.net.close(fd);
        return error.OutOfMemory;
    };
    var total: usize = 0;
    var done: bool = false;
    while (!done) {
        var fds: std.net.fd_set = undefined;
        std.net.fdZero(@ptrCast(*u8, &fds));
        std.net.fdSet(fd, @ptrCast(*u8, &fds));
        const sr = std.net.select(fd + 1, @ptrCast(*u8, &fds), null, null, @intCast(i32, timeout_ms));
        if (sr == 0) {
            std.net.close(fd);
            return error.Timeout;
        }
        if (sr < 0) {
            std.net.close(fd);
            return error.ConnectFailed;
        }
        const n = std.net.recv(fd, rbuf + total, @intCast(i32, MAX_RECV - total));
        if (n == 0) {
            done = true;
        } else if (n > 0) {
            total += @intCast(usize, n);
            if (total >= MAX_RECV) {
                std.net.close(fd);
                return error.TooLarge;
            }
        }
    }
    std.net.close(fd);
    var raw: []const u8 = rbuf[0..total];
    return parseResponse(arena, raw);
}

pub fn get(arena: *std.arena.Arena, url: []const u8, timeout_ms: u32) HttpError!Response {
    var resp = try getOnce(arena, url, timeout_ms);
    if (resp.status == 301 or resp.status == 302 or resp.status == 303 or resp.status == 307) {
        const loc = findHeader(resp, "location");
        if (loc.len > 0) {
            const loc_url = try absoluteLocation(arena, url, loc);
            resp = try getOnce(arena, loc_url, timeout_ms);
        }
    }
    return resp;
}
