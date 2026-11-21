// pkt.zig -- Git pkt-line v0 framing (smart HTTP task 8).
//
// A packet is a four-byte lowercase-hex length prefix followed by that many
// bytes including the prefix. Special lengths:
//   0000  flush-pkt
//   0001  delim-pkt (protocol v2)
//   0002  response-end-pkt (protocol v2)
//   0003  reserved/invalid
//   0004  empty data packet
//
// The encoder never emits a total length above 0xffff (the four hex digits),
// so the maximum payload is 65531 bytes. decodeAt accepts any four hex digits
// (upper or lower case) and is bounds-checked against the supplied buffer.
// Z98 subset only; direct imports (none).

pub const Error = error{
    BadLength,
    Truncated,
    TooLarge,
    OutputTooSmall,
};

pub const Kind = enum { data, flush, delim, response_end };

pub const Packet = struct {
    kind: Kind,
    payload: []const u8,
    total_len: usize,
};

fn hexVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

fn hexDigit(v: u8) u8 {
    if (v < 10) return v + '0';
    return v - 10 + 'a';
}

// Parse the four-byte length prefix. The value is the total packet length,
// including the prefix.
pub fn parseLen(prefix: []const u8) Error!u16 {
    if (prefix.len != 4) return error.Truncated;
    var v: u16 = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const h = hexVal(prefix[i]) orelse return error.BadLength;
        v = (v << 4) | @intCast(u16, h);
    }
    return v;
}

pub fn lenHex(len: usize, out: *[4]u8) Error!void {
    if (len > 65535) return error.TooLarge;
    const v: u16 = @intCast(u16, len);
    out[0] = hexDigit(@intCast(u8, (v >> 12) & 0x0f));
    out[1] = hexDigit(@intCast(u8, (v >> 8) & 0x0f));
    out[2] = hexDigit(@intCast(u8, (v >> 4) & 0x0f));
    out[3] = hexDigit(@intCast(u8, v & 0x0f));
}

// Total encoded length of a data packet carrying `payload_len` bytes.
pub fn encodedLen(payload_len: usize) Error!u16 {
    if (payload_len > 65531) return error.TooLarge;
    return @intCast(u16, payload_len + 4);
}

// Encode one data packet into `out`; returns the number of bytes written.
pub fn encode(out: []u8, payload: []const u8) Error!usize {
    const total: usize = @intCast(try encodedLen(payload.len));
    if (out.len < total) return error.OutputTooSmall;
    var hdr: [4]u8 = undefined;
    try lenHex(total, &hdr);
    var i: usize = 0;
    while (i < 4) : (i += 1) out[i] = hdr[i];
    i = 0;
    while (i < payload.len) : (i += 1) out[4 + i] = payload[i];
    return total;
}

pub fn encodeFlush(out: []u8) Error!usize {
    if (out.len < 4) return error.OutputTooSmall;
    out[0] = '0';
    out[1] = '0';
    out[2] = '0';
    out[3] = '0';
    return 4;
}

// Decode the packet at `pos`. Returns null exactly at the end of `data`.
pub fn decodeAt(data: []const u8, pos: usize) Error!?Packet {
    if (pos == data.len) return null;
    if (pos > data.len or data.len - pos < 4) return error.Truncated;
    const v = try parseLen(data[pos .. pos + 4]);
    if (v == 0) return Packet{ .kind = .flush, .payload = data[pos + 4 .. pos + 4], .total_len = 4 };
    if (v == 1) return Packet{ .kind = .delim, .payload = data[pos + 4 .. pos + 4], .total_len = 4 };
    if (v == 2) return Packet{ .kind = .response_end, .payload = data[pos + 4 .. pos + 4], .total_len = 4 };
    if (v < 4) return error.BadLength;
    const total: usize = @intCast(v);
    if (data.len - pos < total) return error.Truncated;
    return Packet{ .kind = .data, .payload = data[pos + 4 .. pos + total], .total_len = total };
}
