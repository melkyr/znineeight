// pkt_test.zig -- unit harness for the z9git pkt-line v0 codec.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -o "$OUT" examples/z98/z9git/tests/pkt_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/pkt_test"
//   "$OUT/pkt_test"
//
// Covers encode/decode round-trip, empty data packets, flush/delim/response-end,
// reserved length 0003, bad hex, truncation, and the 0xffff length edge.

const pkt = @import("../pkt.zig");

fn emit(s: []const u8) void {
    if (s.len != 0) @stderrWrite(s.ptr, s.len);
}

var passes: usize = 0;
var fails: usize = 0;
var big_in: [65540]u8 = undefined;
var big_out: [65540]u8 = undefined;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        emit("ok - ");
        passes += 1;
    } else {
        emit("FAIL - ");
        fails += 1;
    }
    emit(name);
    emit("\n");
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn oneRoundTrip(payload: []const u8, name: []const u8) void {
    var buf: [128]u8 = undefined;
    const n = pkt.encode(buf[0..], payload) catch {
        report(name, false);
        return;
    };
    const got = pkt.decodeAt(buf[0..n], 0) catch {
        report(name, false);
        return;
    };
    if (got) |p| {
        report(name, p.kind == .data and eq(p.payload, payload) and p.total_len == n);
    } else {
        report(name, false);
    }
}

pub fn main() void {
    oneRoundTrip("hello\n", "round-trip data packet");
    oneRoundTrip("", "round-trip empty data packet");

    var buf: [32]u8 = undefined;
    var n = pkt.encode(buf[0..], "hello\n") catch 0;
    report("encoded length prefix 000a", n == 10 and eq(buf[0..4], "000a"));
    n = pkt.encode(buf[0..], "") catch 0;
    report("empty data packet is 0004", n == 4 and eq(buf[0..4], "0004"));
    n = pkt.encodeFlush(buf[0..]) catch 0;
    report("flush encodes 0000", n == 4 and eq(buf[0..4], "0000"));

    var flush = pkt.decodeAt("0000", 0) catch null;
    if (flush) |p| {
        report("flush decode", p.kind == .flush and p.payload.len == 0 and p.total_len == 4);
    } else {
        report("flush decode", false);
    }
    var delim = pkt.decodeAt("0001", 0) catch null;
    if (delim) |p| {
        report("delim decode 0001", p.kind == .delim and p.total_len == 4);
    } else {
        report("delim decode 0001", false);
    }
    var rend = pkt.decodeAt("0002", 0) catch null;
    if (rend) |p| {
        report("response-end decode 0002", p.kind == .response_end and p.total_len == 4);
    } else {
        report("response-end decode 0002", false);
    }

    var bad = false;
    _ = pkt.decodeAt("0003", 0) catch {
        bad = true;
    };
    report("reserved 0003 is rejected", bad);

    bad = false;
    _ = pkt.decodeAt("00zz", 0) catch {
        bad = true;
    };
    report("non-hex length is rejected", bad);

    bad = false;
    _ = pkt.decodeAt("00", 0) catch {
        bad = true;
    };
    report("truncated prefix is rejected", bad);

    bad = false;
    _ = pkt.decodeAt("0005", 0) catch {
        bad = true;
    };
    report("truncated payload is rejected", bad);

    var probe: [16]u8 = undefined;
    n = pkt.encode(probe[0..], "abcde") catch 0;
    var upper_ok = false;
    if (pkt.decodeAt("0009ABCDE", 0) catch null) |p| {
        upper_ok = p.kind == .data and eq(p.payload, "ABCDE");
    }
    report("uppercase hex accepted", upper_ok and n == 9);

    const max_payload = 65531;
    var i: usize = 0;
    while (i < max_payload) : (i += 1) big_in[i] = @intCast(u8, i & 0xff);
    n = pkt.encode(big_out[0..], big_in[0..max_payload]) catch 0;
    var max_ok = n == 65535 and eq(big_out[0..4], "ffff");
    if (max_ok) {
        if (pkt.decodeAt(big_out[0..n], 0) catch null) |p| {
            max_ok = p.kind == .data and p.payload.len == max_payload and eq(p.payload[0..8], big_in[0..8]);
        } else {
            max_ok = false;
        }
    }
    report("0xffff edge round-trips", max_ok);

    bad = false;
    _ = pkt.encode(big_out[0..], big_in[0..65532]) catch {
        bad = true;
    };
    report("payload above 65531 is rejected", bad);

    bad = false;
    _ = pkt.encode(probe[0..4], "abc") catch {
        bad = true;
    };
    report("short output buffer is rejected", bad);

    emit("pkt_test summary: ");
    if (fails == 0) {
        emit("PASS\n");
    } else {
        emit("FAIL\n");
    }
    if (fails != 0) @panic("pkt_test failed");
}
