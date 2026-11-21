// stdlib_http2_frames_xmod — HTTP/2 frame codec vectors (RFC 7540 §4/§6).
//
// Feeds fixed frame bytes through `std_http2.frameNext` and prints
// `type flags stream len` for each: SETTINGS, SETTINGS ACK, HEADERS with
// END_HEADERS, DATA with END_STREAM, WINDOW_UPDATE, PING, GOAWAY, RST_STREAM.
// The SETTINGS payload is parsed and its six parameters printed. Writer paths
// are exercised with a DATA append, a settingsEncode round-trip, and an
// over-max_frame_size refusal. Malformed cases (bad SETTINGS value, bad
// length, bad stream id, CONTINUATION without END_HEADERS) must print `bad`.
//
// GREEN (contract): deterministic byte-exact stdout, exit code 0.

const std = @import("std");
const h2 = @import("std_http2.zig");

fn typeName(t: h2.FrameType) []const u8 {
    const v: u8 = @intCast(u8, @enumToInt(t));
    if (v == 0) return "data";
    if (v == 1) return "headers";
    if (v == 2) return "priority";
    if (v == 3) return "rst_stream";
    if (v == 4) return "settings";
    if (v == 5) return "push_promise";
    if (v == 6) return "ping";
    if (v == 7) return "goaway";
    if (v == 8) return "window_update";
    if (v == 9) return "continuation";
    return "unknown";
}

fn printFrame(f: h2.Frame) void {
    std.io.write(typeName(f.typ));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, f.flags));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, f.stream_id));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, f.payload.len));
    std.io.writeByte('\n');
}

fn printSettings(s: *const h2.Settings) void {
    std.io.write("settings header_table_size=");
    std.io.printInt(@intCast(i32, s.header_table_size));
    std.io.write(" enable_push=");
    if (s.enable_push) {
        std.io.writeByte('1');
    } else {
        std.io.writeByte('0');
    }
    std.io.write(" max_concurrent_streams=");
    std.io.printInt(@intCast(i32, s.max_concurrent_streams));
    std.io.write(" initial_window_size=");
    std.io.printInt(@intCast(i32, s.initial_window_size));
    std.io.write(" max_frame_size=");
    std.io.printInt(@intCast(i32, s.max_frame_size));
    std.io.write(" max_header_list_size=");
    std.io.printInt(@intCast(i32, s.max_header_list_size));
    std.io.writeByte('\n');
}

fn feedPrint(r: *h2.FrameReader, bytes: []const u8) void {
    const n = h2.frameReaderAppend(r, bytes);
    if (n != bytes.len) {
        std.io.write("short\n");
        return;
    }
    var f: h2.Frame = undefined;
    const got = h2.frameNext(r, &f) catch {
        std.io.write("bad\n");
        return;
    };
    if (!got) {
        std.io.write("incomplete\n");
        return;
    }
    printFrame(f);
}

fn expectBad(bytes: []const u8) void {
    var buf: [512]u8 = undefined;
    var r: h2.FrameReader = undefined;
    h2.frameReaderInit(&r, buf[0..]);
    _ = h2.frameReaderAppend(&r, bytes);
    var f: h2.Frame = undefined;
    const got = h2.frameNext(&r, &f) catch {
        std.io.write("bad\n");
        return;
    };
    if (got) {
        std.io.write("unexpected-ok\n");
    } else {
        std.io.write("incomplete\n");
    }
}

fn expectBadCapacity(bytes: []const u8) void {
    var buf: [32]u8 = undefined;
    var r: h2.FrameReader = undefined;
    h2.frameReaderInit(&r, buf[0..]);
    _ = h2.frameReaderAppend(&r, bytes);
    var f: h2.Frame = undefined;
    const got = h2.frameNext(&r, &f) catch {
        std.io.write("bad\n");
        return;
    };
    if (got) {
        std.io.write("unexpected-ok\n");
    } else {
        std.io.write("incomplete\n");
    }
}

pub fn main() void {
    var rbuf: [4096]u8 = undefined;
    var r: h2.FrameReader = undefined;
    h2.frameReaderInit(&r, rbuf[0..]);

    var settings = [_]u8{
        0x00, 0x00, 0x24, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x00, 0x10, 0x00,
        0x00, 0x02, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x03, 0x00, 0x00, 0x00, 0x64,
        0x00, 0x04, 0x00, 0x00, 0xFF, 0xFF,
        0x00, 0x05, 0x00, 0x00, 0x40, 0x00,
        0x00, 0x06, 0x00, 0x01, 0x00, 0x00,
    };
    feedPrint(&r, settings[0..]);

    var settings_ack = [_]u8{ 0x00, 0x00, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00 };
    feedPrint(&r, settings_ack[0..]);

    var headers = [_]u8{ 0x00, 0x00, 0x03, 0x01, 0x04, 0x00, 0x00, 0x00, 0x01, 0x82, 0x86, 0x84 };
    feedPrint(&r, headers[0..]);

    var data = [_]u8{ 0x00, 0x00, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 'h', 'e', 'l', 'l', 'o' };
    feedPrint(&r, data[0..]);

    var window_update = [_]u8{ 0x00, 0x00, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x04, 0x00 };
    feedPrint(&r, window_update[0..]);

    var ping = [_]u8{ 0x00, 0x00, 0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
    feedPrint(&r, ping[0..]);

    var goaway = [_]u8{ 0x00, 0x00, 0x08, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 };
    feedPrint(&r, goaway[0..]);

    var rst_stream = [_]u8{ 0x00, 0x00, 0x04, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x08 };
    feedPrint(&r, rst_stream[0..]);

    // Unknown frame type 0x0a (extension space) followed by a known PING:
    // RFC 7540 §4.1 says the unknown frame is ignored/discarded.
    std.io.write("unknown-skip ");
    var unknown_then_ping = [_]u8{
        0x00, 0x00, 0x04, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF,
        0x00, 0x00, 0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    };
    feedPrint(&r, unknown_then_ping[0..]);

    var s: h2.Settings = undefined;
    h2.settingsParse(settings[9..], &s) catch {
        std.io.write("bad\n");
        return;
    };
    printSettings(&s);

    var wbuf: [256]u8 = undefined;
    var w: h2.FrameWriter = undefined;
    h2.frameWriterInit(&w, wbuf[0..], h2.DEFAULT_MAX_FRAME_SIZE);
    h2.frameAppend(&w, h2.FrameType.data, 0x01, 1, "abc") catch {
        std.io.write("bad\n");
        return;
    };
    std.io.write("writer len=");
    std.io.printInt(@intCast(i32, w.len));
    std.io.writeByte('\n');

    var wbuf2: [64]u8 = undefined;
    var w2: h2.FrameWriter = undefined;
    h2.frameWriterInit(&w2, wbuf2[0..], 2);
    var append_ok = true;
    h2.frameAppend(&w2, h2.FrameType.data, 0x00, 1, "abc") catch {
        append_ok = false;
    };
    if (append_ok) {
        std.io.write("append-too-large-missing\n");
    } else {
        std.io.write("bad\n");
    }

    var ebuf: [36]u8 = undefined;
    const en = h2.settingsEncode(ebuf[0..], s) catch {
        std.io.write("bad\n");
        return;
    };
    std.io.write("settings-encode ");
    std.io.printInt(@intCast(i32, en));
    std.io.writeByte('\n');
    var s2: h2.Settings = undefined;
    h2.settingsParse(ebuf[0..en], &s2) catch {
        std.io.write("bad\n");
        return;
    };
    if (s2.max_frame_size == s.max_frame_size and s2.max_header_list_size == s.max_header_list_size) {
        std.io.write("settings-encode-ok\n");
    } else {
        std.io.write("settings-encode-mismatch\n");
    }

    // Malformed: INITIAL_WINDOW_SIZE above 2^31-1.
    var bad_window = [_]u8{ 0x00, 0x00, 0x06, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x80, 0x00, 0x00, 0x00 };
    expectBad(bad_window[0..]);

    // Malformed: MAX_FRAME_SIZE below 16384.
    var bad_frame_size = [_]u8{ 0x00, 0x00, 0x06, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x3F, 0xFF };
    expectBad(bad_frame_size[0..]);

    // Malformed: PING declares length 7 (must be 8).
    var bad_len = [_]u8{ 0x00, 0x00, 0x07, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07 };
    expectBad(bad_len[0..]);

    // Malformed: DATA on stream 0.
    var bad_stream = [_]u8{ 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7A };
    expectBad(bad_stream[0..]);

    // Malformed: CONTINUATION without END_HEADERS and no preceding HEADERS.
    var bad_cont = [_]u8{ 0x00, 0x00, 0x02, 0x09, 0x00, 0x00, 0x00, 0x00, 0x01, 0x82, 0x86 };
    expectBad(bad_cont[0..]);

    // Malformed: declared length exceeds the reader buffer capacity (100 > 32-9).
    // Must fail closed, not return false forever.
    var bad_capacity = [_]u8{ 0x00, 0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 };
    expectBadCapacity(bad_capacity[0..]);
}
