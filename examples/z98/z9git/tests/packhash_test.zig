// packhash_test.zig -- unit harness for the z9git pack SHA-1 tail window.
//
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT" examples/z98/z9git/tests/packhash_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/packhash_test"
//   "$OUT/packhash_test"
//
// Feeds synthetic streams in odd chunk sizes through packHashFeed and checks
// that packHashFinal hashes exactly the bytes before the 20-byte git pack
// trailer and reports true only when a whole trailer is present.

const crypto = @import("std_crypto.zig");
const packhash = @import("../packhash.zig");

const MAX_STREAM: usize = 100000;

var stream: [MAX_STREAM]u8 = undefined;

var passes: usize = 0;
var fails: usize = 0;

fn emit(s: []const u8) void {
    if (s.len != 0) @stderrWrite(s.ptr, s.len);
}

fn emitU(v: usize) void {
    var digits: [20]u8 = undefined;
    var n: usize = 0;
    var x: usize = v;
    if (x == 0) {
        emit("0");
        return;
    }
    while (x != 0 and n < digits.len) {
        digits[n] = @intCast(u8, x % 10);
        x = x / 10;
        n += 1;
    }
    while (n != 0) {
        n -= 1;
        var one: [1]u8 = undefined;
        one[0] = digits[n] + 48;
        emit(one[0..1]);
    }
}

fn reportCase(len: usize, chunk: usize, ok: bool) void {
    if (ok) {
        emit("ok - ");
        passes += 1;
    } else {
        emit("FAIL - ");
        fails += 1;
    }
    emit("len=");
    emitU(len);
    emit(" chunk=");
    emitU(chunk);
    emit("\n");
}

fn digestEq(a: []const u8, b: []const u8) bool {
    if (a.len != 20 or b.len != 20) return false;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn expectedDigest(len: usize, out: *[20]u8) void {
    var h = crypto.sha1Init();
    var prefix: usize = 0;
    if (len > 20) prefix = len - 20;
    crypto.sha1Update(&h, stream[0..prefix]);
    crypto.sha1Final(&h, out);
}

fn checkStream(len: usize, chunk: usize) void {
    var ph = packhash.packHashInit();
    var off: usize = 0;
    while (off < len) {
        var take = chunk;
        if (take > len - off) take = len - off;
        packhash.packHashFeed(&ph, stream[off..off + take]);
        off += take;
    }
    var got: [20]u8 = undefined;
    const full = packhash.packHashFinal(&ph, &got);
    var want: [20]u8 = undefined;
    expectedDigest(len, &want);
    const want_full = len >= 20;
    reportCase(len, chunk, digestEq(got[0..], want[0..]) and full == want_full);
}

pub fn main() void {
    var lengths: [9]usize = .{ 0, 1, 19, 20, 21, 4095, 4096, 4097, 100000 };
    var chunks: [6]usize = .{ 1, 3, 7, 19, 31, 257 };

    var i: usize = 0;
    while (i < stream.len) : (i += 1) {
        stream[i] = @intCast(u8, (i * 31 + 7) & 0xff);
    }

    var li: usize = 0;
    while (li < lengths.len) : (li += 1) {
        var ci: usize = 0;
        while (ci < chunks.len) : (ci += 1) {
            checkStream(lengths[li], chunks[ci]);
        }
    }

    emit("packhash_test summary: ");
    emitU(passes);
    emit(" passed, ");
    emitU(fails);
    emit(" failed\n");
    if (fails != 0) @panic("packhash_test failed");
}
